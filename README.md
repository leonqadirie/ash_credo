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
mix igniter.install ash_credo --only dev,test
```

This keeps `ash_credo` scoped to the same `:dev`/`:test` environments as `credo`. The installer also sets `runtime: false`.

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
| `MissingCodeInterface` | Design | Low | No | Flags each action that has no code interface (resource- or domain-level). **Requires compiled project.** |
| `MissingIdentity` | Design | Normal | No | Suggests identities for attributes like `email`, `username`, `slug` |
| `MissingPrimaryAction` | Design | Normal | No | Flags missing `primary?: true` when multiple actions of the same type exist. **Requires compiled project.** |
| `MissingTimestamps` | Design | Normal | No | Suggests adding `timestamps()` to persisted resources. **Requires compiled project.** |
| `ActionMissingDescription` | Readability | Low | No | Flags actions without a `description` |
| `BelongsToMissingAllowNil` | Readability | Normal | No | Flags `belongs_to` without explicit `allow_nil?` |
| `LargeResource` | Refactor | Low | No | Flags resource files exceeding 400 lines |
| `UseCodeInterface` | Refactor | Normal | No | Flags `Ash.*` calls where both resource and action are literals — names the exact code interface function to call instead. **Requires compiled project** and **configurable** (see below). |

## Checks that require a compiled project

Four checks read Ash's runtime introspection (`Ash.Resource.Info` and
`Ash.Domain.Info`) rather than source AST. They see the fully-resolved
resource state — including anything Spark transformers or extensions
contribute — and catch bugs that pure AST scanning would miss.

- `Refactor.UseCodeInterface`
- `Design.MissingCodeInterface`
- `Design.MissingPrimaryAction`
- `Design.MissingTimestamps`

**Your project must be compiled before running `mix credo`**, otherwise
these checks emit a configuration diagnostic and become a no-op. Typically
chain the two commands in a Mix alias:

```elixir
# mix.exs
defp aliases do
  [
    lint: ["compile", "credo --strict"]
  ]
end
```

If a referenced resource cannot be loaded, the check emits a per-call-site
"could not load" issue pointing at the resource. If Ash itself is not
available in the VM running Credo (unusual — requires a project that uses
`ash_credo` without depending on Ash), all four checks emit a single shared
diagnostic and become no-ops. You can disable any of them in `.credo.exs`
if your workflow can't run `mix compile` beforehand.

### Adapting `UseCodeInterface` to your team's conventions

`UseCodeInterface` accepts three params that map to common code-interface
philosophies:

```elixir
# Opinion A — raw Ash.* calls are OK when the caller is in the resource's
# domain (e.g. inside a Change / Preparation / Validation module).
{AshCredo.Check.Refactor.UseCodeInterface,
 [enforce_code_interface_in_domain: false]},

# Opinion B — code interfaces are only defined on resources; never suggest
# reaching for a domain-level interface.
{AshCredo.Check.Refactor.UseCodeInterface,
 [prefer_interface_scope: :resource]},

# Opinion A + B — allow same-domain raw calls AND always direct the rest
# at the resource-level interface.
{AshCredo.Check.Refactor.UseCodeInterface,
 [enforce_code_interface_in_domain: false, prefer_interface_scope: :resource]},

# Default — "in-domain → resource, outside-domain → domain" hierarchy.
{AshCredo.Check.Refactor.UseCodeInterface, []},
```

- **`enforce_code_interface_in_domain`** (`true` default) — when `false`, leaves
  callers that share a domain with the resource alone.
- **`enforce_code_interface_outside_domain`** (`true` default) — when `false`,
  silences every case where the caller is not confirmed to be in the resource's
  domain (different domain, plain controller/LiveView, domainless resource,
  `:not_loadable` resource).
- **`prefer_interface_scope`** (`:auto | :resource | :domain`, default `:auto`)
  — overrides which interface the check points at. `:auto` follows the
  in-domain/outside-domain heuristic; `:resource` always suggests a
  resource-level function; `:domain` always suggests a domain-level function.

Unknown-action issues (e.g. `Ash.read!(Post, action: :publishd)`) are always
emitted when the resource loads — disable the whole check to silence them.

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
| `Refactor.UseCodeInterface` | `enforce_code_interface_in_domain` | `true` | When `false`, leaves callers that share a domain with the resource alone (useful when raw `Ash.*` calls inside `Change`/`Preparation`/`Validation` modules are considered acceptable) |
| `Refactor.UseCodeInterface` | `enforce_code_interface_outside_domain` | `true` | When `false`, silences every case where the caller is not confirmed to be in the resource's domain (different known domain, plain caller, `Ash.Resource` without a `:domain`, `:not_loadable` resource) |
| `Refactor.UseCodeInterface` | `prefer_interface_scope` | `:auto` | Overrides which interface is suggested. `:auto` follows the in-domain/outside-domain heuristic. `:resource` always suggests a resource-level interface. `:domain` always suggests a domain-level interface |
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
