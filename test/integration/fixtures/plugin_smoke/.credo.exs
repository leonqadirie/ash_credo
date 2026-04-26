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
      checks: %{}
    }
  ]
}
