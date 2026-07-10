defmodule AshCredo.Check.Refactor.UseCodeInterface do
  use AshCredo.CompiledCheck,
    base_priority: :normal,
    category: :refactor,
    tags: [:ash],
    param_defaults: [
      enforce_code_interface_in_domain: true,
      enforce_code_interface_outside_domain: true,
      excluded_paths: [~r"/test/", "test"],
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

      `Ash.read_one` calls only match no-key interfaces configured with
      `get?: true`. `Ash.read_first` calls are intentionally not flagged:
      generated get interfaces use `Ash.read_one` and therefore do not
      preserve `read_first`'s behavior when several records match.

      Detection of references to actions that do not exist on the resource
      lives in `AshCredo.Check.Warning.UnknownAction` - enable that check
      separately if you want typo detection.

      ## Configuration

      These params adapt the check to a team's code-interface
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
        * `excluded_paths` (defaults to test directories) - raw `Ash.*`
          calls in tests and factories are idiomatic setup code, not
          missing interfaces. Override (e.g. to `[]`) to scan tests too.

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
        excluded_paths:
          "Paths or regexes to skip. Defaults to test directories, where raw `Ash.*` calls are idiomatic setup code.",
        prefer_interface_scope:
          "Controls which interface the check points at. `:auto` (default) follows the \"in-domain → resource, outside-domain → domain\" heuristic. `:resource` always suggests a resource-level interface. `:domain` always suggests a domain-level interface."
      ]
    ]

  alias AshCredo.Introspection.{AshCallResolver, AshCallSite}
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection
  alias AshCredo.PathFilter

  # Path filtering lives here rather than in `run_compiled/2` so an
  # excluded file cannot emit the Ash-missing diagnostic either - the
  # guard consults `active?/2` before checking Ash availability.
  @impl AshCredo.CompiledCheck
  def active?(source_file, params) do
    enforcing? =
      Params.get(params, :enforce_code_interface_in_domain, __MODULE__) or
        Params.get(params, :enforce_code_interface_outside_domain, __MODULE__)

    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    enforcing? and not PathFilter.excluded?(source_file.filename, excluded_paths)
  end

  @impl AshCredo.CompiledCheck
  def run_compiled(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    config = load_config(params)

    source_file
    |> AshCallResolver.sites()
    |> Enum.flat_map(&check_site(&1, issue_meta, config))
  end

  defp load_config(params) do
    %{
      in_domain: Params.get(params, :enforce_code_interface_in_domain, __MODULE__),
      outside_domain: Params.get(params, :enforce_code_interface_outside_domain, __MODULE__),
      scope: Params.get(params, :prefer_interface_scope, __MODULE__)
    }
  end

  # A generated read code interface either lists records or uses `Ash.read_one`
  # when configured with `get?: true`. It cannot preserve `Ash.read_first`'s
  # "take the first record even when several match" semantics.
  defp check_site(
         %AshCallSite{call_kind: :read_first, resolution: {:ok, _resource, _info}},
         _issue_meta,
         _config
       ), do: []

  defp check_site(%AshCallSite{resolution: {:ok, resource, info}} = site, issue_meta, config) do
    case CompiledIntrospection.action(resource, site.action_name) do
      {:ok, action} ->
        classification = classify(resource, site.action_name, action, info, site, config)

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

  defp classify(resource, action_name, action, info, site, config) do
    caller = caller_atom(site.call_info)
    caller_domain = caller_domain(caller)
    resource_domain = info.domain

    same_domain? =
      not is_nil(resource_domain) and not is_nil(caller_domain) and
        resource_domain == caller_domain

    %{
      resource: resource,
      action: action_name,
      action_type: action.type,
      resource_domain: resource_domain,
      resource_iface: matching_interface(info.interfaces, action_name, action, site, info),
      domain_iface: domain_interface(resource_domain, resource, action_name, action, site, info),
      same_domain?: same_domain?,
      scope: config.scope,
      bang?: AshCallResolver.bang?(site),
      builder_prefix: site.builder_prefix,
      call_kind: site.call_kind,
      fun_name: site.fun_name,
      lookup_keys: site.lookup_keys,
      identities: info.identities,
      not_found_error?: read_one_not_found_error(site)
    }
  end

  defp domain_interface(nil, _resource, _action_name, _action, _site, _info), do: nil

  defp domain_interface(domain, resource, action_name, action, site, info) do
    domain
    |> CompiledIntrospection.domain_interfaces(resource)
    |> matching_interface(action_name, action, site, info)
  end

  defp matching_interface(interfaces, action_name, action, site, info) do
    Enum.find(interfaces, fn iface ->
      interface_action?(iface, action_name) and
        interface_matches_site?(iface, action, site, info)
    end)
  end

  defp interface_action?(iface, action_name) do
    (iface.action || iface.name) == action_name
  end

  defp interface_matches_site?(iface, _action, %{call_kind: :get_one, lookup_keys: keys}, info) do
    get_interface_for_keys?(iface, keys, info)
  end

  defp interface_matches_site?(iface, action, %{call_kind: :read_one}, info) do
    effective_get_interface?(iface, action) and is_nil(interface_lookup_keys(iface, info)) and
      no_required_interface_args?(iface)
  end

  defp interface_matches_site?(iface, _action, %{call_kind: kind}, _info)
       when kind in [:read_many, :stream_many] do
    not get_interface?(iface)
  end

  defp interface_matches_site?(iface, _action, %{builder_prefix: prefix}, _info)
       when not is_nil(prefix) do
    not get_interface?(iface)
  end

  defp interface_matches_site?(_iface, _action, _site, _info), do: true

  defp effective_get_interface?(iface, action) do
    get_interface?(iface) or Map.get(action, :get?) == true
  end

  defp get_interface_for_keys?(_iface, keys, _info) when keys in [nil, []], do: false

  defp get_interface_for_keys?(iface, keys, info) do
    case interface_lookup_keys(iface, info) do
      nil -> false
      iface_keys -> same_keys?(iface_keys, keys)
    end
  end

  defp interface_lookup_keys(iface, info) do
    cond do
      iface.get_by -> List.wrap(iface.get_by)
      iface.get_by_identity -> identity_keys(info, iface.get_by_identity)
      true -> nil
    end
  end

  defp identity_keys(%{identities: identities}, identity_name) when is_list(identities) do
    Enum.find_value(identities, fn identity ->
      if identity.name == identity_name, do: identity.keys
    end)
  end

  defp identity_keys(_info, _identity_name), do: nil

  defp same_keys?(left, right) when is_list(left) and is_list(right) do
    MapSet.new(left) == MapSet.new(right)
  end

  defp get_interface?(iface) do
    iface.get? == true or not is_nil(iface.get_by) or not is_nil(iface.get_by_identity)
  end

  defp no_required_interface_args?(iface) do
    Enum.all?(iface.args || [], &match?({:optional, _}, &1))
  end

  defp read_one_not_found_error(%{call_kind: :read_one, call_info: %{args: args}}) do
    case Enum.fetch(args, 1) do
      {:ok, opts} when is_list(opts) -> literal_not_found_error(opts)
      {:ok, _dynamic_opts} -> :dynamic
      :error -> false
    end
  end

  defp read_one_not_found_error(_site), do: nil

  defp literal_not_found_error(opts) do
    case Keyword.fetch(opts, :not_found_error?) do
      {:ok, value} when is_boolean(value) -> value
      {:ok, _dynamic_value} -> :dynamic
      :error -> false
    end
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
        message =
          format_message(suggestion, classification, qualified, site.arity) <>
            bulk_suffix(classification)

        format_issue(issue_meta,
          message: message,
          trigger: qualified,
          line_no: site.call_meta[:line]
        )
    end
  end

  defp pick_suggestion(%{call_kind: :get_one, lookup_keys: keys}) when keys in [nil, []], do: nil

  defp pick_suggestion(%{call_kind: :read_one, not_found_error?: :dynamic}), do: nil

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
         %{resource: resource, action: action, call_kind: :read_one},
         qualified,
         arity
       ) do
    "Prefer a get code interface on `#{inspect(resource)}` over `#{qualified}/#{arity}`. " <>
      "Define one with `define :#{action}, get?: true` inside the resource's `code_interface` block."
  end

  defp format_message(
         {:define, :domain},
         %{resource: resource, resource_domain: domain, action: action, call_kind: :read_one},
         qualified,
         arity
       ) do
    "Prefer a get code interface on `#{inspect(domain)}` over `#{qualified}/#{arity}`. " <>
      "Define one with `define :some_name, action: :#{action}, get?: true` inside the `resource #{inspect(resource)} do ... end` block of the domain."
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

  defp interface_call(iface, %{call_kind: :read_one} = classification) do
    fun = interface_function_name(iface.name, classification.builder_prefix, classification.bang?)
    args = read_one_call_args(iface, classification.not_found_error?)

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

  defp read_one_call_args(iface, not_found_error?) when is_boolean(not_found_error?) do
    if interface_not_found_error?(iface) == not_found_error? do
      []
    else
      ["not_found_error?: #{not_found_error?}"]
    end
  end

  defp interface_not_found_error?(iface), do: Map.get(iface, :not_found_error?) != false

  defp get_define_name(:read, keys), do: "get_by_#{keys_suffix(keys)}"
  defp get_define_name(action, keys), do: "get_#{action}_by_#{keys_suffix(keys)}"

  defp keys_suffix(keys) do
    keys
    |> Enum.map_join("_and_", &Atom.to_string/1)
  end

  # Appended to bulk-call suggestions so users know the code-interface form
  # dispatches to `Ash.bulk_*` based on input shape, and that bulk-only opts
  # (e.g. `return_records?`, `return_errors?`) must live under `bulk_options:`
  # - they are not part of the single-action option schema and Spark.Options
  # rejects them at the top level.
  #
  # Destroy gets a distinct tail: the generated destroy code interface
  # overwrites `return_records?` from the top-level `return_destroyed?` opt
  # (see `Ash.CodeInterface.destroy_act/9`), so passing `return_records?`
  # under `bulk_options:` silently fails to return records. Point users at
  # `return_destroyed?: true` instead.
  defp bulk_suffix(%{call_kind: :bulk, fun_name: fun, action_type: type}) do
    cond do
      fun in [:bulk_create, :bulk_create!] and type == :create ->
        " " <> bulk_tail("Ash.bulk_create", "a list or stream")

      fun in [:bulk_update, :bulk_update!] and type == :update ->
        " " <> bulk_tail("Ash.bulk_update", "a query, list, or stream")

      fun in [:bulk_destroy, :bulk_destroy!] and type == :destroy ->
        " " <> destroy_bulk_tail()

      true ->
        ""
    end
  end

  defp bulk_suffix(_), do: ""

  defp bulk_tail(verb, subject) do
    "Code interfaces dispatch to `#{verb}` when called with #{subject}; " <>
      "pass bulk-only opts (e.g. `return_records?`, `return_errors?`) under `bulk_options: [...]`."
  end

  defp destroy_bulk_tail do
    "Code interfaces dispatch to `Ash.bulk_destroy` when called with a query, list, or stream; " <>
      "pass bulk-only opts such as `return_errors?` under `bulk_options: [...]`; " <>
      "use `return_destroyed?: true` to return destroyed records."
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
