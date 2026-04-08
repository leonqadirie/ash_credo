defmodule AshCredo.Introspection do
  @moduledoc "Utilities for inspecting Ash DSL constructs in source AST."

  @action_entities ~w(create read update destroy action)a
  @scope_keys ~w(do else after rescue catch)a
  @lexical_scope_nodes ~w(defmodule def defp defmacro defmacrop fn if unless case cond with try receive for)a
  @branch_scope_nodes ~w(if unless case cond with try receive for)a
  @function_scope_nodes ~w(def defp defmacro defmacrop)a

  @doc "Returns all modules in the source file that directly `use Ash.Resource`."
  def resource_modules(source_file), do: modules_using(source_file, [:Ash, :Resource])

  @doc "Returns all modules in the source file that directly `use Ash.Domain`."
  def domain_modules(source_file), do: modules_using(source_file, [:Ash, :Domain])

  @doc "Returns true if the source file or module contains `use Ash.Resource`."
  def ash_resource?({:defmodule, _, _} = module_ast),
    do: module_uses?(module_ast, [:Ash, :Resource])

  def ash_resource?(source_file), do: resource_modules(source_file) != []

  @doc "Returns true if the AST node is a call to an `Ash.*` module (e.g. `Ash.read!/2`)."
  def ash_api_call?(ast, aliases \\ [])

  def ash_api_call?({{:., _, [{:__aliases__, _, segments}, _fun]}, _meta, _args}, aliases) do
    match?([:Ash | _], expand_alias(segments, aliases))
  end

  def ash_api_call?(_, _), do: false

  @doc "Returns all `Ash.*` API call AST nodes found in the source file, resolving aliases lexically."
  def ash_api_calls(source_file) do
    ash_api_traverse(source_file, fn ast, _expanded, _state -> ast end)
  end

  @doc """
  Returns all `Ash.*` API call AST nodes found in the source file together with
  their alias-expanded module segments as `{call_ast, expanded_module_segments}` tuples.
  """
  def ash_api_calls_with_module(source_file) do
    ash_api_traverse(source_file, fn ast, expanded, _state -> {ast, expanded} end)
  end

  @doc """
  Returns all `Ash.*` API call AST nodes found in the source file together with
  their alias-expanded module segments, normalized call arguments, visible
  alias mappings, and straight-line local bindings.

  Each result is a map with keys `:call_ast`, `:expanded_module`, `:args`,
  `:aliases`, and `:bindings`.
  """
  def ash_api_calls_with_context(source_file) do
    ash_api_traverse(source_file, &build_ash_api_call_context/3, track_context?: true)
  end

  defp ash_api_traverse(source_file, collect_fn, opts \\ []) do
    {_, %{calls: calls}} =
      source_file
      |> Credo.SourceFile.ast()
      |> Macro.traverse(
        initial_ash_api_state(opts),
        &enter_ash_api_traversal_node(&1, &2, collect_fn),
        &leave_ash_api_traversal_node/2
      )

    Enum.reverse(calls)
  end

  defp enter_ash_api_traversal_node({scope_key, _body} = ast, state, _collect_fn)
       when scope_key in @scope_keys do
    {ast, push_alias_frame(state)}
  end

  defp enter_ash_api_traversal_node({:->, _, [_args, _body]} = ast, state, _collect_fn) do
    {ast, push_alias_frame(state)}
  end

  defp enter_ash_api_traversal_node({node_name, _, _} = ast, state, _collect_fn)
       when node_name in @lexical_scope_nodes do
    {ast, maybe_enter_ash_api_lexical_scope(state, node_name)}
  end

  defp enter_ash_api_traversal_node({:alias, _, _} = ast, state, _collect_fn) do
    {ast, put_aliases(state, alias_entries(ast))}
  end

  defp enter_ash_api_traversal_node(
         {:|>, _, [left, {{:., _, _}, meta, _}]} = ast,
         state,
         _collect_fn
       )
       when is_list(meta) do
    {ast, maybe_track_pipe_origin(state, meta, left)}
  end

  defp enter_ash_api_traversal_node(
         {{:., _, [module_ast, _fun_name]}, _meta, args} = call_ast,
         state,
         collect_fn
       )
       when is_list(args) do
    expanded_module = expanded_call_module(module_ast, current_aliases(state))

    if match?([:Ash | _], expanded_module) do
      {call_ast, record_ash_api_call(state, call_ast, expanded_module, collect_fn)}
    else
      {call_ast, state}
    end
  end

  defp enter_ash_api_traversal_node(ast, state, _collect_fn), do: {ast, state}

  defp leave_ash_api_traversal_node({scope_key, _body} = ast, state)
       when scope_key in @scope_keys do
    {ast, pop_alias_frame(state)}
  end

  defp leave_ash_api_traversal_node({:->, _, [_args, _body]} = ast, state) do
    {ast, pop_alias_frame(state)}
  end

  defp leave_ash_api_traversal_node({:=, _, [lhs, rhs]} = ast, state) do
    {ast, maybe_record_binding(state, lhs, rhs)}
  end

  defp leave_ash_api_traversal_node({node_name, _, _} = ast, state)
       when node_name in @lexical_scope_nodes do
    {ast, maybe_leave_ash_api_lexical_scope(state, node_name)}
  end

  defp leave_ash_api_traversal_node(ast, state), do: {ast, state}

  defp initial_ash_api_state(opts) do
    %{
      alias_frames: [[]],
      binding_frames: [],
      branch_depth: 0,
      calls: [],
      pipe_origins: %{},
      track_context?: Keyword.get(opts, :track_context?, false)
    }
  end

  defp record_ash_api_call(state, call_ast, expanded_module, collect_fn) do
    %{state | calls: [collect_fn.(call_ast, expanded_module, state) | state.calls]}
  end

  defp build_ash_api_call_context(
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
      bindings: current_bindings(state)
    }
  end

  defp maybe_enter_ash_api_lexical_scope(%{track_context?: false} = state, _node_name), do: state

  defp maybe_enter_ash_api_lexical_scope(state, node_name) do
    state
    |> push_alias_frame()
    |> maybe_push_binding_frame(node_name)
    |> maybe_enter_branch_scope(node_name)
  end

  defp maybe_leave_ash_api_lexical_scope(%{track_context?: false} = state, _node_name), do: state

  defp maybe_leave_ash_api_lexical_scope(state, node_name) do
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

  defp pop_alias_frame(%{alias_frames: [_current, []]} = state) do
    %{state | alias_frames: [[]]}
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
    expand_alias(segments, aliases)
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

  @doc "Returns true if the source file or module contains `use Ash.Domain`."
  def ash_domain?({:defmodule, _, _} = module_ast), do: module_uses?(module_ast, [:Ash, :Domain])
  def ash_domain?(source_file), do: domain_modules(source_file) != []

  @doc "Returns the value of the resource's `data_layer` option, if present."
  def resource_data_layer(%{use_opts: opts}) when is_list(opts) do
    Keyword.get(opts, :data_layer)
  end

  def resource_data_layer({:defmodule, _, _} = module_ast) do
    case use_opts(module_ast, [:Ash, :Resource]) do
      opts when is_list(opts) -> Keyword.get(opts, :data_layer)
      _ -> nil
    end
  end

  def resource_data_layer(source_file) do
    case first_module_using(source_file, [:Ash, :Resource]) do
      nil -> nil
      module_ast -> resource_data_layer(module_ast)
    end
  end

  @doc "Returns true if the resource uses `data_layer: :embedded`."
  def embedded_resource?(resource_or_source),
    do: resource_data_layer(resource_or_source) == :embedded

  @doc "Returns true if the resource declares a non-embedded data layer in `use Ash.Resource`."
  def has_data_layer?(resource_or_source) do
    case resource_data_layer(resource_or_source) do
      nil -> false
      :embedded -> false
      _ -> true
    end
  end

  @doc "Extracts keyword options from a `use` call matching the given module aliases."
  def use_opts({:defmodule, _, _} = module_ast, module_aliases) do
    Enum.find_value(module_body(module_ast), nil, fn
      {:use, _, [{:__aliases__, _, ^module_aliases}, opts]} when is_list(opts) ->
        opts

      {:use, _, [{:__aliases__, _, ^module_aliases}]} ->
        []

      _ ->
        nil
    end)
  end

  def use_opts(source_file, module_aliases) do
    case first_module_using(source_file, module_aliases) do
      nil -> nil
      module_ast -> use_opts(module_ast, module_aliases)
    end
  end

  @doc "Iterates resource modules, finds a DSL section, and flat-maps results through `fun`."
  def flat_map_dsl_section(source_file, section, fun) do
    source_file
    |> resource_modules()
    |> Enum.flat_map(fn module_ast ->
      module_ast |> find_dsl_section(section) |> fun.()
    end)
  end

  @doc "Finds the AST node for a top-level DSL section (e.g. :attributes)."
  def find_dsl_section(%{module_ast: module_ast}, section_name) do
    find_dsl_section(module_ast, section_name)
  end

  def find_dsl_section({:defmodule, _, _} = module_ast, section_name) do
    Enum.find(module_body(module_ast), fn
      {^section_name, _meta, [[do: _body]]} -> true
      _ -> false
    end)
  end

  def find_dsl_section(source_file, section_name) do
    source_file
    |> all_modules()
    |> Enum.find_value(&find_dsl_section(&1, section_name))
  end

  @doc "Checks if an entity call exists inside a section AST node."
  def has_entity?({_section, _, [[do: body]]}, entity_name) do
    body
    |> flatten_block()
    |> Enum.any?(fn
      {^entity_name, _, _} -> true
      _ -> false
    end)
  end

  def has_entity?(nil, _), do: false

  @doc "Returns all entity AST nodes of a given name within a section."
  def entities({_section, _, [[do: body]]}, entity_name) do
    body
    |> flatten_block()
    |> Enum.filter(&match?({^entity_name, _, _}, &1))
  end

  def entities(nil, _), do: []

  @doc "Returns all explicit action entity AST nodes within an `actions` section."
  def action_entities(actions_ast, action_types \\ @action_entities) do
    Enum.flat_map(action_types, &entities(actions_ast, &1))
  end

  @doc "Returns the line number of a section's opening."
  def section_line({_name, meta, _}), do: meta[:line]
  def section_line(_), do: nil

  @doc "Returns the flattened list of top-level statements inside a module body."
  def module_body({:defmodule, _, [_name, [do: body]]}), do: flatten_block(body)
  def module_body(_), do: []

  @doc "Returns the line span of a module AST, if end metadata is available."
  def module_line_count({:defmodule, meta, _}) do
    with start_line when is_integer(start_line) <- meta[:line],
         end_meta when is_list(end_meta) <- meta[:end],
         end_line when is_integer(end_line) <- end_meta[:line] do
      end_line - start_line + 1
    else
      _ -> nil
    end
  end

  def module_line_count(_), do: nil

  @doc "Returns shared resource metadata for a resource module."
  def resource_context({:defmodule, _, _} = module_ast) do
    %{
      module_ast: module_ast,
      aliases: module_aliases(module_ast),
      use_line: find_use_line(module_ast, [:Ash, :Resource]),
      use_opts: normalized_use_opts(module_ast)
    }
  end

  def resource_context(_), do: nil

  @doc "Returns top-level alias mappings in a module body, optionally only those declared before a given line."
  def module_aliases(module_ast, opts \\ [])

  def module_aliases({:defmodule, _, _} = module_ast, opts) do
    before_line = Keyword.get(opts, :before_line)

    Enum.reduce(module_body(module_ast), [], fn
      {:alias, meta, _} = alias_ast, aliases ->
        if alias_before?(meta[:line], before_line) do
          alias_entries(alias_ast) ++ aliases
        else
          aliases
        end

      _stmt, aliases ->
        aliases
    end)
  end

  def module_aliases(_, _opts), do: []

  @doc "Expands module alias segments using alias mappings returned by module_aliases/2."
  def expand_alias(segments, aliases) when is_list(segments) and is_list(aliases) do
    matches =
      Enum.filter(aliases, fn
        {alias_segments, _target_segments} -> List.starts_with?(segments, alias_segments)
        _ -> false
      end)

    case Enum.max_by(
           matches,
           fn {alias_segments, _target_segments} -> length(alias_segments) end,
           fn -> nil end
         ) do
      {alias_segments, target_segments} ->
        target_segments ++ Enum.drop(segments, length(alias_segments))

      nil ->
        segments
    end
  end

  def expand_alias(other, _aliases), do: other

  @doc "Resolves a module reference within a module or resource context."
  def resolved_module_ref(ref_or_segments, module_or_context, opts \\ [])

  def resolved_module_ref({:__aliases__, meta, segments}, module_or_context, opts) do
    resolved_module_ref(
      segments,
      module_or_context,
      Keyword.put_new(opts, :before_line, meta[:line])
    )
  end

  def resolved_module_ref(segments, module_or_context, opts) when is_list(segments) do
    expand_alias(segments, context_aliases(module_or_context, opts))
  end

  def resolved_module_ref(other, _module_or_context, _opts), do: other

  @doc "Returns true if a module reference resolves to the given module segments."
  def module_ref?(ref_or_segments, module_or_context, target_segments, opts \\ []) do
    resolved_module_ref(ref_or_segments, module_or_context, opts) == target_segments
  end

  defp alias_before?(_alias_line, nil), do: true

  defp alias_before?(alias_line, before_line)
       when is_integer(alias_line) and is_integer(before_line), do: alias_line < before_line

  defp alias_before?(_alias_line, _before_line), do: false

  defp alias_entries({:alias, _, [{:__aliases__, _, target_segments}]}) do
    [{default_alias(target_segments), target_segments}]
  end

  defp alias_entries({:alias, _, [{:__aliases__, _, target_segments}, opts]})
       when is_list(opts) do
    case Keyword.get(opts, :as) do
      {:__aliases__, _, alias_segments} -> [{alias_segments, target_segments}]
      _ -> [{default_alias(target_segments), target_segments}]
    end
  end

  defp alias_entries(
         {:alias, _, [{{:., _, [{:__aliases__, _, prefix_segments}, :{}]}, _, suffix_aliases}]}
       )
       when is_list(suffix_aliases) do
    grouped_alias_entries(prefix_segments, suffix_aliases)
  end

  defp alias_entries(
         {:alias, _,
          [{{:., _, [{:__aliases__, _, prefix_segments}, :{}]}, _, suffix_aliases}, opts]}
       )
       when is_list(suffix_aliases) and is_list(opts) do
    grouped_alias_entries(prefix_segments, suffix_aliases)
  end

  defp alias_entries(_), do: []

  defp grouped_alias_entries(prefix_segments, suffix_aliases) do
    Enum.flat_map(suffix_aliases, fn
      {:__aliases__, _, suffix_segments} ->
        target_segments = prefix_segments ++ suffix_segments
        [{default_alias(target_segments), target_segments}]

      _ ->
        []
    end)
  end

  defp default_alias(target_segments), do: [List.last(target_segments)]

  defp normalized_use_opts(module_ast) do
    case use_opts(module_ast, [:Ash, :Resource]) do
      opts when is_list(opts) -> opts
      _ -> []
    end
  end

  defp context_aliases(%{module_ast: module_ast, aliases: aliases}, opts) do
    case Keyword.get(opts, :before_line) do
      nil -> aliases
      _ -> module_aliases(module_ast, opts)
    end
  end

  defp context_aliases({:defmodule, _, _} = module_ast, opts),
    do: module_aliases(module_ast, opts)

  defp context_aliases(_, _opts), do: []

  @doc "Extracts keyword options from an entity AST call."
  def entity_opts({_name, _meta, args}) when is_list(args) do
    args
    |> Enum.reverse()
    |> Enum.find_value([], &extract_entity_opts/1)
  end

  def entity_opts(_), do: []

  defp extract_entity_opts(kw) when is_list(kw) do
    if Keyword.keyword?(kw), do: drop_do_opt(kw)
  end

  defp extract_entity_opts(_), do: nil

  defp drop_do_opt(kw) do
    case Keyword.delete(kw, :do) do
      [] -> nil
      opts -> opts
    end
  end

  @doc "Returns normalized option values with line numbers from inline opts and `do` blocks."
  def option_occurrences({_name, meta, _args} = ast, key) do
    inline = inline_option_occurrences(ast, key, meta[:line])
    body = body_option_occurrences(ast, key)

    inline ++ body
  end

  def option_occurrences(_, _), do: []

  @doc "Returns normalized option values from inline opts and `do` blocks."
  def option_values(ast, key) do
    Enum.map(option_occurrences(ast, key), &elem(&1, 0))
  end

  defp inline_option_occurrences(ast, key, line) do
    case Keyword.fetch(entity_opts(ast), key) do
      {:ok, value} -> [{value, line}]
      :error -> []
    end
  end

  defp body_option_occurrences(ast, key) do
    ast
    |> entity_body()
    |> Enum.flat_map(&body_option_occurrence(&1, key))
  end

  defp body_option_occurrence({key, meta, [value]}, key), do: [{value, meta[:line]}]
  defp body_option_occurrence({key, meta, args}, key), do: [{args, meta[:line]}]
  defp body_option_occurrence(_, _), do: []

  @doc "Checks if a keyword option is set to a specific value in an entity's opts or do block."
  def entity_has_opt?(entity_ast, key, value) do
    Enum.any?(option_values(entity_ast, key), &(&1 == value))
  end

  @doc "Checks if a keyword option is declared inline or inside the entity's do block."
  def entity_has_opt_key?(entity_ast, key) do
    option_occurrences(entity_ast, key) != []
  end

  @doc "Returns the flattened list of statements inside a section body."
  def section_body({_section, _, [[do: body]]}), do: flatten_block(body)
  def section_body(nil), do: []

  @doc "Returns true if a section contains at least one DSL entry."
  def section_has_entries?(section_ast), do: section_body(section_ast) != []

  @doc "Returns true if an `actions` section defines any actions, explicitly or via defaults."
  def actions_defined?(actions_ast) do
    action_entities(actions_ast) != [] or
      Enum.any?(entities(actions_ast, :defaults), &(default_action_entries(&1) != []))
  end

  @doc "Extracts the action entries declared in a `defaults [...]` call."
  def default_action_entries({:defaults, _, [entries]}) when is_list(entries), do: entries
  def default_action_entries(_), do: []

  @doc "Checks whether a `defaults` call sets an action type to a specific value."
  def default_action_has_value?(defaults_ast, action_type, value) do
    defaults_ast
    |> default_action_entries()
    |> Enum.any?(fn
      {^action_type, ^value} -> true
      _ -> false
    end)
  end

  @doc "Returns all `policy` and `bypass` entities from a policies section, including inside `policy_group`."
  def policy_entities(policies_ast) do
    top_level =
      entities(policies_ast, :policy) ++ entities(policies_ast, :bypass)

    nested =
      policies_ast
      |> entities(:policy_group)
      |> Enum.flat_map(fn group ->
        group_body = entity_body(group)
        filter_entities(group_body, :policy) ++ filter_entities(group_body, :bypass)
      end)

    top_level ++ nested
  end

  @doc "Extracts the body statements from an entity's do block."
  def entity_body({_name, _meta, args}) when is_list(args) do
    Enum.find_value(args, [], fn
      [do: body] -> flatten_block(body)
      _ -> nil
    end)
  end

  def entity_body(_), do: []

  defp filter_entities(stmts, name) do
    Enum.filter(stmts, &match?({^name, _, _}, &1))
  end

  @doc "Searches inside an entity's `do` block for a call matching `call_name`."
  def find_in_body({_name, _meta, args}, call_name) when is_list(args) do
    Enum.find_value(args, fn
      [do: body] ->
        body
        |> flatten_block()
        |> Enum.find(&match?({^call_name, _, _}, &1))

      _ ->
        nil
    end)
  end

  def find_in_body(_, _), do: nil

  @doc "Extracts the first atom argument from an entity call (e.g. action name)."
  def entity_name({_call, _meta, [name | _]}) when is_atom(name), do: name
  def entity_name(_), do: nil

  @doc "Returns the line number of a `use` call for the given module aliases."
  def find_use_line({:defmodule, _, _} = module_ast, module_aliases) do
    Enum.find_value(module_body(module_ast), fn
      {:use, meta, [{:__aliases__, _, ^module_aliases} | _]} -> meta[:line]
      _ -> nil
    end)
  end

  def find_use_line(source_file, module_aliases) do
    case first_module_using(source_file, module_aliases) do
      nil -> nil
      module_ast -> find_use_line(module_ast, module_aliases)
    end
  end

  @doc "Normalizes a block AST node into a flat list of statements."
  def flatten_block({:__block__, _, stmts}), do: stmts
  def flatten_block(other), do: [other]

  defp modules_using(source_file, module_aliases) do
    source_file
    |> all_modules()
    |> Enum.filter(&module_uses?(&1, module_aliases))
  end

  defp first_module_using(source_file, module_aliases) do
    source_file
    |> modules_using(module_aliases)
    |> List.first()
  end

  defp all_modules(source_file) do
    source_file
    |> Credo.Code.prewalk(
      fn
        {:defmodule, _, [_name, [do: _body]]} = ast, acc ->
          {ast, [ast | acc]}

        ast, acc ->
          {ast, acc}
      end,
      []
    )
    |> Enum.reverse()
  end

  defp module_uses?(module_ast, module_aliases) do
    Enum.any?(module_body(module_ast), fn
      {:use, _, [{:__aliases__, _, ^module_aliases} | _]} -> true
      _ -> false
    end)
  end
end
