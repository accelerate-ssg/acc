# Accelerate 1.0 Roadmap

Status: draft · Baseline: `0.2.4` (`main` at `eb5d322`) · Written: 2026-10-16

This plan takes acc from 0.2.4 to 1.0. It is based on a read of `main`,
the README, CHANGELOG, CLAUDE.md, `MIGRATION_0_2_2.md`,
`PROPOSAL-content-hashed-assets.md`, `editor-architecture.md`, the release
workflow and `tasks/release.nims`. It also covers the work in flight on
other branches. Findings marked **(verify)** come from reading the code, not
from running it.

---

## 1. What 1.0 commits to

The README's promise is that a new acc builds every site, "no matter how
old". 0.2.2 chose to migrate the fleet rather than carry compatibility (see
`MIGRATION_0_2_2.md`), so after that migration 1.0 is the line from which
the promise actually holds. These contracts are frozen at 1.0 and changed
only with a major version or a new `manifest_version`:

1. **Config:** `acc.yaml` with `manifest_version: v1`, `directories`,
   `workflows` (leaf and composition, `if`, `env`), and the step kinds
   `module`, `script` and `command`, with their options.
2. **Path grammar:** the binding syntax in `path_template.nim` (`{.}`,
   collections, `($ref)` filters, `[attr]` and `[attr[]]` selectors), and
   the rule that dynamic segments choose what a page binds to while static
   segments only shape the output path.
3. **Page context:** the reserved keys `item`, `items` and `page`, and what
   each contains for every kind of route.
4. **Template output:** Liquid and Mustache as rendered by a pinned
   pitchfork version, plus acc's own filters (`git_sha`). A pitchfork bump
   that changes output counts as a contract change.
5. **CLI:** commands, flags and exit codes. For a build server the exit
   code is the contract.
6. **Script API:** what a JavaScript `script:` step sees and may do. That
   covers the context it receives and how its changes merge back, its return
   value, logging, and how an error fails the step.
7. **Build artifacts others consume:** `manifest.json`, once a delta deploy
   reads it.

The context cache (`context.cache`) is *not* a contract. It's versioned and
regenerable, and may change in any release.

---

## 2. Where 0.2.4 stands

### Solid

- **Workflows:** the workflow/step model with compositions and `on_failure`,
  plus a converter that lets pre-0.2 `config.yaml` sites build.
- **Content and routing:** the arena-backed build context with per-file
  origins and access tracking. The new path grammar and router, which have
  test suites.
- **Selective builds:** `--using=git` and `--using=mtime`, a persisted cache,
  route-set diffing that unlinks removed pages and assets, and the build
  manifest.
- **Engines:** pitchfork 0.4.0 running both Liquid and Mustache. Liquid
  renders lazily against the arena, so dependencies are tracked per page.
- **Dev server:** one async thread, every tab reloads, rebuilds are batched,
  path traversal is closed, and the port is free or set with `--port`.
- **File watching:** native watchers (FSEvent, inotify, kqueue, plus an
  untested Windows backend), with no fswatch dependency.
- **Releases:** binaries named per platform, with PCRE statically linked on
  macOS and Linux.

### Blockers: must be resolved before 1.0

| # | Finding | Where |
|---|---------|-------|
| B1 | **Script steps don't work from a release binary.** Runners load from `./script_runners` relative to the *current directory*, not the binary or the project. The committed `script_runners/libaccjs.dylib` is 0 bytes, the runner's source isn't in the repo, and the name is macOS-only. `.nims` scripts print "not yet connected" and do nothing. | `src/action/run_workflow.nim:15-30,94-123` |
| B2 | **Failures that exit 0.** A missing script, a script error, an unknown module and an unknown `acc run` workflow are all logged and the build carries on, exiting 0. So does a config with no workflows. Ctrl-C quits with 0. A build server can't tell these from success. | `run_workflow.nim:70,92-93,114-121`, `run.nim:15`, `acc.nim:15-17` |
| B3 | **Config keys that parse and do nothing.** `depends_on`, `timeout`, `parallel` and `max_concurrent` are accepted silently. Freezing the schema with inert keys in it means either implementing them or changing what they mean later. | `src/config/types.nim:11-36` |
| B4 | **PCRE is still in the binary.** `std/re` comes in through acc (`config.nim`, `config/helpers.nim`, `context_store.nim`), pitchfork's string filters, and nim-markdown. macOS and Linux link it statically, but the Windows build doesn't pass the static flags, so it needs a PCRE DLL at runtime **(verify)**. See M1. | `.github/workflows/release.yaml` |
| B5 | **The dev server is exposed on the LAN.** It binds `0.0.0.0`, and `/about:context` serves the whole build context, content included, to anyone who can reach the port. | `src/action/dev_server.nim` |
| B6 | **Selective builds in a repo subdirectory are wrong (verify).** `gitChangeSet` joins `git diff --name-status` output onto the project root, but git prints paths relative to the *repository* root. A site in a subdirectory of its repo would misclassify every change. | `src/change_set.nim:62-91` |
| B7 | **The docs describe a different program.** The README's "How" section is about Nimscript plugins. There's no reference for the config schema, module options, path grammar, page context or filters, even though §1 freezes all of them. | `README.md` |

