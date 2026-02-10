# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - Unreleased

### Added

- Template engine plugin system: engines register by name and file extensions via `registerEngine()`, replacing hardcoded dispatch.
- Liquid template engine integration via the `liquid_lib` library (lexer -> compiler -> bytecode VM with JsonNode bridge).
- `--show-me` / `-m` CLI flag to dump internal state as JSON and exit. Supports `config` and `files` aspects.
- Comprehensive test suites: file routing (55 tests), config loading (19 tests), CLI/config precedence (19 tests).
- JSON serialization for Config/Directories/Step/Workflow types.
- CLAUDE.md with build commands, test commands, and architecture documentation.

### Changed

- Replaced Plugin system with Step/Workflow architecture for more flexible build pipelines.
- Replaced external libfswatch dependency with native file watcher implementation (FSEvent on macOS, ReadDirectoryChanges on Windows, inotify on Linux).
- Replaced old logger with multi-format structured logger.
- Unified config to single workflow type with optional `if`/`steps`/`workflows` fields.
- Added Duktape JavaScript runner integration for script execution.
- Added CLI parser with `init`, `build`, `dev`, `run <workflow>`, and `clean` commands.
- Dependencies are now vendored in `deps/` directory.
- Mustache renderer extracted from internal function into a plugin wrapper.
- Workflow step module dispatch now checks plugin registry before built-in modules.

### Fixed

- Ported static template item population fix from v0.1.1 with inline context key lookup.
- Ported dynamic template item population fix from v0.1.1 for object-based collections.
- Fixed file router test cases to use correct relative paths (matching production file_list behavior).

## [0.1.1] - 2026-01-12

### Fixed

- Static templates now correctly populate `item` from matching context key. For example, `about.mustache` will have `item` set to the value of `about` in the context, allowing `{{item.name}}` to work as expected. This restores behavior that was broken in 0.1.0.
- Dynamic templates with object-based collections now correctly populate `item`. For example, `products/{products}.mustache` with context `{ "products": { "widget": { "name": "Widget" } } }` will have `item` set to the product object.
