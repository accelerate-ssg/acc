# Accelerate 1.0 Roadmap

Status: draft · Baseline: `0.1.1` (commit `8ce518c`) · Written: 2026-09-27

This document reviews the current documentation and code and lays out a plan
to take Accelerate from `0.1.1` to `1.0.0`. It was written from a full read of
`src/`, the README, CHANGELOG, CLAUDE.md, the release workflow and
`test/config/full.yaml`. The project could not be built for this review: it
pins Nim 2.0.6 and the toolchain couldn't be downloaded. Findings marked
**(verify)** are inferred from the code and should be confirmed by running
the tool before acting on them.

---

## 1. What "1.0" has to mean for Acc

The README's central promise is:

> we only have to keep the core API stable, or backwards compatible using a
> config version string, to be able to run a new build - with a new version of
> the core - on every site no matter how old.

That makes 1.0 primarily a **compatibility commitment**. After 1.0, a site
built today must still build with any later 1.x binary. So 1.0 requires that
these contracts are deliberate, documented and tested, because they become
frozen:

1. **Config file format.** Includes a required version field.
2. **Plugin API.** The Nimscript API surface (`context_get`, `context_set`,
   `exec`, `exe`, `readFile`, `writeFile`, logging, `->`/`<-`), and the
   options accepted by each built-in (`@copy`, `@yaml`, `@markdown`,
   `@mustache`).
3. **Routing semantics.** How `{key.path}` segments in file names expand,
   what `item`/`items` contain, and how output paths and extensions are
   derived.
4. **CLI.** Commands, flags, exit codes.
5. **Directory layout.** Covers `src/`, `content/`, `public/`, `.acc/` and the
   script directory, including where the working directory is while plugins
   run.

Also needed: a binary downloaded from the Releases page must work on a clean
machine, and there must be enough docs for someone outside the team to build a
site.

---

## 2. Current state assessment

### What exists and works (per code and tests)

- The pipeline itself: YAML config, DAG ordering of plugins with
  `before`/`after`, and per-plugin render-state recalculation and file copy
  (`src/action/run_plugins.nim`).
- Four built-ins: `@copy`, `@yaml`, `@markdown` and `@mustache`.
- File-based routing with dynamic segments (`products/{products}.mustache`),
  covered by a reasonable unit-test suite (`src/types/render_state/file_router.nim`).
- A dev server with live reload over WebSocket, fswatch-based rebuilds, a 404
  page with a file tree, and a `/about:context` debug endpoint.
- Release CI building binaries for Linux, macOS arm64/x86 and Windows.

### Blockers: must be fixed before 1.0

| # | Finding | Where |
|---|---------|-------|
| B1 | **Nimscript plugins probably can't run from a release binary.** The interpreter's stdlib search path comes from `findNimStdLibCompileTime()`, which bakes in the CI runner's Nim path. On a user's machine without Nim at that exact path, scripts won't find `system`/`strutils`/`json`. **(verify)** on a clean machine. | `src/script/run.nim:27` |
| B2 | **The script context API is broken.** The API declares `context_get`, but the host registers `getFromContext`, so `context_get` hits the `discard` stub and returns `""`. The `->`/`<-` macros expand to `ctx_set`, which doesn't exist. `context_get` slices `path[8..^1]` regardless of prefix. The `license` template writes to `meta.name`. | `src/script/run.nim:115`, `src/script/api_impl.nim:11,99,188,201`, `src/script/routines.nim:23` |
| B3 | **Unit tests run inside the production binary.** `file_list.nim` and `file_router.nim` import `unittest` and have top-level `suite` blocks. These run at module init on every `acc` invocation, and the file-list suite creates and deletes `$TMP/accelerate_test`. | `src/types/render_state/file_list.nim:111`, `src/types/render_state/file_router.nim:24` |
| B4 | **`acc init` generates a config the loader ignores.** The template writes top-level `name:`/`domains:`, but the parser only reads the `site:` and `build:` sections. A freshly initialised project also has no build steps, so `acc build` does nothing. | `src/action/init/config_template.txt`, `src/types/config/file.nim:143` |
| B5 | **There are two config formats and neither is final.** The parsed format (`site`/`build`) has no version field. The intended next format (`manifest_version`, `directories`, `workflows`, `case`, `steps`) exists only as `test/config/full.yaml`, a commented-out `ConfigNext`, and `file_v2.nim`, which doesn't compile (it imports a nonexistent `types/path` and is missing procs). | `src/types/config.nim:36-90`, `src/types/config/file_v2.nim` |
| B6 | **Dev-server rebuilds aren't correct.** `state.context` is never reset between rebuilds, so deleted content lingers. `@yaml`'s module-level key stack gets the prefix appended on every run and never cleared. Changes that arrive during a build are dropped rather than queued. `build_running` is a plain bool shared across threads. Rebuild exceptions are logged at debug level only. Only `src/` is watched; `content/`, scripts and config are not. | `src/action/dev_server.nim:215-238`, `src/action/internal_functions/yaml_loader.nim:12,51` |
| B7 | **Dev-server exposure.** The server binds `0.0.0.0` and serves the full build context at `/about:context` to the LAN. Request paths are URL-decoded and joined onto the root without normalisation or containment checks, which allows path traversal. **(verify)** with `curl --path-as-is`. | `src/action/dev_server.nim:149-162,256-264` |

