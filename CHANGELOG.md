# Changelog

All notable changes to this project will be documented in this file.
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

## [0.2.0] - 2026-04-05

### Added

- Add igniter installer

### Documentation

- Explain --strict

## [0.1.0] - 2026-04-05

### Added

- Add shared AST helpers for Ash DSL inspection
- Add resource essentials checks: primary key, timestamps, actions
- Add resource design checks: domain, identity, code interface, belongs_to
- Add security checks for sensitive attribute exposure
- Add authorization checks: policies, permissions, wildcard accept
- Add quality checks: large resource, empty domain, action descriptions
- Wire up AshCredo as Credo plugin with default check config
- Increase max_lines default to 400 for large resource check
- Add pinned time in expression check
- Add missing change wrapper check

### Changed

- Use conventional credo module structure
- Rename helpers to introspection and relocate
- Rename introspection functions

### Documentation

- Update README
- Emphasize anticipated breaking changes in README
- Better document configurable options
- Better order checks
- Add license
- Add changelog

### Testing

- Set up test infrastructure and remove placeholder test