### Correctness gaps

- **Mustache doesn't narrow selective builds.** It materializes the whole
  context once per step, so its `@step` consumer reads everything, and any
  content change re-renders every Mustache page. Most hosted sites are
  Mustache. Liquid already renders lazily; Mustache needs the same through
  pitchfork's arena API.
- **Rendered templates always get `.html`.** So `main.css.liquid` becomes
  `main.css.html`, and feeds and sitemaps can't be templates.
  (`file_router.nim:337,387`)
- **Partial loaders disagree.** Mustache collects only `.mustache` partials,
  which `MIGRATION_0_2_2.md` notes as a trap for `.html`-template sites.
  Liquid collects `.html` and `.liquid`.
- **Workflow `if` and `env`.** `if` runs `test <condition>` through the
  shell, which doesn't exist on Windows. `env` is applied with `putEnv` and
  never restored, so it leaks into every later workflow.
- **The dev server watches only `src` and `content`.** Edits to `acc.yaml`,
  scripts, or partial directories outside `src` need a restart.
- **The legacy converter drops non-scalar step config,** for example lists
  under a pre-0.2 plugin's `config:`. (`config/io.nim:86-87`)
- **`@markdown` selects fields by undocumented magic:** a path containing
  `-markdown.`, or content starting with `[//]:`. It also walks the whole
  context.
- **`acc init` scaffolds directories but no template or content,** so the
  first `acc build` renders nothing.
- **`ActionTest` can't be reached** from the CLI, and `action/test.nim` is a
  stub.

### Code health