### Correctness bugs

- The `@copy` default glob is `*.mustache`, a copy-paste from the mustache
  renderer. It also copies from `src/` rather than the build dir, so changes
  made by earlier plugins aren't picked up (`copy.nim:14,24`).
- The `@yaml` default glob is `content/**/*.{yml,yaml}`, but it's matched
  against paths *relative to* the content dir, so the default never matches
  anything (`yaml_loader.nim:49,56`).
- A plugin's identity is its `name`. Two steps using the same built-in (for
  example two `@copy` steps with different globs) are merged by the DAG as
  "duplicates", and the second step's config is lost
  (`DAG.nim:64-74,126`).
- Plugin `config` is limited to string→string maps, so lists aren't possible.
  `full.yaml` already assumes lists (`partial_directories`, `key_suffixes`)
  (`file.nim:70`).
- Option names are inconsistent: `full.yaml` uses `partial_directories` and
  `key_suffixes`, while the code reads `search_dirs`, `path_contains` and
  `content_starts_with`.
- Rendered output is always `.html`, and dynamic segments aren't slugified,
  giving outputs like `products/Curl care.html` (`file_router.nim:16`).
- Stale files are never removed from `.acc/build/` or `public/`.
- `init_raw_file_list` globs `source_directory & "**/*"` without a path
  separator **(verify)** (`file_list.nim:59`).
- A config file inside `src/` isn't blacklisted, because the code checks
  `dir_exists` on a file path (`file_list.nim:43`).
- In live reload, the client acknowledges with `JSON.stringify("reloading")`,
  which the server's `== "reloading"` never matches. The client also hardcodes
  `ws://localhost:1331`, and only one tab can be connected at a time
  (`force_reload.js:20,35`, `dev_server.nim:108`).
- `acc clean` takes no `ROOT_DIR` and acts on empty paths (`clean.nim`).
- Documented but not implemented: `--test` (`test.nim` is a stub),
  `--exclude` (`build.nim:12` TODO), `--set`, and the `WORKFLOW` argument.
- Help-text short options are malformed (`-s. --src`, …), and `-s`/`-d` mean
  different things for `build` and `run` (`help_message.txt:41-54`).
- `--log` is ignored in non-release builds (`cli.nim:122`). Ctrl-C exits with
  status 0 (`acc.nim:12`). A missing local config is reported as "Global
  config" (`file.nim:167`). The global config lives at `~/config.yaml`.
- Leftover debug output logged at warn/error level: `error plugin.name`
  (`cli.nim:98`), `error path` on every context set (`routines.nim:36`), a
  warning plus `echo` on every HTTP request, and file-list and render-state
  dumps at warn level (`calculate.nim:22`, `file_list.nim:107`,
  `utils.nim:24`, `yaml_loader.nim:53`).
- `readFile` in scripts resolves relative paths against `src/`, while
  `writeFile` and `exec` resolve against the cwd, which is the build dir.

### Code health

