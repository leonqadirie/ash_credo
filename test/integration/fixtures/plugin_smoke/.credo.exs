%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/"],
        excluded: []
      },
      plugins: [{AshCredo, []}],
      requires: [],
      strict: true,
      parse_timeout: 5000,
      color: false,
      checks: %{
        extra: [
          # Default-off in the plugin's embedded config; enabled here the way
          # a user would, so the integration test can assert that a
          # user-enabled compiled check delivers issues end-to-end.
          {AshCredo.Check.Design.MissingCodeInterface, []}
        ]
      }
    }
  ]
}
