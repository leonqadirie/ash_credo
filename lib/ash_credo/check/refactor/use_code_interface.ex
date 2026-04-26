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
          no interface targets it yet.

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

      Detection of references to actions that do not exist on the resource
      lives in `AshCredo.Check.Warning.UnknownAction` - enable that check
      separately if you want typo detection.

      ## Configuration

      Three params let you adapt the check to a team's code-interface
      conventions:

        * `enforce_code_interface_in_domain` (default `true`) - when
          `false`, the check leaves callers that share a domain with the
          resource alone. Useful for teams that consider raw `Ash.*` calls
          inside `Change`/`Preparation`/`Validation` modules acceptable.
        * `enforce_code_interface_outside_domain` (default `true`) - when
          `false`, the check silences every case where the caller is not
          confirmed to be in the resource's domain: different known domain,
          plain caller (controller, LiveView, worker), caller that is an
          `Ash.Resource` with no `:domain`, and resources that cannot be
          loaded.
        * `prefer_interface_scope` (`:auto` | `:resource` | `:domain`,
          default `:auto`) - overrides which interface the check points at.
          `:auto` follows the domain-aware heuristic above. `:resource`
          always suggests a resource-level interface (useful if you only
          define code interfaces on resources). `:domain` always suggests a
          domain-level interface.

      Example - a team that allows raw calls inside their domain and only
      defines interfaces on resources:

          {AshCredo.Check.Refactor.UseCodeInterface,
           [enforce_code_interface_in_domain: false, prefer_interface_scope: :resource]}

      ## Requirements

      The check calls `Code.ensure_compiled/1` on every referenced resource
      to query Ash's introspection API. This means **your project must be
      compiled before running `mix credo`** - typically `mix compile && mix
      credo` or a Mix alias that chains the two.

      If Ash is not available in the VM running Credo, the check is a
      no-op and emits a single diagnostic.

      ## Known limitations

        * Calls made via `import Ash; read!(...)` are not traced - only
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

  alias AshCredo.Introspection.{AshCallResolver, AshCallSite}
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    config = load_config(params)

    if config.in_domain or config.outside_domain do
      CompiledIntrospection.with_compiled_check(
        fn ->
          format_issue(issue_meta,
            message:
              "Ash is not loaded in the VM running Credo - `UseCodeInterface` is a no-op. Add `:ash` as a dependency, or disable this check in `.credo.exs`.",
            line_no: 1
          )
        end,
        fn ->
          source_file
          |> AshCallResolver.sites()
          |> Enum.flat_map(&check_site(&1, issue_meta, config))
        end
      )
    else
      []
    end
  end

  defp load_config(params) do
    %{
      in_domain: Params.get(params, :enforce_code_interface_in_domain, __MODULE__),
      outside_domain: Params.get(params, :enforce_code_interface_outside_domain, __MODULE__),
      scope: Params.get(params, :prefer_interface_scope, __MODULE__)
    }
  end

  defp check_site(%AshCallSite{resolution: {:ok, resource, info}} = site, issue_meta, config) do
    case CompiledIntrospection.action(resource, site.action_name) do
      {:ok, _action} ->
        classification = classify(resource, site.action_name, info, site, config)

        if enforced?(classification, config) do
          classification
          |> build_issue(site, issue_meta)
          |> List.wrap()
        else
          []
        end

      # Owned by `AshCredo.Check.Warning.UnknownAction`. Bundling typo
      # detection into a refactor check obscured it - users disabling the
      # nag also lost a correctness check.
      {:error, :unknown_action} ->
        []

      {:error, _} ->
        []
    end
  end

  # Unloadable resources fall into the "outside domain" bucket - we cannot
  # confirm the caller shares a domain with something we can't introspect.
  # The dedup wrapper ensures one diagnostic per unique broken module across
  # all compile-dependent checks.
  defp check_site(%AshCallSite{resolution: {:not_loadable, resource}} = site, issue_meta, %{
         outside_domain: true
       }) do
    CompiledIntrospection.with_unique_not_loadable(resource, fn ->
      not_loadable_issue(resource, site, issue_meta)
    end)
  end

  defp check_site(%AshCallSite{}, _issue_meta, _config), do: []

  defp enforced?(%{same_domain?: true}, %{in_domain: in_domain}), do: in_domain
  defp enforced?(%{same_domain?: false}, %{outside_domain: outside}), do: outside

  defp classify(resource, action_name, info, site, config) do
    caller = caller_atom(site.call_info)
    caller_domain = caller_domain(caller)
    resource_domain = info.domain

    same_domain? =
      not is_nil(resource_domain) and not is_nil(caller_domain) and
        resource_domain == caller_domain

    %{
      resource: resource,
      action: action_name,
      resource_domain: resource_domain,
      resource_iface: matching_interface(info.interfaces, action_name, site, info),
      domain_iface: domain_interface(resource_domain, resource, action_name, site, info),
      same_domain?: same_domain?,
      scope: config.scope,
      bang?: AshCallResolver.bang?(site),
      builder_prefix: site.builder_prefix,
      call_kind: site.call_kind,
      lookup_keys: site.lookup_keys,
      identities: info.identities
    }
  end

  defp domain_interface(nil, _resource, _action_name, _site, _info), do: nil

  defp domain_interface(domain, resource, action_name, site, info) do
    domain
    |> CompiledIntrospection.domain_interfaces(resource)
    |> matching_interface(action_name, site, info)
  end

  defp matching_interface(interfaces, action_name, site, info) do
    Enum.find(interfaces, fn iface ->
      interface_action?(iface, action_name) and interface_matches_site?(iface, site, info)
    end)
  end

  defp interface_action?(iface, action_name) do
    (Map.get(iface, :action) || Map.get(iface, :name)) == action_name
  end

  defp interface_matches_site?(iface, %{call_kind: :get_one, lookup_keys: keys}, info) do
    get_interface_for_keys?(iface, keys, info)
  end

  defp interface_matches_site?(iface, %{call_kind: kind}, _info)
       when kind in [:read_many, :stream_many] do
    not get_interface?(iface)
  end

  defp interface_matches_site?(iface, %{builder_prefix: prefix}, _info) when not is_nil(prefix) do
    not get_interface?(iface)
  end

  defp interface_matches_site?(_iface, _site, _info), do: true

  defp get_interface_for_keys?(_iface, keys, _info) when keys in [nil, []], do: false

  defp get_interface_for_keys?(iface, keys, info) do
    case interface_lookup_keys(iface, info) do
      nil -> false
      iface_keys -> same_keys?(iface_keys, keys)
    end
  end

  defp interface_lookup_keys(iface, info) do
    cond do
      Map.get(iface, :get_by) ->
        List.wrap(Map.get(iface, :get_by))

      Map.get(iface, :get_by_identity) ->
        identity_keys(info, Map.get(iface, :get_by_identity))

      true ->
        nil
    end
  end

  defp identity_keys(%{identities: identities}, identity_name) when is_list(identities) do
    Enum.find_value(identities, fn identity ->
      if Map.get(identity, :name) == identity_name, do: Map.get(identity, :keys)
    end)
  end

  defp identity_keys(_info, _identity_name), do: nil

  defp same_keys?(left, right) when is_list(left) and is_list(right) do
    MapSet.new(left) == MapSet.new(right)
  end

  defp get_interface?(iface) do
    Map.get(iface, :get?) == true or
      not is_nil(Map.get(iface, :get_by)) or
      not is_nil(Map.get(iface, :get_by_identity))
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

  defp build_issue(classification, site, issue_meta) do
    qualified = AshCallResolver.qualified_call(site)

    case pick_suggestion(classification) do
      nil ->
        nil

      suggestion ->
        message = format_message(suggestion, classification, qualified, site.arity)

        format_issue(issue_meta,
          message: message,
          trigger: qualified,
          line_no: site.call_meta[:line]
        )
    end
  end

  defp pick_suggestion(%{call_kind: :get_one, lookup_keys: keys}) when keys in [nil, []], do: nil

  # `:resource` preference: always direct at the resource, even across domains.
  defp pick_suggestion(%{scope: :resource, resource_iface: iface}) when not is_nil(iface),
    do: {:use, :resource, iface}

  defp pick_suggestion(%{scope: :resource}), do: {:define, :resource}

  # `:domain` preference: always direct at the domain (when one exists).
  defp pick_suggestion(%{scope: :domain, domain_iface: iface}) when not is_nil(iface),
    do: {:use, :domain, iface}

  defp pick_suggestion(%{scope: :domain, resource_domain: domain}) when not is_nil(domain),
    do: {:define, :domain}

  # Resource has no domain at all → no domain interface to point at, so we
  # fall back to suggesting a resource-level interface even though the user
  # preferred :domain. There's no other meaningful answer here.
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
         %{resource: resource} = classification,
         qualified,
         arity
       ) do
    fun = interface_call(iface, classification)

    "Prefer `#{inspect(resource)}.#{fun}` over `#{qualified}/#{arity}`."
  end

  defp format_message(
         {:use, :domain, iface},
         %{resource_domain: domain} = classification,
         qualified,
         arity
       ) do
    fun = interface_call(iface, classification)

    "Prefer `#{inspect(domain)}.#{fun}` over `#{qualified}/#{arity}`."
  end

  defp format_message(
         {:define, :resource},
         %{resource: resource, action: action, call_kind: :get_one, lookup_keys: keys},
         qualified,
         arity
       ) do
    "Prefer a get-by code interface on `#{inspect(resource)}` over `#{qualified}/#{arity}`. " <>
      "Define one with `define :#{get_define_name(action, keys)}, action: :#{action}, get_by: #{inspect(keys)}` inside the resource's `code_interface` block."
  end

  defp format_message(
         {:define, :domain},
         %{
           resource: resource,
           resource_domain: domain,
           action: action,
           call_kind: :get_one,
           lookup_keys: keys
         },
         qualified,
         arity
       ) do
    "Prefer a get-by code interface on `#{inspect(domain)}` over `#{qualified}/#{arity}`. " <>
      "Define one with `define :#{get_define_name(action, keys)}, action: :#{action}, get_by: #{inspect(keys)}` inside the `resource #{inspect(resource)} do ... end` block of the domain."
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

  defp interface_call(iface, %{call_kind: :get_one, identities: identities} = classification) do
    fun = interface_function_name(iface.name, classification.builder_prefix, classification.bang?)
    keys = interface_lookup_keys(iface, %{identities: identities}) || classification.lookup_keys
    args = get_call_args(keys, iface)

    "#{fun}(#{Enum.join(args, ", ")})"
  end

  defp interface_call(iface, %{call_kind: :stream_many} = classification) do
    fun = interface_function_name(iface.name, classification.builder_prefix, true)

    "#{fun}(stream?: true)"
  end

  defp interface_call(iface, classification) do
    interface_function_name(iface.name, classification.builder_prefix, classification.bang?)
  end

  defp get_call_args(keys, iface) when is_list(keys) do
    args = Enum.map(keys, &Atom.to_string/1)

    if Map.get(iface, :not_found_error?) == false do
      args
    else
      args ++ ["not_found_error?: false"]
    end
  end

  defp get_define_name(:read, keys), do: "get_by_#{keys_suffix(keys)}"
  defp get_define_name(action, keys), do: "get_#{action}_by_#{keys_suffix(keys)}"

  defp keys_suffix(keys) do
    keys
    |> Enum.map_join("_and_", &Atom.to_string/1)
  end

  defp not_loadable_issue(resource, site, issue_meta) do
    qualified = AshCallResolver.qualified_call(site)

    format_issue(issue_meta,
      message:
        "Could not load `#{inspect(resource)}` while checking `#{qualified}/#{site.arity}`. Run `mix compile` before `mix credo`, or disable `UseCodeInterface` in `.credo.exs`.",
      trigger: qualified,
      line_no: site.call_meta[:line]
    )
  end
end
