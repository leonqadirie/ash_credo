defmodule AshCredo.Check.Ash.AuthorizerWithoutPolicies do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash, :security],
    explanations: [
      check: """
      Resources that declare `Ash.Policy.Authorizer` but define no policies
      will deny all actions by default. An empty `policies` block has the same
      effect. This is almost always unintentional.

      Either add policies:

          policies do
            policy action_type(:read) do
              authorize_if actor_attribute_equals(:active, true)
            end
          end

      Or remove the authorizer if authorization is not needed yet.
      """
    ]

  alias AshCredo.Check.Helpers

  @impl true
  def run(%SourceFile{} = source_file, params) do
    if Helpers.ash_resource?(source_file) do
      authorizer_line = find_authorizer_line(source_file)

      policies_ast = Helpers.find_dsl_section(source_file, :policies)

      has_policies =
        Helpers.find_all_policy_entities(policies_ast) != []

      if authorizer_line != nil and not has_policies do
        issue_meta = IssueMeta.for(source_file, params)

        [
          format_issue(issue_meta,
            message:
              "Resource has Ash.Policy.Authorizer but no policies defined. All actions will be denied.",
            trigger: "Ash.Policy.Authorizer",
            line_no: authorizer_line
          )
        ]
      else
        []
      end
    else
      []
    end
  end

  defp find_authorizer_line(source_file) do
    Credo.Code.prewalk(
      source_file,
      fn
        {:__aliases__, meta, [:Ash, :Policy, :Authorizer]} = ast, nil ->
          {ast, meta[:line]}

        ast, acc ->
          {ast, acc}
      end,
      nil
    )
  end
end
