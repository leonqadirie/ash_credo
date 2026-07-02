defmodule AshCredo.Check.Warning.ActorOnCallOptions do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash],
    explanations: [
      check: """
      `actor:` and `tenant:` belong on the query/changeset/input, set when it
      is built - not in the options of the action call. This enforces the
      rule from Ash's authorization usage rules ("Always set the actor on the
      query/changeset/input, not when calling the action").

          # Bad - the query was built without the actor
          Post
          |> Ash.Query.for_read(:read, %{})
          |> Ash.read!(actor: current_user)

          # Good - the actor is part of the action context from the start
          Post
          |> Ash.Query.for_read(:read, %{}, actor: current_user)
          |> Ash.read!()

      When a query, changeset, or action input is built via `for_read`,
      `for_create`, and friends, everything that runs at build time sees the
      actor and tenant it was built with; supplying them only at call time
      leaves that build-time context inconsistent.

      Only calls whose subject visibly went through a `for_*` builder are
      flagged. Forms without a pre-built subject, such as
      `Ash.read!(Post, actor: actor)` or code interface calls like
      `MyApp.Blog.list_posts!(actor: actor)`, are sanctioned - there Ash
      builds the action context with the given actor itself. The check is
      purely syntactic: it follows pipes and simple variable bindings, but
      cannot see builders hidden behind function calls.
      """
    ]

  alias AshCredo.Introspection.Aliases
  alias AshCredo.Introspection.AshCallScanner

  # Ash action-invocation functions taking a query/changeset/input subject
  # plus an options list. The aggregate and bulk families belong here too:
  # their opts merge Ash's global options, so they take `actor:`/`tenant:`
  # at call time just like `Ash.read!/2`. They are grouped by how many
  # arguments precede the optional trailing opts (subject included), so a
  # required argument that happens to be a keyword-shaped list - e.g. the
  # aggregate specs in `Ash.aggregate(query, [{:actor, :count}])` - is
  # never mistaken for the opts.
  @subject_opts_funs ~w(read read! read_one read_one! first first! stream! count count! exists exists? create create! update update! destroy destroy! run_action run_action!)a
  @aggregate_funs ~w(aggregate aggregate! sum sum! avg avg! min min! max max! list list!)a
  @bulk_funs ~w(bulk_update bulk_update! bulk_destroy bulk_destroy!)a
  @action_funs @subject_opts_funs ++ @aggregate_funs ++ @bulk_funs

  # Builders that establish the action context; actor/tenant belong in their
  # options.
  @builder_funs ~w(for_read for_create for_update for_destroy for_action)a
  @builder_modules [[:Ash, :Query], [:Ash, :Changeset], [:Ash, :ActionInput]]

  # `scope:` is deliberately not flagged: passing a scope at call time is a
  # sanctioned way to inherit actor/tenant from a context.
  @flagged_keys [:actor, :tenant]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> AshCallScanner.calls_with_context()
    |> Enum.flat_map(&check_call(&1, issue_meta))
  end

  defp check_call(%{expanded_module: [:Ash], call_ast: call_ast} = call_info, issue_meta) do
    {{:., _, [_, fun_name]}, meta, _} = call_ast

    with true <- fun_name in @action_funs,
         [subject | _] <- call_info.args,
         keys when keys != [] <- flagged_keys(call_info.args, required_args(fun_name)),
         true <- builder_subject?(subject, call_info, MapSet.new()) do
      Enum.map(keys, &flagged_key_issue(&1, fun_name, meta, issue_meta))
    else
      _ -> []
    end
  end

  defp check_call(_call_info, _issue_meta), do: []

  # Number of arguments (subject included, after pipe normalization) that
  # precede the optional trailing opts. Only a trailing keyword list beyond
  # that count is the options of the call.
  defp required_args(fun_name) when fun_name in @aggregate_funs, do: 2
  defp required_args(fun_name) when fun_name in @bulk_funs, do: 3
  defp required_args(_fun_name), do: 1

  # Descends past the required arguments, then walks to the final argument
  # in one pass with no intermediate list, with the keyword-list shape
  # check fused in. A call with no argument beyond the required ones has
  # no options to scan.
  defp flagged_keys([_arg | rest], required_args) when required_args > 0 do
    flagged_keys(rest, required_args - 1)
  end

  defp flagged_keys([opts], 0) when is_list(opts) do
    for {key, _value} <- opts, is_atom(key), key in @flagged_keys, do: key
  end

  defp flagged_keys([_arg | rest], 0), do: flagged_keys(rest, 0)
  defp flagged_keys(_args, _required_args), do: []

  # True when the call subject visibly went through a `for_*` builder:
  # directly, anywhere in a pipe chain, or via simple variable bindings
  # (cycle-guarded, mirroring AshCallResolver's origin tracing).
  defp builder_subject?({:|>, _, [left, right]}, call_info, seen) do
    builder_call?(right, call_info) or builder_subject?(left, call_info, seen)
  end

  defp builder_subject?({name, _, ctx}, call_info, seen)
       when is_atom(name) and (is_atom(ctx) or is_nil(ctx)) do
    key = {name, ctx}

    with false <- MapSet.member?(seen, key),
         %{^key => bound} <- call_info.bindings do
      builder_subject?(bound, call_info, MapSet.put(seen, key))
    else
      _ -> false
    end
  end

  defp builder_subject?(ast, call_info, _seen), do: builder_call?(ast, call_info)

  defp builder_call?({{:., _, [module_ast, fun_name]}, _, _}, call_info)
       when fun_name in @builder_funs do
    Aliases.resolved_module_ref(module_ast, call_info) in @builder_modules
  end

  defp builder_call?(_, _), do: false

  defp flagged_key_issue(key, fun_name, meta, issue_meta) do
    format_issue(issue_meta,
      message:
        "`#{key}:` passed in the options of `Ash.#{fun_name}` - set it on the " <>
          "query/changeset/input when building it (e.g. `for_read(..., #{key}: ...)`) " <>
          "instead of at call time.",
      trigger: "#{key}",
      line_no: meta[:line]
    )
  end
end
