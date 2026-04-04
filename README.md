# AshCredo

Unofficial static code analysis checks for the [Ash Framework](https://ash-hq.org), built as a [Credo](https://github.com/rrrene/credo) plugin.

AshCredo detects common anti-patterns, security pitfalls, and missing best practices in your Ash resources and domains by analysing unexpanded source AST.

> [!WARNING]
> This project is experimental and might break frequently.

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

That's it. All 18 checks are enabled by default. Run Credo as usual:

```bash
mix credo
```

## Checks

| Check | Category | Priority | Description |
|---|---|---|---|
| `AuthorizerWithoutPolicies` | Warning | High | Detects resources with `Ash.Policy.Authorizer` but no policies defined |
| `MissingChangeWrapper` | Warning | High | Flags builtin change functions (`manage_relationship`, `set_attribute`, ...) used without `change` wrapper in actions |
| `MissingPrimaryKey` | Warning | High | Ensures resources with data layers have a primary key |
| `OverlyPermissivePolicy` | Warning | High | Flags unscoped `authorize_if always()` policies |
| `PinnedTimeInExpression` | Warning | High | Flags `^Date.utc_today()` / `^DateTime.utc_now()` in Ash expressions (frozen at compile time) |
| `SensitiveAttributeExposed` | Warning | High | Flags sensitive attributes (password, token, secret, ...) not marked `sensitive?: true` |
| `SensitiveFieldInAccept` | Warning | High | Flags privilege-escalation fields (`is_admin`, `permissions`, ...) in `accept` lists |
| `WildcardAcceptOnAction` | Warning | High | Detects `accept :*` on `create`/`update` actions (mass-assignment risk) |
| `EmptyDomain` | Warning | Normal | Flags domains with no resources registered |
| `MissingDomain` | Warning | Normal | Ensures non-embedded resources set the `domain:` option |
| `NoActions` | Warning | Normal | Flags resources with data layers but no actions defined |
| `MissingCodeInterface` | Design | Low | Suggests adding a `code_interface` for resources with actions |
| `MissingIdentity` | Design | Normal | Suggests identities for attributes like `email`, `username`, `slug` |
| `MissingPrimaryAction` | Design | Normal | Flags missing `primary?: true` when multiple actions of the same type exist |
| `MissingTimestamps` | Design | Normal | Suggests adding `timestamps()` to persisted resources |
| `ActionMissingDescription` | Readability | Low | Flags actions without a `description` |
| `BelongsToMissingAllowNil` | Readability | Normal | Flags `belongs_to` without explicit `allow_nil?` |
| `LargeResource` | Refactor | Low | Flags resource files exceeding 400 lines |

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
          {AshCredo.Check.Design.MissingCodeInterface, false},

          # Set priority (can also be false to disable)
          {AshCredo.Check.Warning.NoActions, [priority: :low]},

          # Customise parameters
          {AshCredo.Check.Refactor.LargeResource, [max_lines: 250]},
          {AshCredo.Check.Warning.SensitiveAttributeExposed, [
            sensitive_names: ~w(password token secret api_key)a
          ]},
          {AshCredo.Check.Warning.SensitiveFieldInAccept, [
            dangerous_fields: ~w(is_admin role permissions)a
          ]},
          {AshCredo.Check.Design.MissingIdentity, [
            identity_candidates: ~w(email username slug)a
          ]}
        ]
      }
    }
  ]
}
```

### Configurable parameters

The following checks accept custom parameters:

| Check | Parameter | Default | Description |
|---|---|---|---|
| `Design.MissingIdentity` | `identity_candidates` | `~w(email username slug handle phone)a` | Attribute names to suggest adding identities for |
| `Refactor.LargeResource` | `max_lines` | `400` | Maximum line count before triggering |
| `Warning.SensitiveAttributeExposed` | `sensitive_names` | `~w(password hashed_password password_hash token secret api_key private_key ssn)a` | Attribute names to flag when not marked `sensitive?: true` |
| `Warning.SensitiveFieldInAccept` | `dangerous_fields` | `~w(is_admin admin permissions api_key secret_key)a` | Field names to flag when found in `accept` lists |

## Contributing

1. [Fork](https://github.com/leonqadirie/ash_credo/fork) the repository
2. Create your feature branch (`git switch -c my-new-check`)
3. Apply formatting and make sure tests and lints pass (`mix format`, `mix credo`, `mix test`)
4. Commit your changes
5. Open a pull request

## License

MIT - see [LICENSE](LICENSE) for details.

