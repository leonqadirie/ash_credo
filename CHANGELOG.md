# Changelog

All notable changes to this project will be documented in this file.
## [0.8.0](https://github.com/leonqadirie/ash_credo/compare/v0.7.0...v0.8.0) (2026-04-22)


### Features

* add excluded_actions param to MissingCodeInterface ([#82](https://github.com/leonqadirie/ash_credo/issues/82)) ([9fb5c7c](https://github.com/leonqadirie/ash_credo/commit/9fb5c7c3eaddc4e242fb4ab06e9ed7544f898ae6))


### Bug Fixes

* handle custom timestamp types in MissingTimestamps check ([#71](https://github.com/leonqadirie/ash_credo/issues/71)) ([919cf51](https://github.com/leonqadirie/ash_credo/commit/919cf51aa1ac99f4a773aef7b1778a845899ecb9))
* skip embedded resources in MissingCodeInterface ([#81](https://github.com/leonqadirie/ash_credo/issues/81)) ([6094400](https://github.com/leonqadirie/ash_credo/commit/6094400231c65e83f6ece2942000bf8a054b9de5))

## [0.7.0](https://github.com/leonqadirie/ash_credo/compare/v0.6.0...v0.7.0) (2026-04-10)


### Features

* add refactor.directive_in_function_body check ([#66](https://github.com/leonqadirie/ash_credo/issues/66)) ([538edc1](https://github.com/leonqadirie/ash_credo/commit/538edc16255f60f909ebc6e9c80d17973c10adbd))

## [0.6.0](https://github.com/leonqadirie/ash_credo/compare/v0.5.2...v0.6.0) (2026-04-10)


### ⚠ BREAKING CHANGES

* use Ash's introspection and tighten checks ([#53](https://github.com/leonqadirie/ash_credo/issues/53))

### Features

* add check for missing macro directive ([#58](https://github.com/leonqadirie/ash_credo/issues/58)) ([8ee473f](https://github.com/leonqadirie/ash_credo/commit/8ee473f66d43278547b6cae2cd06ac9b265ff9f0))
* enable missing_macro_directive check by default ([#59](https://github.com/leonqadirie/ash_credo/issues/59)) ([9b559c1](https://github.com/leonqadirie/ash_credo/commit/9b559c1d0486c43e06e919eea305d2db6e5212b2))
* extract warning.unknown_action from use_code_interface ([#56](https://github.com/leonqadirie/ash_credo/issues/56)) ([47d5de7](https://github.com/leonqadirie/ash_credo/commit/47d5de7a46c12b671eb45e3bd0aff057ca9ac2a7))
* make clear_cache/0 public ([#55](https://github.com/leonqadirie/ash_credo/issues/55)) ([c1e565d](https://github.com/leonqadirie/ash_credo/commit/c1e565d0c7aa499b8a0ef095558707f3f45b55cd))
* use Ash's introspection and tighten checks ([#53](https://github.com/leonqadirie/ash_credo/issues/53)) ([0cd669b](https://github.com/leonqadirie/ash_credo/commit/0cd669bbe99b709da8614edb99ed09808893db24))

## [0.5.2](https://github.com/leonqadirie/ash_credo/compare/v0.5.1...v0.5.2) (2026-04-08)


### Bug Fixes

* skip default-generated action types in MissingPrimaryAction ([#51](https://github.com/leonqadirie/ash_credo/issues/51)) ([6ad17f8](https://github.com/leonqadirie/ash_credo/commit/6ad17f82da821bc989e2efb6b9ab8be991264e38))

## [0.5.1](https://github.com/leonqadirie/ash_credo/compare/v0.5.0...v0.5.1) (2026-04-08)


### Bug Fixes

* igniter installation ([#45](https://github.com/leonqadirie/ash_credo/issues/45)) ([6c6b1a8](https://github.com/leonqadirie/ash_credo/commit/6c6b1a8e2e1e1285627d20bc202e5aa6b494fdf6))
* use app token for release-please to trigger CI on PRs ([#47](https://github.com/leonqadirie/ash_credo/issues/47)) ([0c1ba8c](https://github.com/leonqadirie/ash_credo/commit/0c1ba8c4492aebdbce22a543bf3e23355d1c326d))

## [0.5.0](https://github.com/leonqadirie/ash_credo/compare/v0.4.0...v0.5.0) (2026-04-08)


### Features

* add UseCodeInterface check for literal resource and action calls ([#41](https://github.com/leonqadirie/ash_credo/issues/41)) ([44b081c](https://github.com/leonqadirie/ash_credo/commit/44b081c758b9e5e8342fa6e11c4911bd4a47c91b))

## [0.4.0](https://github.com/leonqadirie/ash_credo/compare/v0.3.0...v0.4.0) (2026-04-06)


### Features

* improve authorize?: false check ([#34](https://github.com/leonqadirie/ash_credo/issues/34)) ([2231339](https://github.com/leonqadirie/ash_credo/commit/223133909968bf53891c1cb6f5bffb8d4c520ecb))

## [0.3.0](https://github.com/leonqadirie/ash_credo/compare/v0.2.0...v0.3.0) (2026-04-06)


### ⚠ BREAKING CHANGES

* disable most rules by default ([#13](https://github.com/leonqadirie/ash_credo/issues/13))

### Features

* add AuthorizeFalse check: flag authorize?: false usage  ([#7](https://github.com/leonqadirie/ash_credo/issues/7)) ([c8e7aae](https://github.com/leonqadirie/ash_credo/commit/c8e7aaee9b1d5da219c1b3a16afc0e107c3150fc))
* disable most rules by default ([#13](https://github.com/leonqadirie/ash_credo/issues/13)) ([723ba7e](https://github.com/leonqadirie/ash_credo/commit/723ba7ef6575d0bf9ba97159be90feb01df70a38))


### Bug Fixes

* edge cases with nested modules, inline opts, and alias resolution ([#17](https://github.com/leonqadirie/ash_credo/issues/17)) ([778a1ef](https://github.com/leonqadirie/ash_credo/commit/778a1efae70509f34a70a6a4f4ed52b7eb7fcdbd))

## [0.2.0](https://github.com/leonqadirie/ash_credo/compare/v0.1.0...v0.2.0) (2026-04-05)


### Features

* add igniter installer ([7f4ea45](https://github.com/leonqadirie/ash_credo/commit/7f4ea454f265900febbb01a29db7c2cc5528f631))

## [0.1.0](https://github.com/leonqadirie/ash_credo/releases/tag/v0.1.0) (2026-04-05)


### ⚠ BREAKING CHANGES

* use conventional credo module structure ([b716b5c](https://github.com/leonqadirie/ash_credo/commit/b716b5cc94901dea06c89b1c8f851b9ef7b44c8b))

### Features

* add authorization checks: policies, permissions, wildcard accept ([d6e3424](https://github.com/leonqadirie/ash_credo/commit/d6e3424757f8f38a8edd4a7593781c3e05e7da0e))
* add missing change wrapper check ([22297b2](https://github.com/leonqadirie/ash_credo/commit/22297b2b61c93f20b79489d480c4e7dab9e91aa5))
* add pinned time in expression check ([db64709](https://github.com/leonqadirie/ash_credo/commit/db64709e7ee2fff5fc8c6676f3c24734dd18d677))
* add quality checks: large resource, empty domain, action descriptions ([56af703](https://github.com/leonqadirie/ash_credo/commit/56af7036deb6437c61e9ff29c26ce394c79ffddb))
* add resource design checks: domain, identity, code interface, belongs_to ([91980d5](https://github.com/leonqadirie/ash_credo/commit/91980d591005e7988f84d8a02a999f2bd2bec64c))
* add resource essentials checks: primary key, timestamps, actions ([0a938a1](https://github.com/leonqadirie/ash_credo/commit/0a938a1e3eb518bc01e6ebf602ed05572fa11c9d))
* add security checks for sensitive attribute exposure ([4d99460](https://github.com/leonqadirie/ash_credo/commit/4d994600fafcfe71d507edc5f02c2e3d8ec12c24))
* add shared AST helpers for Ash DSL inspection ([77716f2](https://github.com/leonqadirie/ash_credo/commit/77716f2bf977904196168970f5f972b26b308abe))
* increase max_lines default to 400 for large resource check ([ebfaed9](https://github.com/leonqadirie/ash_credo/commit/ebfaed9a5b00b2d3bf968999d08dcb0ce415948f))
* wire up AshCredo as Credo plugin with default check config ([26d5062](https://github.com/leonqadirie/ash_credo/commit/26d50626250a64431811b8785aeff58d6dfa08cf))
