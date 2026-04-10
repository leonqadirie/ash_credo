defmodule AshCredo.Introspection.AshCallSites do
  @moduledoc """
  Walks a source file and yields resolved Ash call sites.

  A "resolved site" is an `Ash.*` API call where both the resource and the
  action arguments are literal values that the walker could trace back to a
  module atom and an action atom. The helper handles all four call shapes
  AshCredo cares about:

    * Pattern A - resource at arg 0, `:action` in keyword opts (`Ash.read!`,
      `Ash.get`, `Ash.stream!`, ...).
    * Pattern B - `Ash.bulk_create/3` (resource at arg 1, action at arg 2).
    * Pattern C - `Ash.bulk_update`/`bulk_destroy` (query/stream at arg 0,
      action at arg 1, resource traced through the query origin).
    * Pattern D - builders `Ash.Changeset.for_*`/`Ash.Query.for_read`/
      `Ash.ActionInput.for_action` (resource at arg 0, action at arg 1).

  For pattern D record-first builders (`for_update`/`for_destroy`) the
  helper additionally traces the first argument back through bindings and
  pipe chains to find the originating literal resource.

  This module is the shared infrastructure used by:

    * `AshCredo.Check.Refactor.UseCodeInterface` - for interface-suggestion
      logic on loaded resources, plus the `:not_loadable` diagnostic for
      unreachable modules.
    * `AshCredo.Check.Warning.UnknownAction` - for flagging references to
      actions that do not exist on the resolved resource.

  Both checks would otherwise need the same call-walking pipeline; the
  helper centralises it so each check only owns its own emission logic.
  """

  alias AshCredo.Introspection
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection
  alias Credo.Code.Name

  # Pattern A: resource at arg 0, action in keyword opts (:action key).
  @action_in_opts ~w(read read! get get! stream!)a

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

  # Builders whose arg 0 is typically a record (struct or variable bound to
  # one) rather than a literal resource module. For these we additionally
  # try to trace the argument's provenance back to a literal resource origin.
  @record_first_builders MapSet.new([
                           {[:Ash, :Changeset], :for_update},
                           {[:Ash, :Changeset], :for_destroy}
                         ])

  # Origin calls from which a bound variable carries a single record whose
  # resource type is the first argument (e.g. `post = Ash.get!(MyApp.Post, id)`).
  # Only the bang variant qualifies: `Ash.get/3` returns `{:ok, record}`, so a
  # binding like `post = Ash.get(Post, id)` holds a result tuple, not a record.
  @record_origin_funs ~w(get!)a

  @type resolution ::
          {:ok, module(), map()}
          | {:not_loadable, module()}
          | :not_a_resource
          | :ash_missing

  @type site :: %{
          resolution: resolution(),
          action_name: atom(),
          fun_name: atom(),
          module: [atom()],
          arity: non_neg_integer(),
          call_ast: Macro.t(),
          call_meta: keyword(),
          call_info: map(),
          builder_prefix: :changeset_to | :query_to | :input_to | nil,
          trace_record?: boolean()
        }

  @doc """
  Walks `source_file` and returns the list of resolved Ash call sites in
  source order.

  Each entry has the resource lookup result attached - either
  `{:ok, atom, info}`, `{:not_loadable, atom}`, `:not_a_resource`, or
  `:ash_missing` - so the caller can apply its own emission logic without
  re-running `Compiled.inspect_module/1`.
  """
  @spec resolved_sites(Credo.SourceFile.t()) :: [site()]
  def resolved_sites(source_file) do
    source_file
    |> Introspection.ash_api_calls_with_context()
    |> Enum.flat_map(&resolve_site/1)
  end

  @doc "Returns `\"<module>.<fun>\"` for a resolved call site."
  @spec qualified_call(site()) :: String.t()
  def qualified_call(%{module: module, fun_name: fun_name}),
    do: Name.full(module) <> ".#{fun_name}"

  @doc """
  Returns `true` if the call uses a bang-style function name (e.g. `read!`).
  Builder calls (`changeset_to_*`/`query_to_*`/`input_to_*`) are never
  bang-suffixed because their generated helpers do not raise.
  """
  @spec bang?(site()) :: boolean()
  def bang?(%{builder_prefix: prefix}) when not is_nil(prefix), do: false

  def bang?(%{fun_name: fun_name}), do: fun_name |> Atom.to_string() |> String.ends_with?("!")

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
      trace_record?: false
    }

    cond do
      expanded_module == [:Ash] and fun_name in @action_in_opts ->
        extract_action_in_opts(args, ctx)

      expanded_module == [:Ash] and fun_name in @bulk_create_funs ->
        extract_positional(args, 1, 2, ctx)

      expanded_module == [:Ash] and fun_name in @bulk_query_funs ->
        extract_bulk_query(args, ctx)

      MapSet.member?(@positional_0_1_funs, {expanded_module, fun_name}) ->
        extract_positional(args, 0, 1, %{
          ctx
          | builder_prefix: builder_prefix(expanded_module),
            trace_record?: MapSet.member?(@record_first_builders, {expanded_module, fun_name})
        })

      true ->
        []
    end
  end

  defp extract_action_in_opts(args, ctx) do
    with {:ok, resource_ast} <- arg_at(args, 0),
         {:ok, segs} <- literal_segments(resource_ast, ast_context(ctx.call_info)),
         action when is_atom(action) and not is_nil(action) <- action_from_opts(args) do
      [build_site(segs, action, ctx)]
    else
      _ -> []
    end
  end

  defp extract_positional(args, resource_idx, action_idx, ctx) do
    context = ast_context(ctx.call_info)

    with {:ok, resource_ast} <- arg_at(args, resource_idx),
         {:ok, segs} <- resolve_positional_segments(resource_ast, context, ctx.trace_record?),
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
    Map.merge(ctx, %{
      resolution: resolve_resource(segments, ctx),
      action_name: action_name
    })
  end

  defp resolve_resource(segments, ctx) do
    resource = Module.concat(segments)

    case CompiledIntrospection.inspect_module(resource) do
      {:ok, info} ->
        {:ok, resource, info}

      {:error, :not_a_resource} ->
        :not_a_resource

      {:error, :ash_missing} ->
        :ash_missing

      {:error, :not_loadable} ->
        case try_implicit_resolution(segments, ctx) do
          {:ok, atom, info} -> {:ok, atom, info}
          :error -> {:not_loadable, resource}
        end
    end
  end

  # Elixir implicitly aliases direct sub-modules: inside `defmodule MyApp.Blog`,
  # `Post` refers to `MyApp.Blog.Post`. If the direct resolution of `segments`
  # is not loadable, try prepending the enclosing defmodule's absolute segments.
  defp try_implicit_resolution(segments, %{call_info: %{enclosing_module_segments: enclosing}})
       when is_list(enclosing) and enclosing != [] do
    candidate = Module.concat(enclosing ++ segments)

    case CompiledIntrospection.inspect_module(candidate) do
      {:ok, info} -> {:ok, candidate, info}
      _ -> :error
    end
  end

  defp try_implicit_resolution(_segments, _ctx), do: :error

  defp builder_prefix([:Ash, :Changeset]), do: :changeset_to
  defp builder_prefix([:Ash, :Query]), do: :query_to
  defp builder_prefix([:Ash, :ActionInput]), do: :input_to
  defp builder_prefix(_), do: nil

  defp ast_context(call_info) do
    %{
      aliases: call_info.aliases,
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

  defp literal_segments({:__aliases__, _, [{:__MODULE__, _, _} | rest]}, context)
       when is_list(rest) do
    if Enum.all?(rest, &is_atom/1) do
      case context.enclosing_module_segments do
        segs when is_list(segs) and segs != [] -> {:ok, segs ++ rest}
        _ -> :error
      end
    else
      :error
    end
  end

  defp literal_segments({:__aliases__, _, segs}, context) when is_list(segs) do
    if Enum.all?(segs, &is_atom/1) do
      {:ok, Introspection.expand_alias(segs, context.aliases)}
    else
      :error
    end
  end

  # Struct literal: `%MyApp.Post{...}` - extract the inner alias AST.
  defp literal_segments({:%, _, [alias_ast, {:%{}, _, _}]}, context),
    do: literal_segments(alias_ast, context)

  defp literal_segments(_, _), do: :error

  defp resolve_positional_segments(ast, context, true) do
    case literal_segments(ast, context) do
      {:ok, segs} -> {:ok, segs}
      :error -> trace_origin_to_literal(ast, context)
    end
  end

  defp resolve_positional_segments(ast, context, false), do: literal_segments(ast, context)

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
    module = Introspection.resolved_module_ref(module_ast, context)
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
    {:ok, Introspection.resolved_module_ref(module_ast, context), fun_name, [left | args]}
  end

  defp piped_call_signature(_left, _right, _context), do: :error

  defp arg_at(args, idx), do: Enum.fetch(args, idx)

  defp action_from_opts(args) do
    case List.last(args) do
      kwl when is_list(kwl) -> Keyword.get(kwl, :action)
      _ -> nil
    end
  end
end
