# AshCredo

Unofficial static code analysis checks for the [Ash Framework](https://ash-hq.org), built as a [Credo](https://github.com/rrrene/credo) plugin.

AshCredo detects common anti-patterns, security pitfalls, and missing best practices in your Ash resources and domains by analysing unexpanded source AST.

> [!WARNING]
> This project is experimental and not yet released on Hex. Install directly from GitHub.

## Installation

Add `ash_credo` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ash_credo, github: "leonqadirie/ash_credo", only: [:dev, :test], runtime: false}
  ]
end
```

Then fetch the dependency:

```bash
mix deps.get
```

## Setup

Register the plugin in your `.credo.exs` configuration:

```elixir
%{
  configs: [
    %{
      name: "default",
      plugins: [{AshCredo, []}]
    }
  ]
}
```

That's it. All 16 checks are enabled by default. Run Credo as usual:

```bash
mix credo
```

## Checks

| Check | Category | Priority | Description |
|---|---|---|---|
| `SensitiveAttributeExposed` | Security | High | Flags sensitive attributes (password, token, secret, ...) not marked `sensitive?: true` |
| `AuthorizerWithoutPolicies` | Security | High | Detects resources with `Ash.Policy.Authorizer` but no policies defined |
| `OverlyPermissivePolicy` | Security | High | Flags unscoped `authorize_if always()` policies |
| `WildcardAcceptOnAction` | Security | High | Detects `accept :*` on `create`/`update` actions (mass-assignment risk) |
| `SensitiveFieldInAccept` | Security | High | Flags privilege-escalation fields (`is_admin`, `permissions`, ...) in `accept` lists |
| `MissingPrimaryKey` | Warning | High | Ensures resources with data layers have a primary key |
| `MissingDomain` | Warning | Normal | Ensures non-embedded resources set the `domain:` option |
| `NoActions` | Warning | Normal | Flags resources with data layers but no actions defined |
| `EmptyDomain` | Warning | Normal | Flags domains with no resources registered |
| `MissingTimestamps` | Design | Normal | Suggests adding `timestamps()` to persisted resources |
| `MissingPrimaryAction` | Design | Normal | Flags missing `primary?: true` when multiple actions of the same type exist |
| `MissingIdentity` | Design | Normal | Suggests identities for attributes like `email`, `username`, `slug` |
| `BelongsToMissingAllowNil` | Readability | Normal | Flags `belongs_to` without explicit `allow_nil?` |
| `MissingCodeInterface` | Design | Low | Suggests adding a `code_interface` for resources with actions |
| `ActionMissingDescription` | Readability | Low | Flags actions without a `description` |
| `LargeResource` | Refactor | Low | Flags resource files exceeding 300 lines |

## Configuration

Checks are registered under the `extra` category. You can disable individual checks or customise their parameters in `.credo.exs`:

```elixir
%{
  configs: [
    %{
      name: "default",
      plugins: [{AshCredo, []}],
      checks: %{
        extra: [
          # Disable a check
          {AshCredo.Check.Ash.MissingCodeInterface, false},

          # Customise parameters
          {AshCredo.Check.Ash.LargeResource, [max_lines: 250]},
          {AshCredo.Check.Ash.SensitiveAttributeExposed, [
            sensitive_names: ~w(password token secret api_key)a
          ]},
          {AshCredo.Check.Ash.SensitiveFieldInAccept, [
            dangerous_fields: ~w(is_admin role permissions)a
          ]},
          {AshCredo.Check.Ash.MissingIdentity, [
            identity_candidates: ~w(email username slug)a
          ]}
        ]
      }
    }
  ]
}
```

## Contributing

1. [Fork](https://github.com/leonqadirie/ash_credo/fork) the repository
2. Create your feature branch (`git switch -c my-new-check`)
3. Apply formatting and make sure tests and lints pass (`mix format`, `mix credo`, `mix test`)
4. Commit your changes
5. Open a pull request

## License

MIT - see [LICENSE](LICENSE) for details.

