# AshCredo

[![Hex.pm](https://img.shields.io/hexpm/v/ash_credo.svg)](https://hex.pm/packages/ash_credo)
[![HexDocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://ash-credo.hexdocs.pm)
[![License: MIT](https://img.shields.io/badge/license-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)

AshCredo is an unofficial set of static analysis checks for the [Ash Framework](https://ash-hq.org), built as a [Credo](https://github.com/rrrene/credo) plugin.

AshCredo finds common anti-patterns, security pitfalls, and missing best practices in your Ash resources, domains, and the code that calls into them. Some checks analyse the unexpanded source AST. Others introspect the compiled modules and see the fully resolved DSL state, including anything Spark transformers and extensions contribute.

> [!WARNING]
> This project is experimental and might break frequently.

**Only the following checks are enabled by default.** All other checks are opt-in: enable them individually in your `.credo.exs` (see [Configuration](#configuration)).

- `Warning.CompileTimeDefault`
- `Warning.MissingBuiltinWrapper`
- `Warning.MissingMacroDirective`
- `Warning.PinnedTimeInExpression`

## Installation

AshCredo requires [Credo](https://credo.hexdocs.pm) to already be installed in your project.

### With Igniter (recommended)

If your project uses [Igniter](https://igniter.hexdocs.pm), a single command adds the dependency and registers the plugin in your `.credo.exs`:

```bash
mix igniter.install ash_credo@0.17.1
```

The explicit version prevents Igniter from generating a broad pre-1.0 requirement. Igniter pins a three-part version exactly, so if you prefer compatible patch updates, use the manual requirement below. The installer scopes `ash_credo` to `:dev`/`:test` and sets `runtime: false` automatically, matching how `credo` itself is typically declared. Pass `--only dev,test` if you'd like an early error when running from another `MIX_ENV`.

### Manual

Add `ash_credo` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ash_credo, "~> 0.17.1", only: [:dev, :test], runtime: false}
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

If you have any compiled-introspection checks enabled, run `mix compile` before `mix credo`, typically via a Mix alias like `lint: ["compile", "credo --strict"]`. See [Checks that require a compiled project](#checks-that-require-a-compiled-project) for the full list and the rationale.

## Checks

| Check | Category | Priority | Default | Description |
|---|---|---|---|---|
| `ActorOnCallOptions` | Warning | High | No | Flags `actor:`/`tenant:` passed in the options of `Ash.read!`/`Ash.create!`/... when the subject visibly went through a `for_*` builder. Per Ash's authorization usage rules, these options belong on the query, changeset, or input |
| `AuthorizeFalse` | Warning | High | No | Flags literal `authorize?: false` in Ash calls, action DSL, and (by default) any other call site |
| `AuthorizerWithoutPolicies` | Warning | High | No | Detects resources with `Ash.Policy.Authorizer` but no policies defined. **Requires a compiled project.** |
| `CompileTimeDefault` | Warning | High | Yes | Flags `default: DateTime.utc_now()` / `Ash.UUID.generate()` (missing the `&.../0` capture) on attributes and arguments. The call runs once at compile time, so every record gets the same frozen value |
| `EmptyDomain` | Warning | Normal | No | Flags domains with no resources registered |
| `MissingBuiltinWrapper` | Warning | High | Yes | Flags builtin change/validation/preparation/calculation functions (`set_attribute`, `present`, `build`, `concat`, ...) used without their `change`/`validate`/`prepare`/`calculate` wrapper in action bodies, pipelines, and global sections. The bare call compiles but is silently discarded |
| `MissingDomain` | Warning | Normal | No | Flags non-embedded resources that don't set the `domain:` option |
| `MissingMacroDirective` | Warning | High | Yes | Flags qualified calls to `Ash.Query`/`Ash.Expr` macros (`filter`, `expr`, ...) when the enclosing module has no matching module-level `require`/`import`. Catches the runtime `UndefinedFunctionError` that slips past the compiler when the macro argument is a bare runtime value. **Requires a compiled project** and **configurable**. |
| `OverlyPermissivePolicy` | Warning | High | No | Flags unscoped `authorize_if always()` policies |
| `PinnedTimeInExpression` | Warning | High | Yes | Flags `^Date.utc_today()` / `^DateTime.utc_now()` in Ash expressions (frozen at compile time) |
| `RedundantValidation` | Warning | Normal | No | Flags `validate present(...)` on attributes that already have `allow_nil? false`. The constraint guarantees presence, so the validation is redundant (skips `allow_nil_input` escape hatches). **Requires a compiled project.** |
| `SensitiveAttributeExposed` | Warning | High | No | Flags sensitive attributes (password, token, secret, ...) not marked `sensitive?: true` |
| `SensitiveFieldInAccept` | Warning | High | No | Flags privilege-escalation fields (`is_admin`, `permissions`, ...) in `accept` lists |
| `UnknownAction` | Warning | High | No | Flags `Ash.*` calls referencing actions that don't exist on the resolved resource, with a fuzzy `Did you mean` hint. **Requires a compiled project.** |
| `WildcardAcceptOnAction` | Warning | High | No | Detects `accept :*` on `create`/`update`/soft `destroy` actions (mass-assignment risk) |
| `AnonymousFunctionInDsl` | Refactor | Normal | No | Flags `fn`/`&` captures passed to `change`/`validate`/`prepare`/`calculate`. Anonymous functions can never be atomic (changes/validations) or supply an expression (calculations), so extract them into callback modules |
| `DirectiveInFunctionBody` | Refactor | Normal | No | Flags `require`/`import`/`alias` of configured modules (default `Ash.Query`, `Ash.Expr`) declared inside function bodies instead of at module level |
| `LargeResource` | Refactor | Low | No | Flags resource files exceeding 400 lines |
| `RaisingCall` | Refactor | Low | No | Flags Ash bang calls: top-level `Ash.read!`/`Ash.create!`/`Ash.Filter.parse!` plus code-interface bangs like `MyApp.Blog.create_post!`. Orphan bangs (those without a non-bang counterpart, e.g. `Ash.stream!`, `Ash.Seed.seed!`) are detected dynamically and skipped. Test directories are excluded by default. **Requires a compiled project.** |
| `UseCodeInterface` | Refactor | Normal | No | Flags `Ash.*` calls where both resource and action are literals, and names the exact code interface function to call instead. **Requires a compiled project** and **configurable** (see below). Pair it with `Warning.UnknownAction` for typo detection |
| `MissingCodeInterface` | Design | Low | No | Flags each action on non-embedded resources that has no code interface (resource- or domain-level). **Requires a compiled project.** |
| `MissingIdentity` | Design | Normal | No | Suggests identities for attributes like `email`, `username`, `slug` on non-embedded resources. **Requires a compiled project.** |
| `MissingPrimaryAction` | Design | Normal | No | Flags missing `primary?: true` when multiple actions of the same CRUD type exist (generic `:action` types are excluded). **Requires a compiled project.** |
| `MissingTimestamps` | Design | Normal | No | Suggests adding `timestamps()` to persisted resources. **Requires a compiled project.** |
| `ActionMissingDescription` | Readability | Low | No | Flags actions without a `description` |
| `BelongsToMissingAllowNil` | Readability | Normal | No | Flags `belongs_to` without an explicit `allow_nil?` |

## Checks that require a compiled project

Several checks read Ash's runtime introspection (`Ash.Resource.Info`, `Ash.Domain.Info`, and `Ash.Policy.Info`) rather than the source AST.
They see the fully resolved resource state, including anything Spark transformers or extensions contribute, and catch bugs that pure AST scanning would miss: identities on AshAuthentication-injected `:email` attributes, fragment-spliced actions, extension-added authorizers, and so on.

- `Warning.AuthorizerWithoutPolicies`
- `Warning.MissingMacroDirective`
- `Warning.RedundantValidation`
- `Warning.UnknownAction`
- `Refactor.RaisingCall`
- `Refactor.UseCodeInterface`
- `Design.MissingCodeInterface`
- `Design.MissingIdentity`
- `Design.MissingPrimaryAction`
- `Design.MissingTimestamps`

**Compile your project before running `mix credo`.** Otherwise these checks emit a configuration diagnostic and become a no-op.
Typically you chain the two commands in a Mix alias:

```elixir
# mix.exs
defp aliases do
  [
    lint: ["compile", "credo --strict"]
  ]
end
```

If a referenced resource can't be loaded, the check emits a per-call-site "could not load" issue pointing at the resource. If Ash itself isn't available in the VM running Credo, these checks emit a single shared diagnostic and become no-ops. You can disable any of them in `.credo.exs` if your workflow can't run `mix compile` beforehand.

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

To enable **all** checks at once (the default-on checks listed above don't need an entry):

```elixir
checks: %{
  extra: [
    {AshCredo.Check.Warning.ActorOnCallOptions, []},
    {AshCredo.Check.Warning.AuthorizeFalse, []},
    {AshCredo.Check.Warning.AuthorizerWithoutPolicies, []},
    {AshCredo.Check.Warning.EmptyDomain, []},
    {AshCredo.Check.Warning.MissingDomain, []},
    {AshCredo.Check.Warning.OverlyPermissivePolicy, []},
    {AshCredo.Check.Warning.RedundantValidation, []},
    {AshCredo.Check.Warning.SensitiveAttributeExposed, []},
    {AshCredo.Check.Warning.SensitiveFieldInAccept, []},
    {AshCredo.Check.Warning.UnknownAction, []},
    {AshCredo.Check.Warning.WildcardAcceptOnAction, []},
    {AshCredo.Check.Refactor.AnonymousFunctionInDsl, []},
    {AshCredo.Check.Refactor.DirectiveInFunctionBody, []},
    {AshCredo.Check.Refactor.LargeResource, []},
    {AshCredo.Check.Refactor.RaisingCall, []},
    {AshCredo.Check.Refactor.UseCodeInterface, []},
    {AshCredo.Check.Design.MissingCodeInterface, []},
    {AshCredo.Check.Design.MissingIdentity, []},
    {AshCredo.Check.Design.MissingPrimaryAction, []},
    {AshCredo.Check.Design.MissingTimestamps, []},
    {AshCredo.Check.Readability.ActionMissingDescription, []},
    {AshCredo.Check.Readability.BelongsToMissingAllowNil, []}
  ]
}
```

### Configurable parameters

The following checks accept custom parameters:

| Check | Parameter | Default | Description |
|---|---|---|---|
| `Warning.AuthorizeFalse` | `include_non_ash_calls` | `true` | When `false`, only checks Ash API calls and action DSL definitions |
| `Warning.AuthorizeFalse` | `excluded_paths` | `[~r"/test/", "test"]` | Paths or regexes to skip. Binary entries match as path segments or full file paths. Defaults to test directories, where `authorize?: false` is typically intentional |
| `Warning.MissingMacroDirective` | `macro_modules` | `[Ash.Query, Ash.Expr]` | Modules whose qualified macro calls the check validates. Macros are read from `module.__info__(:macros)`, so only real macros are flagged |
| `Warning.SensitiveAttributeExposed` | `sensitive_names` | `~w(password hashed_password password_hash password_digest token access_token secret client_secret totp_secret api_key private_key ssn)a` | Attribute names to flag when not marked `sensitive?: true`. Atom entries match exactly; `Regex` entries (e.g. `~r/_token$/`) match against the attribute name |
| `Warning.SensitiveAttributeExposed` | `excluded_paths` | `[~r"/test/", "test"]` | Paths or regexes to skip. Binary entries match as path segments or full file paths. Defaults to test directories, where fake sensitive attributes are common in test resources |
| `Warning.SensitiveFieldInAccept` | `dangerous_fields` | `~w(is_admin admin permissions api_key secret_key)a` | Field names to flag when found in `accept` lists |
| `Warning.SensitiveFieldInAccept` | `excluded_paths` | `[~r"/test/", "test"]` | Paths or regexes to skip. Binary entries match as path segments or full file paths. Defaults to test directories, where accepting these fields is often intentional |
| `Warning.WildcardAcceptOnAction` | `excluded_paths` | `[~r"/test/", "test"]` | Paths or regexes to skip. Binary entries match as path segments or full file paths. Defaults to test directories, where `accept :*` is often intentional |
| `Refactor.DirectiveInFunctionBody` | `directive_modules` | `[Ash.Query, Ash.Expr]` | Modules whose `require`/`import`/`alias` must live at module level. Add any other macro module your team treats the same way |
| `Refactor.LargeResource` | `max_lines` | `400` | Maximum line count before the check triggers |
| `Refactor.RaisingCall` | `excluded_functions` | `[]` | `{module, :fun!}` tuples to allow without flagging. Bang-only APIs (those with no non-bang counterpart) are detected dynamically by probing `module.__info__(:functions)`, so no curated allowlist is needed. This option only exists for cases where you want to silence a real bang/non-bang pair |
| `Refactor.RaisingCall` | `excluded_paths` | `[~r"/test/", "test"]` | Paths or regexes to skip. Binary entries match as path segments (`"test"` excludes any file under a `test/` directory) or as full file paths (`"priv/seeds.exs"` excludes that file). Defaults to test directories, where bang versions are idiomatic |
| `Refactor.RaisingCall` | `flag_bang_only_apis` | `false` | When `true`, also flags bangs whose non-bang counterpart doesn't exist (e.g. `Ash.stream!`, `Ash.Seed.seed!`) with a generic "ensure failures are properly handled" message. Defaults to `false` since the suggested non-bang twin wouldn't exist for these calls; opt in only if your team policy is "no bare bang calls anywhere" |
| `Refactor.UseCodeInterface` | `enforce_code_interface_in_domain` | `true` | See [Adapting UseCodeInterface](#adapting-usecodeinterface-to-your-teams-conventions) below |
| `Refactor.UseCodeInterface` | `enforce_code_interface_outside_domain` | `true` | See [Adapting UseCodeInterface](#adapting-usecodeinterface-to-your-teams-conventions) below |
| `Refactor.UseCodeInterface` | `excluded_paths` | `[~r"/test/", "test"]` | Paths or regexes to skip. Binary entries match as path segments or full file paths. Defaults to test directories, where raw `Ash.*` calls are idiomatic setup code |
| `Refactor.UseCodeInterface` | `prefer_interface_scope` | `:auto` | See [Adapting UseCodeInterface](#adapting-usecodeinterface-to-your-teams-conventions) below |
| `Design.MissingCodeInterface` | `excluded_actions` | `[]` | List of `"Module.action_name"` strings whose missing interface should be suppressed (e.g. `AshAuthentication`-generated actions) |
| `Design.MissingIdentity` | `identity_candidates` | `~w(email username slug handle phone)a` | Attribute names to suggest adding identities for |

### Adapting `UseCodeInterface` to your team's conventions

`UseCodeInterface` accepts params that map to common code-interface
philosophies. The two `enforce_*` flags decide which call sites the check
fires on; `prefer_interface_scope` decides which interface the suggestion
points at. They compose freely.

```elixir
# Default: an in-domain caller gets the resource interface.
# An outside-domain caller gets the domain interface.
{AshCredo.Check.Refactor.UseCodeInterface, []},

# Opinion A: raw Ash.* calls are OK when the caller is in the resource's
# domain (e.g. inside a Change / Preparation / Validation module). Only
# flag callers from outside the domain.
{AshCredo.Check.Refactor.UseCodeInterface,
 [enforce_code_interface_in_domain: false]},

# Opinion B: code interfaces are only defined on resources. Never suggest
# reaching for a domain-level interface, regardless of the call site.
{AshCredo.Check.Refactor.UseCodeInterface,
 [prefer_interface_scope: :resource]},

# Opinion C: the inverse of Opinion A. Strict inside the domain (changes,
# preparations, validations, sibling resources must use code interfaces),
# but permissive outside (controllers, LiveViews, workers can call Ash.*
# directly without a nag). Useful for incremental adoption: enforce the
# pattern in the resource layer first, clean up the web layer later.
{AshCredo.Check.Refactor.UseCodeInterface,
 [enforce_code_interface_outside_domain: false]},

# Opinion A + B: allow same-domain raw calls AND always direct the rest
# at the resource-level interface.
{AshCredo.Check.Refactor.UseCodeInterface,
 [enforce_code_interface_in_domain: false, prefer_interface_scope: :resource]},
```

- **`enforce_code_interface_in_domain`** (default `true`). When `false`, the
  check leaves callers that share a domain with the resource alone
  (Opinion A).
- **`enforce_code_interface_outside_domain`** (default `true`). When `false`,
  the check silences every case where the caller isn't confirmed to be in the
  resource's domain: a different domain, a plain controller or LiveView, a
  domainless resource, or a `:not_loadable` resource (Opinion C).
- **`prefer_interface_scope`** (`:auto | :resource | :domain`, default
  `:auto`). Overrides which interface the check points at. `:auto` follows
  the in-domain/outside-domain heuristic; `:resource` always suggests a
  resource-level function (Opinion B); `:domain` always suggests a
  domain-level function.

Setting both `enforce_*` flags to `false` effectively disables the check
for loadable resources. In this configuration `prefer_interface_scope`
becomes inert, since no suggestion path fires, so combining Opinions
A + B + C is observationally identical to A + C alone.

## Contributing

1. [Fork](https://github.com/leonqadirie/ash_credo/fork) the repository
2. Create your feature branch (`git switch -c my-new-check`)
3. Apply formatting and make sure tests and lints pass (`mix format`, `mix test`, `mix lint`)
4. Commit your changes
5. Open a pull request. PR titles must follow the [Conventional Commits](https://www.conventionalcommits.org) format (e.g. `feat: add check for XY`, `fix: handle XY edge case`)

## License

MIT, see [LICENSE](LICENSE) for details.
