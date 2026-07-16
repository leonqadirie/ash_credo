defmodule AshCredo.Introspection do
  @moduledoc """
  Resource- and domain-level introspection of Ash DSL constructs in source AST:
  resource/domain detection, resource contexts, DSL sections, entities, options,
  and policies.

  This module owns only those DSL/resource semantics. Lower-level tools live in
  sibling modules under `AshCredo.Introspection.*` and are called directly by
  consumers; there is intentionally no single facade re-exporting them:

    * `Aliases` - `Macro.Env`-backed directive application and resolution
    * `AshCallScanner` / `AshCallResolver` / `AshCallSite` - `Ash.*` API call detection
    * `RemoteBangScanner` - `Mod.fun!/n` call sites
    * `Block` - do-block and module-body AST access
    * `LexicalScopeWalker` - scope-aware traversal
    * `ResourceContext` / `UseMetadata` - shared data structs
    * `Compiled` - compile-time/runtime metadata, and the sole gateway for it.
      The boundary (only `Compiled` may call Ash's runtime introspection
      modules) is enforced structurally by the `calls.forbidden` policy in
      `.reach.exs`.

  Do not add thin pass-through wrappers here for those modules; call the owning
  module directly so dependencies stay honest.

  ## Why two introspection worlds

  Checks draw on two complementary sources, and both are load-bearing:

    * **Source AST** (this module and its `*Scanner`/`*Walker` siblings) works
      without compiling the host project and carries source positions, which
      diagnostics anchor to. It is the only way to find *call sites* -
      `Ash.read!(...)` scattered across a codebase - because compiled
      introspection knows resource definitions, not where they are called.
    * **`Compiled`** reads the fully-resolved DSL state of loaded modules,
      including attributes/actions/policies that Spark transformers and
      extensions contribute and that the source AST never sees.

  Source-AST lexical resolution is built on real `Macro.Env` values:
  `Aliases` applies `alias`/`require`/`import` nodes to an env via
  `Macro.Env.define_alias/4` and `define_require/4`, and resolves
  references via `Macro.Env.expand_alias/4` and `Macro.Env.required?/2`
  (Elixir 1.17+ APIs added for exactly this kind of tooling). The walkers
  (`LexicalScopeWalker`, `AshCallScanner`) own only what an env cannot
  know from source: scope-frame push/pop for blocks and branches, quote
  suppression, and the `defmodule` module stack that substitutes
  `__MODULE__` targets at declaration time. `Credo.Code.Module.aliases/1`
  remains unsuitable - it collects alias names flat across a module,
  dropping `as:` renames and lexical scoping.

  Each file is parsed once (Credo caches `SourceFile.ast/1`) and each derived
  view is memoized on `{filename, source_hash/1}` - `resource_contexts/1` here,
  `AshCallResolver.sites/1` next door - so the several specialised walkers each
  run once per file, not once per consuming check.
  """

  alias AshCredo.Cache

  alias AshCredo.Introspection.{
    Block,
    LexicalScopeWalker,
    ResourceContext,
    UseMetadata
  }

  alias Credo.SourceFile

  @action_entities ~w(create read update destroy action)a

  @resource_contexts_key_tag {__MODULE__, :resource_contexts}

  @doc "Returns all modules in the source file that directly `use Ash.Resource`."
  def resource_modules(source_file), do: modules_using(source_file, [:Ash, :Resource])

  @doc """
  Returns resource contexts for all resource modules in the source file, in
  file order. Each context now includes `:absolute_segments` - the full
  enclosing path of the resource's `defmodule` name (e.g. `[:MyApp, :Blog, :Post]`
  for a nested `defmodule Post` inside `defmodule MyApp.Blog`). This lets
  compiled-introspection checks resolve the resource to its runtime module atom.

  Memoized in the run-scoped cache keyed on filename plus source hash, so the
  underlying scope-tracking traversal runs once per file per Credo run instead
  of once per enabled check.
  """
  def resource_contexts(source_file) do
    key = {@resource_contexts_key_tag, source_file.filename, source_hash(source_file)}

    Cache.memoize(key, fn -> compute_resource_contexts(source_file) end)
  end

  defp compute_resource_contexts(source_file) do
    source_file
    |> all_modules_with_path()
    |> Enum.filter(fn {ast, _segs} -> module_uses?(ast, [:Ash, :Resource]) end)
    |> Enum.map(fn {ast, segs} -> resource_context_with_segments(ast, segs) end)
  end

  @doc """
  Hashes a source file's content for use in content-addressed cache keys.
  Filename alone is not a safe key: distinct `SourceFile`s regularly share a
  filename with different content (most prominently in this project's own
  test suite).
  """
  def source_hash(source_file), do: :erlang.md5(SourceFile.source(source_file))

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
        fn _node, _scope, acc -> acc end
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

    %ResourceContext{
      module_ast: module_ast,
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

  @doc "Returns true if the source file or module contains `use Ash.Domain`."
  def ash_domain?({:defmodule, _, _} = module_ast), do: module_uses?(module_ast, [:Ash, :Domain])
  def ash_domain?(source_file), do: domain_modules(source_file) != []

  @doc "Returns the value of the resource's `data_layer` option, if present."
  def resource_data_layer(%ResourceContext{use_opts: opts}) when is_list(opts) do
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

  @doc """
  Finds the AST node of the first top-level DSL section (e.g. :attributes)
  in a module AST or resource/domain context.

  Suitable only for line anchoring: Spark merges multiple same-named
  top-level blocks into one section, so entries may live in later blocks.
  Use `find_dsl_sections/2` to enumerate entries.
  """
  def find_dsl_section(%ResourceContext{module_ast: module_ast}, section_name) do
    find_dsl_section(module_ast, section_name)
  end

  def find_dsl_section({:defmodule, _, _} = module_ast, section_name) do
    module_ast
    |> find_dsl_sections(section_name)
    |> List.first()
  end

  def find_dsl_section(%SourceFile{}, _section_name) do
    raise ArgumentError,
          "find_dsl_section/2 no longer accepts a SourceFile; pass a module AST or resource/domain context"
  end

  @doc """
  Finds the AST nodes of all same-named top-level DSL sections (e.g.
  :attributes) in a module AST or resource/domain context, in source order.

  Spark merges multiple same-named top-level blocks into one section, so
  entry enumeration must consider every block, not just the first.
  """
  def find_dsl_sections(%ResourceContext{module_ast: module_ast}, section_name) do
    find_dsl_sections(module_ast, section_name)
  end

  def find_dsl_sections({:defmodule, _, _} = module_ast, section_name) do
    Enum.filter(Block.module_body(module_ast), fn
      {^section_name, _meta, [[do: _body]]} -> true
      _ -> false
    end)
  end

  def find_dsl_sections(%SourceFile{}, _section_name) do
    raise ArgumentError,
          "find_dsl_sections/2 does not accept a SourceFile; pass a module AST or resource/domain context"
  end

  @doc "Checks if an entity call exists inside a section AST node or list of section blocks."
  def has_entity?(nil, _), do: false

  def has_entity?(section_asts, entity_name) when is_list(section_asts) do
    Enum.any?(section_asts, &has_entity?(&1, entity_name))
  end

  def has_entity?({_section, _, [[do: _body]]} = section_ast, entity_name) do
    section_ast
    |> section_entries()
    |> Enum.any?(fn
      {^entity_name, _, _} -> true
      _ -> false
    end)
  end

  @doc "Returns all entity AST nodes of a given name within a section or list of section blocks."
  def entities(nil, _), do: []

  def entities(section_asts, entity_name) when is_list(section_asts) do
    Enum.flat_map(section_asts, &entities(&1, entity_name))
  end

  def entities({_section, _, [[do: _body]]} = section_ast, entity_name) do
    filter_entities(section_entries(section_ast), entity_name)
  end

  @doc "Returns all explicit action entity AST nodes within an `actions` section or list of section blocks."
  def action_entities(actions_ast, action_types \\ @action_entities) do
    entries = section_entries(actions_ast)

    Enum.flat_map(action_types, &filter_entities(entries, &1))
  end

  @doc """
  Returns the explicit action entities whose `accept` option is honored at
  runtime: creates, updates, and soft destroys. Ash's `DefaultAccept`
  transformer resets `accept` to `[]` on hard destroys (`soft?` false), so
  an accept list there is dead configuration rather than an input surface.
  """
  def accepting_action_entities(actions_ast) do
    action_entities(actions_ast, ~w(create update)a) ++
      soft_destroy_entities(actions_ast)
  end

  @doc """
  Returns true when some action in the section can inherit
  `default_accept`: an accepting action (create, update, soft destroy)
  without its own `accept` option, or a bare `:create`/`:update` atom in
  `defaults`. Ash's DefaultAccept transformer applies the default only to
  those - explicit accept lists override it, and hard destroys and reads
  never take one.

  Non-literal shapes count as inheritors: `defaults @actions` may expand
  to inheriting entries and `soft? @soft` may compile a destroy soft, so
  silencing a warning based on an unreadable value would hide a real
  mass-assignment surface.
  """
  def default_accept_inheritors?(actions_ast) do
    inheriting_accepting_entity?(actions_ast) or
      inheriting_defaults_entry?(actions_ast) or
      potentially_soft_destroy_inheritor?(actions_ast)
  end

  defp inheriting_accepting_entity?(actions_ast) do
    actions_ast
    |> accepting_action_entities()
    |> Enum.any?(&(not entity_has_opt_key?(&1, :accept)))
  end

  defp inheriting_defaults_entry?(actions_ast) do
    Enum.any?(entities(actions_ast, :defaults), fn
      {:defaults, _, [entries]} when is_list(entries) ->
        Enum.any?(entries, &(&1 in [:create, :update]))

      _non_literal ->
        true
    end)
  end

  # A destroy whose `soft?` value is anything but the literal `false` may
  # compile soft and then inherits like an update, unless it carries its
  # own accept list.
  defp potentially_soft_destroy_inheritor?(actions_ast) do
    actions_ast
    |> action_entities([:destroy])
    |> Enum.any?(fn entity ->
      entity_has_opt_key?(entity, :soft?) and
        not entity_has_opt?(entity, :soft?, false) and
        not entity_has_opt_key?(entity, :accept)
    end)
  end

  defp soft_destroy_entities(actions_ast) do
    actions_ast
    |> action_entities([:destroy])
    |> Enum.filter(&entity_has_opt?(&1, :soft?, true))
  end

  @doc "Returns the line number of a section's opening."
  def section_line({_name, meta, _}), do: meta[:line]
  def section_line(_), do: nil

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

  @doc "Finds the first top-level DSL section from a resource context. Suitable only for line anchoring; use `resource_sections/2` to enumerate entries."
  def resource_section(%ResourceContext{} = resource_context, section_name) do
    find_dsl_section(resource_context, section_name)
  end

  def resource_section(_, _section_name), do: nil

  @doc "Finds all same-named top-level DSL section blocks from a resource context, in source order."
  def resource_sections(%ResourceContext{} = resource_context, section_name) do
    find_dsl_sections(resource_context, section_name)
  end

  def resource_sections(_, _section_name), do: []

  @doc "Returns the best issue anchor line for a section, falling back to `line` and then `fallback`."
  def section_issue_line(section_ast, line \\ nil, fallback \\ 1) do
    section_line(section_ast) || line || fallback
  end

  @doc "Returns the best issue anchor line for a module's `actions` section, falling back to the `use` line and then line 1."
  def actions_section_line(module_ast, %ResourceContext{use_line: use_line}) do
    module_ast
    |> find_dsl_section(:actions)
    |> section_issue_line(use_line, 1)
  end

  @doc "Returns the best issue anchor line for a resource section, falling back to the `use` line and then `fallback`."
  def resource_issue_line(resource_context, section_ast \\ nil, fallback \\ 1)

  def resource_issue_line(%ResourceContext{use_line: use_line}, section_ast, fallback) do
    section_issue_line(section_ast, use_line, fallback)
  end

  def resource_issue_line(_resource_context, section_ast, fallback) do
    section_issue_line(section_ast, nil, fallback)
  end

  defp normalized_use_opts(%UseMetadata{opts: opts}), do: opts
  defp normalized_use_opts(nil), do: nil

  defp normalized_resource_use_opts(use_metadata) do
    case normalized_use_opts(use_metadata) do
      opts when is_list(opts) -> opts
      _ -> []
    end
  end

  defp use_metadata_line(%UseMetadata{line: line}) when is_integer(line), do: line
  defp use_metadata_line(_), do: nil

  defp use_metadata_opt(%UseMetadata{opts: opts}, key), do: Keyword.get(opts, key)
  defp use_metadata_opt(_, _key), do: nil

  defp section_entries(section_asts) when is_list(section_asts) do
    Enum.flat_map(section_asts, &section_entries/1)
  end

  defp section_entries(section_ast), do: Block.do_block_entries(section_ast)

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

  @doc "Returns normalized option values with line numbers from inline opts and `do` blocks. Accepts a single AST node or a list of nodes (e.g. duplicate section blocks)."
  def option_occurrences({_name, meta, _args} = ast, key) do
    normalized_option_occurrences(ast, key, meta[:line])
  end

  def option_occurrences(asts, key) when is_list(asts) do
    Enum.flat_map(asts, &option_occurrences(&1, key))
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
    |> Block.do_block_entries()
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

  @doc "Returns the flattened list of statements inside a section body or across a list of section blocks."
  def section_body({_section, _, [[do: _body]]} = section_ast), do: section_entries(section_ast)
  def section_body(section_asts) when is_list(section_asts), do: section_entries(section_asts)
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

  @doc "Returns all `policy` and `bypass` entities from a policies section, including inside `policy_group`s at any depth."
  def policy_entities(policies_ast) do
    policies_ast
    |> policy_entities_with_conditions()
    |> Enum.map(&elem(&1, 0))
  end

  @doc """
  Returns `{entity, inherited_conditions}` pairs for all `policy` and
  `bypass` entities in a policies section, in source order.

  `policy_group`s are descended at any depth (`policy_group` is declared
  `recursive_as: :policies` in Ash) and their condition arguments are
  accumulated, outermost first: Ash adds the group conditions to each
  policy the group contains, so `inherited_conditions` is part of every
  contained policy's effective condition.
  """
  def policy_entities_with_conditions(policies_ast) do
    policies_ast
    |> section_entries()
    |> collect_policy_entities([])
  end

  defp collect_policy_entities(entries, inherited) do
    Enum.flat_map(entries, fn
      {kind, _, _} = entity when kind in [:policy, :bypass] ->
        [{entity, inherited}]

      {:policy_group, _, args} = group ->
        conditions = Enum.reject(List.wrap(args), &do_block?/1)
        collect_policy_entities(Block.do_block_entries(group), inherited ++ conditions)

      _other ->
        []
    end)
  end

  defp do_block?([{:do, _} | _]), do: true
  defp do_block?(_), do: false

  @doc "Extracts the body statements from an entity's do block."
  def entity_body(ast), do: Block.do_block_entries(ast)

  defp filter_entities(stmts, name) do
    Enum.filter(stmts, &match?({^name, _, _}, &1))
  end

  @doc "Searches inside an entity's `do` block for a call matching `call_name`."
  def find_in_body(ast, call_name),
    do: Enum.find(Block.do_block_entries(ast), &match?({^call_name, _, _}, &1))

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
    Enum.find_value(Block.module_body(module_ast), fn
      {:use, meta, [{:__aliases__, _, ^module_aliases}, opts]} when is_list(opts) ->
        %UseMetadata{line: meta[:line], opts: opts}

      {:use, meta, [{:__aliases__, _, ^module_aliases}]} ->
        %UseMetadata{line: meta[:line], opts: []}

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
