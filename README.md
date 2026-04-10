# AshCredo

[![Hex.pm](https://img.shields.io/hexpm/v/ash_credo.svg)](https://hex.pm/packages/ash_credo)
[![HexDocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/ash_credo)
[![License: MIT](https://img.shields.io/badge/license-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)

Unofficial static code analysis checks for the [Ash Framework](https://ash-hq.org), built as a [Credo](https://github.com/rrrene/credo) plugin.

AshCredo detects common anti-patterns, security pitfalls, and missing best practices in your Ash resources and domains. Some checks analyse unexpanded source AST; others read Ash's runtime introspection to see the fully-resolved DSL state, including anything Spark transformers and extensions contribute.

> [!WARNING]
> This project is experimental and might break frequently.

**Note: Only `MissingChangeWrapper` is enabled by default.** All other checks are opt-in - enable them individually in your `.credo.exs` (see [Configuration](#configuration)).

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

If you have any compiled-introspection checks enabled, run `mix compile` before `mix credo` - typically via a Mix alias like `lint: ["compile", "credo --strict"]`. See [Checks that require a compiled project](#checks-that-require-a-compiled-project) for the full list and the rationale.

## Checks

| Check | Category | Priority | Default | Description |
|---|---|---|---|---|
| `AuthorizeFalse` | Warning | High | No | Flags literal `authorize?: false` in Ash calls, action DSL, and (by default) any other call site |
| `AuthorizerWithoutPolicies` | Warning | High | No | Detects resources with `Ash.Policy.Authorizer` but no policies defined. **Requires compiled project.** |
| `EmptyDomain` | Warning | Normal | No | Flags domains with no resources registered |
| `MissingChangeWrapper` | Warning | High | Yes | Flags builtin change functions (`manage_relationship`, `set_attribute`, ...) used without `change` wrapper in actions |
| `MissingDomain` | Warning | Normal | No | Ensures non-embedded resources set the `domain:` option |
| `MissingMacroDirective` | Warning | High | No | Flags qualified calls to `Ash.Query`/`Ash.Expr` macros (`filter`, `expr`, ...) when the enclosing module does not have a matching module-level `require`/`import`. Catches the runtime `UndefinedFunctionError` that slips past the compiler when the macro argument is a bare runtime value. **Requires compiled project** and **configurable**. |
| `MissingPrimaryKey` | Warning | High | No | Ensures resources with data layers have a primary key |
| `NoActions` | Warning | Normal | No | Flags resources with data layers but no actions defined. **Requires compiled project.** |
| `OverlyPermissivePolicy` | Warning | High | No | Flags unscoped `authorize_if always()` policies |
| `PinnedTimeInExpression` | Warning | High | No | Flags `^Date.utc_today()` / `^DateTime.utc_now()` in Ash expressions (frozen at compile time) |
| `SensitiveAttributeExposed` | Warning | High | No | Flags sensitive attributes (password, token, secret, ...) not marked `sensitive?: true` |
| `SensitiveFieldInAccept` | Warning | High | No | Flags privilege-escalation fields (`is_admin`, `permissions`, ...) in `accept` lists |
| `UnknownAction` | Warning | High | No | Flags `Ash.*` calls referencing actions that do not exist on the resolved resource, with a fuzzy `Did you mean` hint. **Requires compiled project.** |
| `WildcardAcceptOnAction` | Warning | High | No | Detects `accept :*` on `create`/`update` actions (mass-assignment risk) |
| `MissingCodeInterface` | Design | Low | No | Flags each action that has no code interface (resource- or domain-level). **Requires compiled project.** |
| `MissingIdentity` | Design | Normal | No | Suggests identities for attributes like `email`, `username`, `slug`. **Requires compiled project.** |
| `MissingPrimaryAction` | Design | Normal | No | Flags missing `primary?: true` when multiple actions of the same type exist. **Requires compiled project.** |
| `MissingTimestamps` | Design | Normal | No | Suggests adding `timestamps()` to persisted resources. **Requires compiled project.** |
| `ActionMissingDescription` | Readability | Low | No | Flags actions without a `description` |
| `BelongsToMissingAllowNil` | Readability | Normal | No | Flags `belongs_to` without explicit `allow_nil?` |
| `LargeResource` | Refactor | Low | No | Flags resource files exceeding 400 lines |
| `UseCodeInterface` | Refactor | Normal | No | Flags `Ash.*` calls where both resource and action are literals - names the exact code interface function to call instead. **Requires compiled project** and **configurable** (see below). Pair with `Warning.UnknownAction` for typo detection. |

## Checks that require a compiled project

Several checks read Ash's runtime introspection (`Ash.Resource.Info`, `Ash.Domain.Info`, and `Ash.Policy.Info`) rather than source AST.
They see the fully-resolved resource state - including anything Spark transformers or extensions contribute - and catch bugs that pure AST scanning would miss (e.g. identities on AshAuthentication-injected `:email` attributes, fragment-spliced actions, extension-added authorizers).

- `Refactor.UseCodeInterface`
- `Design.MissingCodeInterface`
- `Design.MissingPrimaryAction`
- `Design.MissingTimestamps`
- `Design.MissingIdentity`
- `Warning.MissingMacroDirective`
- `Warning.NoActions`
- `Warning.AuthorizerWithoutPolicies`
- `Warning.UnknownAction`

**Your project must be compiled before running `mix credo`**, otherwise these checks emit a configuration diagnostic and become a no-op.
Typically chain the two commands in a Mix alias:

```elixir
# mix.exs
defp aliases do
  [
    lint: ["compile", "credo --strict"]
  ]
end
```

If a referenced resource cannot be loaded, the check emits a per-call-site "could not load" issue pointing at the resource. If Ash itself is not available in the VM running Credo (why are you using `ash_credo` without depending on Ash?), these checks emit a single shared diagnostic and become no-ops. You can disable any of them in `.credo.exs` if your workflow can't run `mix compile` beforehand.

### Caching and long-lived VMs

Compiled checks cache introspection results (per-module facts, per-domain resource references, and the `ash_available?` probe) in Erlang's `:persistent_term`. This keeps a single `mix credo` run cheap - Credo dispatches each check × file pair into its own short-lived task, and `:persistent_term` is the only process-independent store that survives that task churn without the ETS ownership problem.

This has ramifications for setups that reuse a single BEAM across multiple Credo invocations:

- **`mix credo` from the shell** - each invocation boots a fresh VM, so the cache is always empty at the start. No action needed.
- **Long-running `iex -S mix` sessions that invoke Credo repeatedly, file-watchers, custom Mix tasks that call Credo in-process** - the cache persists across runs in the same VM. After you edit a resource and recompile, the code reload refreshes the modules themselves, but the cached introspection snapshots under the old module versions remain in `:persistent_term` until the VM exits. Compiled checks may then report on stale DSL state (missing an action you just added, flagging an identity you just introduced, etc.).

If you hit stale results in a long-lived VM, restart it or run `AshCredo.Introspection.Compiled.clear_cache/0`.

## Configuration

Enable additional checks by adding them to the `extra` section of your `.credo.exs`:

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

To enable **all** checks at once (`Warning.MissingChangeWrapper` is already on by default and does not need an entry):

```elixir
checks: %{
  extra: [
    {AshCredo.Check.Warning.AuthorizeFalse, []},
    {AshCredo.Check.Warning.AuthorizerWithoutPolicies, []},
    {AshCredo.Check.Warning.EmptyDomain, []},
    {AshCredo.Check.Warning.MissingDomain, []},
    {AshCredo.Check.Warning.MissingMacroDirective, []},
    {AshCredo.Check.Warning.MissingPrimaryKey, []},
    {AshCredo.Check.Warning.NoActions, []},
    {AshCredo.Check.Warning.OverlyPermissivePolicy, []},
    {AshCredo.Check.Warning.PinnedTimeInExpression, []},
    {AshCredo.Check.Warning.SensitiveAttributeExposed, []},
    {AshCredo.Check.Warning.SensitiveFieldInAccept, []},
    {AshCredo.Check.Warning.UnknownAction, []},
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
| `Warning.MissingMacroDirective` | `macro_modules` | `[Ash.Query, Ash.Expr]` | Modules whose qualified macro calls the check validates. Macros are read from `module.__info__(:macros)`, so only real macros are flagged |
| `Refactor.LargeResource` | `max_lines` | `400` | Maximum line count before triggering |
| `Refactor.UseCodeInterface` | `enforce_code_interface_in_domain` | `true` | See [Adapting UseCodeInterface](#adapting-usecodeinterface-to-your-teams-conventions) below |
| `Refactor.UseCodeInterface` | `enforce_code_interface_outside_domain` | `true` | See [Adapting UseCodeInterface](#adapting-usecodeinterface-to-your-teams-conventions) below |
| `Refactor.UseCodeInterface` | `prefer_interface_scope` | `:auto` | See [Adapting UseCodeInterface](#adapting-usecodeinterface-to-your-teams-conventions) below |
| `Warning.SensitiveAttributeExposed` | `sensitive_names` | `~w(password hashed_password password_hash token secret api_key private_key ssn)a` | Attribute names to flag when not marked `sensitive?: true` |
| `Warning.SensitiveFieldInAccept` | `dangerous_fields` | `~w(is_admin admin permissions api_key secret_key)a` | Field names to flag when found in `accept` lists |

### Adapting `UseCodeInterface` to your team's conventions

`UseCodeInterface` accepts three params that map to common code-interface
philosophies. The two `enforce_*` flags decide *which call sites* the check
fires on; `prefer_interface_scope` decides *which interface* the suggestion
points at. They compose freely.

```elixir
# Default - "in-domain caller → resource interface,
#            outside-domain caller → domain interface" hierarchy.
{AshCredo.Check.Refactor.UseCodeInterface, []},

# Opinion A - raw Ash.* calls are OK when the caller is in the resource's
# domain (e.g. inside a Change / Preparation / Validation module). Only
# flag callers from outside the domain.
{AshCredo.Check.Refactor.UseCodeInterface,
 [enforce_code_interface_in_domain: false]},

# Opinion B - code interfaces are only defined on resources; never suggest
# reaching for a domain-level interface, regardless of the call site.
{AshCredo.Check.Refactor.UseCodeInterface,
 [prefer_interface_scope: :resource]},

# Opinion C - the inverse of Opinion A. Strict inside the domain (changes,
# preparations, validations, sibling resources must use code interfaces),
# but permissive outside (controllers, LiveViews, workers can call Ash.*
# directly without a nag). Useful for incremental adoption - enforce the
# pattern in the resource layer first, clean up the web layer later.
{AshCredo.Check.Refactor.UseCodeInterface,
 [enforce_code_interface_outside_domain: false]},

# Opinion A + B - allow same-domain raw calls AND always direct the rest
# at the resource-level interface.
{AshCredo.Check.Refactor.UseCodeInterface,
 [enforce_code_interface_in_domain: false, prefer_interface_scope: :resource]},
```

- **`enforce_code_interface_in_domain`** (`true` default) - when `false`, leaves
  callers that share a domain with the resource alone (Opinion A).
- **`enforce_code_interface_outside_domain`** (`true` default) - when `false`,
  silences every case where the caller is not confirmed to be in the resource's
  domain (different domain, plain controller/LiveView, domainless resource,
  `:not_loadable` resource) (Opinion C).
- **`prefer_interface_scope`** (`:auto | :resource | :domain`, default `:auto`)
  - overrides which interface the check points at. `:auto` follows the
  in-domain/outside-domain heuristic; `:resource` always suggests a
  resource-level function (Opinion B); `:domain` always suggests a
  domain-level function.

Setting both `enforce_*` flags to `false` effectively disables the check
for loadable resources. In this configuration `prefer_interface_scope`
becomes inert - no suggestion path fires, so combining Opinions A + B + C
is observationally identical to A + C alone.

## Contributing

1. [Fork](https://github.com/leonqadirie/ash_credo/fork) the repository
2. Create your feature branch (`git switch -c my-new-check`)
3. Apply formatting and make sure tests and lints pass (`mix format`, `mix test`, `mix lint`)
4. Commit your changes
5. Open a pull request - PR titles must follow the [Conventional Commits](https://www.conventionalcommits.org) format (e.g. `feat: add check for XY`, `fix: handle XY edge case`)

## License

MIT - see [LICENSE](LICENSE) for details.
