defmodule AshCredo.Check.Refactor.UseCodeInterface do
  use Credo.Check,
    base_priority: :normal,
    category: :refactor,
    tags: [:ash],
    explanations: [
      check: """
      When both the resource and action name are literal values, prefer calling
      a code interface function on the resource module.

          # Flagged — resource and action are both literals
          Ash.read(MyApp.Post, action: :published)
          Ash.bulk_create(inputs, MyApp.Post, :import)

          # Preferred — use the code interface
          MyApp.Post.published()
          MyApp.Post.import(inputs)

      Builder functions are also flagged, but note that the code interface
      equivalent preserves the return type via generated `query_to_*`,
      `changeset_to_*`, or `input_to_*` helpers:

          # Flagged
          Ash.Query.for_read(MyApp.Post, :published)
          Ash.Changeset.for_create(MyApp.Post, :create, params)

          # Preferred — returns a query / changeset, not results
          MyApp.Post.query_to_published()
          MyApp.Post.changeset_to_create(params)

      This applies to direct Ash API calls, bulk operations, and
      changeset/query/action-input builder functions.
      """
    ]

  alias AshCredo.Introspection

  # Pattern A: resource at arg 0, action in keyword opts (:action key)
  @action_in_opts ~w(read read! get get! stream stream!)a

  # Pattern B: bulk_create — resource at arg 1, action at arg 2
  # (bulk_create takes (inputs, resource, action, opts))
  @bulk_create_funs ~w(bulk_create bulk_create!)a

  # Pattern C: bulk_update/destroy — query_or_stream at arg 0, action at arg 1
  # The first arg is not itself a resource module, so we only flag when we can
  # statically trace that query/stream back to a literal resource.
  @bulk_query_funs ~w(bulk_update bulk_update! bulk_destroy bulk_destroy!)a

  # Pattern D: resource at arg 0, action at arg 1 (builders)
  @positional_0_1_funs MapSet.new([
                         {[:Ash, :Changeset], :for_create},
                         {[:Ash, :Changeset], :for_update},
                         {[:Ash, :Changeset], :for_destroy},
                         {[:Ash, :Changeset], :for_action},
                         {[:Ash, :Query], :for_read},
                         {[:Ash, :ActionInput], :for_action}
                       ])

  @stream_funs ~w(stream stream!)a

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Introspection.ash_api_calls_with_context()
    |> Enum.flat_map(&check_call(&1, issue_meta))
  end

  defp check_call(
         %{call_ast: call_ast, expanded_module: expanded_module, args: normalized_args} =
           call_info,
         issue_meta
       ) do
    {{:., _, [_, fun_name]}, call_meta, _raw_args} = call_ast
    context = %{aliases: call_info.aliases, bindings: call_info.bindings}

    cond do
      expanded_module == [:Ash] and fun_name in @action_in_opts ->
        check_action_in_opts(normalized_args, 0, fun_name, expanded_module, call_meta, issue_meta)

      expanded_module == [:Ash] and fun_name in @bulk_create_funs ->
        check_positional(normalized_args, 1, 2, fun_name, expanded_module, call_meta, issue_meta)

      expanded_module == [:Ash] and fun_name in @bulk_query_funs ->
        check_bulk_query(
          normalized_args,
          fun_name,
          expanded_module,
          call_meta,
          issue_meta,
          context
        )

      MapSet.member?(@positional_0_1_funs, {expanded_module, fun_name}) ->
        check_positional(normalized_args, 0, 1, fun_name, expanded_module, call_meta, issue_meta)

      true ->
        []
    end
  end

  defp check_action_in_opts(args, resource_idx, fun_name, module, call_meta, issue_meta) do
    with {:ok, resource} <- arg_at(args, resource_idx),
         true <- literal_module?(resource),
         action when is_atom(action) and not is_nil(action) <- action_from_opts(args) do
      [make_issue(module, fun_name, length(args), call_meta, issue_meta)]
    else
      _ -> []
    end
  end

  defp check_positional(args, resource_idx, action_idx, fun_name, module, call_meta, issue_meta) do
    with {:ok, resource} <- arg_at(args, resource_idx),
         true <- literal_module?(resource),
         {:ok, action} <- arg_at(args, action_idx),
         true <- is_atom(action) do
      [make_issue(module, fun_name, length(args), call_meta, issue_meta)]
    else
      _ -> []
    end
  end

  defp check_bulk_query(args, fun_name, module, call_meta, issue_meta, context) do
    with {:ok, query_or_stream} <- arg_at(args, 0),
         true <- originates_from_literal_resource?(query_or_stream, context),
         {:ok, action} <- arg_at(args, 1),
         true <- is_atom(action) do
      [make_issue(module, fun_name, length(args), call_meta, issue_meta)]
    else
      _ -> []
    end
  end

  defp arg_at(args, idx), do: Enum.fetch(args, idx)

  defp literal_module?({:__aliases__, _, segments}) when is_list(segments), do: true
  defp literal_module?(_), do: false

  defp originates_from_literal_resource?(ast, context, seen_vars \\ MapSet.new())

  defp originates_from_literal_resource?({name, _, ctx}, context, seen_vars)
       when is_atom(name) and (is_atom(ctx) or is_nil(ctx)) do
    key = {name, ctx}

    if MapSet.member?(seen_vars, key) do
      false
    else
      case Map.get(context.bindings, key) do
        nil ->
          false

        bound_ast ->
          originates_from_literal_resource?(bound_ast, context, MapSet.put(seen_vars, key))
      end
    end
  end

  defp originates_from_literal_resource?({:|>, _, [left, right]}, context, seen_vars) do
    case piped_call_signature(left, right, context) do
      {:ok, expanded_module, fun_name, args} ->
        origin_call?(expanded_module, fun_name, args, context, seen_vars)

      :error ->
        false
    end
  end

  defp originates_from_literal_resource?(
         {{:., _, [module_ast, fun_name]}, _meta, args},
         context,
         seen_vars
       )
       when is_list(args) do
    module = Introspection.resolved_module_ref(module_ast, context)
    origin_call?(module, fun_name, args, context, seen_vars)
  end

  defp originates_from_literal_resource?(_ast, _context, _seen_vars), do: false

  defp origin_call?([:Ash, :Query], _fun_name, args, context, seen_vars) do
    case arg_at(args, 0) do
      {:ok, resource_or_query} ->
        literal_resource_argument?(resource_or_query, context, seen_vars)

      _ ->
        false
    end
  end

  defp origin_call?([:Ash], fun_name, args, context, seen_vars) when fun_name in @stream_funs do
    case arg_at(args, 0) do
      {:ok, resource_or_query} ->
        literal_resource_argument?(resource_or_query, context, seen_vars)

      _ ->
        false
    end
  end

  defp origin_call?(_module, _fun_name, _args, _context, _seen_vars), do: false

  defp literal_resource_argument?(ast, context, seen_vars) do
    literal_module?(ast) or originates_from_literal_resource?(ast, context, seen_vars)
  end

  defp piped_call_signature(left, {{:., _, [module_ast, fun_name]}, _meta, args}, context)
       when is_list(args) do
    {:ok, Introspection.resolved_module_ref(module_ast, context), fun_name, [left | args]}
  end

  defp piped_call_signature(_left, _right, _context), do: :error

  defp action_from_opts(args) do
    case List.last(args) do
      kwl when is_list(kwl) -> Keyword.get(kwl, :action)
      _ -> nil
    end
  end

  defp make_issue(module, fun_name, arity, call_meta, issue_meta) do
    qualified = Enum.map_join(module, ".", &Atom.to_string/1) <> ".#{fun_name}"

    format_issue(issue_meta,
      message:
        "Both resource and action are literal values — use a code interface function instead of `#{qualified}/#{arity}`.",
      trigger: qualified,
      line_no: call_meta[:line]
    )
  end
end
