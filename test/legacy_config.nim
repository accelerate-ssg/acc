# Legacy (pre-0.2) config conversion and path grammar.
import std/[unittest, json, sequtils, sugar]
import config
import types/render_state
import types/render_state/file_router

suite "legacy config conversion":
  const LEGACY = """
name: old-site
pipeline: accelerate
domains:
  - old-site.se
content_root: innehall

build:
  - name: '@copy'
    config:
      glob: '**/*.{png,css}'
  - name: '@yaml'
    config:
      glob: '**/*.{yml,yaml,json}'
  - name: '@mustache'
    config:
      search_dirs: '.,src/partials'
      glob: '**/*.mustache'
"""

  test "a build list becomes per-step workflows chained by a composition":
    let cfg = loadConfig(LEGACY)
    # Per-step workflows are not packaging: the old engine recomputed the
    # render state before every plugin, and acc2 snapshots per workflow.
    check cfg.workflows.mapIt(it.name) ==
      @["step-1-copy", "step-2-yaml", "step-3-mustache", "build"]
    check cfg.workflows[^1].isComposition
    check cfg.workflows[^1].workflows ==
      @["step-1-copy", "step-2-yaml", "step-3-mustache"]
    for wf in cfg.workflows[0 .. ^2]:
      check wf.isLeaf
      check wf.steps.len == 1

  test "step config keys land in extraConfig and the module keeps its @":
    let cfg = loadConfig(LEGACY)
    check cfg.workflows[0].steps[0].module == "@copy"
    check cfg.workflows[0].steps[0].extraConfig{"glob"}.getStr ==
      "**/*.{png,css}"
    check cfg.workflows[2].steps[0].extraConfig{"search_dirs"}.getStr ==
      ".,src/partials"

  test "legacy directory defaults apply, honouring content_root":
    let cfg = loadConfig(LEGACY)
    check cfg.directories.src == "src"
    check cfg.directories.destination == "public"   # not "build"
    check cfg.directories.content == "innehall"
    check cfg.legacyPaths

  test "a v1 manifest is untouched and does not get legacy routing":
    let cfg = loadConfig("""
manifest_version: v1
name: "new"
domains: []
directories: { src: "src", destination: "build", content: "content", config: ".acc", work: ".acc/work", build: ".acc/build" }
workflows:
  - name: "build"
    steps:
      - module: "@copy"
        glob: "*"
""")
    check cfg.workflows.mapIt(it.name) == @["build"]
    check not cfg.legacyPaths
    check cfg.directories.destination == "build"

suite "legacy path grammar":
  let ctx = %* {
    "manufacturers": [
      {"path": "kubota", "name": "Kubota"},
      {"path": "wrag", "name": "Wrag"},
    ],
    "nested": {"path": {"test": {"name": "still a context path"}}},
  }

  test "{a.b} falls back to grouping collection a by attribute b":
    let results = ctx.calculate_render_state_items_for(
      "produkter/{manufacturers.path}.mustache", legacy_paths = true)
    check results.map((r) => r.output_path) ==
      @["produkter/kubota.html", "produkter/wrag.html"]

  test "a real context path still wins over the fallback":
    let results = ctx.calculate_render_state_items_for(
      "nested/{nested.path}.mustache", legacy_paths = true)
    check results.map((r) => r.output_path) == @["nested/test.html"]

  test "without the flag the miss still skips":
    let results = ctx.calculate_render_state_items_for(
      "produkter/{manufacturers.path}.mustache")
    check results.len == 0
