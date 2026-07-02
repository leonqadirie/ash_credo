defmodule AshCredo.Introspection.LexicalScopeWalker do
  @moduledoc """
  Thin wrapper around `Macro.traverse/4` that owns the lexical-scope plumbing
  (`Macro.Env` frames, `quote` depth, the `defmodule` module stack) and
  exposes a callback API to consumers.

  Each scope frame holds a `Macro.Env` snapshot: entering a block copies
  the parent env, `alias`/`require`/`import` nodes are applied to the head
  env via `AshCredo.Introspection.Aliases.apply_directive/3`, and leaving
  the block discards the copy. Resolution semantics therefore come from
  the compiler's own `Macro.Env` APIs; the walker only decides WHERE
  scopes begin and end and what to suppress inside `quote`.

  **Note on `AshCallScanner`:** that module deliberately stays outside the
  walker. Its state (`binding_frames`, `branch_depth`, `pipe_origins`, plus
  `:=` LHS-binding capture) is heterogeneous enough that routing it through
  callbacks would cost more clarity than the env/quote plumbing saves.
  The scanner maintains its own env frames via `Aliases.apply_directive/3`.

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

  - On enter: the walker updates the scope FIRST (e.g. pushes a new env
    frame, or applies a directive to the current env), THEN invokes
    `on_enter` with the updated scope. So inside `on_enter` for an
    `{:alias, ...}` node, `env/1` already includes the alias.
  - On leave: `on_leave` runs FIRST (with the still-current scope), THEN the
    walker pops. So a callback that wants to read the final scope state of a
    do-block can do so before the pop.

  ## Opts

  - `:lexical_scope_nodes` - extra atoms for which to push an alias scope
    frame on entry and pop on exit. Defaults to `[:with, :for]` because
    these constructs ARE empirically-verified separate scopes in Elixir
    (a `require`/`alias` declared inside a `with` clause or `for`
    generator does NOT propagate past the construct). The walker always
    additionally pushes for `@scope_keys` (`do/else/after/rescue/catch`)
    and `:->` arrows. Pass `lexical_scope_nodes: []` to opt out (only
    sensible if you have a specific reason; doing so will let
    `with`/`for` clause-level aliases leak into the enclosing scope).
  - `:track_quote` (default `true`) - track `{:quote, _, _}` depth. When
    truthy, `in_quote?/1` and `quote_depth/1` reflect it, and aliases
    declared inside `quote` are dropped (see `:track_aliases_in_quote`
    to override).
  - `:track_aliases_in_quote` (default `false`) - when `false`, aliases
    declared inside a `quote do ... end` are NOT recorded into frames.
    They belong to the macro caller, not the macro author. Set `true`
    only if you specifically need to model the author's lexical view.
  - `:initial_env` - a `Macro.Env` seeding the base frame, for walking a
    defmodule body that inherits directives from an enclosing scope.

  The module stack is always maintained: `current_module_segments/1`
  returns the absolute segments of the innermost enclosing `defmodule`,
  and directive capture substitutes `__MODULE__` targets through it.
  """

  alias AshCredo.Introspection.Aliases

  @scope_keys ~w(do else after rescue catch)a

  defmodule Scope do
    @moduledoc """
    Read-only view of the lexical context at a traversal point. Callers query
    it via the accessor functions on `LexicalScopeWalker`.
    """

    @type t :: %__MODULE__{
            env_frames: [Macro.Env.t()],
            quote_depth: non_neg_integer(),
            module_stack: [[atom()] | nil]
          }

    defstruct env_frames: [],
              quote_depth: 0,
              module_stack: []
  end

  @typedoc "User-provided state threaded through the traversal."
  @type user_state :: any()

  @typedoc "Callback signature for on_enter / on_leave."
  @type callback :: (Macro.t(), Scope.t(), user_state() -> user_state())

  @typedoc """
  Walker options (see module docs). `:initial_env` seeds the base env
  frame - useful when the walker is invoked on a defmodule body that
  should inherit directives from an enclosing scope.
  """
  @type opts :: [
          lexical_scope_nodes: [atom()],
          track_quote: boolean(),
          track_aliases_in_quote: boolean(),
          initial_env: Macro.Env.t()
        ]

  # ── Public accessors on Scope ──

  @doc """
  Returns the `Macro.Env` visible at the current traversal point. Frames
  inherit their parent env on push, so the head env always carries every
  directive lexically in scope.
  """
  @spec env(Scope.t()) :: Macro.Env.t()
  def env(%Scope{env_frames: [env | _]}), do: env
  def env(%Scope{env_frames: []}), do: Aliases.base_env()

  @doc "Returns the current `quote do ... end` nesting depth (0 outside any quote)."
  @spec quote_depth(Scope.t()) :: non_neg_integer()
  def quote_depth(%Scope{quote_depth: depth}), do: depth

  @doc "Returns `true` if the current traversal point is inside any `quote do ... end`."
  @spec in_quote?(Scope.t()) :: boolean()
  def in_quote?(%Scope{quote_depth: depth}), do: depth > 0

  @doc """
  Returns the absolute module segments of the innermost enclosing `defmodule`,
  or `nil` if there is no enclosing module. Top-level modules have visible
  aliases applied to their literal segments; nested modules prepend the
  enclosing path without re-aliasing (matches Elixir's actual resolution).
  """
  @spec current_module_segments(Scope.t()) :: [atom()] | nil
  def current_module_segments(%Scope{module_stack: []}), do: nil
  def current_module_segments(%Scope{module_stack: [top | _]}), do: top

  @doc """
  Returns `true` if the current traversal point is lexically inside ANY
  `defmodule` (including ones with non-literal names like
  `defmodule Module.concat(...) do ... end`). Distinct from
  `current_module_segments/1`, which returns `nil` both for "not in a module"
  AND for "in a module with a non-literal name." Use this when you need to
  decide whether to skip into a nested-module body.
  """
  @spec in_module?(Scope.t()) :: boolean()
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

  defp initial_scope(%{initial_env: %Macro.Env{} = env}), do: %Scope{env_frames: [env]}
  defp initial_scope(_options), do: %Scope{env_frames: [Aliases.base_env()]}

  defp normalize_opts(opts) do
    %{
      lexical_scope_nodes:
        opts |> Keyword.get(:lexical_scope_nodes, [:with, :for]) |> List.wrap() |> MapSet.new(),
      track_quote: Keyword.get(opts, :track_quote, true),
      track_aliases_in_quote: Keyword.get(opts, :track_aliases_in_quote, false),
      initial_env: Keyword.get(opts, :initial_env)
    }
  end

  # Each `enter`/`leave` clause:
  #   1. updates `scope` for its node kind (push frames, capture aliases,
  #      adjust quote depth, push module stack)
  #   2. invokes the user callback with the updated scope
  # The order here matters: more-specific patterns (`:alias`, `:quote`,
  # `:defmodule`) take precedence over the generic scope-key/arrow/extras
  # patterns. A node that matches multiple kinds (e.g. a `{form, _, _}` that
  # is also in `lexical_scope_nodes`) is handled by exactly one clause -
  # follow each clause's chain to confirm.

  # `capture_directive/3` applies the node to the head env; shapes that
  # create nothing (e.g. a bare `alias __MODULE__`) leave it unchanged.
  defp enter({directive, _, _} = node, {user, scope}, on_enter, options)
       when directive in [:alias, :require, :import] do
    scope = capture_directive(scope, node, options)
    {node, {on_enter.(node, scope, user), scope}}
  end

  defp enter({:quote, _, _} = node, {user, scope}, on_enter, %{track_quote: true} = _options) do
    scope = %{scope | quote_depth: scope.quote_depth + 1}
    {node, {on_enter.(node, scope, user), scope}}
  end

  defp enter({:defmodule, _, _} = node, {user, scope}, on_enter, _options) do
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

  defp leave({directive, _, _} = node, {user, scope}, on_leave, _options)
       when directive in [:alias, :require, :import] do
    {node, {on_leave.(node, scope, user), scope}}
  end

  defp leave({:quote, _, _} = node, {user, scope}, on_leave, %{track_quote: true} = _options) do
    user = on_leave.(node, scope, user)
    scope = %{scope | quote_depth: max(scope.quote_depth - 1, 0)}
    {node, {user, scope}}
  end

  defp leave({:defmodule, _, _} = node, {user, scope}, on_leave, _options) do
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

  defp enter_with_frame(node, user, scope, on_enter, _options) do
    scope = push_env_frame(scope)
    {node, {on_enter.(node, scope, user), scope}}
  end

  defp leave_with_frame(node, user, scope, on_leave, _options) do
    user = on_leave.(node, scope, user)
    scope = pop_env_frame(scope)
    {node, {user, scope}}
  end

  # A pushed frame starts as a copy of its parent env, so everything
  # lexically visible stays visible; the pop discards additions made
  # inside the scope.
  defp push_env_frame(%Scope{env_frames: frames} = scope) do
    %{scope | env_frames: [env(scope) | frames]}
  end

  defp pop_env_frame(%Scope{env_frames: [_ | rest]} = scope), do: %{scope | env_frames: rest}
  defp pop_env_frame(scope), do: scope

  defp capture_directive(%Scope{quote_depth: depth} = scope, _node, %{
         track_quote: true,
         track_aliases_in_quote: false
       })
       when depth > 0, do: scope

  defp capture_directive(%Scope{env_frames: frames} = scope, node, _options) do
    updated = Aliases.apply_directive(env(scope), node, current_module_segments(scope))

    case frames do
      [_head | rest] -> %{scope | env_frames: [updated | rest]}
      [] -> %{scope | env_frames: [updated]}
    end
  end

  defp push_module_stack(%Scope{module_stack: stack} = scope, defmodule_ast) do
    literal = Aliases.defmodule_literal_segments(defmodule_ast)

    parent_absolute =
      case stack do
        [top | _] -> top
        [] -> []
      end

    absolute = Aliases.absolute_module_segments(literal, parent_absolute, env(scope))
    %{scope | module_stack: [absolute | stack]}
  end

  defp pop_module_stack(%Scope{module_stack: [_ | rest]} = scope),
    do: %{scope | module_stack: rest}

  defp pop_module_stack(scope), do: scope
end
