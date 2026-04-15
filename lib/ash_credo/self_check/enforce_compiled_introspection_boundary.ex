defmodule AshCredo.SelfCheck.EnforceCompiledIntrospectionBoundary do
  @moduledoc false

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      All Ash runtime introspection in this project must go through
      `AshCredo.Introspection.Compiled` rather than calling
      `Ash.Resource.Info`, `Ash.Domain.Info`, `Ash.Policy.Info`,
      `Ash.Type.NewType`, or similar Ash introspection modules directly.

      The wrapper caches results in `:persistent_term` so that repeated
      lookups across Credo's per-file task pool are cheap, and it normalises
      the error modes (`:ash_missing`, `:not_loadable`, `:not_a_resource`)
      into a single interface that every check can rely on.

      If you need a new piece of Ash metadata, add a function to
      `AshCredo.Introspection.Compiled` and call that instead.
      """
    ]

  alias AshCredo.Introspection

  @banned_modules [
    [:Ash, :Resource, :Info],
    [:Ash, :Domain, :Info],
    [:Ash, :Policy, :Info],
    [:Ash, :DataLayer, :Ets, :Info],
    [:Ash, :DataLayer, :Mnesia, :Info],
    [:Ash, :Notifier, :PubSub, :Info],
    [:Ash, :TypedStruct, :Info],
    [:Ash, :Type, :NewType],
    [:Ash, :Type]
  ]

  @gateway_path ~w(lib ash_credo introspection compiled.ex)

  @impl true
  def run(%SourceFile{} = source_file, params) do
    if gateway_file?(source_file.filename) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Introspection.ash_api_calls_with_module()
      |> Enum.flat_map(&issue_for_call(&1, issue_meta))
    end
  end

  defp issue_for_call({{{:., _, [_module_ast, func]}, meta, _args}, expanded_module}, issue_meta)
       when expanded_module in @banned_modules do
    module_name = Enum.join(expanded_module, ".")

    [
      format_issue(issue_meta,
        message:
          "Direct call to `#{module_name}.#{func}/…` -- " <>
            "use `AshCredo.Introspection.Compiled` instead.",
        line_no: meta[:line],
        trigger: "#{module_name}.#{func}"
      )
    ]
  end

  defp issue_for_call(_call, _issue_meta), do: []

  defp gateway_file?(filename) when is_binary(filename) do
    Path.split(filename) |> Enum.take(-length(@gateway_path)) == @gateway_path
  end
end
