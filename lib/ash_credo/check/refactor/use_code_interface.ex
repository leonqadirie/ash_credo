defmodule AshCredo.Check.Refactor.UseCodeInterface do
  use Credo.Check,
    base_priority: :normal,
    category: :refactor,
    tags: [:ash],
    param_defaults: [
      enforce_code_interface_in_domain: true,
      enforce_code_interface_outside_domain: true,
      prefer_interface_scope: :auto
    ],
    explanations: [
      check: """
      When both the resource and action name are literal values, prefer
      calling a code interface function instead of a raw `Ash.*` API call.

      This check queries Ash's runtime introspection (`Ash.Resource.Info`
      and `Ash.Domain.Info`) to produce precise suggestions:

        * names the exact existing code interface function when one is
          defined on the resource or the domain;
        * suggests defining a code interface when the action exists but
          no interface targets it yet;
        * flags calls to actions that do not exist on the resource.

      By default the check is domain-aware: if the caller and the resource
      share a domain it prefers the resource-level interface, otherwise it
      points at the domain-level interface.

          # In-domain caller, resource has `define :published`
          # Flagged
          Ash.read!(MyApp.Post, action: :published)
          # Preferred
          MyApp.Post.published!()

          # Outside-domain caller, domain has `define :list_posts, action: :read`
          # Flagged
          Ash.read!(MyApp.Post)
          # Preferred
          MyApp.Blog.list_posts()

      Builder calls (`Ash.Query.for_read/3`, `Ash.Changeset.for_*/4`,
      `Ash.ActionInput.for_action/3`) are flagged with the matching
      `query_to_*` / `changeset_to_*` / `input_to_*` helper that Ash
      generates for code interfaces.

      ## Configuration

      Three params let you adapt the check to a team's code-interface
      conventions:

        * `enforce_code_interface_in_domain` (default `true`) — when
          `false`, the check leaves callers that share a domain with the
          resource alone. Useful for teams that consider raw `Ash.*` calls
          inside `Change`/`Preparation`/`Validation` modules acceptable.
        * `enforce_code_interface_outside_domain` (default `true`) — when
          `false`, the check silences every case where the caller is not
          confirmed to be in the resource's domain: different known domain,
          plain caller (controller, LiveView, worker), caller that is an
          `Ash.Resource` with no `:domain`, and resources that cannot be
          loaded.
        * `prefer_interface_scope` (`:auto` | `:resource` | `:domain`,
          default `:auto`) — overrides which interface the check points at.
          `:auto` follows the domain-aware heuristic above. `:resource`
          always suggests a resource-level interface (useful if you only
          define code interfaces on resources). `:domain` always suggests a
          domain-level interface.

      Example — a team that allows raw calls inside their domain and only
      defines interfaces on resources:

          {AshCredo.Check.Refactor.UseCodeInterface,
           [enforce_code_interface_in_domain: false, prefer_interface_scope: :resource]}

      Unknown-action issues (e.g. `Ash.read!(Post, action: :publishd)`) are
      always emitted when the resource loads, regardless of the enforcement
      flags. Disable the whole check to silence them.

      ## Requirements

      The check calls `Code.ensure_compiled/1` on every referenced resource
      to query Ash's introspection API. This means **your project must be
      compiled before running `mix credo`** — typically `mix compile && mix
      credo` or a Mix alias that chains the two.

      If Ash is not available in the VM running Credo, the check is a
      no-op and emits a single diagnostic.

      ## Known limitations

        * Calls made via `import Ash; read!(...)` are not traced — only
          fully qualified `Ash.*` (or aliased) module calls are detected.
        * Records obtained via pattern matching (e.g.
          `{:ok, post} = Ash.get(...)`) or helper functions are not traced
          through bindings; only direct `post = Ash.get!(...)` / `Ash.get(...)`
          assignments and pipe chains are recognised.
      """,
      params: [
        enforce_code_interface_in_domain:
          "Flag raw `Ash.*` calls whose caller shares a domain with the resource. Set to `false` to leave same-domain callers alone (useful for teams that consider raw calls inside `Change`/`Preparation`/`Validation` modules acceptable).",
        enforce_code_interface_outside_domain:
          "Flag raw `Ash.*` calls whose caller is not in the resource's domain. This covers different known domains, plain callers (controller, LiveView, worker), callers that are an `Ash.Resource` with no `:domain`, and resources that cannot be loaded. Set to `false` to silence all of them.",
        prefer_interface_scope:
          "Controls which interface the check points at. `:auto` (default) follows the \"in-domain → resource, outside-domain → domain\" heuristic. `:resource` always suggests a resource-level interface. `:domain` always suggests a domain-level interface."
      ]
    ]

  alias AshCredo.Introspection
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection
  alias Credo.Code.Name

  # Pattern A: resource at arg 0, action in keyword opts (:action key)
  @action_in_opts ~w(read read! get get! stream!)a

  # Pattern B: bulk_create — resource at arg 1, action at arg 2
  @bulk_create_funs ~w(bulk_create bulk_create!)a

  # Pattern C: bulk_update/destroy — query_or_stream at arg 0, action at arg 1
  @bulk_query_funs ~w(bulk_update bulk_update! bulk_destroy bulk_destroy!)a

  @stream_funs ~w(stream!)a

  # Pattern D: resource at arg 0, action at arg 1 (builders)
  @positional_0_1_funs MapSet.new([
                         {[:Ash, :Changeset], :for_create},
                         {[:Ash, :Changeset], :for_update},
                         {[:Ash, :Changeset], :for_destroy},
                         {[:Ash, :Changeset], :for_action},
                         {[:Ash, :Query], :for_read},
                         {[:Ash, :ActionInput], :for_action}
                       ])

  # Builders whose arg 0 is typically a record (struct or variable bound to
  # one) rather than a literal resource module. For these we additionally try
  # to trace the argument's provenance back to a literal resource origin.
  @record_first_builders MapSet.new([
                           {[:Ash, :Changeset], :for_update},
                           {[:Ash, :Changeset], :for_destroy}
                         ])

  # Origin calls from which a bound variable carries a single record whose
  # resource type is the first argument (e.g. `post = Ash.get!(MyApp.Post, id)`).
  # Only the bang variant qualifies: `Ash.get/3` returns `{:ok, record}`, so a
  # binding like `post = Ash.get(Post, id)` holds a result tuple, not a record.
  @record_origin_funs ~w(get!)a

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    config = load_config(params)

    cond do
      not (config.in_domain or config.outside_domain) ->
        []

      not CompiledIntrospection.ash_available?() ->
        ash_missing_diagnostic(issue_meta)

      true ->
        source_file
        |> Introspection.ash_api_calls_with_context()
        |> Enum.flat_map(&check_call(&1, issue_meta, config))
    end
  end

  defp load_config(params) do
    %{
      in_domain: Params.get(params, :enforce_code_interface_in_domain, __MODULE__),
      outside_domain: Params.get(params, :enforce_code_interface_outside_domain, __MODULE__),
      scope: Params.get(params, :prefer_interface_scope, __MODULE__)
    }
  end

  defp ash_missing_diagnostic(issue_meta) do
    if CompiledIntrospection.ash_missing_warned?() do
      []
    else
      CompiledIntrospection.mark_ash_missing_warned()

      [
        format_issue(issue_meta,
          message:
            "Ash is not loaded in the VM running Credo — the UseCodeInterface check is a no-op in this project. Add `:ash` as a dependency, or disable this check in `.credo.exs`.",
          line_no: 1
        )
      ]
    end
  end

  # ── Call-site dispatch ──

  defp check_call(
         %{call_ast: call_ast, expanded_module: expanded_module, args: args} = call_info,
         issue_meta,
         config
       ) do
    {{:., _, [_, fun_name]}, call_meta, _raw_args} = call_ast

    ctx = %{
      fun_name: fun_name,
      module: expanded_module,
      arity: length(args),
      call_meta: call_meta,
      call_info: call_info,
      issue_meta: issue_meta,
      config: config,
      builder_prefix: nil,
      trace_record?: false
    }

    cond do
      expanded_module == [:Ash] and fun_name in @action_in_opts ->
        handle_action_in_opts(args, ctx)

      expanded_module == [:Ash] and fun_name in @bulk_create_funs ->
        handle_positional(args, 1, 2, ctx)

      expanded_module == [:Ash] and fun_name in @bulk_query_funs ->
        handle_bulk_query(args, ctx)

      MapSet.member?(@positional_0_1_funs, {expanded_module, fun_name}) ->
        handle_positional(args, 0, 1, %{
          ctx
          | builder_prefix: builder_prefix(expanded_module),
            trace_record?: MapSet.member?(@record_first_builders, {expanded_module, fun_name})
        })

      true ->
        []
    end
  end

  defp handle_action_in_opts(args, ctx) do
    with {:ok, resource_ast} <- arg_at(args, 0),
         {:ok, segs} <- literal_segments(resource_ast, ast_context(ctx.call_info)),
         action when is_atom(action) and not is_nil(action) <- action_from_opts(args) do
      classify_and_emit(segs, action, ctx)
    else
      _ -> []
    end
  end

  defp handle_positional(args, resource_idx, action_idx, ctx) do
    context = ast_context(ctx.call_info)

    with {:ok, resource_ast} <- arg_at(args, resource_idx),
         {:ok, segs} <- resolve_positional_segments(resource_ast, context, ctx.trace_record?),
         {:ok, action} <- arg_at(args, action_idx),
         true <- is_atom(action) do
      classify_and_emit(segs, action, ctx)
    else
      _ -> []
    end
  end

  defp resolve_positional_segments(ast, context, true) do
    case literal_segments(ast, context) do
      {:ok, segs} -> {:ok, segs}
      :error -> trace_origin_to_literal(ast, context)
    end
  end

  defp resolve_positional_segments(ast, context, false), do: literal_segments(ast, context)

  defp handle_bulk_query(args, ctx) do
    context = ast_context(ctx.call_info)

    with {:ok, query_or_stream} <- arg_at(args, 0),
         {:ok, segs} <- trace_origin_to_literal(query_or_stream, context),
         {:ok, action} <- arg_at(args, 1),
         true <- is_atom(action) do
      classify_and_emit(segs, action, ctx)
    else
      _ -> []
    end
  end

  defp ast_context(call_info) do
    %{
      aliases: call_info.aliases,
      bindings: call_info.bindings,
      enclosing_module_segments: call_info.enclosing_module_segments
    }
  end

  # ── Classification + issue building ──

  defp classify_and_emit(segments, action_name, ctx) do
    resource = Module.concat(segments)

    case CompiledIntrospection.inspect_module(resource) do
      {:ok, info} ->
        handle_loaded(resource, action_name, info, ctx)

      {:error, :not_a_resource} ->
        []

      {:error, :ash_missing} ->
        []

      {:error, :not_loadable} ->
        handle_not_loadable(segments, resource, action_name, ctx)
    end
  end

  defp handle_not_loadable(segments, resource, action_name, ctx) do
    case try_implicit_resolution(segments, ctx) do
      {:ok, atom, info} ->
        handle_loaded(atom, action_name, info, ctx)

      :error ->
        # Unloadable resources fall into the "outside domain" bucket — we
        # cannot confirm the caller shares a domain with something we can't
        # introspect.
        if ctx.config.outside_domain do
          [not_loadable_issue(resource, ctx)]
        else
          []
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

  defp handle_loaded(resource, action_name, info, ctx) do
    case CompiledIntrospection.action(resource, action_name) do
      {:ok, _action} ->
        classification = classify(resource, action_name, info, ctx)

        if enforced?(classification, ctx.config) do
          [build_issue(classification, ctx)]
        else
          []
        end

      {:error, :unknown_action} ->
        # Always emitted — orthogonal to the enforcement flags.
        [unknown_action_issue(resource, action_name, info.actions, ctx)]

      {:error, _} ->
        []
    end
  end

  defp enforced?(%{same_domain?: true}, %{in_domain: in_domain}), do: in_domain
  defp enforced?(%{same_domain?: false}, %{outside_domain: outside}), do: outside

  defp classify(resource, action_name, info, ctx) do
    caller = caller_atom(ctx.call_info)
    caller_domain = caller_domain(caller)
    resource_domain = info.domain

    same_domain? =
      not is_nil(resource_domain) and not is_nil(caller_domain) and
        resource_domain == caller_domain

    %{
      resource: resource,
      action: action_name,
      resource_domain: resource_domain,
      resource_iface: CompiledIntrospection.find_interface(info.interfaces, action_name),
      domain_iface:
        CompiledIntrospection.domain_interface(resource_domain, resource, action_name),
      same_domain?: same_domain?,
      scope: ctx.config.scope,
      bang?: bang?(ctx.fun_name, ctx.builder_prefix),
      builder_prefix: ctx.builder_prefix
    }
  end

  defp caller_atom(%{enclosing_module_segments: segs}) when is_list(segs) and segs != [] do
    Module.concat(segs)
  end

  defp caller_atom(_), do: nil

  defp caller_domain(nil), do: nil

  defp caller_domain(module) do
    cond do
      CompiledIntrospection.domain?(module) ->
        module

      CompiledIntrospection.ash_callback_module?(module) ->
        CompiledIntrospection.enclosing_domain(module)

      true ->
        case CompiledIntrospection.domain(module) do
          {:ok, domain} -> domain
          _ -> nil
        end
    end
  end

  defp build_issue(classification, ctx) do
    qualified = qualified_call(ctx.module, ctx.fun_name)
    suggestion = pick_suggestion(classification)
    message = format_message(suggestion, classification, qualified, ctx.arity)

    format_issue(ctx.issue_meta,
      message: message,
      trigger: qualified,
      line_no: ctx.call_meta[:line]
    )
  end

  # `:resource` preference: always direct at the resource, even across domains.
  defp pick_suggestion(%{scope: :resource, resource_iface: iface}) when not is_nil(iface),
    do: {:use, :resource, iface}

  defp pick_suggestion(%{scope: :resource}), do: {:define, :resource}

  # `:domain` preference: always direct at the domain (when one exists).
  defp pick_suggestion(%{scope: :domain, domain_iface: iface}) when not is_nil(iface),
    do: {:use, :domain, iface}

  defp pick_suggestion(%{scope: :domain, resource_domain: domain}) when not is_nil(domain),
    do: {:define, :domain}

  defp pick_suggestion(%{scope: :domain}), do: {:define, :resource}

  # `:auto`: same-domain callers go to the resource, others to the domain.
  defp pick_suggestion(%{same_domain?: true, resource_iface: iface}) when not is_nil(iface),
    do: {:use, :resource, iface}

  defp pick_suggestion(%{same_domain?: true, domain_iface: iface}) when not is_nil(iface),
    do: {:use, :domain, iface}

  defp pick_suggestion(%{same_domain?: true}), do: {:define, :resource}

  defp pick_suggestion(%{domain_iface: iface}) when not is_nil(iface), do: {:use, :domain, iface}

  defp pick_suggestion(%{resource_iface: iface}) when not is_nil(iface),
    do: {:use, :resource, iface}

  defp pick_suggestion(%{resource_domain: domain}) when not is_nil(domain), do: {:define, :domain}

  defp pick_suggestion(_), do: {:define, :resource}

  defp format_message(
         {:use, :resource, iface},
         %{resource: resource, bang?: bang?, builder_prefix: prefix},
         qualified,
         arity
       ) do
    fun = interface_function_name(iface.name, prefix, bang?)

    "Prefer `#{inspect(resource)}.#{fun}` over `#{qualified}/#{arity}`."
  end

  defp format_message(
         {:use, :domain, iface},
         %{resource_domain: domain, bang?: bang?, builder_prefix: prefix},
         qualified,
         arity
       ) do
    fun = interface_function_name(iface.name, prefix, bang?)

    "Prefer `#{inspect(domain)}.#{fun}` over `#{qualified}/#{arity}`."
  end

  defp format_message(
         {:define, :resource},
         %{resource: resource, action: action},
         qualified,
         arity
       ) do
    "Prefer a code interface on `#{inspect(resource)}` over `#{qualified}/#{arity}`. " <>
      "Define one with `define :#{action}` inside the resource's `code_interface` block."
  end

  defp format_message(
         {:define, :domain},
         %{resource: resource, resource_domain: domain, action: action},
         qualified,
         arity
       ) do
    "Prefer a code interface on `#{inspect(domain)}` over `#{qualified}/#{arity}`. " <>
      "Define one with `define :some_name, action: :#{action}` inside the `resource #{inspect(resource)} do ... end` block of the domain."
  end

  defp interface_function_name(name, nil, true), do: "#{name}!"
  defp interface_function_name(name, nil, false), do: "#{name}"
  defp interface_function_name(name, :changeset_to, _), do: "changeset_to_#{name}"
  defp interface_function_name(name, :query_to, _), do: "query_to_#{name}"
  defp interface_function_name(name, :input_to, _), do: "input_to_#{name}"

  defp builder_prefix([:Ash, :Changeset]), do: :changeset_to
  defp builder_prefix([:Ash, :Query]), do: :query_to
  defp builder_prefix([:Ash, :ActionInput]), do: :input_to
  defp builder_prefix(_), do: nil

  defp bang?(_fun_name, prefix) when not is_nil(prefix), do: false

  defp bang?(fun_name, _prefix), do: fun_name |> Atom.to_string() |> String.ends_with?("!")

  defp unknown_action_issue(resource, action, known_actions, ctx) do
    qualified = qualified_call(ctx.module, ctx.fun_name)
    suggestion = CompiledIntrospection.suggest_action_name(known_actions, action)

    hint =
      case suggestion do
        nil -> ""
        name -> " Did you mean `:#{name}`?"
      end

    format_issue(ctx.issue_meta,
      message:
        "Unknown action `:#{action}` on `#{inspect(resource)}` (called via `#{qualified}/#{ctx.arity}`).#{hint}",
      trigger: qualified,
      line_no: ctx.call_meta[:line]
    )
  end

  defp not_loadable_issue(resource, ctx) do
    qualified = qualified_call(ctx.module, ctx.fun_name)

    format_issue(ctx.issue_meta,
      message:
        "Could not load `#{inspect(resource)}` while checking `#{qualified}/#{ctx.arity}`. Run `mix compile` before `mix credo`, or disable `UseCodeInterface` in `.credo.exs`.",
      trigger: qualified,
      line_no: ctx.call_meta[:line]
    )
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

  # Struct literal: `%MyApp.Post{...}` — extract the inner alias AST.
  defp literal_segments({:%, _, [alias_ast, {:%{}, _, _}]}, context),
    do: literal_segments(alias_ast, context)

  defp literal_segments(_, _), do: :error

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

  defp qualified_call(module, fun_name), do: Name.full(module) <> ".#{fun_name}"
end
