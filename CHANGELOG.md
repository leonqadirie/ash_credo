# Changelog

All notable changes to this project will be documented in this file.
## [0.16.1](https://github.com/leonqadirie/ash_credo/compare/v0.16.0...v0.16.1) (2026-07-04)


### Performance Improvements

* replace global lock with name-registration claim for hint dedup ([#215](https://github.com/leonqadirie/ash_credo/issues/215)) ([0d4486e](https://github.com/leonqadirie/ash_credo/commit/0d4486eace2f0ac2d32bed4218848a2528e83065)) by [@leonqadirie](https://github.com/leonqadirie)

## [0.16.0](https://github.com/leonqadirie/ash_credo/compare/v0.15.0...v0.16.0) (2026-07-03)


### ⚠ BREAKING CHANGES

* The minimum supported Elixir version is now 1.17 (previously 1.15). Lexical scope is resolved through the `Macro.Env` define/expand APIs introduced in Elixir 1.17.

### Features

* add excluded_paths to the accept-list security checks ([#182](https://github.com/leonqadirie/ash_credo/issues/182)) ([3776099](https://github.com/leonqadirie/ash_credo/commit/37760995abf5171f316bb6dfbe8a3880f25b3499)) by [@leonqadirie](https://github.com/leonqadirie)
* add excluded_paths to UseCodeInterface ([#208](https://github.com/leonqadirie/ash_credo/issues/208)) ([97407f2](https://github.com/leonqadirie/ash_credo/commit/97407f2496f14d0b31ceb4183b0cd719a2c01e30)) by [@leonqadirie](https://github.com/leonqadirie)
* support regex entries in SensitiveFieldInAccept dangerous_fields ([#181](https://github.com/leonqadirie/ash_credo/issues/181)) ([31643ff](https://github.com/leonqadirie/ash_credo/commit/31643ff0e11c9402d50fcf417c040d22bdfe00b3)) by [@leonqadirie](https://github.com/leonqadirie)


### Bug Fixes

* check accept lists on soft destroy actions ([#199](https://github.com/leonqadirie/ash_credo/issues/199)) ([87a4b51](https://github.com/leonqadirie/ash_credo/commit/87a4b51a8f7989efd6b04cfd703aba4438a9e018)) by [@leonqadirie](https://github.com/leonqadirie)
* compile before running the lint alias ([#204](https://github.com/leonqadirie/ash_credo/issues/204)) ([3204f17](https://github.com/leonqadirie/ash_credo/commit/3204f17c1f1e28b1be8d2d039b90a49668c02cf6)) by [@leonqadirie](https://github.com/leonqadirie)
* emit the missing-table hint exactly once under concurrent access ([#202](https://github.com/leonqadirie/ash_credo/issues/202)) ([31e4d89](https://github.com/leonqadirie/ash_credo/commit/31e4d89f247424e4f0e8f5eb7fef354f130e4b0f)) by [@leonqadirie](https://github.com/leonqadirie)
* flag call-time actor on aggregate functions ([#200](https://github.com/leonqadirie/ash_credo/issues/200)) ([9c1d967](https://github.com/leonqadirie/ash_credo/commit/9c1d967df3db0b2648dd81eb103216a6f6ebcc27)) by [@leonqadirie](https://github.com/leonqadirie)
* flag frozen Ash.UUIDv7.generate() defaults in CompileTimeDefault ([#193](https://github.com/leonqadirie/ash_credo/issues/193)) ([7f8a563](https://github.com/leonqadirie/ash_credo/commit/7f8a56365f36cb3ee2c18e98e9f3686b4cfacbd8)) by [@leonqadirie](https://github.com/leonqadirie)
* flag pinned Time.utc_now in expressions ([#212](https://github.com/leonqadirie/ash_credo/issues/212)) ([d7aa9eb](https://github.com/leonqadirie/ash_credo/commit/d7aa9eb5b3897147a0a2e4497ecf38f4ba6e0301)) by [@leonqadirie](https://github.com/leonqadirie)
* model the alias a defmodule creates instead of guessing nesting ([#207](https://github.com/leonqadirie/ash_credo/issues/207)) ([3b519a3](https://github.com/leonqadirie/ash_credo/commit/3b519a3d2f3743afb4a29288eb19830ab35216d3)) by [@leonqadirie](https://github.com/leonqadirie)
* name the missing timestamp side and the domain opt-out ([#210](https://github.com/leonqadirie/ash_credo/issues/210)) ([aa3025e](https://github.com/leonqadirie/ash_credo/commit/aa3025ebda192a79a9ed5cc9780b29838b33b79e)) by [@leonqadirie](https://github.com/leonqadirie)
* resolve alias __MODULE__.X targets instead of crashing the resolver ([#195](https://github.com/leonqadirie/ash_credo/issues/195)) ([59ae1ff](https://github.com/leonqadirie/ash_credo/commit/59ae1ff8c5aea1f1a9dfa2727d5ed060de089d2d)) by [@leonqadirie](https://github.com/leonqadirie)
* respect policy_group conditions and forbid guards in OverlyPermissivePolicy ([#197](https://github.com/leonqadirie/ash_credo/issues/197)) ([b4649c5](https://github.com/leonqadirie/ash_credo/commit/b4649c5bbb7256f5feff166b59cb64e6f93f365c)) by [@leonqadirie](https://github.com/leonqadirie)
* silence default_accept warnings without an inheriting action ([#213](https://github.com/leonqadirie/ash_credo/issues/213)) ([a77830e](https://github.com/leonqadirie/ash_credo/commit/a77830e988c5142ee7953733194262fc8a81d204)) by [@leonqadirie](https://github.com/leonqadirie)
* skip argument-backed fields in RedundantValidation ([#196](https://github.com/leonqadirie/ash_credo/issues/196)) ([861ecea](https://github.com/leonqadirie/ash_credo/commit/861ecea65680ae5ff8de4bb3223ac1cc9a7b3ab4)) by [@leonqadirie](https://github.com/leonqadirie)
* skip identity suggestion for a sole primary-key attribute ([#209](https://github.com/leonqadirie/ash_credo/issues/209)) ([6100355](https://github.com/leonqadirie/ash_credo/commit/61003551a684535ed19f019301a1185ba174b463)) by [@leonqadirie](https://github.com/leonqadirie)
* stop PinnedTimeInExpression flagging expr in function bodies ([#194](https://github.com/leonqadirie/ash_credo/issues/194)) ([2cd2d25](https://github.com/leonqadirie/ash_credo/commit/2cd2d25dfc653b3ab9145bd6e561ac52061b4dd4)) by [@leonqadirie](https://github.com/leonqadirie)
* treat require ... as: as the alias it creates ([#198](https://github.com/leonqadirie/ash_credo/issues/198)) ([b957355](https://github.com/leonqadirie/ash_credo/commit/b9573552951a6f24ef17febaf6d2a9fdfc4bbccd)) by [@leonqadirie](https://github.com/leonqadirie)


### Code Refactoring

* resolve lexical scope through Macro.Env ([4d86b0a](https://github.com/leonqadirie/ash_credo/commit/4d86b0ac06dccfe6fe3690347931d0f15e02d084)) by [@leonqadirie](https://github.com/leonqadirie)

## [0.15.0](https://github.com/leonqadirie/ash_credo/compare/v0.14.0...v0.15.0) (2026-06-12)


### ⚠ BREAKING CHANGES

* AshCredo.Check.Warning.MissingChangeWrapper and the intermediary AshCredo.Check.Warning.MissingValidationWrapper and AshCredo.Check.Warning.MissingPrepareWrapper no longer exist; their coverage is provided by AshCredo.Check.Warning.MissingBuiltinWrapper (default-on, like its predecessors). Remove any entries for the old module names from your .credo.exs, or Credo will fail to load them.
* AshCredo.Check.Warning.NoActions no longer exists. Remove any {AshCredo.Check.Warning.NoActions, ...} entry from the checks in your .credo.exs, or Credo will fail to load the module.

### Features

* add ActorOnCallOptions check ([#164](https://github.com/leonqadirie/ash_credo/issues/164)) ([82c815b](https://github.com/leonqadirie/ash_credo/commit/82c815b4a89e0f117b4591563a2af9e375059834)) by [@leonqadirie](https://github.com/leonqadirie)
* add AnonymousFunctionInDsl check for fn callbacks in the DSL ([#167](https://github.com/leonqadirie/ash_credo/issues/167)) ([1d93ed6](https://github.com/leonqadirie/ash_credo/commit/1d93ed64aae9be5a0c18d95a8f7070a423098351)) by [@leonqadirie](https://github.com/leonqadirie)
* add CompileTimeDefault check for frozen attribute/argument defaults ([#168](https://github.com/leonqadirie/ash_credo/issues/168)) ([5ff4b23](https://github.com/leonqadirie/ash_credo/commit/5ff4b23dc97d5760a1bab6100bfb0060f9fa80aa)) by [@leonqadirie](https://github.com/leonqadirie)
* add MissingValidationWrapper check for naked validation builtins ([#163](https://github.com/leonqadirie/ash_credo/issues/163)) ([29e776e](https://github.com/leonqadirie/ash_credo/commit/29e776e62585d57bbbacde6e49f1aabc22e866a2)) by [@leonqadirie](https://github.com/leonqadirie)
* add RedundantValidation check for present on non-nullable attributes ([#166](https://github.com/leonqadirie/ash_credo/issues/166)) ([1c8b81f](https://github.com/leonqadirie/ash_credo/commit/1c8b81f35d079670f5cfb011ae72d932a605c825)) by [@leonqadirie](https://github.com/leonqadirie)
* cover pipeline bodies and preparations in the wrapper checks ([#165](https://github.com/leonqadirie/ash_credo/issues/165)) ([4136a5d](https://github.com/leonqadirie/ash_credo/commit/4136a5d37c641b727b6d7c6cc2f65065c6a778a6)) by [@leonqadirie](https://github.com/leonqadirie)
* merge builtin wrapper checks ([#171](https://github.com/leonqadirie/ash_credo/issues/171)) ([f128341](https://github.com/leonqadirie/ash_credo/commit/f128341235cdd7f31c20940e1217a209fcac3db3)) by [@leonqadirie](https://github.com/leonqadirie)
* point installer users at the opt-in checks via an Igniter notice ([#154](https://github.com/leonqadirie/ash_credo/issues/154)) ([f5b959d](https://github.com/leonqadirie/ash_credo/commit/f5b959d74cb715c024d3e0b28a7ae2e9c7900d8c)) by [@leonqadirie](https://github.com/leonqadirie)
* remove NoActions check ([#170](https://github.com/leonqadirie/ash_credo/issues/170)) ([4e281a7](https://github.com/leonqadirie/ash_credo/commit/4e281a7c6d1b9c6aac2cd51a7688998f89680611)) by [@leonqadirie](https://github.com/leonqadirie)
* support regex entries and more defaults in sensitive_names ([#159](https://github.com/leonqadirie/ash_credo/issues/159)) ([a90b07a](https://github.com/leonqadirie/ash_credo/commit/a90b07a5c12cab223d8252f0b8209cb4e3911cf1)) by [@leonqadirie](https://github.com/leonqadirie)


### Bug Fixes

* anchor accept :* issues at the accept line in WildcardAcceptOnAction ([#158](https://github.com/leonqadirie/ash_credo/issues/158)) ([33f4ead](https://github.com/leonqadirie/ash_credo/commit/33f4eadad6e6fcc3ffa78cc0d558581a2abe508d)) by [@leonqadirie](https://github.com/leonqadirie)
* degrade gracefully when cache table is missing ([#148](https://github.com/leonqadirie/ash_credo/issues/148)) ([99b1c97](https://github.com/leonqadirie/ash_credo/commit/99b1c9701fe64882305c3858543c25f5fda477d9)) by [@leonqadirie](https://github.com/leonqadirie)
* detect additional unscoped policy forms in OverlyPermissivePolicy ([#147](https://github.com/leonqadirie/ash_credo/issues/147)) ([bf5a809](https://github.com/leonqadirie/ash_credo/commit/bf5a809ea14903251ff2ca9af67d702d4cd52b88)) by [@leonqadirie](https://github.com/leonqadirie)
* handle bare authorize? variables in AST lists in AuthorizeFalse ([#145](https://github.com/leonqadirie/ash_credo/issues/145)) ([7d598cd](https://github.com/leonqadirie/ash_credo/commit/7d598cd7bc274af1b3246f0f2cdf922251ea393d)) by [@leonqadirie](https://github.com/leonqadirie)
* warn instead of crashing on non-literal .credo.exs in installer ([#151](https://github.com/leonqadirie/ash_credo/issues/151)) ([ce90429](https://github.com/leonqadirie/ash_credo/commit/ce9042994cbd7878075083f38865b5c785dbc74c)) by [@leonqadirie](https://github.com/leonqadirie)


### Performance Improvements

* memoize per-file AST traversals and module probes ([#149](https://github.com/leonqadirie/ash_credo/issues/149)) ([f9bd746](https://github.com/leonqadirie/ash_credo/commit/f9bd7465bd682b3d0a3b3081cd678a2ed99f1a80)) by [@leonqadirie](https://github.com/leonqadirie)

## [0.14.0](https://github.com/leonqadirie/ash_credo/compare/v0.13.0...v0.14.0) (2026-05-27)


### ⚠ BREAKING CHANGES

* `AshCredo.Check.Warning.MissingPrimaryKey` is removed. Drop any entry referencing it from `.credo.exs`. To fail CI on missing primary keys, rely on Ash's compile-time warning paired with `mix compile --warnings-as-errors`.

### Features

* remove MissingPrimaryKey check ([#141](https://github.com/leonqadirie/ash_credo/issues/141)) ([8aad232](https://github.com/leonqadirie/ash_credo/commit/8aad2327531188768c6a4cfcfd9ff14dcb8eb80a)) by [@leonqadirie](https://github.com/leonqadirie)


### Bug Fixes

* exclude generic actions from missing primary action check ([#137](https://github.com/leonqadirie/ash_credo/issues/137)) ([2236ac9](https://github.com/leonqadirie/ash_credo/commit/2236ac9689578601e4cf106f5cc82da1913d284d)) by [@leonqadirie](https://github.com/leonqadirie)
* MissingPrimaryKey didn't detect fragments or adhere to Ash's exemptions ([#139](https://github.com/leonqadirie/ash_credo/issues/139)) ([917acf3](https://github.com/leonqadirie/ash_credo/commit/917acf32757a90fd715d3fa7cb4465b9516aba4f)) by [@leonqadirie](https://github.com/leonqadirie)

## [0.13.0](https://github.com/leonqadirie/ash_credo/compare/v0.12.1...v0.13.0) (2026-05-20)


### ⚠ BREAKING CHANGES

* hoist `PinnedTimeInExpression` check to be enabled by default. It is expected this is an accident in the overwhelming amount of times and in the unlikely case it is not, a local override is preferred.

### Features

* hoist `PinnedTimeInExpression` check to be enabled by default ([#127](https://github.com/leonqadirie/ash_credo/issues/127)) ([80397a6](https://github.com/leonqadirie/ash_credo/commit/80397a64e309476169a9b164909a174a6606f196)) by [@leonqadirie](https://github.com/leonqadirie)

## [0.12.1](https://github.com/leonqadirie/ash_credo/compare/v0.12.0...v0.12.1) (2026-05-14)


### Bug Fixes

* skip uniqueness checks in embedded resources ([#123](https://github.com/leonqadirie/ash_credo/issues/123)) ([9e6b04e](https://github.com/leonqadirie/ash_credo/commit/9e6b04e33e342316ca21434a8846d9ceeb1ce21c)) by [@leonqadirie](https://github.com/leonqadirie)

## [0.12.0](https://github.com/leonqadirie/ash_credo/compare/v0.11.0...v0.12.0) (2026-05-13)


### Features

* **check:** raising call in ash sites ([#119](https://github.com/leonqadirie/ash_credo/issues/119)) ([a67e75d](https://github.com/leonqadirie/ash_credo/commit/a67e75df603dfc7420322b2471c38bbdc1846fef)) by [@leonqadirie](https://github.com/leonqadirie)

## [0.11.0](https://github.com/leonqadirie/ash_credo/compare/v0.10.0...v0.11.0) (2026-05-09)


### Features

* clarify UseCodeInterface suggestion for bulk operations ([#113](https://github.com/leonqadirie/ash_credo/issues/113)) ([da19a48](https://github.com/leonqadirie/ash_credo/commit/da19a4891dad010ae2ba1acaebbf87786786c72d)) by [@leonqadirie](https://github.com/leonqadirie)

## [0.10.0](https://github.com/leonqadirie/ash_credo/compare/v0.9.0...v0.10.0) (2026-04-26)


### ⚠ BREAKING CHANGES

* `UseCodeInterface` now flags `Ash.read!(MyApp.Post)`, `Ash.read/1`, `Ash.get!/3`, `Ash.get/3`, and `Ash.stream!/2` calls that omit the `:action` keyword, treating them as targeting the resource's primary `:read` action. Projects whose CI was previously green on bare- form calls will see new issues - either define a code interface, add an explicit `action: :read`, or disable the check.

### Features

* refine use code interface and missing macro directive against real semantics ([#97](https://github.com/leonqadirie/ash_credo/issues/97)) ([9eaa617](https://github.com/leonqadirie/ash_credo/commit/9eaa617136bc057702ee3dedcac4f0e270be376c)) by [@leonqadirie](https://github.com/leonqadirie)
* replace persistent term-based cache with ETS ([#100](https://github.com/leonqadirie/ash_credo/issues/100)) ([e6ba2f1](https://github.com/leonqadirie/ash_credo/commit/e6ba2f1700e39c26a78e2de25e056bdfedbecbcd)) by [@leonqadirie](https://github.com/leonqadirie)


### Bug Fixes

* failures when ash_credo is consumed as a dependency ([#102](https://github.com/leonqadirie/ash_credo/issues/102)) ([6be6898](https://github.com/leonqadirie/ash_credo/commit/6be68986c7ea411c6ba620459b1704d0a6a37671)) by [@leonqadirie](https://github.com/leonqadirie)

## [0.9.0](https://github.com/leonqadirie/ash_credo/compare/v0.8.0...v0.9.0) (2026-04-26)


### ⚠ BREAKING CHANGES

* AuthorizeFalse now excludes test directories by default via the new `excluded_paths` param ([#92](https://github.com/leonqadirie/ash_credo/issues/92))

### Features

* add excluded_paths param to AuthorizeFalse check, excluding test directories by default ([#92](https://github.com/leonqadirie/ash_credo/issues/92)) ([3f725fd](https://github.com/leonqadirie/ash_credo/commit/3f725fdf8446323e9c5440267d5a704dde564062)) by [@leonqadirie](https://github.com/leonqadirie)

## [0.8.0](https://github.com/leonqadirie/ash_credo/compare/v0.7.0...v0.8.0) (2026-04-22)


### Features

* add excluded_actions param to MissingCodeInterface ([#82](https://github.com/leonqadirie/ash_credo/issues/82)) ([9fb5c7c](https://github.com/leonqadirie/ash_credo/commit/9fb5c7c3eaddc4e242fb4ab06e9ed7544f898ae6)) by [@bigardone](https://github.com/bigardone)


### Bug Fixes

* handle custom timestamp types in MissingTimestamps check ([#71](https://github.com/leonqadirie/ash_credo/issues/71)) ([919cf51](https://github.com/leonqadirie/ash_credo/commit/919cf51aa1ac99f4a773aef7b1778a845899ecb9)) by [@bigardone](https://github.com/bigardone)
* skip embedded resources in MissingCodeInterface ([#81](https://github.com/leonqadirie/ash_credo/issues/81)) ([6094400](https://github.com/leonqadirie/ash_credo/commit/6094400231c65e83f6ece2942000bf8a054b9de5)) by [@bigardone](https://github.com/bigardone)

## [0.7.0](https://github.com/leonqadirie/ash_credo/compare/v0.6.0...v0.7.0) (2026-04-10)


### Features

* add refactor.directive_in_function_body check ([#66](https://github.com/leonqadirie/ash_credo/issues/66)) ([538edc1](https://github.com/leonqadirie/ash_credo/commit/538edc16255f60f909ebc6e9c80d17973c10adbd)) by [@leonqadirie](https://github.com/leonqadirie)

## [0.6.0](https://github.com/leonqadirie/ash_credo/compare/v0.5.2...v0.6.0) (2026-04-10)


### ⚠ BREAKING CHANGES

* use Ash's introspection and tighten checks ([#53](https://github.com/leonqadirie/ash_credo/issues/53))

### Features

* add check for missing macro directive ([#58](https://github.com/leonqadirie/ash_credo/issues/58)) ([8ee473f](https://github.com/leonqadirie/ash_credo/commit/8ee473f66d43278547b6cae2cd06ac9b265ff9f0)) by [@leonqadirie](https://github.com/leonqadirie)
* enable missing_macro_directive check by default ([#59](https://github.com/leonqadirie/ash_credo/issues/59)) ([9b559c1](https://github.com/leonqadirie/ash_credo/commit/9b559c1d0486c43e06e919eea305d2db6e5212b2)) by [@leonqadirie](https://github.com/leonqadirie)
* extract warning.unknown_action from use_code_interface ([#56](https://github.com/leonqadirie/ash_credo/issues/56)) ([47d5de7](https://github.com/leonqadirie/ash_credo/commit/47d5de7a46c12b671eb45e3bd0aff057ca9ac2a7)) by [@leonqadirie](https://github.com/leonqadirie)
* make clear_cache/0 public ([#55](https://github.com/leonqadirie/ash_credo/issues/55)) ([c1e565d](https://github.com/leonqadirie/ash_credo/commit/c1e565d0c7aa499b8a0ef095558707f3f45b55cd)) by [@leonqadirie](https://github.com/leonqadirie)
* use Ash's introspection and tighten checks ([#53](https://github.com/leonqadirie/ash_credo/issues/53)) ([0cd669b](https://github.com/leonqadirie/ash_credo/commit/0cd669bbe99b709da8614edb99ed09808893db24)) by [@leonqadirie](https://github.com/leonqadirie)

## [0.5.2](https://github.com/leonqadirie/ash_credo/compare/v0.5.1...v0.5.2) (2026-04-08)


### Bug Fixes

* skip default-generated action types in MissingPrimaryAction ([#51](https://github.com/leonqadirie/ash_credo/issues/51)) ([6ad17f8](https://github.com/leonqadirie/ash_credo/commit/6ad17f82da821bc989e2efb6b9ab8be991264e38)) by [@leonqadirie](https://github.com/leonqadirie)

## [0.5.1](https://github.com/leonqadirie/ash_credo/compare/v0.5.0...v0.5.1) (2026-04-08)


### Bug Fixes

* igniter installation ([#45](https://github.com/leonqadirie/ash_credo/issues/45)) ([6c6b1a8](https://github.com/leonqadirie/ash_credo/commit/6c6b1a8e2e1e1285627d20bc202e5aa6b494fdf6)) by [@leonqadirie](https://github.com/leonqadirie)
* use app token for release-please to trigger CI on PRs ([#47](https://github.com/leonqadirie/ash_credo/issues/47)) ([0c1ba8c](https://github.com/leonqadirie/ash_credo/commit/0c1ba8c4492aebdbce22a543bf3e23355d1c326d)) by [@leonqadirie](https://github.com/leonqadirie)

## [0.5.0](https://github.com/leonqadirie/ash_credo/compare/v0.4.0...v0.5.0) (2026-04-08)


### Features

* add UseCodeInterface check for literal resource and action calls ([#41](https://github.com/leonqadirie/ash_credo/issues/41)) ([44b081c](https://github.com/leonqadirie/ash_credo/commit/44b081c758b9e5e8342fa6e11c4911bd4a47c91b)) by [@leonqadirie](https://github.com/leonqadirie)

## [0.4.0](https://github.com/leonqadirie/ash_credo/compare/v0.3.0...v0.4.0) (2026-04-06)


### Features

* improve authorize?: false check ([#34](https://github.com/leonqadirie/ash_credo/issues/34)) ([2231339](https://github.com/leonqadirie/ash_credo/commit/223133909968bf53891c1cb6f5bffb8d4c520ecb)) by [@leonqadirie](https://github.com/leonqadirie)

## [0.3.0](https://github.com/leonqadirie/ash_credo/compare/v0.2.0...v0.3.0) (2026-04-06)


### ⚠ BREAKING CHANGES

* disable most rules by default ([#13](https://github.com/leonqadirie/ash_credo/issues/13))

### Features

* add AuthorizeFalse check: flag authorize?: false usage  ([#7](https://github.com/leonqadirie/ash_credo/issues/7)) ([c8e7aae](https://github.com/leonqadirie/ash_credo/commit/c8e7aaee9b1d5da219c1b3a16afc0e107c3150fc)) by [@leonqadirie](https://github.com/leonqadirie), [@olivermt](https://github.com/olivermt)
* disable most rules by default ([#13](https://github.com/leonqadirie/ash_credo/issues/13)) ([723ba7e](https://github.com/leonqadirie/ash_credo/commit/723ba7ef6575d0bf9ba97159be90feb01df70a38)) by [@leonqadirie](https://github.com/leonqadirie)


### Bug Fixes

* edge cases with nested modules, inline opts, and alias resolution ([#17](https://github.com/leonqadirie/ash_credo/issues/17)) ([778a1ef](https://github.com/leonqadirie/ash_credo/commit/778a1efae70509f34a70a6a4f4ed52b7eb7fcdbd)) by [@leonqadirie](https://github.com/leonqadirie)

## [0.2.0](https://github.com/leonqadirie/ash_credo/compare/v0.1.0...v0.2.0) (2026-04-05)


### Features

* add igniter installer ([7f4ea45](https://github.com/leonqadirie/ash_credo/commit/7f4ea454f265900febbb01a29db7c2cc5528f631)) by [@leonqadirie](https://github.com/leonqadirie)

## [0.1.0](https://github.com/leonqadirie/ash_credo/releases/tag/v0.1.0) (2026-04-05)


### ⚠ BREAKING CHANGES

* use conventional credo module structure ([b716b5c](https://github.com/leonqadirie/ash_credo/commit/b716b5cc94901dea06c89b1c8f851b9ef7b44c8b)) by [@leonqadirie](https://github.com/leonqadirie)

### Features

* add authorization checks: policies, permissions, wildcard accept ([d6e3424](https://github.com/leonqadirie/ash_credo/commit/d6e3424757f8f38a8edd4a7593781c3e05e7da0e)) by [@leonqadirie](https://github.com/leonqadirie)
* add missing change wrapper check ([22297b2](https://github.com/leonqadirie/ash_credo/commit/22297b2b61c93f20b79489d480c4e7dab9e91aa5)) by [@leonqadirie](https://github.com/leonqadirie)
* add pinned time in expression check ([db64709](https://github.com/leonqadirie/ash_credo/commit/db64709e7ee2fff5fc8c6676f3c24734dd18d677)) by [@leonqadirie](https://github.com/leonqadirie)
* add quality checks: large resource, empty domain, action descriptions ([56af703](https://github.com/leonqadirie/ash_credo/commit/56af7036deb6437c61e9ff29c26ce394c79ffddb)) by [@leonqadirie](https://github.com/leonqadirie)
* add resource design checks: domain, identity, code interface, belongs_to ([91980d5](https://github.com/leonqadirie/ash_credo/commit/91980d591005e7988f84d8a02a999f2bd2bec64c)) by [@leonqadirie](https://github.com/leonqadirie)
* add resource essentials checks: primary key, timestamps, actions ([0a938a1](https://github.com/leonqadirie/ash_credo/commit/0a938a1e3eb518bc01e6ebf602ed05572fa11c9d)) by [@leonqadirie](https://github.com/leonqadirie)
* add security checks for sensitive attribute exposure ([4d99460](https://github.com/leonqadirie/ash_credo/commit/4d994600fafcfe71d507edc5f02c2e3d8ec12c24)) by [@leonqadirie](https://github.com/leonqadirie)
* add shared AST helpers for Ash DSL inspection ([77716f2](https://github.com/leonqadirie/ash_credo/commit/77716f2bf977904196168970f5f972b26b308abe)) by [@leonqadirie](https://github.com/leonqadirie)
* increase max_lines default to 400 for large resource check ([ebfaed9](https://github.com/leonqadirie/ash_credo/commit/ebfaed9a5b00b2d3bf968999d08dcb0ce415948f)) by [@leonqadirie](https://github.com/leonqadirie)
* wire up AshCredo as Credo plugin with default check config ([26d5062](https://github.com/leonqadirie/ash_credo/commit/26d50626250a64431811b8785aeff58d6dfa08cf)) by [@leonqadirie](https://github.com/leonqadirie)
