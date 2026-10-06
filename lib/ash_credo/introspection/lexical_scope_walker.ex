defmodule AshCredo.Introspection.LexicalScopeWalker do
  @moduledoc """
  Thin wrapper around `Macro.traverse/4` that owns the lexical-scope
  plumbing (`Macro.Env` frames, the `quote` depth, the module stack)
  and exposes a callback API to consumers.

  Each scope frame holds a `Macro.Env` snapshot: entering a block copies
  the parent env, `alias`/`require`/`import` nodes are applied to the
  head env via `AshCredo.Introspection.Aliases.apply_directive/3`, and
  leaving the block discards the copy. Resolution semantics therefore
  come from the compiler's own `Macro.Env` APIs; the walker only decides
  WHERE scopes start and end, and what to suppress inside `quote`.

  **Note on `AshCallScanner`:** that module deliberately stays outside
  the walker. Its state (`binding_frames`, `branch_depth`,
  `pipe_origins`, plus the `:=` LHS-binding capture) is heterogeneous
  enough that routing it through callbacks would cost more clarity than
  the env/quote plumbing saves. The scanner maintains its own env frames
  via `Aliases.apply_directive/3` and shares module identity with the
  walker through `AshCredo.Introspection.ModuleStack`.

  ## API

      LexicalScopeWalker.traverse(ast, user_state, on_enter, on_leave, opts)

  - `ast` - any Macro AST.
  - `user_state` - opaque caller state (any term). The walker doesn't
    touch it.
  - `on_enter` / `on_leave` - 3-arity callbacks
    `(ast_node, %Scope{}, user_state) :: user_state`. Callbacks return
    ONLY `user_state`; the walker manages the scope and the AST.
    Letting a callback rewrite the AST would be dangerous: the leave
    handler pattern-matches the original node shape, and a transformed
    node could silently skip scope pops.

  Returns `{final_user_state, final_scope}`.

  ## Callback timing

  - On enter: the walker updates the scope FIRST (e.g. pushes a new env
    frame, or applies a directive to the current env), THEN invokes
    `on_enter` with the updated scope. So inside `on_enter` for an
    `{:alias, ...}` node, `env/1` already includes the alias.
  - On leave: `on_leave` runs FIRST, with the still-current scope, THEN
    the walker pops. So a callback that wants to read the final scope
    state of a do-block can do so before the pop.
  - Module-definition callbacks see the declared module's identity.
    Name and option expressions are visited in the enclosing context;
    the child module is entered only for its `do` body.

  ## Opts

  - `:lexical_scope_nodes` - the call forms for which the walker pushes
    an alias scope frame on entry and pops it on exit, on top of the
    frames it always pushes for `Aliases.scope_keys/0`
    (`do/else/after/rescue/catch`) and `:->` arrows. Defaults to
    `Aliases.alias_scope_nodes/0` (`with`, `for`, and default arguments),
    which documents the Elixir scoping rule behind it. A passed list
    replaces the default instead of extending it, so include
    `Aliases.alias_scope_nodes()` to keep those scopes. Pass `[]` to opt
    out, but only with a specific reason: those aliases then leak into
    the enclosing scope.
  - `:track_quote` (default `true`) - track the `{:quote, _, _}` depth.
    When truthy, `in_quote?/1` and `quote_depth/1` reflect it, and
    aliases declared inside `quote` are dropped (see
    `:track_aliases_in_quote` to override this).
  - `:track_aliases_in_quote` (default `false`) - when `false`, aliases
    declared inside a `quote do ... end` are NOT recorded into frames.
    They belong to the macro caller, not the macro author. Set this to
    `true` only if you specifically need to model the author's lexical
    view.
  The module stack is always maintained: `current_module_segments/1`
  returns the absolute segments of the innermost enclosing module,
  including `defprotocol` and `defimpl` bodies,
  and directive capture substitutes `__MODULE__` targets through it.
  """

  import AshCredo.Introspection.ModuleStack, only: [is_module_definition: 1]

  alias AshCredo.Introspection.Aliases
  alias AshCredo.Introspection.ModuleStack

  @scope_keys Aliases.scope_keys()
  @default_lexical_scope_nodes Aliases.alias_scope_nodes()

  defmodule Scope do
    @moduledoc """
    Read-only view of the lexical context at a traversal point. Callers query
    it via the accessor functions on `LexicalScopeWalker`.
    """

    @type t :: %__MODULE__{
            env_frames: [Macro.Env.t()],
            quote_depth: non_neg_integer(),
            module_stack: AshCredo.Introspection.ModuleStack.t()
          }

    defstruct env_frames: [],
              quote_depth: 0,
              module_stack: %AshCredo.Introspection.ModuleStack{}
  end

  @typedoc "User-provided state threaded through the traversal."
  @type user_state :: any()

  @typedoc "Callback signature for on_enter / on_leave."
  @type callback :: (Macro.t(), Scope.t(), user_state() -> user_state())

  @typedoc "Walker options (see the module docs)."
  @type opts :: [
          lexical_scope_nodes: [atom()],
          track_quote: boolean(),
          track_aliases_in_quote: boolean()
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
  Returns the absolute module segments of the innermost enclosing
  `defmodule`, `defprotocol`, or `defimpl`, or `nil` when its name is
  unknown or there is no enclosing module. Top-level
  modules have the visible aliases applied to their literal segments;
  nested modules prepend the enclosing path without re-aliasing the
  nested name. Explicit `Elixir.*` names are absolute at every depth;
  `__MODULE__.*` names use the parent's full path. Implementations use
  the protocol and target names (for example, `Inspect.Foo`); computed
  or multiple targets have unknown identity. A computed
  name is visited in the parent context before entering its body.
  """
  @spec current_module_segments(Scope.t()) :: [atom()] | nil
  def current_module_segments(%Scope{module_stack: stack}), do: ModuleStack.current(stack)

  @doc """
  Resolves alias segments through the visible env and the current module
  identity. See `AshCredo.Introspection.Aliases.resolve_alias/3`.
  """
  @spec resolve_alias([Macro.t()], Scope.t()) :: {:ok, [atom()]} | :error
  def resolve_alias(segments, %Scope{} = scope),
    do: Aliases.resolve_alias(segments, env(scope), current_module_segments(scope))

  @doc """
  Returns `true` if the current traversal point is lexically inside ANY
  module body (`defmodule`, `defprotocol`, or `defimpl`), including
  non-literal names like
  `defmodule Module.concat(...) do ... end`. Distinct from
  `current_module_segments/1`, which returns `nil` both for "not in a
  module" AND for "in a module with a non-literal name." Use this when
  you need to distinguish module code from expressions outside modules.
  """
  @spec in_module?(Scope.t()) :: boolean()
  def in_module?(%Scope{module_stack: stack}), do: ModuleStack.in_module?(stack)

  # ── Public traverse ──

  @doc """
  Walks `ast` with lexical-scope tracking. See the module docs for the
  API, callback timing, and opts.
  """
  @spec traverse(Macro.t(), user_state(), callback(), callback(), opts()) ::
          {user_state(), Scope.t()}
  def traverse(ast, user_state, on_enter, on_leave, opts \\ [])
      when is_function(on_enter, 3) and is_function(on_leave, 3) do
    options = %{
      lexical_scope_nodes:
        opts
        |> Keyword.get(:lexical_scope_nodes, @default_lexical_scope_nodes)
        |> List.wrap()
        |> MapSet.new(),
      track_quote: Keyword.get(opts, :track_quote, true),
      track_aliases_in_quote: Keyword.get(opts, :track_aliases_in_quote, false)
    }

    scope = %Scope{env_frames: [Aliases.base_env()]}

    {_ast, {final_user, final_scope}} =
      Macro.traverse(
        ast,
        {user_state, scope},
        fn node, acc -> enter_node(node, acc, on_enter, options) end,
        fn node, acc -> leave_node(node, acc, on_leave, options) end
      )

    {final_user, final_scope}
  end

  # ── Internals ──

  # Each `enter_node`/`leave_node` clause:
  #   1. updates `scope` for its node kind (push frames, capture aliases,
  #      adjust the quote depth, track module definitions)
  #   2. invokes the user callback with the updated scope
  # The order here matters: more-specific patterns (`:alias`, `:quote`,
  # module definitions, `{:do, _}`) take precedence over the generic
  # scope-key/arrow/extras patterns. A definition node only records a
  # pending module; the dedicated `{:do, _}` clause pushes and pops it
  # through `ModuleStack.enter_do/2` and `leave_do/2`, so it must stay
  # ahead of the generic `@scope_keys` clause. A node that matches multiple kinds (e.g. a `{form, _, _}`
  # that is also in `lexical_scope_nodes`) is handled by exactly one
  # clause - follow each clause's chain to confirm.

  # `capture_directive/3` applies the node to the head env; shapes that
  # create nothing (e.g. a bare `alias __MODULE__`) leave it unchanged.
  defp enter_node({directive, _, _} = node, {user, scope}, on_enter, options)
       when directive in [:alias, :require, :import] do
    scope = capture_directive(scope, node, options)
    {node, {on_enter.(node, scope, user), scope}}
  end

  defp enter_node({:quote, _, _} = node, {user, scope}, on_enter, %{track_quote: true} = _options) do
    scope = %{scope | quote_depth: scope.quote_depth + 1}
    {node, {on_enter.(node, scope, user), scope}}
  end

  defp enter_node({kind, _, _} = node, {user, scope}, on_enter, _options)
       when is_module_definition(kind) do
    {stack, segments} = ModuleStack.enter_definition(scope.module_stack, node, env(scope))
    scope = %{scope | module_stack: stack}
    declared_scope = %{scope | module_stack: ModuleStack.with_module(stack, segments)}
    {node, {on_enter.(node, declared_scope, user), scope}}
  end

  defp enter_node({:do, _body} = node, {user, scope}, on_enter, options) do
    scope = %{scope | module_stack: ModuleStack.enter_do(scope.module_stack, node)}
    enter_with_frame(node, user, scope, on_enter, options)
  end

  defp enter_node({scope_key, _body} = node, {user, scope}, on_enter, options)
       when scope_key in @scope_keys do
    enter_with_frame(node, user, scope, on_enter, options)
  end

  defp enter_node({:->, _, [_args, _body]} = node, {user, scope}, on_enter, options) do
    enter_with_frame(node, user, scope, on_enter, options)
  end

  defp enter_node(
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

  defp enter_node(node, {user, scope}, on_enter, _options) do
    {node, {on_enter.(node, scope, user), scope}}
  end

  # Leave: the callback runs with the current scope, then we pop. Mirrors
  # the enter clauses so each push has a matching pop.

  defp leave_node({directive, _, _} = node, {user, scope}, on_leave, _options)
       when directive in [:alias, :require, :import] do
    {node, {on_leave.(node, scope, user), scope}}
  end

  defp leave_node({:quote, _, _} = node, {user, scope}, on_leave, %{track_quote: true} = _options) do
    user = on_leave.(node, scope, user)
    scope = %{scope | quote_depth: max(scope.quote_depth - 1, 0)}
    {node, {user, scope}}
  end

  # A defmodule aliases its (first literal) name in the enclosing scope
  # for the rest of that body; the alias lands in the frame that is
  # current after the definition's do body has left the child module.
  defp leave_node({kind, _, _} = node, {user, scope}, on_leave, options)
       when is_module_definition(kind) do
    {stack, segments} = ModuleStack.leave_definition(scope.module_stack)
    scope = %{scope | module_stack: stack}
    declared_scope = %{scope | module_stack: ModuleStack.with_module(stack, segments)}
    user = on_leave.(node, declared_scope, user)

    {node, {user, register_defmodule_alias(scope, node, segments, options)}}
  end

  defp leave_node({:do, _body} = node, {user, scope}, on_leave, _options) do
    user = on_leave.(node, scope, user)
    scope = pop_env_frame(scope)
    scope = %{scope | module_stack: ModuleStack.leave_do(scope.module_stack, node)}
    {node, {user, scope}}
  end

  defp leave_node({scope_key, _body} = node, {user, scope}, on_leave, options)
       when scope_key in @scope_keys do
    leave_with_frame(node, user, scope, on_leave, options)
  end

  defp leave_node({:->, _, [_args, _body]} = node, {user, scope}, on_leave, options) do
    leave_with_frame(node, user, scope, on_leave, options)
  end

  defp leave_node(
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

  defp leave_node(node, {user, scope}, on_leave, _options) do
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
  # lexically visible stays visible; the pop discards the additions made
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

  defp register_defmodule_alias(%Scope{quote_depth: depth} = scope, _node, _child_absolute, %{
         track_quote: true,
         track_aliases_in_quote: false
       })
       when depth > 0, do: scope

  defp register_defmodule_alias(
         %Scope{env_frames: frames} = scope,
         node,
         child_absolute,
         _options
       ) do
    updated = Aliases.define_defmodule_alias(env(scope), node, child_absolute)

    case frames do
      [_head | rest] -> %{scope | env_frames: [updated | rest]}
      [] -> %{scope | env_frames: [updated]}
    end
  end
end
