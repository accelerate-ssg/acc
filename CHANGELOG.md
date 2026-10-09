# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.4] - 2026-10-09

### Added

- `acc dev` takes the first free port at or above 1331 instead of insisting on
  1331, and `--port` pins one explicitly. Serving a second site meant stopping
  the first, because the port was a `const` and a clash surfaced as an
  unhandled `OSError` traceback — after the initial build had already run. The
  scan covers 1331-1340 and logs the port it settled on, so the banner names
  where each site is being served. An explicit `--port` is deliberately not
  scanned from: it is used or the run stops, since a pinned port is usually one
  something else has to reach. Either way the port is bound before the build,
  so a clash costs a line instead of a full render.

### Fixed

- Live reload survives a non-default port. The injected reload script dialled
  `ws://localhost:1331/ws` literally, so a page served anywhere else loaded
  fine and then never reloaded. It now derives the socket URL from the page's
  own location, which also repairs reload for a site opened over the LAN — the
  server has always bound `0.0.0.0`, but `localhost` in the script meant a
  phone or tablet resolved the socket to itself.
- Released binaries no longer print a `dlopen` failure for a library they go on
  to load. pcre is linked in at build time (`-d:usePcreHeader` against the
  static archive) rather than resolved at startup through Nim's
  `libpcre(.3|.1|).dylib` fallback list, whose first candidate is the Debian
  soname and never exists on macOS. 0.2.2 and 0.2.3 were also built with
  `-d:nimDebugDlOpen`, which reported that successful fallback as a seven-line
  error ahead of acc's own output; that flag is gone from the release builds
  too. The binaries no longer need a pcre installed at all.

## [0.2.3] - 2026-10-08

Packaging only. The source tree is identical to 0.2.2, so there is no
behaviour change and the fleet output verified against 0.2.2 still holds.

### Fixed

- Release assets are named for the platform they were built for. All four
  matrix jobs uploaded their binary as plain `acc` (`acc.exe` on Windows), and
  a GitHub release is a flat namespace, so the three Unix builds collided in
  it: the release action keeps the first and appends a content hash to the
  rest. v0.2.2 therefore shipped `acc`,
  `acc-48d984d64309c7b2ae31626e3c4f8659` and
  `acc-6d9145401579a37159f6c0f5ecae6de1`, and nothing short of running one
  revealed which platform it was for. Each job now renames its binary to the
  matrix artifact name before upload, so a release carries `acc-linux`,
  `acc-osx-arm64`, `acc-osx-x86` and `acc-windows.exe`. That is what lets a
  consumer pin a download URL rather than compile acc itself — the
  `build-accelerate` Docker image drops its Nim toolchain stage because of it.

## [0.2.2] - 2026-10-08

### Added

- A page's own URL in the template context as `page.path`, in both the Mustache and Liquid engines. Derived from the page's routed output path — `.html` stripped, a trailing `index` collapsed, leading slash, no trailing slash — so `index.html` is `/`, `om-oss/film.html` is `/om-oss/film`, and a dynamic template follows the slug it was routed by rather than its own filename. This lets a shared `head` partial default the canonical URL to `{{general.url}}{{page.path}}` instead of every page hand-writing a `slug:` field, where a forgotten override silently claimed the site root. The `$url` block stays overridable, for pages served at a path `acc` cannot see (an internal nginx rewrite).
- `page`, alongside `item` and `items`, is now a reserved top-level context key: the render pass binds it per page. The content loader warns when a content file would bind one of them, instead of the file being silently shadowed as it was before.
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
- Only a rendering step's pages are recorded as routes. The router names
  every file it is handed `<name>.html`, whichever step's glob pulled it in,
  and the whole render state was recorded — so a `@copy`-only workflow, which
  is what `convertLegacyConfig` produces for every pre-0.2 site, filled the
  route table and the persisted cache with pairs like
  `(assets/images/a.jpg, assets/images/a.html)` that nothing ever writes.
