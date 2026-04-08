# AshCredo

[![Hex.pm](https://img.shields.io/hexpm/v/ash_credo.svg)](https://hex.pm/packages/ash_credo)
[![HexDocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/ash_credo)
[![License: MIT](https://img.shields.io/badge/license-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)

Unofficial static code analysis checks for the [Ash Framework](https://ash-hq.org), built as a [Credo](https://github.com/rrrene/credo) plugin.

AshCredo detects common anti-patterns, security pitfalls, and missing best practices in your Ash resources and domains by analysing unexpanded source AST.

> [!WARNING]
> This project is experimental and might break frequently.

**Note: Only `MissingChangeWrapper` is enabled by default.** All other checks are opt-in — enable them individually in your `.credo.exs` (see [Configuration](#configuration)).

## Installation

AshCredo requires [Credo](https://hexdocs.pm/credo) to already be installed in your project.

### With Igniter (recommended)

If your project uses [Igniter](https://hexdocs.pm/igniter), a single command will add the dependency and register the plugin in your `.credo.exs`:

```bash
mix igniter.install ash_credo
```

### Manual

Add `ash_credo` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ash_credo, "~> 0.5", only: [:dev, :test], runtime: false}
  ]
end
```

Then fetch the dependency and register the plugin in your `.credo.exs`:

```bash
mix deps.get
```

```elixir
# .credo.exs
%{
  configs: [
    %{
      name: "default",
      plugins: [{AshCredo, []}]
    }
  ]
}
```

### Running

```bash
mix credo
```

## Checks

| Check | Category | Priority | Default | Description |
|---|---|---|---|---|
| `AuthorizeFalse` | Warning | High | No | Flags literal `authorize?: false` in Ash calls, action DSL, and (by default) any other call site |
| `AuthorizerWithoutPolicies` | Warning | High | No | Detects resources with `Ash.Policy.Authorizer` but no policies defined |
| `EmptyDomain` | Warning | Normal | No | Flags domains with no resources registered |
| `MissingChangeWrapper` | Warning | High | Yes | Flags builtin change functions (`manage_relationship`, `set_attribute`, ...) used without `change` wrapper in actions |
| `MissingDomain` | Warning | Normal | No | Ensures non-embedded resources set the `domain:` option |
| `MissingPrimaryKey` | Warning | High | No | Ensures resources with data layers have a primary key |
| `NoActions` | Warning | Normal | No | Flags resources with data layers but no actions defined |
| `OverlyPermissivePolicy` | Warning | High | No | Flags unscoped `authorize_if always()` policies |
| `PinnedTimeInExpression` | Warning | High | No | Flags `^Date.utc_today()` / `^DateTime.utc_now()` in Ash expressions (frozen at compile time) |
| `SensitiveAttributeExposed` | Warning | High | No | Flags sensitive attributes (password, token, secret, ...) not marked `sensitive?: true` |
| `SensitiveFieldInAccept` | Warning | High | No | Flags privilege-escalation fields (`is_admin`, `permissions`, ...) in `accept` lists |
| `WildcardAcceptOnAction` | Warning | High | No | Detects `accept :*` on `create`/`update` actions (mass-assignment risk) |
| `MissingCodeInterface` | Design | Low | No | Suggests adding a `code_interface` for resources with actions |
| `MissingIdentity` | Design | Normal | No | Suggests identities for attributes like `email`, `username`, `slug` |
| `MissingPrimaryAction` | Design | Normal | No | Flags missing `primary?: true` when multiple actions of the same type exist |
| `MissingTimestamps` | Design | Normal | No | Suggests adding `timestamps()` to persisted resources |
| `ActionMissingDescription` | Readability | Low | No | Flags actions without a `description` |
| `BelongsToMissingAllowNil` | Readability | Normal | No | Flags `belongs_to` without explicit `allow_nil?` |
| `LargeResource` | Refactor | Low | No | Flags resource files exceeding 400 lines |
| `UseCodeInterface` | Refactor | Normal | No | Flags `Ash.*` calls where both resource and action are literals — use a code interface function instead |

## Configuration

**Only `MissingChangeWrapper` is enabled by default.** Enable additional checks by adding them to the `extra` section of your `.credo.exs`:

```elixir
%{
  configs: [
    %{
      name: "default",
      plugins: [{AshCredo, []}],
      checks: %{
        extra: [
          # Enable checks
          {AshCredo.Check.Warning.AuthorizeFalse, []},
          {AshCredo.Check.Warning.SensitiveFieldInAccept, []},
          {AshCredo.Check.Warning.WildcardAcceptOnAction, []},

          # Enable with custom parameters
          {AshCredo.Check.Refactor.LargeResource, [max_lines: 250]},
          {AshCredo.Check.Warning.SensitiveAttributeExposed, [
            sensitive_names: ~w(password token secret api_key)a
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

To enable **all** checks at once:

```elixir
checks: %{
  extra: [
    {AshCredo.Check.Warning.AuthorizeFalse, []},
    {AshCredo.Check.Warning.AuthorizerWithoutPolicies, []},
    {AshCredo.Check.Warning.EmptyDomain, []},
    {AshCredo.Check.Warning.MissingDomain, []},
    {AshCredo.Check.Warning.MissingPrimaryKey, []},
    {AshCredo.Check.Warning.NoActions, []},
    {AshCredo.Check.Warning.OverlyPermissivePolicy, []},
    {AshCredo.Check.Warning.PinnedTimeInExpression, []},
    {AshCredo.Check.Warning.SensitiveAttributeExposed, []},
    {AshCredo.Check.Warning.SensitiveFieldInAccept, []},
    {AshCredo.Check.Warning.WildcardAcceptOnAction, []},
    {AshCredo.Check.Design.MissingCodeInterface, []},
    {AshCredo.Check.Design.MissingIdentity, []},
    {AshCredo.Check.Design.MissingPrimaryAction, []},
    {AshCredo.Check.Design.MissingTimestamps, []},
    {AshCredo.Check.Readability.ActionMissingDescription, []},
    {AshCredo.Check.Readability.BelongsToMissingAllowNil, []},
    {AshCredo.Check.Refactor.LargeResource, []},
    {AshCredo.Check.Refactor.UseCodeInterface, []}
  ]
}
```

### Configurable parameters

The following checks accept custom parameters:

| Check | Parameter | Default | Description |
|---|---|---|---|
| `Warning.AuthorizeFalse` | `include_non_ash_calls` | `true` | When `false`, only checks Ash API calls and action DSL definitions |
| `Design.MissingIdentity` | `identity_candidates` | `~w(email username slug handle phone)a` | Attribute names to suggest adding identities for |
| `Refactor.LargeResource` | `max_lines` | `400` | Maximum line count before triggering |
| `Warning.SensitiveAttributeExposed` | `sensitive_names` | `~w(password hashed_password password_hash token secret api_key private_key ssn)a` | Attribute names to flag when not marked `sensitive?: true` |
| `Warning.SensitiveFieldInAccept` | `dangerous_fields` | `~w(is_admin admin permissions api_key secret_key)a` | Field names to flag when found in `accept` lists |

## Contributing

1. [Fork](https://github.com/leonqadirie/ash_credo/fork) the repository
2. Create your feature branch (`git switch -c my-new-check`)
3. Apply formatting and make sure tests and lints pass (`mix format`, `mix test`, `mix lint`)
4. Commit your changes
5. Open a pull request — PR titles must follow the [Conventional Commits](https://www.conventionalcommits.org) format (e.g. `feat: add check for XY`, `fix: handle XY edge case`)

## License

MIT - see [LICENSE](LICENSE) for details.

