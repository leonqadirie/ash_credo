defmodule AshCredo.Introspection do
  @moduledoc "Utilities for inspecting Ash DSL constructs in source AST."

  @action_entities ~w(create read update destroy action)a

  @doc "Returns all modules in the source file that directly `use Ash.Resource`."
  def resource_modules(source_file), do: modules_using(source_file, [:Ash, :Resource])

  @doc "Returns all modules in the source file that directly `use Ash.Domain`."
  def domain_modules(source_file), do: modules_using(source_file, [:Ash, :Domain])

  @doc "Returns true if the source file or module contains `use Ash.Resource`."
  def ash_resource?({:defmodule, _, _} = module_ast),
    do: module_uses?(module_ast, [:Ash, :Resource])

  def ash_resource?(source_file), do: resource_modules(source_file) != []

  @doc "Returns true if the AST node is a call to an `Ash.*` module (e.g. `Ash.read!/2`)."
  def ash_api_call?({{:., _, [{:__aliases__, _, [:Ash | _]}, _fun]}, _meta, _args}), do: true
  def ash_api_call?(_), do: false

  @doc "Returns all `Ash.*` API call AST nodes found in the source file."
  def ash_api_calls(source_file) do
    Credo.Code.prewalk(
      source_file,
      fn
        {_call, _meta, args} = ast, acc when is_list(args) ->
          if ash_api_call?(ast), do: {ast, [ast | acc]}, else: {ast, acc}

        ast, acc ->
          {ast, acc}
      end,
      []
    )
  end

  @doc "Returns true if the source file or module contains `use Ash.Domain`."
  def ash_domain?({:defmodule, _, _} = module_ast), do: module_uses?(module_ast, [:Ash, :Domain])
  def ash_domain?(source_file), do: domain_modules(source_file) != []

  @doc "Returns the value of the resource's `data_layer` option, if present."
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

  @doc "Finds the AST node for a top-level DSL section (e.g. :attributes)."
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

  @doc "Checks if a keyword option is set to a specific value in an entity's opts or do block."
  def entity_has_opt?(entity_ast, key, value) do
    in_inline_opts?(entity_ast, key, value) or in_body_opts?(entity_ast, key, value)
  end

  @doc "Checks if a keyword option is declared inline or inside the entity's do block."
  def entity_has_opt_key?(entity_ast, key) do
    Keyword.has_key?(entity_opts(entity_ast), key) or find_in_body(entity_ast, key) != nil
  end

  defp in_inline_opts?(entity_ast, key, value) do
    Keyword.get(entity_opts(entity_ast), key) == value
  end

  defp in_body_opts?(entity_ast, key, value) do
    case find_in_body(entity_ast, key) do
      {^key, _, [^value]} -> true
      _ -> false
    end
  end

  @doc "Returns the flattened list of statements inside a section body."
  def section_body({_section, _, [[do: body]]}), do: flatten_block(body)
  def section_body(nil), do: []

  @doc "Returns true if a section contains at least one DSL entry."
  def section_has_entries?(section_ast), do: section_body(section_ast) != []

  @doc "Returns true if an `actions` section defines any actions, explicitly or via defaults."
  def actions_defined?(actions_ast) do
    Enum.any?(@action_entities, &has_entity?(actions_ast, &1)) or
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

  @doc false
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
