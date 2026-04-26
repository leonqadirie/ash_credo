defmodule AshCredo.Introspection.Compiled do
  @moduledoc """
  Introspection that reads **compiled BEAM metadata** - a wrapper around
  `Ash.Resource.Info` and `Ash.Domain.Info`.

  Sibling of `AshCredo.Introspection` (AST-level) and
  `AshCredo.Introspection.AshCallScanner` (AST-level Ash call discovery). This is
  the module that reaches for the compiled artifact: it loads target
  modules on demand, reads their DSL metadata through Ash's own
  introspection API, and caches the results per-module in `:persistent_term`
  so repeated lookups during a single `mix credo` run are cheap.

  The cache lives in `:persistent_term` rather than ETS because Credo
  dispatches each check × source_file pair into its own short-lived
  Task.Supervised process. An ETS table would be owned by whichever task
  created it first and would vanish the moment that task exited, crashing
  every sibling task that still held the table name. `:persistent_term` is
  process-independent and survives arbitrary task churn. Each cached entry
  is a brand-new key (we never overwrite), so the well-known
  `:persistent_term` GC penalty does not apply here.

  Checks in `AshCredo` that need authoritative metadata about a referenced
  module (its domain, its actions, its code interfaces, whether it is even
  an Ash resource) call into this module instead of scanning source AST.

  ## Error modes

    * `{:error, :ash_missing}` - Ash itself is not loaded in the VM running
      Credo. This happens when `ash_credo` is used in a project that does not
      depend on Ash. Callers should treat this as "Ash-aware checks are a
      no-op in this project" and emit a single diagnostic.
    * `{:error, :not_loadable}` - `Code.ensure_compiled/1` returned an error,
      typically because the host project has not been compiled yet. The
      caller should surface a "run `mix compile` first" hint.
    * `{:error, :not_a_resource}` - the module loaded successfully but is
      not an Ash resource. Checks targeting resources should silently skip.
  """

  # Ash is not a runtime dependency of ash_credo - users bring their own.
  # Suppress compile-time warnings for the remote calls below; they are guarded
  # at runtime by `ash_available?/0`.
  alias Ash.Type.NewType
  alias AshCredo.Cache

  @compile {:no_warn_undefined,
            [
              Ash.Resource.Info,
              Ash.Domain.Info,
              Ash.Policy.Info,
              Ash.Policy.Authorizer,
              Ash.Type,
              Ash.Type.NewType
            ]}

  # Tags namespace per-key entries inside the shared cache table.
  @cache_key_tag {__MODULE__, :cache}
  @domain_refs_key_tag {__MODULE__, :domain_refs}
  @macros_key_tag {__MODULE__, :macros}
  @ash_available_key {__MODULE__, :ash_available?}
  @ash_missing_warned_key {__MODULE__, :ash_missing_warned}
  @not_loadable_warned_key_tag {__MODULE__, :not_loadable_warned}

  # Behaviours that mark a module as an Ash resource auxiliary - i.e. a
  # module that gets attached to a resource via `change`, `preparation`,
  # `validation`, `calculate`, or a `manual` action option. These modules
  # don't themselves declare a `:domain`, but conventionally belong to the
  # domain of the resource that references them.
  @ash_callback_behaviours [
    Ash.Resource.Change,
    Ash.Resource.Preparation,
    Ash.Resource.Validation,
    Ash.Resource.Calculation,
    Ash.Resource.ManualCreate,
    Ash.Resource.ManualUpdate,
    Ash.Resource.ManualDestroy,
    Ash.Resource.ManualRead
  ]

  @type info_map :: %{
          resource?: boolean(),
          domain: module() | nil,
          interfaces: [struct()],
          actions: [struct()],
          attributes: [struct()],
          primary_key: [atom()],
          identities: [struct()],
          authorizers: [module()],
          policies: [struct()]
        }

  @type error ::
          :ash_missing | :not_loadable | :not_a_resource | :not_a_domain | :unknown_action

  @doc """
  Returns `true` if `Ash.Resource.Info` is loadable in the current VM.

  Cached after the first call so subsequent calls are essentially free.
  """
  @spec ash_available?() :: boolean()
  def ash_available? do
    case Cache.get(@ash_available_key, :unknown) do
      :unknown ->
        available? =
          Code.ensure_loaded?(Ash.Resource.Info) and Code.ensure_loaded?(Ash.Domain.Info)

        Cache.put(@ash_available_key, available?)
        available?

      cached ->
        cached
    end
  end

  @doc """
  Returns a map of introspection facts about `module`, or an error tuple.

  The map has keys `:resource?`, `:domain`, `:interfaces`, `:actions`.
  Results are cached per-module.
  """
  @spec inspect_module(module()) :: {:ok, info_map()} | {:error, error()}
  def inspect_module(module) when is_atom(module) do
    if ash_available?() do
      case cache_fetch(module) do
        {:ok, cached} ->
          cached

        :miss ->
          result = do_inspect(module)
          cache_put(module, result)
          result
      end
    else
      {:error, :ash_missing}
    end
  end

  @doc "Returns the resource's declared domain, or `nil` if it has none."
  @spec domain(module()) :: {:ok, module() | nil} | {:error, error()}
  def domain(module) do
    case inspect_module(module) do
      {:ok, %{domain: domain}} -> {:ok, domain}
      error -> error
    end
  end

  @doc "Returns the resource's list of `%Ash.Resource.Interface{}` entries."
  @spec interfaces(module()) :: {:ok, [struct()]} | {:error, error()}
  def interfaces(module) do
    case inspect_module(module) do
      {:ok, %{interfaces: interfaces}} -> {:ok, interfaces}
      error -> error
    end
  end

  @doc "Returns the resource's list of action structs (fully resolved)."
  @spec actions(module()) :: {:ok, [struct()]} | {:error, error()}
  def actions(module) do
    case inspect_module(module) do
      {:ok, %{actions: actions}} -> {:ok, actions}
      error -> error
    end
  end

  @doc "Returns the resource's list of attribute structs (fully resolved)."
  @spec attributes(module()) :: {:ok, [struct()]} | {:error, error()}
  def attributes(module) do
    case inspect_module(module) do
      {:ok, %{attributes: attributes}} -> {:ok, attributes}
      error -> error
    end
  end

  @doc "Returns the resource's primary key attribute names as a list of atoms."
  @spec primary_key(module()) :: {:ok, [atom()]} | {:error, error()}
  def primary_key(module) do
    case inspect_module(module) do
      {:ok, %{primary_key: keys}} -> {:ok, keys}
      error -> error
    end
  end

  @doc "Returns the resource's identity entries (each with `:name` and `:keys`)."
  @spec identities(module()) :: {:ok, [struct()]} | {:error, error()}
  def identities(module) do
    case inspect_module(module) do
      {:ok, %{identities: identities}} -> {:ok, identities}
      error -> error
    end
  end

  @doc "Returns the resource's list of authorizer modules (e.g. `Ash.Policy.Authorizer`)."
  @spec authorizers(module()) :: {:ok, [module()]} | {:error, error()}
  def authorizers(module) do
    case inspect_module(module) do
      {:ok, %{authorizers: authorizers}} -> {:ok, authorizers}
      error -> error
    end
  end

  @doc """
  Returns the resource's policy entries from `Ash.Policy.Info.policies/1`.
  Returns `[]` for resources without `Ash.Policy.Authorizer` declared.
  """
  @spec policies(module()) :: {:ok, [struct()]} | {:error, error()}
  def policies(module) do
    case inspect_module(module) do
      {:ok, %{policies: policies}} -> {:ok, policies}
      error -> error
    end
  end

  @doc """
  Returns the list of resources registered inside `domain`'s `resources do
  ... end` block, or an error tuple if `domain` is not a loaded Ash.Domain.
  """
  @spec domain_resources(module()) :: {:ok, [module()]} | {:error, error()}
  def domain_resources(module) when is_atom(module) do
    cond do
      not ash_available?() -> {:error, :ash_missing}
      not match?({:module, _}, Code.ensure_compiled(module)) -> {:error, :not_loadable}
      not domain?(module) -> {:error, :not_a_domain}
      true -> {:ok, Ash.Domain.Info.resources(module)}
    end
  end

  @doc """
  Returns the action struct for `action_name` on `module`, or
  `{:error, :unknown_action}` if the action is not defined.
  """
  @spec action(module(), atom()) :: {:ok, struct()} | {:error, error()}
  def action(module, action_name) when is_atom(action_name) do
    case inspect_module(module) do
      {:ok, _info} ->
        case Ash.Resource.Info.action(module, action_name) do
          nil -> {:error, :unknown_action}
          action -> {:ok, action}
        end

      error ->
        error
    end
  end

  @doc """
  Returns the set of macro names defined by `module` (read from
  `module.__info__(:macros)`), or `{:error, :not_loadable}` if the module
  cannot be loaded. Cached per-module in `:persistent_term`.

  Unlike `inspect_module/1`, this does not require the target to be an Ash
  resource. It works for any compiled Elixir module and exists so checks can
  ask "which functions on this module are macros?" without hardcoding a list
  that drifts from reality when upstream adds or renames macros.

  Used by `Warning.MissingMacroDirective` to resolve its configured
  `macro_modules` list to exact macro sets per module.
  """
  @spec macros(module()) :: {:ok, MapSet.t(atom())} | {:error, :not_loadable}
  def macros(module) when is_atom(module) do
    key = {@macros_key_tag, module}

    case Cache.get(key, :miss) do
      :miss ->
        result = do_macros(module)
        Cache.put(key, result)
        result

      cached ->
        cached
    end
  end

  defp do_macros(module) do
    with {:module, ^module} <- Code.ensure_compiled(module),
         true <- function_exported?(module, :__info__, 1) do
      macros =
        module.__info__(:macros)
        |> MapSet.new(fn {name, _arity} -> name end)

      {:ok, macros}
    else
      _ -> {:error, :not_loadable}
    end
  rescue
    _ -> {:error, :not_loadable}
  end

  @doc "Returns `true` if `module` is an Ash resource loadable in this VM."
  @spec resource?(module()) :: boolean()
  def resource?(module) when is_atom(module) do
    match?({:ok, %{resource?: true}}, inspect_module(module))
  end

  @doc """
  Returns `true` if `module` is an Ash domain loadable in this VM.

  Determined by the `spark_is/0` function that Spark DSL modules inject.
  Not cached - the check is cheap (already-loaded module attribute read).
  """
  @spec domain?(module()) :: boolean()
  def domain?(module) when is_atom(module) do
    ash_available?() and
      match?({:module, _}, Code.ensure_compiled(module)) and
      function_exported?(module, :spark_is, 0) and
      module.spark_is() == Ash.Domain
  end

  @doc """
  Returns `true` if `module` implements one of the Ash resource auxiliary
  behaviours (`Ash.Resource.Change`, `Preparation`, `Validation`,
  `Calculation`, or any of the `Manual*` action behaviours).

  Detected by inspecting the module's `:behaviour` attribute, populated by
  `use Ash.Resource.Change` and siblings at compile time.
  """
  @spec ash_callback_module?(module()) :: boolean()
  def ash_callback_module?(module) when is_atom(module) do
    with true <- ash_available?(),
         {:module, _} <- Code.ensure_compiled(module) do
      module_behaviours(module)
      |> Enum.any?(&(&1 in @ash_callback_behaviours))
    else
      _ -> false
    end
  end

  defp module_behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  rescue
    _ -> []
  end

  @doc """
  Given a resource's `interfaces` list (as returned by `interfaces/1`) and an
  action name, returns the `%Ash.Resource.Interface{}` whose action matches
  (either via the explicit `:action` field or by name equality when the
  interface uses its own name as the action). Returns `nil` if no match.
  """
  @spec find_interface([struct()], atom()) :: struct() | nil
  def find_interface(interfaces, action_name) when is_list(interfaces) and is_atom(action_name) do
    Enum.find(interfaces, fn iface ->
      (iface.action || iface.name) == action_name
    end)
  end

  @doc """
  Returns the domain-level interface definition for `resource`'s `action_name`
  declared inside `domain`'s `resources do ... end` block, or `nil` if no
  matching definition exists. `domain == nil` is handled gracefully.
  """
  @spec domain_interface(module() | nil, module(), atom()) :: struct() | nil
  def domain_interface(nil, _resource, _action_name), do: nil

  def domain_interface(domain, resource, action_name)
      when is_atom(domain) and is_atom(resource) and is_atom(action_name) do
    with true <- ash_available?(),
         {:module, _} <- Code.ensure_compiled(domain),
         ref when not is_nil(ref) <- resource_reference(domain, resource) do
      Enum.find(ref.definitions, fn def ->
        (def.action || def.name) == action_name
      end)
    else
      _ -> nil
    end
  end

  @doc """
  Returns all domain-level interface definitions (as `%Ash.Resource.Interface{}`)
  declared for `resource` inside `domain`'s `resources do ... end` block, or
  `[]` if the resource is not referenced.
  """
  @spec domain_interfaces(module() | nil, module()) :: [struct()]
  def domain_interfaces(nil, _resource), do: []

  def domain_interfaces(domain, resource) when is_atom(domain) and is_atom(resource) do
    with true <- ash_available?(),
         {:module, _} <- Code.ensure_compiled(domain),
         ref when not is_nil(ref) <- resource_reference(domain, resource) do
      ref.definitions
    else
      _ -> []
    end
  end

  defp resource_reference(domain, resource) do
    domain
    |> cached_domain_references()
    |> Enum.find(fn ref -> ref.resource == resource end)
  end

  # Cached per-domain in `:persistent_term`. A domain's reference list is
  # constant for the VM lifetime (set at compile time by Ash), so we read it
  # from Ash once per `mix credo` run and reuse the same list for every
  # subsequent `domain_interface/3` / `domain_interfaces/2` lookup. Keeps
  # `UseCodeInterface` at O(N) across a file with N `Ash.*` calls into the
  # same domain instead of O(N*M).
  defp cached_domain_references(domain) do
    key = {@domain_refs_key_tag, domain}

    case Cache.get(key, :miss) do
      :miss ->
        refs = Ash.Domain.Info.resource_references(domain)
        Cache.put(key, refs)
        refs

      cached ->
        cached
    end
  end

  @doc """
  Given a list of action structs and a target action name, returns the name of
  the action whose name is most similar to `target_name` (jaro distance ≥ 0.75),
  or `nil` if no close match exists. Used to suggest typo fixes in issue
  messages.
  """
  @spec suggest_action_name([struct()], atom()) :: atom() | nil
  def suggest_action_name(known_actions, target_name)
      when is_list(known_actions) and is_atom(target_name) do
    target_str = Atom.to_string(target_name)

    known_actions
    |> Enum.map(fn action ->
      {action.name, String.jaro_distance(target_str, Atom.to_string(action.name))}
    end)
    |> Enum.filter(fn {_, score} -> score >= 0.75 end)
    |> case do
      [] -> nil
      scored -> scored |> Enum.max_by(&elem(&1, 1)) |> elem(0)
    end
  end

  @doc """
  Builds a `:not_loadable` diagnostic for `module` only the first time it is
  seen this run. Subsequent calls for the same module return `[]`, so an
  unloadable resource produces at most ONE diagnostic across all
  compile-dependent checks per `mix credo` invocation. Atomic across
  concurrent Credo tasks.

  `build_issue_fn` is a 0-arity function that returns a single
  `Credo.Issue.t()` - typically a `format_issue/2` call inside the calling
  check module (since `format_issue/2` is a macro from `use Credo.Check` and
  can only be built from there).
  """
  @spec with_unique_not_loadable(module(), (-> struct())) :: [struct()]
  def with_unique_not_loadable(module, build_issue_fn)
      when is_atom(module) and is_function(build_issue_fn, 0) do
    if Cache.insert_new({@not_loadable_warned_key_tag, module}) do
      [build_issue_fn.()]
    else
      []
    end
  end

  @doc """
  Shared scaffold for compile-dependent checks. Wraps the common pattern of:

    * bail out early with an `:ash_missing` diagnostic (emitted at most once
      per `mix credo` run across all compile-dependent checks) if Ash is not
      loaded in the VM;
    * otherwise run the check body.

  `missing_issue_fn` must be a 0-arity function that returns a single
  `Credo.Issue.t()` (typically a `format_issue/2` call - which is a macro
  from `use Credo.Check`, so it can only be built from inside the check
  module itself).

  `check_fn` is the 0-arity function that runs the actual check and returns
  the list of issues.

  Returns a list of issues either way.
  """
  @spec with_compiled_check((-> struct()), (-> [struct()])) :: [struct()]
  def with_compiled_check(missing_issue_fn, check_fn)
      when is_function(missing_issue_fn, 0) and is_function(check_fn, 0) do
    cond do
      ash_available?() -> check_fn.()
      Cache.insert_new(@ash_missing_warned_key) -> [missing_issue_fn.()]
      true -> []
    end
  end

  @doc """
  Walks `module`'s name segments upward and returns the innermost ancestor
  that is a loaded `Ash.Domain`, or `nil` if none is found.

  Used to give Ash callback modules (`Change`/`Preparation`/`Validation`/
  `Calculation`/`Manual*`) a domain by namespace convention - e.g.
  `MyApp.Blog.Changes.Archive` resolves to `MyApp.Blog` when that module is
  a loaded domain.

  **Heuristic, not authoritative.** This is a namespace-convention guess,
  not a reverse lookup of which resources actually reference the callback
  module. A "shared infrastructure" change module nested under one domain's
  namespace but used by resources in multiple domains will be classified as
  belonging to the namespace's domain, which can occasionally surface a
  misleading suggestion. Acceptable tradeoff for the common case of teams
  that organise callback modules under their owning domain.
  """
  @spec enclosing_domain(module()) :: module() | nil
  def enclosing_domain(module) when is_atom(module) do
    module
    |> Module.split()
    |> Enum.drop(-1)
    |> name_ancestors()
    |> Enum.find_value(fn segs ->
      candidate = Module.concat(segs)
      if domain?(candidate), do: candidate
    end)
  end

  defp name_ancestors([]), do: []
  defp name_ancestors(segs), do: [segs | name_ancestors(Enum.drop(segs, -1))]

  @doc """
  Clears every cache entry: per-module introspection results, per-domain
  resource-reference lists, the `ash_available?` probe, and the one-shot
  `:ash_missing` / `:not_loadable` diagnostic flags.

  Called automatically by `AshCredo.init/1` at the start of every Credo
  run, so callers rarely need to invoke it directly. Useful in tests that
  need a clean slate between assertions.
  """
  @spec clear_cache() :: :ok
  def clear_cache do
    Cache.clear()
  end

  @datetime_storage_types [
    :utc_datetime,
    :utc_datetime_usec,
    :naive_datetime,
    :naive_datetime_usec
  ]

  @doc """
  Returns `true` if `type` is a datetime attribute type, resolving through
  `Ash.Type.NewType.subtype_of/1` for custom NewTypes (e.g.
  `AshPostgres.TimestamptzUsec`) whose `storage_type/1` returns a DB-specific
  atom rather than a standard Ecto datetime type.
  """
  @spec datetime_type?(term()) :: boolean()
  def datetime_type?(type) when is_atom(type) and not is_nil(type) do
    type
    |> NewType.subtype_of()
    |> Ash.Type.storage_type([])
    |> Kernel.in(@datetime_storage_types)
  end

  def datetime_type?(_), do: false

  # ── Private ──

  defp do_inspect(module) do
    case Code.ensure_compiled(module) do
      {:module, ^module} ->
        if Ash.Resource.Info.resource?(module) do
          {:ok,
           %{
             resource?: true,
             domain: Ash.Resource.Info.domain(module),
             interfaces: Ash.Resource.Info.interfaces(module),
             actions: Ash.Resource.Info.actions(module),
             attributes: Ash.Resource.Info.attributes(module),
             primary_key: Ash.Resource.Info.primary_key(module),
             identities: Ash.Resource.Info.identities(module),
             authorizers: Ash.Resource.Info.authorizers(module),
             policies: read_policies(module)
           }}
        else
          {:error, :not_a_resource}
        end

      {:error, _reason} ->
        {:error, :not_loadable}
    end
  end

  # Policies live in `Ash.Policy.Info` (a separate module from `Ash.Resource.Info`).
  # `Ash.Policy.Info.policies/1` always returns a list - `[]` for resources
  # without `Ash.Policy.Authorizer`.
  defp read_policies(module) do
    Ash.Policy.Info.policies(module)
  rescue
    _ -> []
  end

  defp cache_fetch(module) do
    case Cache.get({@cache_key_tag, module}, :miss) do
      :miss -> :miss
      cached -> {:ok, cached}
    end
  end

  defp cache_put(module, result) do
    Cache.put({@cache_key_tag, module}, result)
    result
  end
end
