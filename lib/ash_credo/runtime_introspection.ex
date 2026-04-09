defmodule AshCredo.RuntimeIntrospection do
  @moduledoc """
  Runtime wrapper around `Ash.Resource.Info` and `Ash.Domain.Info`.

  Checks in `AshCredo` that need authoritative metadata about a referenced
  module (its domain, its actions, its code interfaces, whether it is even an
  Ash resource) call into this module instead of scanning source AST. Every
  call first ensures the target module is compiled and loaded, then queries
  Ash's own introspection API. Results are cached per-module in a lazy ETS
  table so repeated lookups during a single `mix credo` run are cheap.

  ## Error modes

    * `{:error, :ash_missing}` — Ash itself is not loaded in the VM running
      Credo. This happens when `ash_credo` is used in a project that does not
      depend on Ash. Callers should treat this as "Ash-aware checks are a
      no-op in this project" and emit a single diagnostic.
    * `{:error, :not_loadable}` — `Code.ensure_compiled/1` returned an error,
      typically because the host project has not been compiled yet. The
      caller should surface a "run `mix compile` first" hint.
    * `{:error, :not_a_resource}` — the module loaded successfully but is
      not an Ash resource. Checks targeting resources should silently skip.
  """

  # Ash is not a runtime dependency of ash_credo — users bring their own.
  # Suppress compile-time warnings for the remote calls below; they are guarded
  # at runtime by `ash_available?/0`.
  @compile {:no_warn_undefined, [Ash.Resource.Info, Ash.Domain.Info]}

  @cache_table :ash_credo_runtime_introspection_cache
  @ash_available_key {__MODULE__, :ash_available?}

  # Behaviours that mark a module as an Ash resource auxiliary — i.e. a
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
          actions: [struct()]
        }

  @type error :: :ash_missing | :not_loadable | :not_a_resource | :unknown_action

  @doc """
  Returns `true` if `Ash.Resource.Info` is loadable in the current VM.

  Cached in `:persistent_term` after the first call so subsequent calls are
  essentially free.
  """
  @spec ash_available?() :: boolean()
  def ash_available? do
    case :persistent_term.get(@ash_available_key, :unknown) do
      :unknown ->
        available? =
          Code.ensure_loaded?(Ash.Resource.Info) and Code.ensure_loaded?(Ash.Domain.Info)

        :persistent_term.put(@ash_available_key, available?)
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

  @doc "Returns `true` if `module` is an Ash resource loadable in this VM."
  @spec resource?(module()) :: boolean()
  def resource?(module) when is_atom(module) do
    match?({:ok, %{resource?: true}}, inspect_module(module))
  end

  @doc """
  Returns `true` if `module` is an Ash domain loadable in this VM.

  Determined by the `spark_is/0` function that Spark DSL modules inject.
  Not cached — the check is cheap (already-loaded module attribute read).
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

  defp resource_reference(domain, resource) do
    domain
    |> Ash.Domain.Info.resource_references()
    |> Enum.find(fn ref -> ref.resource == resource end)
  end

  @doc """
  Walks `module`'s name segments upward and returns the innermost ancestor
  that is a loaded `Ash.Domain`, or `nil` if none is found.

  Used to give Ash callback modules (`Change`/`Preparation`/`Validation`/
  `Calculation`/`Manual*`) a domain by namespace convention — e.g.
  `MyApp.Blog.Changes.Archive` resolves to `MyApp.Blog` when that module is
  a loaded domain.
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
  Clears the per-module cache. Intended for tests that compile fixture
  resources after first use of the cache.
  """
  @spec clear_cache() :: :ok
  def clear_cache do
    case :ets.whereis(@cache_table) do
      :undefined -> :ok
      _ -> :ets.delete_all_objects(@cache_table)
    end

    :persistent_term.erase(@ash_available_key)
    :ok
  end

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
             actions: Ash.Resource.Info.actions(module)
           }}
        else
          {:error, :not_a_resource}
        end

      {:error, _reason} ->
        {:error, :not_loadable}
    end
  end

  defp cache_table do
    case :ets.whereis(@cache_table) do
      :undefined ->
        try do
          :ets.new(@cache_table, [:named_table, :public, :set, read_concurrency: true])
        rescue
          ArgumentError -> @cache_table
        end

      _tid ->
        @cache_table
    end
  end

  defp cache_fetch(module) do
    case :ets.lookup(cache_table(), module) do
      [{^module, result}] -> {:ok, result}
      [] -> :miss
    end
  end

  defp cache_put(module, result) do
    :ets.insert(cache_table(), {module, result})
    result
  end
end