- **Dead code:**
  - `src/types/config/file_v2.nim` (doesn't compile, never imported)
  - `src/config/to_str.nim` (empty)
  - `src/action/internal_functions/utils.nim` (never imported; warns per file)
  - `action/test.nim`
  - the `.nims` branch in `runScriptStep`
  - the `isMainModule` demo in `src/fswatch.nim`, with hard-coded `/Users/jonas/...` paths
  - `src/modules/script_runner/main.nim`, a harness that runs `test_script.js`
  - the 0-byte `script_runners/libaccjs.dylib`
- **CI runs no tests.** The release workflow builds and publishes only. There
  is no `nimble test` task, the suites need sibling checkouts of pitchfork
  and arena, and there's no end-to-end fixture site. Tests are a mix of
  `test/*.nim`, inline `when isMainModule` blocks, and suites `include`d into
  `src/config.nim`.
- **Release workflow:**
  - it still triggers on pushes to `development`
  - it uses the unmaintained `marvinpinto/action-automatic-releases@latest`
  - it publishes no checksums
  - it doesn't check the tag against `acc.nimble`
- **Release tooling:** `tasks/release.nims` exists but isn't included from
  `acc.nimble`.
- **Stale branches:**
  - `development` (7 commits that are cherry-pick duplicates of `main`'s,
    8 behind)
  - `docker-fixes` (2024, 109 behind)
- **Old toolchain:** Nim is pinned at 2.0.6, the line the
  `Options.map`/orc segfault workaround in `config/io.nim` was written for.
- **Sibling pins:** pitchfork and arena are pinned by git tag, so nimble warns
  "underspecified version" on every install.

### Docs drift

- **README:**
  - the "How" section describes Nimscript
  - "Development" refers to `acc run -d ../test_site ...plugins/test.nims`
  - "Usage" leaves out `init`
- **CLAUDE.md:** says `State.context` is a `JsonNode`; it's a `ContextStore`.
- **`PROPOSAL-content-hashed-assets.md`:** its sketch uses the pre-0.2
  `config.yaml`/`name: '@digest'` form, refers to Nimscript, and puts the
  step in `mustache_renderer.nim`, which no longer exists.

---

## 3. Work in flight

| Work | Where | State |
|------|-------|-------|
| `git_sha` Liquid filter, tracked through the arena | `claude/relaxed-ramanujan-mx3du3` | Ready for review |
| Remove direct `std/re` from acc | `refactor/regex` (`2857306`) | Not merged |
| Remove direct `std/re` from pitchfork | pitchfork branch | Not merged |
| Content-hashed assets (`@digest`) | `PROPOSAL-content-hashed-assets.md` | Proposal |
| Visual editor | `editor-architecture.md` | Design; post-1.0 |
| Fleet follow-ups | `MIGRATION_0_2_2.md` "After the image lands" | Per site |

---

## 4. Decisions needed

**D1. How JavaScript script steps ship (B1).** *Decided:* JavaScript
scripting is required for 1.0. What's left to decide is how the engine
reaches the binary. The runner's source isn't in any `accelerate-ssg`
repository today, so the first step either way is to bring it in.

- *Embedded:* compile the engine into `acc` with `{.compile.}`, the same way
  M1 brings in md4c. Duktape, which the current runner uses, is a single C
  file. This removes the runner discovery relative to the current
  directory, the per-platform dynamic library, and the `JsonNode` cast to
  `pointer` across a dynlib boundary.
- *Shipped beside the binary:* build the runner library in CI for every
  platform, publish it in a release archive next to `acc`, and locate it
  relative to the binary.

*Recommendation:* embedded. A single binary keeps the "place it in your
path" install true, and the script API in §1 becomes a Nim interface rather
than a C ABI. The dynamic-runner loader can come back after 1.0 if a second
language is ever wanted. Choosing the engine is part of this decision.
Duktape is what exists, but it targets ES5.1 with partial ES2015+. QuickJS
supports ES2023 and is a handful of C files. Which one depends on what the
existing scripts use. Either way, `.nims` steps are rejected at load:
Nimscript is gone.

**D2. Inert config keys (B3).** *Recommendation:* warn at load for v1, and
reserve them, so a later minor version can implement them without changing
what an existing config means. Implement `timeout` before 1.0 if the build
server needs a hung step to fail.

**D3. Legacy `config.yaml` support in 1.x.** Keep `convertLegacyConfig`
(cheap, and it keeps "no matter how old" true), but drop the `legacyPaths`
routing fallback once the fleet is migrated, as `MIGRATION_0_2_2.md`
already plans. *Recommendation:* keep the converter, drop the fallback, and
fail a legacy site whose templates still use the old grammar with a message
naming the file.

**D4. Lazy Mustache before or after 1.0.** *Recommendation:* before. It's
the difference between selective builds working and not working for most
hosted sites, and it may need a pitchfork release that is easier to land
during 0.x.

**D5. `git_sha` and `@digest`.** Both are answers to cache busting.
*Recommendation:* ship `git_sha` now, since it's built, needs no reference
rewriting, and fits `?v=` schemes. Take `@digest` as the 1.x answer, once
output extensions (§2) and lazy Mustache land.

**D6. Platform tiers.** *Recommendation:* Linux and macOS (arm64, x86) are
tier 1, tested in CI and used in production. Windows is tier 2: built and
smoke-tested, with the watcher and dev server best effort until someone runs
them.

---

## 5. Milestones

### M1 → 0.3.0: PCRE-free and tested on every push

1. Replace nim-markdown with md4c to drop PCRE. nim-markdown (0.8.8)
   imports `std/re`, which loads libpcre at runtime via `dlopen`, so `acc`
   currently depends on PCRE being installed on the target machine. Replace
   it with md4c (plain C, CommonMark), vendored and compiled in via
   `{.compile.}` with a thin Nim wrapper.
   - Vendor md4c at a pinned tag.
   - Write the wrapper and swap the `@markdown` step to use it.
   - Merge the pending removals of acc's and pitchfork's direct `std/re`
     imports to their `main` branches; until then the check below still
     finds libpcre.
   - Compare output on helmaskin.se and hagges.se (output hashes or a diff).
   - Verify: `strings acc | grep -i libpcre` prints nothing.
   - Related: tag new releases of `arena` and `pitchfork` with their
     `regex` migrations and bump the pins in `acc.nimble`.
2. Then remove the PCRE steps from the release workflow and the README's
   production build section. Windows gets the same binary as everyone else
   (B4).
3. A CI workflow that runs every suite on pull requests and on `main`. It
   should check out pitchfork and arena at the pinned tags, and add a
   `nimble test` task that runs the same list locally.
4. An end-to-end fixture site under `test/fixtures/` that exercises `@copy`,
   `@yaml`, `@markdown`, both engines, dynamic routes and a selective
   rebuild. Golden-file comparison of its output.
5. Delete the dead code listed in §2, and the `development` and
   `docker-fixes` branches (tag them first if anything should be kept).
6. Rewrite the README's "How", "Development" and "Usage" sections for the
   workflow model, and fix CLAUDE.md's `State` description (B7, first
   half).

*Exit:* CI is green on every PR, and the md4c output diff on the two sites is
empty or explained.

### M2 → 0.4.0: Failure semantics

1. Every failure in B2 exits non-zero: an unknown module or workflow, a
   missing script, a script error (unless `on_failure: continue`), and no
   workflows. Ctrl-C exits 130. Add a CLI test per case.
