defmodule AshCredo.Introspection.LexicalScopeWalker do
  @moduledoc """
  Thin wrapper around `Macro.traverse/4` that owns the lexical-scope plumbing
  (alias frames, optional `quote` depth, optional `defmodule` module stack)
  and exposes a callback API to consumers.

  Before this module existed, every traversal that needed lexical alias
  context (`AshCredo.Introspection.AshCallScanner`, `AshCredo.Introspection`,
  `AshCredo.Check.Warning.MissingMacroDirective`,
  `AshCredo.SelfCheck.EnforceCompiledCheckWrapper`) re-implemented identical
  push/pop helpers around `LexicalAliases`, identical `@scope_keys`/`->`
  enter/leave clauses, and identical `quote_depth` inc/dec/clamp logic. Each
  diverged in subtle ways: which `lexical_scope_nodes` to push frames for,
  whether to suppress aliases inside `quote`, whether to track the module
  stack. This walker centralises the plumbing while keeping every divergence
  expressible as an opt.

  **Note on `AshCallScanner`:** that module deliberately stays outside the
  walker. Its state (`binding_frames`, `branch_depth`, `pipe_origins`, plus
  `:=` LHS-binding capture) is heterogeneous enough that routing it through
  callbacks would cost more clarity than the alias/quote plumbing saves.
  The scanner uses `LexicalAliases` directly.

  ## API

      LexicalScopeWalker.traverse(ast, user_state, on_enter, on_leave, opts)

  - `ast` - any Macro AST.
  - `user_state` - opaque caller state (any term). The walker does not touch it.
  - `on_enter` / `on_leave` - 3-arity callbacks
    `(ast_node, %Scope{}, user_state) :: user_state`. Callbacks return ONLY
    `user_state`; the walker manages scope and AST. Allowing callbacks to
    rewrite the AST would be a landmine - the leave handler pattern-matches
    the original node shape, and a transformed node could silently skip
    scope pops.

  Returns `{final_user_state, final_scope}`.

  ## Callback timing

  - On enter: the walker updates the scope FIRST (e.g. pushes a new alias
    frame, or records a captured alias in the current frame), THEN invokes
    `on_enter` with the updated scope. So inside `on_enter` for an
    `{:alias, ...}` node, `aliases/1` already includes the alias.
  - On leave: `on_leave` runs FIRST (with the still-current scope), THEN the
    walker pops. So a callback that wants to read the final scope state of a
    do-block can do so before the pop.

  ## Opts

  - `:lexical_scope_nodes` - extra atoms for which to push an alias scope
    frame on entry and pop on exit. Defaults to `[]`. The walker always
    pushes for `@scope_keys` (`do/else/after/rescue/catch`) and `:->`
    arrows; opts add to that set. `MissingMacroDirective` uses
    `[:with, :for]` to model Elixir's empirically-verified construct
    scoping for those constructs.
  - `:track_quote` (default `true`) - track `{:quote, _, _}` depth. When
    truthy, `in_quote?/1` and `quote_depth/1` reflect it, and aliases
    declared inside `quote` are dropped (see `:track_aliases_in_quote`
    to override).
  - `:track_aliases_in_quote` (default `false`) - when `false`, aliases
    declared inside a `quote do ... end` are NOT recorded into frames.
    They belong to the macro caller, not the macro author. Set `true`
    only if you specifically need to model the author's lexical view.
  - `:track_module_stack` (default `false`) - when truthy, the walker
    maintains a module stack and `current_module_segments/1` returns
    the absolute segments of the innermost enclosing `defmodule`.
  """

  alias AshCredo.Introspection.{Aliases, LexicalAliases}

  @scope_keys ~w(do else after rescue catch)a

  defmodule Scope do
    @moduledoc """
    Read-only view of the lexical context at a traversal point. Callers query
    it via the accessor functions on `LexicalScopeWalker`.
    """

    @type t :: %__MODULE__{
            alias_frames: [[{[atom()], [atom()]}]],
            quote_depth: non_neg_integer(),
            module_stack: [[atom()]] | nil
          }

    defstruct alias_frames: [[]],
              quote_depth: 0,
              module_stack: nil
  end

  @typedoc "User-provided state threaded through the traversal."
  @type user_state :: any()

  @typedoc "Callback signature for on_enter / on_leave."
  @type callback :: (Macro.t(), Scope.t(), user_state() -> user_state())

  @typedoc """
  Walker options (see module docs). `on_frame_push`/`on_frame_pop` are
  optional 1-arity functions that mutate `user_state` in lockstep with
  every alias-frame push/pop the walker performs - useful for callers who
  maintain their own per-scope frame stacks (e.g. `MissingMacroDirective`'s
  `require_frames`). `:initial_aliases` pre-populates the base alias frame
  - useful when the walker is invoked on a defmodule body that should
  inherit aliases from an enclosing scope.
  """
  @type opts :: [
          lexical_scope_nodes: [atom()],
          track_quote: boolean(),
          track_aliases_in_quote: boolean(),
          track_module_stack: boolean(),
          initial_aliases: [{[atom()], [atom()]}],
          on_frame_push: (user_state() -> user_state()),
          on_frame_pop: (user_state() -> user_state())
        ]

  # ── Public accessors on Scope ──

  @doc """
  Returns alias entries visible at the current traversal point, flattened
  across all enclosing frames. Most-recently-declared aliases come first, so
  `Aliases.expand_alias/2` (which longest-matches and tie-breaks by first
  position) honours shadowing automatically.
  """
  @spec aliases(Scope.t()) :: [{[atom()], [atom()]}]
  def aliases(%Scope{alias_frames: frames}), do: LexicalAliases.current_aliases(frames)

  @doc "Returns the current `quote do ... end` nesting depth (0 outside any quote)."
  @spec quote_depth(Scope.t()) :: non_neg_integer()
  def quote_depth(%Scope{quote_depth: depth}), do: depth

  @doc "Returns `true` if the current traversal point is inside any `quote do ... end`."
  @spec in_quote?(Scope.t()) :: boolean()
  def in_quote?(%Scope{quote_depth: depth}), do: depth > 0

  @doc """
  Returns the absolute module segments of the innermost enclosing `defmodule`,
  or `nil` if there is no enclosing module or `:track_module_stack` was not
  enabled. Top-level modules have visible aliases applied to their literal
  segments; nested modules prepend the enclosing path without re-aliasing
  (matches Elixir's actual resolution).
  """
  @spec current_module_segments(Scope.t()) :: [atom()] | nil
  def current_module_segments(%Scope{module_stack: nil}), do: nil
  def current_module_segments(%Scope{module_stack: []}), do: nil
  def current_module_segments(%Scope{module_stack: [top | _]}), do: top

  @doc """
  Returns `true` if the current traversal point is lexically inside ANY
  `defmodule` (including ones with non-literal names like
  `defmodule Module.concat(...) do ... end`). Distinct from
  `current_module_segments/1`, which returns `nil` both for "not in a module"
  AND for "in a module with a non-literal name." Use this when you need to
  decide whether to skip into a nested-module body.

  Returns `false` if `:track_module_stack` was not enabled.
  """
  @spec in_module?(Scope.t()) :: boolean()
  def in_module?(%Scope{module_stack: nil}), do: false
  def in_module?(%Scope{module_stack: []}), do: false
  def in_module?(%Scope{module_stack: [_ | _]}), do: true

  # ── Public traverse ──

  @doc """
  Walk `ast` with lexical-scope tracking. See module docs for the API,
  callback timing, and opts.
  """
  @spec traverse(Macro.t(), user_state(), callback(), callback(), opts()) ::
          {user_state(), Scope.t()}
  def traverse(ast, user_state, on_enter, on_leave, opts \\ [])
      when is_function(on_enter, 3) and is_function(on_leave, 3) do
    options = normalize_opts(opts)
    scope = initial_scope(options)

    {_ast, {final_user, final_scope}} =
      Macro.traverse(
        ast,
        {user_state, scope},
        fn node, acc -> enter(node, acc, on_enter, options) end,
        fn node, acc -> leave(node, acc, on_leave, options) end
      )

    {final_user, final_scope}
  end

  # ── Internals ──

  defp initial_scope(%{track_module_stack: track_module_stack, initial_aliases: initial_aliases}) do
    %Scope{
      alias_frames: [initial_aliases],
      module_stack: if(track_module_stack, do: [])
    }
  end

  defp normalize_opts(opts) do
    %{
      lexical_scope_nodes:
        opts |> Keyword.get(:lexical_scope_nodes, []) |> List.wrap() |> MapSet.new(),
      track_quote: Keyword.get(opts, :track_quote, true),
      track_aliases_in_quote: Keyword.get(opts, :track_aliases_in_quote, false),
      track_module_stack: Keyword.get(opts, :track_module_stack, false),
      initial_aliases: Keyword.get(opts, :initial_aliases, []),
      on_frame_push: Keyword.get(opts, :on_frame_push, &noop/1),
      on_frame_pop: Keyword.get(opts, :on_frame_pop, &noop/1)
    }
  end

  defp noop(user_state), do: user_state

  # Each `enter`/`leave` clause:
  #   1. updates `scope` for its node kind (push frames, capture aliases,
  #      adjust quote depth, push module stack)
  #   2. invokes the user callback with the updated scope
  # The order here matters: more-specific patterns (`:alias`, `:quote`,
  # `:defmodule`) take precedence over the generic scope-key/arrow/extras
  # patterns. A node that matches multiple kinds (e.g. a `{form, _, _}` that
  # is also in `lexical_scope_nodes`) is handled by exactly one clause -
  # follow each clause's chain to confirm.

  defp enter({:alias, _, _} = node, {user, scope}, on_enter, options) do
    scope = capture_alias(scope, node, options)
    {node, {on_enter.(node, scope, user), scope}}
  end

  defp enter({:quote, _, _} = node, {user, scope}, on_enter, %{track_quote: true} = _options) do
    scope = %{scope | quote_depth: scope.quote_depth + 1}
    {node, {on_enter.(node, scope, user), scope}}
  end

  defp enter({:defmodule, _, _} = node, {user, scope}, on_enter, %{track_module_stack: true}) do
    scope = push_module_stack(scope, node)
    {node, {on_enter.(node, scope, user), scope}}
  end

  defp enter({scope_key, _body} = node, {user, scope}, on_enter, options)
       when scope_key in @scope_keys do
    enter_with_frame(node, user, scope, on_enter, options)
  end

  defp enter({:->, _, [_args, _body]} = node, {user, scope}, on_enter, options) do
    enter_with_frame(node, user, scope, on_enter, options)
  end

  defp enter(
         {form, _, _} = node,
         {user, scope},
         on_enter,
         %{lexical_scope_nodes: extras} = options
       )
       when is_atom(form) do
    if MapSet.member?(extras, form) do
      enter_with_frame(node, user, scope, on_enter, options)
    else
      {node, {on_enter.(node, scope, user), scope}}
    end
  end

  defp enter(node, {user, scope}, on_enter, _options) do
    {node, {on_enter.(node, scope, user), scope}}
  end

  # Leave: callback runs with current scope, then we pop. Mirror the enter
  # clauses so each push has a matching pop.

  defp leave({:alias, _, _} = node, {user, scope}, on_leave, _options) do
    {node, {on_leave.(node, scope, user), scope}}
  end

  defp leave({:quote, _, _} = node, {user, scope}, on_leave, %{track_quote: true} = _options) do
    user = on_leave.(node, scope, user)
    scope = %{scope | quote_depth: max(scope.quote_depth - 1, 0)}
    {node, {user, scope}}
  end

  defp leave({:defmodule, _, _} = node, {user, scope}, on_leave, %{track_module_stack: true}) do
    user = on_leave.(node, scope, user)
    scope = pop_module_stack(scope)
    {node, {user, scope}}
  end

  defp leave({scope_key, _body} = node, {user, scope}, on_leave, options)
       when scope_key in @scope_keys do
    leave_with_frame(node, user, scope, on_leave, options)
  end

  defp leave({:->, _, [_args, _body]} = node, {user, scope}, on_leave, options) do
    leave_with_frame(node, user, scope, on_leave, options)
  end

  defp leave(
         {form, _, _} = node,
         {user, scope},
         on_leave,
         %{lexical_scope_nodes: extras} = options
       )
       when is_atom(form) do
    if MapSet.member?(extras, form) do
      leave_with_frame(node, user, scope, on_leave, options)
    else
      {node, {on_leave.(node, scope, user), scope}}
    end
  end

  defp leave(node, {user, scope}, on_leave, _options) do
    {node, {on_leave.(node, scope, user), scope}}
  end

  # ── Scope mutators ──

  defp enter_with_frame(node, user, scope, on_enter, %{on_frame_push: on_frame_push}) do
    scope = push_alias_frame(scope)
    user = on_frame_push.(user)
    {node, {on_enter.(node, scope, user), scope}}
  end

  defp leave_with_frame(node, user, scope, on_leave, %{on_frame_pop: on_frame_pop}) do
    user = on_leave.(node, scope, user)
    user = on_frame_pop.(user)
    scope = pop_alias_frame(scope)
    {node, {user, scope}}
  end

  defp push_alias_frame(%Scope{alias_frames: frames} = scope) do
    %{scope | alias_frames: LexicalAliases.push_frame(frames)}
  end

  defp pop_alias_frame(%Scope{alias_frames: frames} = scope) do
    %{scope | alias_frames: LexicalAliases.pop_frame(frames)}
  end

  defp capture_alias(%Scope{quote_depth: depth} = scope, _node, %{
         track_quote: true,
         track_aliases_in_quote: false
       })
       when depth > 0, do: scope

  defp capture_alias(%Scope{alias_frames: frames} = scope, alias_node, _options) do
    entries = Aliases.alias_entries(alias_node)
    %{scope | alias_frames: LexicalAliases.put_aliases(frames, entries)}
  end

  defp push_module_stack(%Scope{module_stack: stack, alias_frames: frames} = scope, defmodule_ast) do
    literal = defmodule_literal_segments(defmodule_ast)

    parent_absolute =
      case stack do
        [top | _] -> top
        [] -> []
      end

    absolute = LexicalAliases.absolute_module_segments(literal, parent_absolute, frames)
    %{scope | module_stack: [absolute | stack]}
  end

  defp pop_module_stack(%Scope{module_stack: [_ | rest]} = scope),
    do: %{scope | module_stack: rest}

  defp pop_module_stack(scope), do: scope

  defp defmodule_literal_segments({:defmodule, _, [{:__aliases__, _, segs}, _]})
       when is_list(segs), do: segs

  defp defmodule_literal_segments(_), do: nil
end
