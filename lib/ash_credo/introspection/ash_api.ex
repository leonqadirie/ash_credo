defmodule AshCredo.Introspection.AshApi do
  @moduledoc false

  alias AshCredo.Introspection.Aliases

  @scope_keys ~w(do else after rescue catch)a
  @lexical_scope_nodes ~w(defmodule def defp defmacro defmacrop fn if unless case cond with try receive for)a
  @branch_scope_nodes ~w(if unless case cond with try receive for)a
  @function_scope_nodes ~w(def defp defmacro defmacrop)a

  @doc "Returns true if the AST node is a call to an `Ash.*` module."
  def call?(ast, aliases \\ [])

  def call?({{:., _, [{:__aliases__, _, segments}, _fun]}, _meta, _args}, aliases) do
    match?([:Ash | _], Aliases.expand_alias(segments, aliases))
  end

  def call?(_, _), do: false

  @doc "Returns all `Ash.*` API call AST nodes, resolving aliases lexically."
  def calls(source_file) do
    traverse(source_file, fn ast, _expanded, _state -> ast end)
  end

  @doc "Returns `{call_ast, expanded_module_segments}` tuples for all `Ash.*` calls."
  def calls_with_module(source_file) do
    traverse(source_file, fn ast, expanded, _state -> {ast, expanded} end)
  end

  @doc "Returns enriched call maps with `:call_ast`, `:expanded_module`, `:args`, `:aliases`, and `:bindings`."
  def calls_with_context(source_file) do
    traverse(source_file, &build_call_context/3, track_context?: true)
  end

  defp traverse(source_file, collect_fn, opts \\ []) do
    {_, %{calls: calls}} =
      source_file
      |> Credo.SourceFile.ast()
      |> Macro.traverse(
        initial_state(opts),
        &enter_node(&1, &2, collect_fn),
        &leave_node/2
      )

    Enum.reverse(calls)
  end

  defp enter_node({scope_key, _body} = ast, state, _collect_fn) when scope_key in @scope_keys do
    {ast, push_alias_frame(state)}
  end

  defp enter_node({:->, _, [_args, _body]} = ast, state, _collect_fn) do
    {ast, push_alias_frame(state)}
  end

  defp enter_node({node_name, _, _} = ast, state, _collect_fn)
       when node_name in @lexical_scope_nodes do
    {ast, maybe_enter_lexical_scope(state, node_name)}
  end

  defp enter_node({:alias, _, _} = ast, state, _collect_fn) do
    {ast, put_aliases(state, Aliases.alias_entries(ast))}
  end

  defp enter_node({:|>, _, [left, {{:., _, _}, meta, _}]} = ast, state, _collect_fn)
       when is_list(meta) do
    {ast, maybe_track_pipe_origin(state, meta, left)}
  end

  defp enter_node({:defmodule, _, _} = ast, state, _collect_fn) do
    {ast,
     state
     |> maybe_enter_lexical_scope(:defmodule)
     |> push_module_stack(ast)}
  end

  defp enter_node({{:., _, [module_ast, _fun_name]}, _meta, args} = call_ast, state, collect_fn)
       when is_list(args) do
    expanded_module = expanded_call_module(module_ast, current_aliases(state))

    if match?([:Ash | _], expanded_module) do
      {call_ast, record_call(state, call_ast, expanded_module, collect_fn)}
    else
      {call_ast, state}
    end
  end

  defp enter_node(ast, state, _collect_fn), do: {ast, state}

  defp leave_node({scope_key, _body} = ast, state) when scope_key in @scope_keys do
    {ast, pop_alias_frame(state)}
  end

  defp leave_node({:->, _, [_args, _body]} = ast, state) do
    {ast, pop_alias_frame(state)}
  end

  defp leave_node({:=, _, [lhs, rhs]} = ast, state) do
    {ast, maybe_record_binding(state, lhs, rhs)}
  end

  defp leave_node({:defmodule, _, _} = ast, state) do
    {ast,
     state
     |> pop_module_stack()
     |> maybe_leave_lexical_scope(:defmodule)}
  end

  defp leave_node({node_name, _, _} = ast, state) when node_name in @lexical_scope_nodes do
    {ast, maybe_leave_lexical_scope(state, node_name)}
  end

  defp leave_node(ast, state), do: {ast, state}

  defp initial_state(opts) do
    %{
      alias_frames: [[]],
      binding_frames: [],
      branch_depth: 0,
      calls: [],
      pipe_origins: %{},
      module_stack: [],
      track_context?: Keyword.get(opts, :track_context?, false)
    }
  end

  defp record_call(state, call_ast, expanded_module, collect_fn) do
    %{state | calls: [collect_fn.(call_ast, expanded_module, state) | state.calls]}
  end

  defp build_call_context(
         {{:., _, [_module_ast, _fun_name]}, call_meta, args} = call_ast,
         expanded_module,
         state
       )
       when is_list(args) do
    %{
      call_ast: call_ast,
      expanded_module: expanded_module,
      args: normalized_call_args(args, call_meta, state.pipe_origins),
      aliases: current_aliases(state),
      bindings: current_bindings(state),
      enclosing_module_segments: current_module_segments(state)
    }
  end

  defp push_module_stack(state, ast) do
    literal = defmodule_literal_segments(ast)

    parent_absolute =
      case state.module_stack do
        [top | _] -> top || []
        [] -> []
      end

    absolute = if literal, do: parent_absolute ++ literal
    %{state | module_stack: [absolute | state.module_stack]}
  end

  defp pop_module_stack(%{module_stack: [_ | rest]} = state), do: %{state | module_stack: rest}
  defp pop_module_stack(state), do: state

  defp current_module_segments(%{module_stack: [top | _]}), do: top
  defp current_module_segments(%{module_stack: []}), do: nil

  defp defmodule_literal_segments({:defmodule, _, [{:__aliases__, _, segs}, _]})
       when is_list(segs), do: segs

  defp defmodule_literal_segments(_), do: nil

  defp maybe_enter_lexical_scope(%{track_context?: false} = state, _node_name), do: state

  defp maybe_enter_lexical_scope(state, node_name) do
    state
    |> push_alias_frame()
    |> maybe_push_binding_frame(node_name)
    |> maybe_enter_branch_scope(node_name)
  end

  defp maybe_leave_lexical_scope(%{track_context?: false} = state, _node_name), do: state

  defp maybe_leave_lexical_scope(state, node_name) do
    state
    |> maybe_leave_branch_scope(node_name)
    |> maybe_pop_binding_frame(node_name)
    |> pop_alias_frame()
  end

  defp maybe_track_pipe_origin(%{track_context?: false} = state, _meta, _left), do: state

  defp maybe_track_pipe_origin(state, meta, left) do
    key = call_key(meta)
    %{state | pipe_origins: Map.put(state.pipe_origins, key, left)}
  end

  defp push_alias_frame(state) do
    update_in(state.alias_frames, &[[] | &1])
  end

  defp pop_alias_frame(%{alias_frames: [_current | frames]} = state) do
    %{state | alias_frames: frames}
  end

  defp put_aliases(%{alias_frames: [current | frames]} = state, new_aliases) do
    %{state | alias_frames: [new_aliases ++ current | frames]}
  end

  defp current_aliases(%{alias_frames: frames}) do
    Enum.concat(frames)
  end

  defp normalized_call_args(args, call_meta, pipe_origins) do
    case Map.get(pipe_origins, call_key(call_meta)) do
      nil -> args
      piped_arg -> [piped_arg | args]
    end
  end

  defp call_key(meta), do: {meta[:line], meta[:column] || 0}

  defp expanded_call_module({:__aliases__, _, segments}, aliases) when is_list(segments) do
    Aliases.expand_alias(segments, aliases)
  end

  defp expanded_call_module(_module_ast, _aliases), do: []

  defp maybe_push_binding_frame(state, node_name) when node_name in @function_scope_nodes do
    update_in(state.binding_frames, &[%{} | &1])
  end

  defp maybe_push_binding_frame(state, :fn) do
    update_in(state.binding_frames, &[current_bindings(state) | &1])
  end

  defp maybe_push_binding_frame(state, _node_name), do: state

  defp maybe_pop_binding_frame(%{binding_frames: [_current | frames]} = state, node_name)
       when node_name in @function_scope_nodes or node_name == :fn do
    %{state | binding_frames: frames}
  end

  defp maybe_pop_binding_frame(state, _node_name), do: state

  defp current_bindings(%{binding_frames: [bindings | _]}), do: bindings
  defp current_bindings(_state), do: %{}

  defp maybe_enter_branch_scope(state, node_name) when node_name in @branch_scope_nodes do
    update_in(state.branch_depth, &(&1 + 1))
  end

  defp maybe_enter_branch_scope(state, _node_name), do: state

  defp maybe_leave_branch_scope(state, node_name) when node_name in @branch_scope_nodes do
    update_in(state.branch_depth, &max(&1 - 1, 0))
  end

  defp maybe_leave_branch_scope(state, _node_name), do: state

  defp maybe_record_binding(%{binding_frames: []} = state, _lhs, _rhs), do: state

  defp maybe_record_binding(%{branch_depth: branch_depth} = state, _lhs, _rhs)
       when branch_depth > 0 do
    state
  end

  defp maybe_record_binding(state, lhs, rhs) do
    binding_keys =
      lhs
      |> binding_keys()
      |> Enum.reject(fn {name, _ctx} -> name == :_ end)

    update_in(state.binding_frames, fn
      [bindings | rest] ->
        new_bindings =
          Enum.reduce(binding_keys, bindings, fn key, acc ->
            Map.put(acc, key, rhs)
          end)

        [new_bindings | rest]

      [] ->
        []
    end)
  end

  defp binding_keys(lhs) do
    lhs
    |> do_binding_keys()
    |> Enum.uniq()
  end

  defp do_binding_keys({:^, _, [_inner]}), do: []

  defp do_binding_keys({name, _, ctx}) when is_atom(name) and (is_atom(ctx) or is_nil(ctx)) do
    [{name, ctx}]
  end

  defp do_binding_keys({_form, _meta, args}) when is_list(args) do
    Enum.flat_map(args, &do_binding_keys/1)
  end

  defp do_binding_keys(list) when is_list(list) do
    Enum.flat_map(list, &do_binding_keys/1)
  end

  defp do_binding_keys(_), do: []
end
