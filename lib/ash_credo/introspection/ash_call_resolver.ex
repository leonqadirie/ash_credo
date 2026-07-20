defmodule AshCredo.Introspection.AshCallResolver do
  @moduledoc """
  Upper layer of the Ash call pipeline: consumes the call stream from
  `AshCredo.Introspection.AshCallScanner` and yields *resolved* Ash call
  sites, calls where both the resource and the action arguments are
  literal values that map to a real module atom and a real action atom.

  This module knows the specific Ash API entry-point shapes; the lower
  layer doesn't. It recognises four dispatch patterns:

    * Pattern A - resource at arg 0, `:action` in the keyword opts
      (`Ash.read!`, `Ash.get`, `Ash.read_one`, `Ash.stream!`, ...).
      When no `:action` is present, read-like calls resolve to the
      resource's primary `:read` action, but still carry their original
      call shape so checks can preserve list/get/stream semantics in
      suggestions.
    * Pattern B - `Ash.bulk_create/3` (resource at arg 1, action at
      arg 2).
    * Pattern C - `Ash.bulk_update`/`bulk_destroy` (query/stream at
      arg 0, action at arg 1, resource traced through the query origin).
    * Pattern D - the builders `Ash.Changeset.for_*`/`Ash.Query.for_read`/
      `Ash.ActionInput.for_action` (resource at arg 0, action at arg 1).

  For the pattern D record-first builders (`for_update`/`for_destroy`),
  the resolver additionally traces the first argument back through
  bindings and pipe chains to find the originating literal resource.

  Each yielded site has the resource lookup result attached, either
  `{:ok, atom, info}`, `{:not_loadable, atom}`, `:not_a_resource`, or
  `:ash_missing`, so consumers can apply their own emission logic
  without re-running `Compiled.inspect_module/1`.

  Consumers:

    * `AshCredo.Check.Refactor.UseCodeInterface` - the
      interface-suggestion logic on loaded resources, plus the
      `:not_loadable` diagnostic for unreachable modules.
    * `AshCredo.Check.Warning.UnknownAction` - flags references to
      actions that don't exist on the resolved resource.
  """

  alias AshCredo.Cache
  alias AshCredo.Introspection
  alias AshCredo.Introspection.{Aliases, AshCallScanner, AshCallSite}
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection
  alias Credo.Code.Name

  @sites_key_tag {__MODULE__, :sites}

  # Pattern A: resource at arg 0, action in keyword opts (:action key).
  @action_in_opts ~w(read read! get get! read_one read_one! read_first read_first! stream!)a
  @get_funs ~w(get get!)a

  # Pattern B: bulk_create - resource at arg 1, action at arg 2.
  @bulk_create_funs ~w(bulk_create bulk_create!)a

  # Pattern C: bulk_update/destroy - query/stream at arg 0, action at arg 1.
  @bulk_query_funs ~w(bulk_update bulk_update! bulk_destroy bulk_destroy!)a

  @stream_funs ~w(stream!)a

  # Pattern D: resource at arg 0, action at arg 1 (builders).
  @positional_0_1_funs MapSet.new([
                         {[:Ash, :Changeset], :for_create},
                         {[:Ash, :Changeset], :for_update},
                         {[:Ash, :Changeset], :for_destroy},
                         {[:Ash, :Changeset], :for_action},
                         {[:Ash, :Query], :for_read},
                         {[:Ash, :ActionInput], :for_action}
                       ])

  # Builders whose arg 0 is typically a record (a struct or a variable
  # bound to one) rather than a literal resource module. For these we also
  # try to trace the argument's provenance back to a literal resource origin.
  @record_first_builders MapSet.new([
                           {[:Ash, :Changeset], :for_update},
                           {[:Ash, :Changeset], :for_destroy}
                         ])

  # Origin calls from which a bound variable carries a single record whose
  # resource type is the first argument (e.g.
  # `post = Ash.get!(MyApp.Post, id)`). Only the bang variant qualifies:
  # `Ash.get/3` returns `{:ok, record}`, so a binding like
  # `post = Ash.get(Post, id)` holds a result tuple, not a record.
  @record_origin_funs ~w(get!)a

  @doc """
  Walks `source_file` and returns the list of resolved Ash call sites in
  source order.

  Memoized in the run-scoped cache, keyed on filename plus source hash,
  so the scan-and-resolve pass runs once per file per Credo run instead
  of once per consuming check. Safe to cache despite embedding compiled
  resolution results: the compiled world is fixed within a run, and
  `AshCredo.init/1` clears the cache at the run boundaries.
  """
  @spec sites(Credo.SourceFile.t()) :: [AshCallSite.t()]
  def sites(source_file) do
    key = {@sites_key_tag, source_file.filename, Introspection.source_hash(source_file)}

    Cache.memoize(key, fn -> compute_sites(source_file) end)
  end

  defp compute_sites(source_file) do
    source_file
    |> AshCallScanner.calls_with_context()
    |> Enum.flat_map(&resolve_site/1)
  end

  @doc "Returns `\"<module>.<fun>\"` for a resolved call site."
  @spec qualified_call(AshCallSite.t()) :: String.t()
  def qualified_call(%AshCallSite{module: module, fun_name: fun_name}),
    do: Name.full(module) <> ".#{fun_name}"

  @doc """
  Returns `true` if the call uses a bang-style function name (e.g.
  `read!`). Builder calls (`changeset_to_*`/`query_to_*`/`input_to_*`)
  are never bang-suffixed because their generated helpers don't raise.
  """
  @spec bang?(AshCallSite.t()) :: boolean()
  def bang?(%AshCallSite{builder_prefix: prefix}) when not is_nil(prefix), do: false

  def bang?(%AshCallSite{fun_name: fun_name}),
    do: fun_name |> Atom.to_string() |> String.ends_with?("!")

  # ── Site resolution ──

  defp resolve_site(
         %{call_ast: call_ast, expanded_module: expanded_module, args: args} = call_info
       ) do
    {{:., _, [_, fun_name]}, call_meta, _raw_args} = call_ast

    ctx = %{
      fun_name: fun_name,
      module: expanded_module,
      arity: length(args),
      call_meta: call_meta,
      call_info: call_info,
      builder_prefix: nil,
      trace_record?: false,
      call_kind: call_kind(expanded_module, fun_name)
    }

    dispatch_site(expanded_module, fun_name, args, ctx)
  end

  defp dispatch_site([:Ash], fun_name, args, ctx) when fun_name in @action_in_opts,
    do: extract_action_in_opts(args, ctx)

  defp dispatch_site([:Ash], fun_name, args, ctx) when fun_name in @bulk_create_funs,
    do: extract_positional(args, 1, 2, ctx)

  defp dispatch_site([:Ash], fun_name, args, ctx) when fun_name in @bulk_query_funs,
    do: extract_bulk_query(args, ctx)

  # `@positional_0_1_funs`/`@record_first_builders` are MapSets, so this
  # case cannot be a function-head guard; it falls through to the catch-all.
  defp dispatch_site(module, fun_name, args, ctx) do
    if MapSet.member?(@positional_0_1_funs, {module, fun_name}) do
      extract_positional(args, 0, 1, %{
        ctx
        | builder_prefix: builder_prefix(module),
          call_kind: :builder,
          trace_record?: MapSet.member?(@record_first_builders, {module, fun_name})
      })
    else
      []
    end
  end

  defp extract_action_in_opts(args, ctx) do
    with {:ok, resource_ast} <- arg_at(args, 0),
         {:ok, segs} <- literal_segments(resource_ast, ast_context(ctx.call_info)) do
      case action_in_opts(args, ctx.fun_name) do
        {:literal, action} -> [build_site(segs, action, ctx)]
        :absent -> implicit_read_sites(segs, ctx)
        # `:action` is present but not a literal atom (e.g. a bound
        # variable). The caller intends a specific runtime action, so
        # don't silently fall back to `:read`.
        :non_literal -> []
      end
    else
      _ -> []
    end
  end

  # `Ash.read!/get!/stream!` without an `:action` keyword dispatches to the
  # resource's primary :read action at runtime. Mirror that here so bare
  # `Ash.read!(MyApp.Post)` gets the same code-interface suggestion as the
  # explicit `Ash.read!(MyApp.Post, action: :read)` form, and so a
  # `:not_loadable` diagnostic still fires for projects that only ever call
  # the bare shape.
  defp implicit_read_sites(segments, ctx) do
    case resolve_resource(segments) do
      {:ok, _resource, %{actions: actions}} = resolution ->
        case primary_read_action_name(actions) do
          nil -> []
          action -> [build_site_with(ctx, action, resolution)]
        end

      {:not_loadable, _resource} = resolution ->
        # Only the `{:ok, ...}` branch in checks uses action_name. The
        # `:not_loadable` branch ignores it. We pass `:read` as a stable
        # placeholder, not a sentinel, so any future inspection reads
        # naturally.
        [build_site_with(ctx, :read, resolution)]

      _ ->
        []
    end
  end

  defp build_site_with(ctx, action_name, resolution) do
    # `:trace_record?` is resolver-local scratch (it drives the
    # resource_segments/3 dispatch) and not part of the AshCallSite
    # contract, so drop it before building the struct.
    fields =
      ctx
      |> Map.delete(:trace_record?)
      |> Map.merge(%{
        resolution: resolution,
        action_name: action_name,
        lookup_keys: lookup_keys(ctx, resolution)
      })

    struct!(AshCallSite, fields)
  end

  defp primary_read_action_name(actions) when is_list(actions) do
    Enum.find_value(actions, fn
      %{type: :read, primary?: true, name: name} -> name
      _ -> nil
    end)
  end

  defp call_kind([:Ash], fun_name) when fun_name in [:read, :read!], do: :read_many
  defp call_kind([:Ash], fun_name) when fun_name in [:get, :get!], do: :get_one
  defp call_kind([:Ash], fun_name) when fun_name in [:read_one, :read_one!], do: :read_one
  defp call_kind([:Ash], fun_name) when fun_name in [:read_first, :read_first!], do: :read_first
  defp call_kind([:Ash], :stream!), do: :stream_many
  defp call_kind([:Ash], fun_name) when fun_name in @bulk_create_funs, do: :bulk
  defp call_kind([:Ash], fun_name) when fun_name in @bulk_query_funs, do: :bulk
  defp call_kind(_module, _fun_name), do: nil

  defp lookup_keys(%{call_kind: :get_one, call_info: %{args: args}}, {:ok, _resource, info}) do
    case arg_at(args, 1) do
      {:ok, id_ast} -> literal_lookup_keys(id_ast) || simple_primary_key(info)
      _ -> nil
    end
  end

  defp lookup_keys(_ctx, _resolution), do: nil

  defp literal_lookup_keys({:%{}, _, pairs}) when is_list(pairs) do
    pairs
    |> Enum.map(fn
      {key, _value} when is_atom(key) -> key
      _ -> nil
    end)
    |> all_or_nil()
  end

  defp literal_lookup_keys(keys) when is_list(keys) do
    if Keyword.keyword?(keys) do
      keys
      |> Keyword.keys()
      |> case do
        [] -> nil
        literal_keys -> literal_keys
      end
    end
  end

  defp literal_lookup_keys(_ast), do: nil

  defp all_or_nil(values) do
    if Enum.all?(values, &is_atom/1), do: values
  end

  defp simple_primary_key(%{primary_key: [key]}) when is_atom(key), do: [key]
  defp simple_primary_key(_info), do: nil

  defp extract_positional(args, resource_idx, action_idx, ctx) do
    context = ast_context(ctx.call_info)

    with {:ok, resource_ast} <- arg_at(args, resource_idx),
         {:ok, segs} <- resource_segments(resource_ast, context, ctx),
         {:ok, action} <- arg_at(args, action_idx),
         true <- is_atom(action) do
      [build_site(segs, action, ctx)]
    else
      _ -> []
    end
  end

  defp extract_bulk_query(args, ctx) do
    context = ast_context(ctx.call_info)

    with {:ok, query_or_stream} <- arg_at(args, 0),
         {:ok, segs} <- trace_origin_to_literal(query_or_stream, context),
         {:ok, action} <- arg_at(args, 1),
         true <- is_atom(action) do
      [build_site(segs, action, ctx)]
    else
      _ -> []
    end
  end

  defp build_site(segments, action_name, ctx) do
    build_site_with(ctx, action_name, resolve_resource(segments))
  end

  # No enclosing-module fallback here: a bare `Post` inside
  # `defmodule MyApp.Blog` is the top-level `Post` unless a nested
  # `defmodule Post` (or an alias) precedes it, and the scanner registers
  # that defmodule-created alias, so `segments` arrive fully resolved.
  defp resolve_resource(segments) do
    resource = Module.concat(segments)

    case CompiledIntrospection.inspect_module(resource) do
      {:ok, info} -> {:ok, resource, info}
      {:error, :not_a_resource} -> :not_a_resource
      {:error, :ash_missing} -> :ash_missing
      {:error, :not_loadable} -> {:not_loadable, resource}
    end
  end

  defp builder_prefix([:Ash, :Changeset]), do: :changeset_to
  defp builder_prefix([:Ash, :Query]), do: :query_to
  defp builder_prefix([:Ash, :ActionInput]), do: :input_to
  defp builder_prefix(_), do: nil

  defp ast_context(call_info) do
    %{
      env: call_info.env,
      bindings: call_info.bindings,
      enclosing_module_segments: call_info.enclosing_module_segments
    }
  end

  # ── AST helpers ──

  defp literal_segments({:__MODULE__, _, _}, context) do
    case context.enclosing_module_segments do
      segs when is_list(segs) and segs != [] -> {:ok, segs}
      _ -> :error
    end
  end

  defp literal_segments({:__aliases__, _, [{:__MODULE__, _, _} | rest]}, context) do
    if Enum.all?(rest, &is_atom/1) do
      case context.enclosing_module_segments do
        segs when is_list(segs) and segs != [] -> {:ok, segs ++ rest}
        _ -> :error
      end
    else
      :error
    end
  end

  # `alias __MODULE__.Post` targets are substituted at declaration time by
  # the scanner's directive capture, so env expansion always yields plain
  # atom segments here.
  defp literal_segments({:__aliases__, _, segs}, context) when is_list(segs) do
    if Enum.all?(segs, &is_atom/1) do
      {:ok, Aliases.expand_alias(segs, context.env)}
    else
      :error
    end
  end

  # Struct literal like `%MyApp.Post{...}`: extract the inner alias AST.
  defp literal_segments({:%, _, [alias_ast, {:%{}, _, _}]}, context),
    do: literal_segments(alias_ast, context)

  defp literal_segments(_, _), do: :error

  # Builders that carry the record/changeset as arg0 may receive it via a
  # pipeline or a binding, so trace the origin back to a literal; plain
  # positional calls name the resource directly.
  defp resource_segments(ast, context, %{trace_record?: true}) do
    case literal_segments(ast, context) do
      {:ok, segs} -> {:ok, segs}
      :error -> trace_origin_to_literal(ast, context)
    end
  end

  defp resource_segments(ast, context, %{trace_record?: false}),
    do: literal_segments(ast, context)

  defp trace_origin_to_literal(ast, context), do: trace_origin(ast, context, MapSet.new())

  defp trace_origin({name, _, ctx}, context, seen)
       when is_atom(name) and (is_atom(ctx) or is_nil(ctx)) do
    key = {name, ctx}

    if MapSet.member?(seen, key) do
      :error
    else
      case Map.get(context.bindings, key) do
        nil -> :error
        bound -> trace_origin(bound, context, MapSet.put(seen, key))
      end
    end
  end

  defp trace_origin({:|>, _, [left, right]}, context, seen) do
    case piped_call_signature(left, right, context) do
      {:ok, module, fun_name, args} -> trace_call_origin(module, fun_name, args, context, seen)
      :error -> :error
    end
  end

  defp trace_origin({{:., _, [module_ast, fun_name]}, _meta, args}, context, seen)
       when is_list(args) do
    module = Aliases.resolved_module_ref(module_ast, context)
    trace_call_origin(module, fun_name, args, context, seen)
  end

  defp trace_origin(_ast, _context, _seen), do: :error

  defp trace_call_origin([:Ash, :Query], _fun_name, args, context, seen),
    do: trace_arg0(args, context, seen)

  defp trace_call_origin([:Ash], fun_name, args, context, seen)
       when fun_name in @stream_funs or fun_name in @record_origin_funs,
       do: trace_arg0(args, context, seen)

  defp trace_call_origin(_module, _fun_name, _args, _context, _seen), do: :error

  defp trace_arg0(args, context, seen) do
    case arg_at(args, 0) do
      {:ok, resource_or_query} -> literal_or_traced(resource_or_query, context, seen)
      _ -> :error
    end
  end

  defp literal_or_traced(ast, context, seen) do
    case literal_segments(ast, context) do
      {:ok, segs} -> {:ok, segs}
      :error -> trace_origin(ast, context, seen)
    end
  end

  defp piped_call_signature(left, {{:., _, [module_ast, fun_name]}, _meta, args}, context)
       when is_list(args) do
    {:ok, Aliases.resolved_module_ref(module_ast, context), fun_name, [left | args]}
  end

  defp piped_call_signature(_left, _right, _context), do: :error

  defp arg_at(args, idx), do: Enum.fetch(args, idx)

  # `Ash.get/2`'s second argument is always the identifier, even when it is
  # a keyword list containing an `:action` attribute. Only `Ash.get/3` has
  # call options. The other Pattern A functions take options at index 1.
  defp action_in_opts(args, fun_name) do
    opts_idx = if fun_name in @get_funs, do: 2, else: 1

    case arg_at(args, opts_idx) do
      {:ok, opts} when is_list(opts) -> action_from_literal_opts(opts)
      {:ok, _dynamic_or_invalid_opts} -> :non_literal
      :error -> :absent
    end
  end

  defp action_from_literal_opts(opts) do
    case Keyword.fetch(opts, :action) do
      {:ok, value} when is_atom(value) and not is_nil(value) -> {:literal, value}
      {:ok, _value} -> :non_literal
      :error -> :absent
    end
  end
end
