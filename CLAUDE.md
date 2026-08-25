# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Development build and run
nimble -d:debug -d:nimDebugDlOpen -p:src --threads:on --mm:orc --deepcopy:on run acc dev ../test_site

# Production build
nimble build -d:release -p:src --threads:on --mm:orc --deepcopy:on

# Run tests (inline unit tests in source files)
nim c -r -p:src --threads:on --mm:orc --deepcopy:on src/types/render_state/file_router.nim
nim c -r -p:src --threads:on --mm:orc --deepcopy:on src/types/render_state/file_list.nim

# Run standalone test suites
nim c -r -p:src --threads:on --mm:orc --deepcopy:on src/config.nim
nim c -r -p:src --threads:on --mm:orc --deepcopy:on test/test_cli.nim
nim c -r -p:src --threads:on --mm:orc --deepcopy:on test/render_paths.nim

# Run template engine tests (from the pitchfork/ directory)
nim c -r -p:src src/liquid_lib.nim
nim c -r -p:src src/mustache_lib.nim
```

Required system dependencies (macOS):
- pcre: `brew install pcre`

## Architecture

Accelerate (Acc) is a static site generator implemented in Nim. It uses a workflow-based build pipeline where each step operates on shared state.

### Core Components

**Entry Point & Actions** (`src/acc.nim`, `src/action/`):
- Main dispatches to actions based on CLI command: `dev`, `build`, `test`, `clean`, `run`, `init`
- `dev_server.nim` - Async HTTP server (port 1331) with WebSocket live reload and native file watching
- `build.nim` - Finds and runs the "build" workflow (or all workflows)
- `run_workflow.nim` - Executes workflow pipelines with step orchestration

**Global State** (`src/global_state.nim`, `src/state.nim`):
- `State` ref object holds: `context` (JsonNode), `config`, `render_state`, `current_step`, `current_workflow`
- Context is a JSON tree accessed via dot-notation paths (e.g., `state{"site.name"}`)
- Custom `{}=` and `{}` operators handle nested path traversal with array index support
- `diff` proc computes JSON diffs between context snapshots

**Workflow & Step System** (`src/config/types.nim`):
- `Workflow` contains steps or references to sub-workflows, with optional `if` conditionals
- `Step` can be a `module` (built-in), `script` (external), or `command` (shell)
- Steps have optional `dependsOn`, `timeout`, and `onFailure` fields
- Workflows can run in parallel with `maxConcurrent` control

**Configuration** (`src/config/`):
- YAML config parsed with sections for directories and workflows
- CLI options via docopt (`src/config/cli.nim`)
- Default config file: `acc.yaml`
- Directories: `root`, `src`, `destination`, `content`, `config`, `work`, `scripts`, `build`

**Render State** (`src/types/render_state/`):
- Tracks files to process: source path, output path, render flag, item/items data
- `calculate.nim` computes render state from config, steps, and context
- `file_router.nim` handles path routing with three match types:
  - `()` - Key match: expands to keys of object or indices of array
  - `{attribute}` - Attribute match: expands to values of a named attribute
  - `[attribute]` - Array match: expands to unique values from array attributes
- `file_list.nim` generates relative file paths from source directory with glob filtering

**File Watcher** (`src/fswatch.nim`):
- Native implementation using platform-specific APIs (FSEvent on macOS, inotify on Linux)
- No external fswatch dependency required

**Plugin System** (`src/plugins/`):
- Template engines register via `registry.nim` by name and file extensions
- `shared_types.nim` defines `TemplateEnginePlugin` (name, extensions, run proc)
- Built-in engines: `mustache_engine.nim` (`.mustache`), `liquid_engine.nim` (`.liquid`)
- `run_workflow.nim` checks the plugin registry before hardcoded module dispatch
- New engines can be added by implementing the plugin interface and calling `registerEngine`

**Template Engine** (`../pitchfork/`):
- One bytecode VM with per-language frontends ("tines") under `pitchfork/tines/`
- Both built-in engines run on it: `liquid_lib.nim` and `mustache_lib.nim` are
  the per-language convenience APIs, each accepting a `JsonNode` context
- The Liquid API also renders lazily against an arena context store, so context
  reads are tracked by node identity rather than by dotted path
- Both support pre-compilation via `CompiledTemplate` for reuse
- Partials are passed in as a name -> source table; acc collects them from the
  step's search and partial directories, resolved against the project root

**Script Execution** (`src/script/ducktape.nim`):
- Duktape JavaScript runtime integration for running JS-based build steps

**Logger** (`src/logger.nim`):
- Multi-format structured logger with color support

### Dependencies

Dependencies are declared in `acc.nimble` and resolved by nimble — there is no
vendored `deps/` tree and no Atlas workspace. `nimble install -y` from a fresh
checkout is enough to build.

- Third party: glob, yaml (NimYAML), docopt, markdown, ws
- No external fswatch library needed (native implementation)
- No external mustache library needed (pitchfork renders both languages)

Two sibling projects are ours, declared by git URL in `acc.nimble` and also
listed as paths in `src/nim.cfg`, so a checkout that keeps them side by side
compiles against those working copies rather than an installed snapshot:
- `../pitchfork/` — the template engine
- `../arena_context_store/` — the build context store

### Build Pipeline Flow

1. Parse CLI args and YAML config
2. Resolve directory paths (root, src, destination, build, etc.)
3. For the "build" workflow (or all workflows):
   - Calculate file list from source directory using step globs
   - Calculate render state (maps source files to output paths with context data)
   - Execute each step in order (module, script, or command)
4. Dev server watches for file changes and triggers rebuilds with WebSocket reload