2. JavaScript script steps that work from a release binary (B1, D1):
   - Bring the runner's source into the repository, or a sibling one,
     pinned like pitchfork and arena.
   - Ship the engine as D1 decides, embedded by recommendation. Then delete
     the 0-byte `script_runners/libaccjs.dylib`, and the runner lookup
     relative to the current directory if it's no longer needed.
   - Define and document the script API (§1.6): how the script receives the
     context and how its changes merge back (today
     `ContextStore.applyScriptChanges`), what it returns, where
     `console.log` goes (the logger), and how a thrown error fails the step
     with the script's file and line.
   - Decide what a script's reads mean for selective builds. Today a script
     gets the whole context, so its writes invalidate like a content
     reload, but its reads are not narrowed.
   - Reject `.nims` steps at config load with a message.
   - Tests: a script step in the fixture site, plus error, missing-script
     and `on_failure: continue` cases, run in CI against the release build
     on every tier-1 platform.
3. Resolve D2: warn on inert keys.
4. Workflow `if` evaluated without `test(1)`, so it works on Windows, and
   `env` scoped to the workflow that declares it, then restored.
5. The dev server binds `127.0.0.1` by default, with `--host` to opt in to
   the LAN. `/about:context` is served on loopback only (B5).
6. Make `gitChangeSet` paths repository-relative (B6). Use
   `git rev-parse --show-prefix`, as `git_filter.nim` does, and add a test
   with the site in a subdirectory.
7. Merge `git_sha`.

*Exit:* a scripted fleet build (every hosted site) reports failures by exit
code alone, and the fixture's JavaScript step runs from the release binary on
Linux and macOS with nothing installed beside it.

### M3 → 0.5.0: Precision

1. Lazy Mustache rendering against the arena (D4), so selective builds
   narrow for Mustache sites. Measure on the largest hosted site: pages
   rendered for a one-file content change, before and after.
2. Output extensions follow the template: `feed.xml.liquid` → `feed.xml`,
   `main.css.liquid` → `main.css`, with `.html` when there's no inner
   extension. Check the fleet for templates this would rename first.
3. One partial-loader rule for both engines, honouring the step glob's
   extension (fixes the `.html`-template trap).
4. The dev server also watches `acc.yaml`, the scripts directory and
   configured partial directories. A config change reloads the config and
   does a full rebuild.
5. `acc init` scaffolds a page, a content file and a partial, so `init` then
   `build` renders something.
6. The legacy converter keeps list and map step config.

### M4 → 1.0.0-rc: Freeze and document

1. Reference docs for everything in §1: config schema and module options
   (`glob`, `partial_directories`, `search_dirs`, `context_path_prefix`,
   `@markdown`'s selection keys), the path grammar with worked examples, page
   context keys, filters, CLI and exit codes, and selective builds.
   `path_template.nim`'s header is a good start for the grammar (B7, second
   half).
2. A compatibility policy, written down: what §1 freezes, how
   `manifest_version` gates breaking changes, and how long a deprecated
   spelling keeps working.
3. Drop the `legacyPaths` fallback once no hosted site needs it (D3), along
   with its cases in `test/legacy_config.nim`.
4. Release hygiene:
   - wire `tasks/release.nims` into `acc.nimble`
   - replace `marvinpinto/action-automatic-releases` with `gh release`
   - publish SHA-256 checksums
   - fail the release if the tag and `acc.nimble` disagree
   - drop the `development` trigger
5. The fleet builds on the RC from the build image for an agreed period,
   with the output compared against 0.x.

### 1.0.0 release checklist

- [ ] Every blocker in §2 is fixed with a test, or moved past 1.0 by an
      explicit decision recorded here.
- [ ] D2–D6 are decided, D1's shipping question is settled, and all of
      it is reflected in the code.
- [ ] Every contract in §1 is documented, and covered by a test or the
      fixture site.
- [ ] `strings acc | grep -i libpcre` prints nothing on every platform.
- [ ] A JavaScript script step runs from the downloaded release binary on
      every tier-1 platform, on a machine with nothing else installed.
- [ ] CI is green on the release commit. The tag matches `acc.nimble`.
      Checksums are published.
- [ ] Every hosted site builds on the RC with the expected output.

---

## 6. Out of scope for 1.0

- `@digest` content-hashed assets (D5), unless it turns out to be cheap
  after M3.
- The visual editor (`editor-architecture.md`). 1.0 should keep its
  prerequisites possible (Liquid `include` with variable names, live reload)
  rather than build any of it.
- A consumer for `manifest.json` (delta deploys). The manifest is correct
  today; nothing reads it yet.
- `parallel` workflows and `depends_on` ordering, beyond reserving the keys
  (D2).
- A Nim toolchain bump past 2.0.x. Do it as its own release, with the
  fixture site as the safety net, not bundled with 1.0.
