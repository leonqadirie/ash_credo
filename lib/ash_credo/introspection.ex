defmodule AshCredo.Introspection do
  @moduledoc "Utilities for inspecting Ash DSL constructs in source AST."

  alias AshCredo.Introspection.{Aliases, AshCallScanner, LexicalScopeWalker}
  alias Credo.Code.Block
  alias Credo.SourceFile

  @action_entities ~w(create read update destroy action)a

  @doc "Returns all modules in the source file that directly `use Ash.Resource`."
  def resource_modules(source_file), do: modules_using(source_file, [:Ash, :Resource])

  @doc """
  Returns resource contexts for all resource modules in the source file, in
  file order. Each context now includes `:absolute_segments` - the full
  enclosing path of the resource's `defmodule` name (e.g. `[:MyApp, :Blog, :Post]`
  for a nested `defmodule Post` inside `defmodule MyApp.Blog`). This lets
  compiled-introspection checks resolve the resource to its runtime module atom.
  """
  def resource_contexts(source_file) do
    source_file
    |> all_modules_with_path()
    |> Enum.filter(fn {ast, _segs} -> module_uses?(ast, [:Ash, :Resource]) end)
    |> Enum.map(fn {ast, segs} -> resource_context_with_segments(ast, segs) end)
  end

  @doc """
  Walks every `defmodule` in a source file and returns
  `{module_ast, absolute_segments}` tuples in file order.

  `absolute_segments` is the concatenation of all enclosing `defmodule` names
  (top-to-bottom), so a `defmodule Bar` nested inside `defmodule Foo` is
  reported as `[:Foo, :Bar]`. Modules whose name is not a literal alias are
  reported with `absolute_segments: nil` (they still appear in the output).
  """
  def all_modules_with_path(source_file) do
    {%{out: out}, _scope} =
      source_file
      |> Credo.SourceFile.ast()
      |> LexicalScopeWalker.traverse(
        %{out: []},
        &collect_module_with_path/3,
        fn _node, _scope, acc -> acc end,
        track_module_stack: true
      )

    Enum.reverse(out)
  end

  # Only literal `defmodule Name do ... end` forms are emitted; non-literal
  # names (e.g. `defmodule unquote(name) do ... end`) are skipped to match
  # the pre-walker behaviour. The walker still tracks them on the module
  # stack so nested modules under a non-literal parent are reported as nil.
  defp collect_module_with_path(
         {:defmodule, _, [{:__aliases__, _, segs}, [do: _body]]} = ast,
         scope,
         state
       )
       when is_list(segs) do
    %{state | out: [{ast, LexicalScopeWalker.current_module_segments(scope)} | state.out]}
  end

  defp collect_module_with_path(_node, _scope, state), do: state

  defp resource_context_with_segments(module_ast, absolute_segments) do
    use_metadata = find_use(module_ast, [:Ash, :Resource])

    %{
      module_ast: module_ast,
      aliases: module_aliases(module_ast),
      use_line: use_metadata_line(use_metadata),
      use_opts: normalized_resource_use_opts(use_metadata),
      absolute_segments: absolute_segments
    }
  end

  @doc "Returns all modules in the source file that directly `use Ash.Domain`."
  def domain_modules(source_file), do: modules_using(source_file, [:Ash, :Domain])

  @doc "Returns true if the source file or module contains `use Ash.Resource`."
  def ash_resource?({:defmodule, _, _} = module_ast),
    do: module_uses?(module_ast, [:Ash, :Resource])

  def ash_resource?(source_file), do: resource_modules(source_file) != []

  @doc "Returns true if the AST node is a call to an `Ash.*` module (e.g. `Ash.read!/2`)."
  def ash_api_call?(ast, aliases \\ []), do: AshCallScanner.call?(ast, aliases)

  @doc "Returns all `Ash.*` API call AST nodes found in the source file, resolving aliases lexically."
  def ash_api_calls(source_file), do: AshCallScanner.calls(source_file)

  @doc """
  Returns all `Ash.*` API call AST nodes found in the source file together with
  their alias-expanded module segments as `{call_ast, expanded_module_segments}` tuples.
  """
  def ash_api_calls_with_module(source_file), do: AshCallScanner.calls_with_module(source_file)

  @doc """
  Returns all `Ash.*` API call AST nodes found in the source file together with
  their alias-expanded module segments, normalized call arguments, visible
  alias mappings, and straight-line local bindings.

  Each result is a map with keys `:call_ast`, `:expanded_module`, `:args`,
  `:aliases`, and `:bindings`.
  """
  def ash_api_calls_with_context(source_file), do: AshCallScanner.calls_with_context(source_file)

  @doc "Returns true if the source file or module contains `use Ash.Domain`."
  def ash_domain?({:defmodule, _, _} = module_ast), do: module_uses?(module_ast, [:Ash, :Domain])
  def ash_domain?(source_file), do: domain_modules(source_file) != []

  @doc "Returns the value of the resource's `data_layer` option, if present."
  def resource_data_layer(%{use_opts: opts}) when is_list(opts) do
    Keyword.get(opts, :data_layer)
  end

  def resource_data_layer(resource_or_source) do
    resource_or_source
    |> find_use([:Ash, :Resource])
    |> use_metadata_opt(:data_layer)
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
    module_ast
    |> find_use(module_aliases)
    |> normalized_use_opts()
  end

  def use_opts(source_file, module_aliases) do
    source_file
    |> find_use(module_aliases)
    |> normalized_use_opts()
  end

  @doc "Finds the AST node for a top-level DSL section (e.g. :attributes) in a module AST or resource/domain context."
  def find_dsl_section(%{module_ast: module_ast}, section_name) do
    find_dsl_section(module_ast, section_name)
  end

  def find_dsl_section({:defmodule, _, _} = module_ast, section_name) do
    Enum.find(module_body(module_ast), fn
      {^section_name, _meta, [[do: _body]]} -> true
      _ -> false
    end)
  end

  def find_dsl_section(%SourceFile{}, _section_name) do
    raise ArgumentError,
          "find_dsl_section/2 no longer accepts a SourceFile; pass a module AST or resource/domain context"
  end

  @doc "Checks if an entity call exists inside a section AST node."
  def has_entity?(nil, _), do: false

  def has_entity?({_section, _, [[do: _body]]} = section_ast, entity_name) do
    section_ast
    |> section_entries()
    |> Enum.any?(fn
      {^entity_name, _, _} -> true
      _ -> false
    end)
  end

  @doc "Returns all entity AST nodes of a given name within a section."
  def entities(nil, _), do: []

  def entities({_section, _, [[do: _body]]} = section_ast, entity_name) do
    filter_entities(section_entries(section_ast), entity_name)
  end

  @doc "Returns all explicit action entity AST nodes within an `actions` section."
  def action_entities(actions_ast, action_types \\ @action_entities) do
    entries = section_entries(actions_ast)

    Enum.flat_map(action_types, &filter_entities(entries, &1))
  end

  @doc "Returns the line number of a section's opening."
  def section_line({_name, meta, _}), do: meta[:line]
  def section_line(_), do: nil

  @doc "Returns the flattened list of top-level statements inside a module body."
  def module_body({:defmodule, _, _} = module_ast), do: do_block_entries(module_ast)
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
    use_metadata = find_use(module_ast, [:Ash, :Resource])

    %{
      module_ast: module_ast,
      aliases: module_aliases(module_ast),
      use_line: use_metadata_line(use_metadata),
      use_opts: normalized_resource_use_opts(use_metadata)
    }
  end

  def resource_context(_), do: nil

  @doc "Finds a top-level DSL section from a resource context."
  def resource_section(%{module_ast: _} = resource_context, section_name) do
    find_dsl_section(resource_context, section_name)
  end

  def resource_section(_, _section_name), do: nil

  @doc "Returns the best issue anchor line for a section, falling back to `line` and then `fallback`."
  def section_issue_line(section_ast, line \\ nil, fallback \\ 1) do
    section_line(section_ast) || line || fallback
  end

  @doc "Returns the best issue anchor line for a resource section, falling back to the `use` line and then `fallback`."
  def resource_issue_line(resource_context, section_ast \\ nil, fallback \\ 1)

  def resource_issue_line(%{use_line: use_line}, section_ast, fallback) do
    section_issue_line(section_ast, use_line, fallback)
  end

  def resource_issue_line(_resource_context, section_ast, fallback) do
    section_issue_line(section_ast, nil, fallback)
  end

  @doc "Returns top-level alias mappings in a module body, optionally only those declared before a given line."
  def module_aliases(module_ast, opts \\ []), do: Aliases.module_aliases(module_ast, opts)

  @doc "Expands module alias segments using alias mappings returned by module_aliases/2."
  def expand_alias(segments, aliases), do: Aliases.expand_alias(segments, aliases)

  @doc "Resolves a module reference within a module or resource context."
  def resolved_module_ref(ref_or_segments, module_or_context, opts \\ []) do
    Aliases.resolved_module_ref(ref_or_segments, module_or_context, opts)
  end

  @doc "Returns true if a module reference resolves to the given module segments."
  def module_ref?(ref_or_segments, module_or_context, target_segments, opts \\ []) do
    Aliases.module_ref?(ref_or_segments, module_or_context, target_segments, opts)
  end

  defp normalized_use_opts(%{opts: opts}) when is_list(opts), do: opts
  defp normalized_use_opts(nil), do: nil
  defp normalized_use_opts(_), do: []

  defp normalized_resource_use_opts(use_metadata) do
    case normalized_use_opts(use_metadata) do
      opts when is_list(opts) -> opts
      _ -> []
    end
  end

  defp use_metadata_line(%{line: line}) when is_integer(line), do: line
  defp use_metadata_line(_), do: nil

  defp use_metadata_opt(%{opts: opts}, key) when is_list(opts), do: Keyword.get(opts, key)
  defp use_metadata_opt(_, _key), do: nil

  defp section_entries(section_ast), do: do_block_entries(section_ast)

  defp do_block_entries(ast) do
    case Block.do_block_for(ast) do
      {:ok, _body} -> Block.calls_in_do_block(ast)
      nil -> []
    end
  end

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
    normalized_option_occurrences(ast, key, meta[:line])
  end

  def option_occurrences(_, _), do: []

  @doc "Returns normalized option values from inline opts and `do` blocks."
  def option_values(ast, key) do
    Enum.map(option_occurrences(ast, key), &elem(&1, 0))
  end

  defp normalized_option_occurrences(ast, key, line) do
    inline = inline_option_occurrences(ast, key, line)
    body = do_block_option_occurrences(ast, key)

    inline ++ body
  end

  defp inline_option_occurrences(ast, key, line) do
    case Keyword.fetch(entity_opts(ast), key) do
      {:ok, value} -> [{value, line}]
      :error -> []
    end
  end

  defp do_block_option_occurrences(ast, key) do
    ast
    |> do_block_entries()
    |> Enum.flat_map(&do_block_option_occurrence(&1, key))
  end

  defp do_block_option_occurrence({key, meta, [value]}, key), do: [{value, meta[:line]}]
  defp do_block_option_occurrence({key, meta, args}, key), do: [{args, meta[:line]}]
  defp do_block_option_occurrence(_, _), do: []

  @doc "Checks if a keyword option is set to a specific value in an entity's opts or do block."
  def entity_has_opt?(entity_ast, key, value) do
    Enum.any?(option_values(entity_ast, key), &(&1 == value))
  end

  @doc "Checks if a keyword option is declared inline or inside the entity's do block."
  def entity_has_opt_key?(entity_ast, key) do
    option_occurrences(entity_ast, key) != []
  end

  @doc "Returns the flattened list of statements inside a section body."
  def section_body({_section, _, [[do: _body]]} = section_ast), do: section_entries(section_ast)
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
    entries = section_entries(policies_ast)

    top_level =
      filter_entities(entries, :policy) ++ filter_entities(entries, :bypass)

    nested =
      entries
      |> filter_entities(:policy_group)
      |> Enum.flat_map(fn group ->
        group_body = do_block_entries(group)
        filter_entities(group_body, :policy) ++ filter_entities(group_body, :bypass)
      end)

    top_level ++ nested
  end

  @doc "Extracts the body statements from an entity's do block."
  def entity_body(ast), do: do_block_entries(ast)

  defp filter_entities(stmts, name) do
    Enum.filter(stmts, &match?({^name, _, _}, &1))
  end

  @doc "Searches inside an entity's `do` block for a call matching `call_name`."
  def find_in_body(ast, call_name),
    do: Enum.find(do_block_entries(ast), &match?({^call_name, _, _}, &1))

  @doc "Extracts the first atom argument from an entity call (e.g. action name)."
  def entity_name({_call, _meta, [name | _]}) when is_atom(name), do: name
  def entity_name(_), do: nil

  @doc "Returns the line number of a `use` call for the given module aliases."
  def find_use_line({:defmodule, _, _} = module_ast, module_aliases) do
    module_ast
    |> find_use(module_aliases)
    |> use_metadata_line()
  end

  def find_use_line(source_file, module_aliases) do
    source_file
    |> find_use(module_aliases)
    |> use_metadata_line()
  end

  defp modules_using(source_file, module_aliases) do
    source_file
    |> all_modules()
    |> Enum.filter(&module_uses?(&1, module_aliases))
  end

  defp find_use({:defmodule, _, _} = module_ast, module_aliases) do
    Enum.find_value(module_body(module_ast), fn
      {:use, meta, [{:__aliases__, _, ^module_aliases}, opts]} = use_ast when is_list(opts) ->
        %{module_ast: module_ast, use_ast: use_ast, line: meta[:line], opts: opts}

      {:use, meta, [{:__aliases__, _, ^module_aliases}]} = use_ast ->
        %{module_ast: module_ast, use_ast: use_ast, line: meta[:line], opts: []}

      _ ->
        nil
    end)
  end

  defp find_use(source_file, module_aliases) do
    source_file
    |> all_modules()
    |> Enum.find_value(&find_use(&1, module_aliases))
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
    not is_nil(find_use(module_ast, module_aliases))
  end
end