- Deleting an asset removes it from the output. `@copy` only ever walked the
  source, there was no route-set diff as there is for pages, and a build does
  not clean the destination first — so a removed image, font or script stayed
  on disk, stayed in the serving image (which is built from the whole output
  directory), and was absent from `removed_outputs`. The step now diffs the
  assets it would copy against the previous build's and unlinks what is gone.
- `acc init` creates the directories its generated config declares. It read
  them from `state.config.directories`, but init runs before any config is
  loaded, so every field was empty and all six guards skipped: the scaffold
  wrote `acc.yaml` naming seven directories and created none of them. The
  defaults now sit beside the template they have to agree with, and a fresh
  `acc init` followed by `acc build` renders.
- The dev server no longer serves files outside the directories it is given.
  The decoded request path was joined straight onto the destination and source
  roots, so `GET /../../../../etc/passwd` read whatever the process could —
  and the server listens on every interface, not just loopback, so anyone who
  could reach port 1331 could do it. Each candidate path is now made absolute,
  normalized, has its symlinks resolved where it exists, and is checked to be
  inside the root it was built from — which handles `..`, an absolute request
  path, and a symlink pointing out of the tree. A symlink *within* the tree
  still works. Verified with canary files for both the dot-segment and the
  symlink route: served before, 404 after, with normal pages unaffected.
- The Windows file watcher observes every configured path, one thread per
  watch, instead of only the first. `acc dev` registers a source watch and a
  content watch, so content edits were never seen on Windows. Untested on
  Windows like the rest of that backend — it cross-checks clean, nothing more.
- A renamed-away file is treated as removed rather than changed, so the output
  its template produced is unlinked. Watchers report a rename as two events,
  the old path and the new one, and both were classified as changes.
- Each log flush replaces the file instead of appending to it. The whole log
  is rendered every time, so a target flushed twice held two documents back to
  back and parsed as neither.
- A malformed `parallel` or `max_concurrent` reports a config-shape error
  instead of crashing. Both read `.content` off the YAML node, which on a
  mapping or list is a `FieldDefect` — not a `CatchableError`, so it escaped
  the CLI's handler as a stack trace.
- The Windows file watcher compiles. `include fswatch/file-change-notification`
  is not a legal Nim include — the dashes made it `Cannot use '-' in 'include'`
  — and behind that the backend had ten type errors: every Win32 constant was
  declared `'u32` while winlean's `DWORD` is `int32`, and a local `createFileW`
  binding shadowed winlean's with an incompatible string type. The module is
  spliced in only on Windows, so nothing else ever parsed it.
- `.json` content is parsed with `std/json` instead of being routed through
  NimYAML, which is about twice as fast on the content we host. Trees agree:
  verified over every `.json` file in the hosted sites (519 files, 5.6 MB)
  with no difference, and over the cases the two parsers could disagree on.
  An empty or whitespace-only file still loads as an empty array, as the YAML
  path gave it, rather than becoming the parse error `std/json` would raise.
- The build manifest lists copied assets, not only rendered pages. `@copy`
  wrote files without recording them in `rendered_outputs`, which is what
  `manifest.json` is built from, so every image, font, stylesheet and script
  was missing from it — on a small site, 4 entries for 31 output files. The
  manifest stays a delta: an asset skipped because it was already up to date
  is still omitted, since a deploy does not need to transfer it. Nothing
  consumes the manifest yet, so no deployment was affected.
- A scoped selector over a grouped collection expands a group of one. `{products[cat]}/{.[slug]}.mustache` only produced pages for categories holding two or more products, because the enclosing scope was treated as a collection only when it held more than one element; a single-element group was dug into for its fields instead. Routing therefore depended on how many rows happened to share a grouping value, so adding a second product to a category made its sibling's page appear.

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

[Unreleased]: https://github.com/accelerate-ssg/acc/compare/v0.2.4...HEAD
[0.2.4]: https://github.com/accelerate-ssg/acc/compare/v0.2.3...v0.2.4