- Dead or experimental code: `src/script/ducktape.nim` (JavaScript inside a
  `.nim` file), `src/script/callbacks/*` (don't compile, never imported),
  `file_v2.nim`, the commented `ConfigNext`, the unused `with_debug`, and the
  unused `cligen` dependency.
- Dependencies are managed two ways: `acc.nimble` for nimble, and `src/nim.cfg`
  with Atlas `--noNimblePath` and `../deps` paths.
- Runtime native dependencies: PCRE (through `std/re`, used in four files) and
  libfswatch. Both have to be installed separately, and fswatch doesn't exist
  on Windows, so the Windows dev server is unlikely to work.
- `.gitignore` ignores all non-`.nim` files under `src/`, so new embedded
  assets (html/js/txt) have to be force-added.
- Tests are inline `suite`s plus some `isMainModule` asserts. There's no
  `nimble test` task, no end-to-end test against a fixture site, and CI never
  runs tests.
- Release CI uses the unmaintained `marvinpinto/action-automatic-releases@latest`,
  publishes no checksums, doesn't check the tag against the `acc.nimble`
  version, and triggers on a `development` branch that doesn't exist.
- The repo has no `LICENSE` file, although `acc.nimble` declares GPL-3.0.

### Documentation

The README explains *why* Acc exists well, but it has no quickstart, config
reference, built-in plugin reference, routing guide or plugin-authoring guide.
Installation is documented for macOS only. The Development section points at a
`../test_site` that isn't in the repo and references an `acc run -d …` command
that doesn't match what's shown. The help text links to
`github.com/accelerate-ssg/acc#readme` for plugin docs that don't exist yet.

---

## 3. Decisions needed before work starts

These shape everything after them. Each has a recommendation.

**D1. Which config format becomes 1.0?**
*Recommendation:* freeze a **trimmed v2**, meaning `manifest_version`,
`directories`, `meta`, and an ordered `steps` list that carries each step's
`name`, `script`, `before`/`after` and typed `config`. Defer
`workflows`/`case`/env-conditional orchestration to 1.x. Branch-conditional
deploys are already well served by CI systems. Once `manifest_version` is
required, workflows can be added later without breaking anything. Keep
reading the current `site`/`build` format as the implicit `v0`, with a
deprecation warning and an `acc migrate` command.

**D2. How do Nimscript plugins get a stdlib on user machines? (B1)**
*Recommendation:* publish release **archives** (`acc` plus a pruned `lib/`
matching the compiling Nim version). Resolve the stdlib at runtime in this
order: `$ACC_NIM_LIB`, then `<appDir>/../lib`, then `<appDir>/lib`, then the
compile-time path. Alternative: embed the needed stdlib modules in the binary
and write them to a cache dir on first run. That gives a single-file
download but is more complex.

**D3. File watching.**
*Recommendation:* make a pure-Nim polling watcher the default, available on
every OS with no native dependency. Keep libfswatch as an optional
compile-time feature. This fixes Windows and removes an install step.

**D4. Supported platforms for 1.0.**
*Recommendation:* Tier 1 is Linux x86_64 and macOS arm64/x86_64, tested in
CI. Windows is Tier 2: it builds in CI and `build` is smoke-tested, but it
has no dev-server guarantee until D3 lands.

**D5. Compatibility policy.**
*Recommendation:* SemVer on the five contracts in §1. Deprecations warn for at
least one minor version. A `manifest_version` is supported for all of 1.x.

---

## 4. Milestones

Each milestone is a releasable minor version, so users get fixes along the
way and the CHANGELOG stays meaningful.

### M0 → 0.2.0: Foundations (make change safe)

1. Move the inline `suite`s into `tests/` and add a `nimble test` task (fixes B3).
2. Add a CI workflow that runs `nimble test` and a build on every PR and on
   pushes to `main`.
3. Add an **end-to-end fixture site** at `tests/fixtures/site/` covering
   `@copy`, `@yaml`, `@markdown`, `@mustache`, dynamic routes and one Nimscript
   plugin. Add a golden-file test that runs `acc build` and diffs the
   resulting `public/` against the expected output.
4. Delete the dead code (`ducktape.nim`, `callbacks/`, `file_v2.nim`, the
   commented `ConfigNext`, `with_debug`, `cligen`), pick one dependency
   manager, and fix `.gitignore`.
5. Clean up logging: remove the leftover `error`/`warn`/`echo` debugging,
   honour `--log` in all builds, write logs to stderr, and add `NO_COLOR`
   and non-TTY support.
6. Add a `LICENSE` file.

*Exit criteria:* CI is green and runs unit and e2e tests; `acc --help` prints
no test output; `acc build` of the fixture produces no warnings.

### M1 → 0.3.0: Correctness

1. Script API (B2): register routines under the declared names, define
   `context_set` for the macros, handle `context.`/`config.`/bare paths
   consistently, and fix the `license` meta template. Add a test for every
   API function run through a real script.
2. Built-ins: fix the default globs for `@copy` and `@yaml`; make `@copy` read
   from the build dir.
3. Make builds deterministic: reset `state.context` and module state (the
   `@yaml` key stack) at the start of each build, and clean or sync the build
   and destination dirs so deleted sources disappear.
4. Dev server (B6/B7): queue a rebuild when changes arrive mid-build; use an
   atomic or lock for the build flag; show build errors in the terminal and
   as a browser overlay; watch `content/`, scripts and config; bind to
   `127.0.0.1` by default (`--host` to opt in to the LAN); add `--port`; make
   the reload client derive its URL from `location`; support multiple clients;
   fix the ack; normalise request paths and reject traversal.
5. CLI: fix the help text and short-option collisions; make `clean` take
   `ROOT_DIR`; implement or remove `--test`, `--exclude`, `--set` and
   `WORKFLOW`; exit non-zero on failure and on Ctrl-C (130); fix the wrong
   log messages.
6. Make `acc init` scaffold a project that builds and serves on the first
   try: a config with steps, a sample template, sample content and a sample
   script (fixes B4).

*Exit criteria:* every bug in §2 has either a regression test or a
documented "won't fix", and `acc init x && acc build x` produces a working
page.

### M2 → 0.4.0 / 1.0.0-rc.1: Freeze the contracts

1. Implement the chosen config format (D1): a required `manifest_version`,
   schema validation with readable errors that include the file, key and a
   hint (replacing `assert`s and the stateful event parser), typed plugin
   config (lists, maps, bools), a legacy-format reader with a deprecation
   warning, and `acc migrate`.
2. Plugin identity: give each step an explicit `id` (defaulting to `name`),
   so the same built-in can appear more than once.
3. Built-in option names: settle one naming scheme (e.g. `glob`,
   `partials`, `key_suffixes`) and document each one.
4. Routing: output extension follows the template's inner extension
   (`feed.xml.mustache` → `feed.xml`, falling back to `.html`); slugify
   dynamic segments by default with an opt-out; define and test `item` and
   `items` for every case (object collection, array of objects, array of
   scalars, grouping).
5. Script environment: document and fix the cwd and path-resolution rules
   for `readFile`, `writeFile` and `exec`; expose read-only config values
   (directories, site meta, plugin config) in a documented way.
6. Write the **compatibility policy** (D5) into the docs.

*Exit criteria:* the API reference is complete, and every documented option
has a test.

### M3 → 0.5.0: Distribution

1. Ship the stdlib with releases (D2) and test it in CI by running the e2e
   fixture with the *release artifact* in a clean container that has no Nim
   installed.
2. Replace `std/re` with `nim-regex` to drop the PCRE runtime dependency.
3. Add the polling watcher (D3).
4. Modernise the release workflow: use `softprops/action-gh-release` or `gh
   release`, publish `.tar.gz`/`.zip` archives with SHA-256 checksums, fail if
   the tag doesn't match `acc.nimble`, and pull release notes from the
   CHANGELOG.
5. Install channels: an install script, a Homebrew tap, and optionally a
   Docker image, which suits the "build image with global plugins" workflow
   the README describes.
6. Global config at an XDG path (`~/.config/acc/config.yaml`), with the old
   path supported plus a warning.

*Exit criteria:* the documented install steps work on fresh macOS, Ubuntu
and Windows machines.

### M4 → 1.0.0-rc.N: Documentation and dogfooding

1. A docs site built **with Acc**, which also serves as a second e2e
   fixture. It should cover a quickstart, installation, concepts (pipeline,
   context, render state, routing), a config reference, a built-in reference,
   a plugin-authoring guide with API reference and examples (fetching from an
   API, running an external tool such as Tailwind or esbuild), dev-server
   usage, and the compatibility policy.
2. Rewrite the README: keep the "Why", then add a 60-second quickstart and
   link to the docs.
3. An `examples/` directory with a blog, a product catalogue with dynamic
   routes, and a site that uses an external tool.
4. Update CLAUDE.md to describe the new layout and test commands.
5. Run at least one real client site on the RC for an agreed period
   (suggested: two weeks) with no new blockers.

### 1.0.0 release checklist

- [ ] Every item in §2 is either fixed with a test or explicitly moved to
      post-1.0 in the issue tracker.
- [ ] The config format, plugin API, routing, CLI and layout are documented
      and covered by tests.
- [ ] A release artifact runs the e2e fixture on a clean Tier 1 machine
      without Nim, PCRE or fswatch installed.
- [ ] The legacy config (`0.x`) builds, with a deprecation warning, and
      `acc migrate` converts it.
- [ ] The CHANGELOG is complete from 0.1.1 onwards; the tag matches
      `acc.nimble`; checksums are published.
- [ ] A real production site has run on the RC.

---

## 5. Explicitly out of scope for 1.0 (candidates for 1.x)

- The `workflows`/`case`/`env` orchestration from `test/config/full.yaml`.
- The JavaScript plugin runtime (the Duktape experiment).
- Script callbacks (`for_each_file`, `for_each_field`), unless the plugin
  guide shows they're needed. If so, move them to M2.
- Incremental builds and caching beyond what dev-server speed requires.
- Remote/global plugin registries.

---

## 6. Suggested order of first PRs

1. Move tests out of the binary and add `nimble test` plus a CI test job
   (B3, M0.1–2).
2. Add the e2e fixture site and golden test (M0.3). Everything after this can
   be checked against it.
3. Remove dead code and debug logging (M0.4–5).
4. Fix the script API (B2), with tests.
5. Reproduce the stdlib problem (B1) with the current release binary in a
   clean container. The result decides how urgent D2 is.
6. Fix `acc init` (B4) and the built-in default globs.
