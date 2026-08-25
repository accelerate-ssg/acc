# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - Unreleased

### Added

- Arena-backed build context: the context tree lives in `arena_context_store` instead of a `JsonNode` tree, with per-file origins and an always-on access log. Every context read is attributed to the consumer that made it.
- Incremental rebuilds: a change reaches only the pages that read the data it touched. Reloading a content file merges node by node, so editing one post in a shared file re-renders that post's page and nothing else.
- Change-set strategies chosen by the caller: `acc build --using=git --since=REF` (diff plus untracked files, renames as remove+change), `--using=mtime` against the cached build stamp, and the default full walk. The dev server feeds watcher events through the same classifier.
- Persisted build context, on by default (`--no-cache` opts out): the tree, origins, access log and consumer labels are saved to the work directory, so a cold process has the previous build's dependency knowledge.
- Route-set diffing: pages that appeared since the last build are rendered, and pages that ceased to exist have their outputs unlinked.
- Build manifest (`manifest.json` in the work directory) listing rendered and removed outputs — the delta a deploy needs to transfer and delete.
- Liquid templates read the arena lazily by node, so `{% assign s = site %}` followed by `s.name` records the same single dependency `site.name` would.
- Performance benchmark suite in `arena_context_store` (`nimble bench`).
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

- Dev server rewritten around a single async thread and a client list: every open tab reloads, not just the most recent one. Change events batch into one rebuild, a save during a build is no longer dropped, and a broken template no longer stops the server from starting.
- A page that fails to render is logged and skipped so the rest of the site still builds; the step then fails with a summary naming the failed pages, unless it declares `on_failure: continue`.
- Assets are cloned rather than copied where the filesystem supports it (APFS), and unchanged assets are skipped entirely.

### Fixed

- Ported dynamic template item population fix from v0.1.1 for object-based collections.
- Fixed file router test cases to use correct relative paths (matching production file_list behavior).
- Percent-encoded request paths are decoded by the dev server, so pages with non-ASCII names are served instead of 404ing (ported from the legacy line).
- The development server no longer serves pages in quirks mode. The live reload script is injected after `<!DOCTYPE html>` instead of before it, so layout in `acc dev` matches what `acc build` produces (ported from the legacy line).

### Reconciled with the legacy development line

The `development` branch published before this release forked at `3d6b1b3`
(June 2023) and evolved the pre-restructure architecture independently. It is
preserved as the `legacy/development-2026-01` tag. Every commit on it was
audited against this line; the outcome:

- The 0.1.1 release engineering, CI matrix, Windows build fixes, CHANGELOG and
  install/release documentation are all present here.
- `tasks/release.nims` is carried across unchanged. It is not wired up on
  either line: `acc.nimble` does not include it yet, and it expects a
  `## [Unreleased]` heading and `[Unreleased]: ` link definition in this file,
  plus a `main` release branch.
- Building fswatch from source on Linux is obsolete: the file watcher is now a
  native implementation with no external dependency.
- Two routing fixes from that line are obsolete under the current router
  contract, which is that **dynamic segments choose what in the context a page
  binds to, while static path segments only shape the output path**. A page
  produced by an all-literal template therefore binds the enclosing scope, and a
  page produced from an array attribute exposes the matched value as `key`,
  reserving `item` for the element itself so its type does not change as data
  grows. Templates written against the older behaviour address their data
  explicitly instead (`{{ item.training.content_html }}`).

## [0.1.1] - 2026-01-12

### Fixed

- Static templates now correctly populate `item` from matching context key. For example, `about.mustache` will have `item` set to the value of `about` in the context, allowing `{{item.name}}` to work as expected. This restores behavior that was broken in 0.1.0.
- Dynamic templates with object-based collections now correctly populate `item`. For example, `products/{products}.mustache` with context `{ "products": { "widget": { "name": "Widget" } } }` will have `item` set to the product object.
