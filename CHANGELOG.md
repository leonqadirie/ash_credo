# Changelog

All notable changes to this project will be documented in this file.
## [0.2.1] - 2026-04-05

### Documentation

- Remove number in readme (#4)
- Update changelog
- Update changelog
- Update changelog
- Update changelog

### Features

- Add AuthorizeFalse check: flag authorize?: false usage  (#7)
- Disable most rules by default (#13)

### Refactor

- Extract Ash API call helper (#12)

### Testing

- Enforce check registry completeness and alphabetical order (#6)

## [0.2.0] - 2026-04-05

### Documentation

- Update README
- Emphasize anticipated breaking changes in README
- Better document configurable options
- Better order checks
- Add license
- Add changelog
- Explain --strict

### Features

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
- Add igniter installer

### Refactor

- Use conventional credo module structure
- Rename helpers to introspection and relocate
- Rename introspection functions

### Testing

- Set up test infrastructure and remove placeholder test

