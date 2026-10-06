defmodule AshCredo.Introspection.ModuleStack do
  @moduledoc """
  Tracks the identity of nested `defmodule`, `defprotocol`, and
  `defimpl` definitions during a `Macro.traverse/4` walk. Both
  `AshCredo.Introspection.LexicalScopeWalker` and
  `AshCredo.Introspection.AshCallScanner` hold one, so every consumer
  agrees on which module encloses a node.

  A definition's name and options belong to the enclosing module; the
  declared module is current only inside its `do` body. The traversal
  calls `enter_definition/3` and `leave_definition/1` on the definition
  node, and `enter_do/2` and `leave_do/2` on every `{:do, _}` node.
  `enter_definition/3` resolves the identity once and keeps it on a
  pending entry until the definition's own `do` body arrives.
  """

  alias AshCredo.Introspection.Aliases

  @definition_kinds [:defmodule, :defprotocol, :defimpl]

  @typedoc "Absolute module segments, or `nil` when the name is unknown."
  @type segments :: [atom()] | nil

  @type t :: %__MODULE__{modules: [segments()], definitions: [map()]}

  defstruct modules: [], definitions: []

  @doc "Returns `true` for the call names that define a module."
  defguard is_module_definition(kind) when kind in @definition_kinds

  @doc "Returns the innermost enclosing module's segments, or `nil`."
  @spec current(t()) :: segments()
  def current(%__MODULE__{modules: [top | _]}), do: top
  def current(%__MODULE__{modules: []}), do: nil

  @doc "Returns `true` inside any module body, named or not."
  @spec in_module?(t()) :: boolean()
  def in_module?(%__MODULE__{modules: modules}), do: modules != []

  @doc """
  Returns `stack` with `segments` as the current module. The walker
  hands this view to definition callbacks so they see the declared
  module's identity.
  """
  @spec with_module(t(), segments()) :: t()
  def with_module(%__MODULE__{modules: modules} = stack, segments),
    do: %{stack | modules: [segments | modules]}

  @doc """
  Resolves the definition's identity through `env` and the enclosing
  module, then records it as pending. Returns the stack and the
  resolved segments.
  """
  @spec enter_definition(t(), Macro.t(), Macro.Env.t()) :: {t(), segments()}
  def enter_definition(%__MODULE__{} = stack, definition, %Macro.Env{} = env) do
    segments = definition_segments(definition, stack, env)
    {body, skip} = body_node(definition)
    pending = %{segments: segments, body: body, skip: skip, state: :pending}
    {%{stack | definitions: [pending | stack.definitions]}, segments}
  end

  @doc """
  Pops the innermost definition. Returns the stack and the definition's
  segments.
  """
  @spec leave_definition(t()) :: {t(), segments()}
  def leave_definition(%__MODULE__{definitions: [%{segments: segments} | rest]} = stack),
    do: {%{stack | definitions: rest}, segments}

  def leave_definition(%__MODULE__{} = stack), do: {stack, nil}

  @doc """
  Pushes the pending module when `do_node` is its definition's body.
  Other `do` blocks leave the stack unchanged.
  """
  @spec enter_do(t(), Macro.t()) :: t()
  def enter_do(
        %__MODULE__{definitions: [%{state: :pending, body: body} = pending | rest]} = stack,
        do_node
      )
      when do_node === body do
    case pending do
      %{skip: 0, segments: segments} ->
        %{
          stack
          | modules: [segments | stack.modules],
            definitions: [%{pending | state: :body} | rest]
        }

      %{skip: skip} ->
        %{stack | definitions: [%{pending | skip: skip - 1} | rest]}
    end
  end

  def enter_do(%__MODULE__{} = stack, _do_node), do: stack

  @doc "Pops the module when `do_node` closes the current definition's body."
  @spec leave_do(t(), Macro.t()) :: t()
  def leave_do(
        %__MODULE__{
          modules: [_ | modules],
          definitions: [%{state: :body, body: body} = pending | rest]
        } = stack,
        do_node
      )
      when do_node === body do
    %{stack | modules: modules, definitions: [%{pending | state: :closed} | rest]}
  end

  def leave_do(%__MODULE__{} = stack, _do_node), do: stack

  # ── Identity ──

  defp definition_segments({:defimpl, _, [protocol | option_lists]}, stack, env) do
    implementation_segments(protocol, option_lists, stack, env)
  end

  defp definition_segments(definition, stack, env) do
    parent =
      case stack.modules do
        [top | _] -> top
        [] -> []
      end

    definition
    |> Aliases.defmodule_literal_segments()
    |> Aliases.absolute_module_segments(parent, env)
  end

  defp implementation_segments(protocol, option_lists, stack, env) do
    if Enum.all?(option_lists, &Keyword.keyword?/1) do
      opts = Enum.reduce(option_lists, [], &Keyword.merge(&2, &1))
      target = Keyword.get(opts, :for, {:__MODULE__, [], nil})

      with {:ok, protocol_segments} <- literal_module_segments(protocol, stack, env),
           {:ok, target_segments} <- literal_module_segments(target, stack, env) do
        protocol_segments ++ target_segments
      else
        _ -> nil
      end
    end
  end

  defp literal_module_segments({:__aliases__, _, segments}, stack, env),
    do: Aliases.resolve_alias(segments, env, current(stack))

  defp literal_module_segments({:__MODULE__, _, _}, stack, _env) do
    case current(stack) do
      [_ | _] = segments -> {:ok, segments}
      _ -> :error
    end
  end

  defp literal_module_segments(module, _stack, _env)
       when is_atom(module) and not is_nil(module) do
    {:ok, Aliases.elixir_module_segments(module) || [module]}
  end

  defp literal_module_segments([target], stack, env),
    do: literal_module_segments(target, stack, env)

  defp literal_module_segments(_dynamic, _stack, _env), do: :error

  # ── Body detection ──

  # The body is the `{:do, _}` element of the definition's last option
  # list. `skip` counts structurally equal `{:do, _}` nodes that the
  # traversal visits before it, so a name such as `if x, do: y` cannot
  # open the module early.
  defp body_node({:defimpl, _, [protocol, target_opts, opts]}),
    do: body_in_options([protocol, target_opts], opts)

  defp body_node({kind, _, [name, opts]}) when is_module_definition(kind),
    do: body_in_options([name], opts)

  defp body_node(_definition), do: {nil, 0}

  defp body_in_options(leading_args, opts) when is_list(opts) do
    case Enum.split_while(opts, &(not match?({:do, _}, &1))) do
      {preceding, [body | _]} -> {body, occurrences(leading_args ++ preceding, body)}
      {_opts, []} -> {nil, 0}
    end
  end

  defp body_in_options(_leading_args, _opts), do: {nil, 0}

  defp occurrences(term, target) when term === target, do: 1

  defp occurrences({left, right}, target),
    do: occurrences(left, target) + occurrences(right, target)

  defp occurrences({form, _meta, args}, target),
    do: occurrences(form, target) + occurrences(args, target)

  defp occurrences(list, target) when is_list(list),
    do: Enum.reduce(list, 0, &(occurrences(&1, target) + &2))

  defp occurrences(_term, _target), do: 0
end
