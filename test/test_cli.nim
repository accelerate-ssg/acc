import unittest, os, json, options

import config

# ============================================================================
# CLI helper function tests
# ============================================================================

suite "resolveDir":

  test "empty value returns empty string":
    check resolveDir("/root", "") == ""

  test "relative path is resolved against root":
    let result = resolveDir("/root", "src")
    check result == "/root/src"

  test "nested relative path is resolved":
    let result = resolveDir("/root", "a/b/c")
    check result == "/root/a/b/c"

  test "dot-relative paths are normalized":
    let result = resolveDir("/root", "./src")
    check result == "/root/src"

  test "parent-relative paths are normalized":
    let result = resolveDir("/root/sub", "../other")
    check result == "/root/other"


# ============================================================================
# Config precedence tests (config file + manual overrides)
# ============================================================================

suite "Config precedence":

  test "config file sets directory values":
    let yamlStr = """
manifest_version: v1
directories:
  src: "source"
  destination: "dist"
  build: ".build"
"""
    let config = loadConfig(yamlStr)
    check config.directories.src == "source"
    check config.directories.destination == "dist"
    check config.directories.build == ".build"

  test "CLI override replaces config file value":
    var config = loadConfig("""
manifest_version: v1
directories:
  src: "source"
  destination: "dist"
""")
    let root = "/project"
    # Simulate CLI override: --src custom_src
    config.directories.src = resolveDir(root, "custom_src")
    check config.directories.src == "/project/custom_src"

  test "config file value preserved when no CLI override":
    let config = loadConfig("""
manifest_version: v1
directories:
  src: "source"
""")
    # Without CLI override, the config value stays as-is (relative)
    check config.directories.src == "source"

  test "empty config + no CLI override gives empty directories":
    let config = loadConfig("""
manifest_version: v1
""")
    check config.directories.src == ""
    check config.directories.destination == ""
    check config.directories.content == ""

  test "log level default is lvlAll (0) from empty config":
    let config = loadConfig("""
manifest_version: v1
""")
    # Config object initializes logLevel to default enum value (0 = lvlAll)
    check config.logLevel == lvlAll

  test "action default is ActionNone from empty config":
    let config = loadConfig("""
manifest_version: v1
""")
    check config.action == ActionNone


suite "Step kind determination":

  test "module step":
    let step = Step(module: "@copy")
    check step.stepKind == "module"

  test "script step":
    let step = Step(script: "build.sh")
    check step.stepKind == "script"

  test "command step":
    let step = Step(command: "echo hello")
    check step.stepKind == "command"

  test "empty step is unknown":
    let step = Step()
    check step.stepKind == "unknown"

  test "module takes priority over command":
    # If both are set, module wins (checked first)
    let step = Step(module: "@copy", command: "echo")
    check step.stepKind == "module"


suite "Workflow predicates":

  test "leaf workflow has steps":
    let wf = Workflow(name: "build", steps: @[Step(command: "echo")])
    check wf.isLeaf
    check not wf.isComposition

  test "composition workflow has sub-workflows":
    let wf = Workflow(name: "pipeline", workflows: @["build", "deploy"])
    check wf.isComposition
    check not wf.isLeaf

  test "empty workflow is neither leaf nor composition":
    let wf = Workflow(name: "empty")
    check not wf.isLeaf
    check not wf.isComposition
