# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Development build and run
nimble -d:debug -d:nimDebugDlOpen -p:src --threads:on --mm:orc --deepcopy:on run acc dev ../test_site

# Production build
nimble build -d:release -p:src --threads:on --mm:orc --deepcopy:on
```

Required system dependencies (macOS):
- fswatch: `brew install fswatch`
- pcre: `brew install pcre`

If `libfswatch.dylib` not found, add to `.zshrc`: `export DYLD_LIBRARY_PATH="/usr/local/lib"`

## Architecture

Accelerate (Acc) is a static site generator implemented in Nim. Unlike framework-based SSGs, it's a build pipeline that runs Nimscript plugins against a shared state.

### Core Components

**Entry Point & Actions** (`src/acc.nim`, `src/action/`):
- Main dispatches to actions based on CLI command: `dev`, `build`, `test`, `clean`, `run`, `init`
- `dev_server.nim` - Development server with WebSocket-based live reload and fswatch file monitoring
- `build.nim` - Production build orchestration
- `run_plugins.nim` - Executes plugin pipeline in order

**Global State** (`src/global_state.nim`, `src/types/state.nim`):
- `State` object holds: `context` (JsonNode), `config`, `render_state`, `current_plugin`
- Context is a JSON tree accessed via dot-notation paths (e.g., `state{"site.name"}`)
- Custom `{}=` and `{}` operators handle nested path traversal with array index support

**Plugin System** (`src/script/run.nim`, `src/types/plugin.nim`):
- Plugins are either Nimscript files or built-in functions
- Built-in functions: `@copy`, `@yaml`, `@mustache`, `@markdown`
- Plugins ordered via DAG based on `before`/`after` dependencies
- Nimscript plugins get `api_impl.nim` prepended, providing logging, context access, and shell execution

**Configuration** (`src/types/config/`):
- YAML config parsed in `file.nim` with sections: `site`, `build`
- CLI options in `cli.nim` using docopt
- Default directories: `src/`, `public/`, `content/`, `.acc/`, `scripts/`

**Render State** (`src/types/render_state/`):
- Tracks files to process: source path, output path, render flag, associated data
- `calculate.nim` computes render state from config and context
- `file_router.nim` handles path routing for content-driven pages

### Plugin API

Nimscript plugins have access to:
- `context_get(path)` / `context_set(path, value)` - Read/write shared context
- `readFile(path)` / `writeFile(path, content)` - File operations
- `exec(command)` / `exe(command)` - Shell execution (exit code vs output)
- `->` and `<-` macros for context assignment
- Logging: `notice`, `info`, `warn`, `err`, `fatal`, `debug`

### Build Pipeline Flow

1. Parse CLI args and YAML config
2. Calculate render state (file list from source directory)
3. For each plugin in dependency order:
   - Recalculate render state
   - Copy source files to build directory
   - Execute plugin (Nimscript or built-in function)
4. Output to `.acc/build/` (workspace) or `public/` (destination)
