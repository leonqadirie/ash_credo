defmodule AshCredo.Introspection do
  @moduledoc "Utilities for inspecting Ash DSL constructs in source AST."

  @action_entities ~w(create read update destroy action)a

  @doc "Returns true if the source file contains `use Ash.Resource`."
  def ash_resource?(source_file) do
    Credo.Code.prewalk(
      source_file,
      fn
        {:use, _, [{:__aliases__, _, [:Ash, :Resource]} | _]} = ast, _acc ->
          {ast, true}

        ast, acc ->
          {ast, acc}
      end,
      false
    )
  end

  @doc "Returns true if the source file contains `use Ash.Domain`."
  def ash_domain?(source_file) do
    Credo.Code.prewalk(
      source_file,
      fn
        {:use, _, [{:__aliases__, _, [:Ash, :Domain]} | _]} = ast, _acc ->
          {ast, true}

        ast, acc ->
          {ast, acc}
      end,
      false
    )
  end

  @doc "Returns the value of the resource's `data_layer` option, if present."
  def resource_data_layer(source_file) do
    case use_opts(source_file, [:Ash, :Resource]) do
      opts when is_list(opts) -> Keyword.get(opts, :data_layer)
      _ -> nil
    end
  end

  @doc "Returns true if the resource uses `data_layer: :embedded`."
  def embedded_resource?(source_file), do: resource_data_layer(source_file) == :embedded

  @doc "Returns true if the resource declares a non-embedded data layer in `use Ash.Resource`."
  def has_data_layer?(source_file) do
    case resource_data_layer(source_file) do
      nil -> false
      :embedded -> false
      _ -> true
    end
  end

  @doc "Extracts keyword options from a `use` call matching the given module aliases."
  def use_opts(source_file, module_aliases) do
    Credo.Code.prewalk(
      source_file,
      fn
        {:use, _, [{:__aliases__, _, ^module_aliases}, opts]} = ast, _acc when is_list(opts) ->
          {ast, opts}

        {:use, _, [{:__aliases__, _, ^module_aliases}]} = ast, _acc ->
          {ast, []}

        ast, acc ->
          {ast, acc}
      end,
      nil
    )
  end

  @doc "Finds the AST node for a top-level DSL section (e.g. :attributes)."
  def find_dsl_section(source_file, section_name) do
    Credo.Code.prewalk(
      source_file,
      fn
        {^section_name, _meta, [[do: _body]]} = ast, nil ->
          {ast, ast}

        ast, acc ->
          {ast, acc}
      end,
      nil
    )
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
  def find_entities({_section, _, [[do: body]]}, entity_name) do
    body
    |> flatten_block()
    |> Enum.filter(&match?({^entity_name, _, _}, &1))
  end

  def find_entities(nil, _), do: []

  @doc "Returns the line number of a section's opening."
  def section_line({_name, meta, _}), do: meta[:line]
  def section_line(_), do: nil

  @doc "Extracts keyword options from an entity AST call."
  def entity_opts({_name, _meta, args}) when is_list(args) do
    case List.last(args) do
      [{_key, _val} | _] = kw -> Keyword.delete(kw, :do)
      _ -> []
    end
  end

  def entity_opts(_), do: []

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
      Enum.any?(find_entities(actions_ast, :defaults), &(default_action_entries(&1) != []))
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
  def find_all_policy_entities(policies_ast) do
    top_level =
      find_entities(policies_ast, :policy) ++ find_entities(policies_ast, :bypass)

    nested =
      policies_ast
      |> find_entities(:policy_group)
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
  def find_use_line(source_file, module_aliases) do
    Credo.Code.prewalk(
      source_file,
      fn
        {:use, meta, [{:__aliases__, _, ^module_aliases} | _]} = ast, nil ->
          {ast, meta[:line]}

        ast, acc ->
          {ast, acc}
      end,
      nil
    )
  end

  @doc false
  def flatten_block({:__block__, _, stmts}), do: stmts
  def flatten_block(other), do: [other]
end
