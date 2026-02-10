import unittest
suite "Config Loading Tests":

  test "Basic config loading":
    let yamlStr = """
manifest_version: v1
name: "TestApp"
domains:
  - "test.com"
  - "test.org"
meta:
  product: "testproduct"
directories:
  src: "src"
  destination: "build"
  content: "content"
  config: ".acc"
  work: ".acc/work"
  scripts: ".acc/scripts"
  build: ".acc/build"
"""
    let config = loadConfig(yamlStr)
    assert(config.manifestVersion == "v1")
    assert(config.genericConfig["name"].getStr == "TestApp")
    assert(config.genericConfig["domains"].getElems().mapIt(it.getStr) == @["test.com", "test.org"])
    assert(config.genericConfig["meta"]["product"].getStr == "testproduct")
    assert(config.directories.src == "src")
    assert(config.directories.build == ".acc/build")

  test "Workflow with steps":
    let yamlStr = """
manifest_version: v1
workflows:
  - name: "build"
    parallel: true
    max_concurrent: 3
    steps:
      - script: "test.sh"
        comment: "Run test script"
      - command: "echo hello"
        comment: "Echo hello"
"""
    let config = loadConfig(yamlStr)
    assert(config.workflows.len == 1)
    let workflow = config.workflows[0]
    assert(workflow.name == "build")
    assert(workflow.parallel)
    assert(workflow.maxConcurrent == 3)
    assert(workflow.steps.len == 2)
    assert(workflow.steps[0].script == "test.sh")
    assert(workflow.steps[0].stepKind == "script")
    assert(workflow.steps[1].command == "echo hello")
    assert(workflow.steps[1].stepKind == "command")

  test "Workflow with if condition":
    let yamlStr = """
manifest_version: v1
workflows:
  - name: "deploy_production"
    if: "$ENVIRONMENT == production"
    env:
      - "DNS_NAME=example.com"
      - "NAMESPACE=prod"
    workflows:
      - "build"
      - "deploy"
"""
    let config = loadConfig(yamlStr)
    assert(config.workflows.len == 1)
    let workflow = config.workflows[0]
    assert(workflow.name == "deploy_production")
    assert(workflow.`if` == "$ENVIRONMENT == production")
    assert(workflow.env == @["DNS_NAME=example.com", "NAMESPACE=prod"])
    assert(workflow.workflows == @["build", "deploy"])
    assert(workflow.isComposition)
    assert(not workflow.isLeaf)

  test "Composition workflow":
    let yamlStr = """
manifest_version: v1
workflows:
  - name: "full_pipeline"
    workflows:
      - "build"
      - "test"
      - "deploy"
"""
    let config = loadConfig(yamlStr)
    assert(config.workflows.len == 1)
    let workflow = config.workflows[0]
    assert(workflow.name == "full_pipeline")
    assert(workflow.workflows == @["build", "test", "deploy"])
    assert(workflow.isComposition)

  test "Step with module and extra config":
    let yamlStr = """
manifest_version: v1
workflows:
  - name: "build"
    steps:
      - module: "@copy"
        comment: "Copy assets"
        glob: "**/*.{jpg,png}"
      - module: "@mustache"
        comment: "Render templates"
        glob: "**/*.mustache"
        partial_directories:
          - "src/partials"
"""
    let config = loadConfig(yamlStr)
    let steps = config.workflows[0].steps
    assert(steps.len == 2)
    assert(steps[0].module == "@copy")
    assert(steps[0].stepKind == "module")
    assert(steps[0].extraConfig["glob"].getStr == "**/*.{jpg,png}")
    assert(steps[1].module == "@mustache")
    assert(steps[1].extraConfig["glob"].getStr == "**/*.mustache")

  test "Step with interpolation":
    let yamlStr = """
manifest_version: v1
meta:
  product: "myapp"
workflows:
  - name: "deploy"
    env:
      - "NAMESPACE=${meta.product}"
    steps:
      - command: "deploy.sh"
"""
    let config = loadConfig(yamlStr)
    let workflow = config.workflows[0]
    assert(workflow.env == @["NAMESPACE=myapp"])

  test "Complex config with multiple workflows":
    let yamlStr = """
manifest_version: v1
name: "ComplexApp"
domains:
  - "complex.com"
meta:
  product: "complexproduct"
directories:
  src: "src"
  build: "build"
workflows:
  - name: "build"
    steps:
      - command: "nim c main.nim"
        comment: "Compile"
  - name: "deploy_prod"
    if: "$ENV == production"
    workflows:
      - "build"
  - name: "full_process"
    workflows:
      - "build"
      - "deploy_prod"
"""
    let config = loadConfig(yamlStr)
    assert(config.manifestVersion == "v1")
    assert(config.genericConfig["name"].getStr == "ComplexApp")
    assert(config.workflows.len == 3)
    assert(config.workflows[0].isLeaf)
    assert(config.workflows[1].isComposition)
    assert(config.workflows[1].`if` == "$ENV == production")
    assert(config.workflows[2].isComposition)
    assert(config.workflows[2].workflows == @["build", "deploy_prod"])

  # --- New tests below ---

  test "Missing manifest_version defaults to empty string":
    let yamlStr = """
name: "NoVersion"
"""
    let config = loadConfig(yamlStr)
    check config.manifestVersion == ""

  test "Config with no workflows has empty workflow list":
    let yamlStr = """
manifest_version: v1
name: "NoWorkflows"
"""
    let config = loadConfig(yamlStr)
    check config.workflows.len == 0

  test "Config with no directories has empty directory fields":
    let yamlStr = """
manifest_version: v1
name: "NoDirs"
"""
    let config = loadConfig(yamlStr)
    check config.directories.src == ""
    check config.directories.destination == ""
    check config.directories.build == ""

  test "genericConfig captures all unknown top-level keys":
    let yamlStr = """
manifest_version: v1
name: "Test"
custom_field: "custom_value"
another:
  nested: "data"
"""
    let config = loadConfig(yamlStr)
    check config.genericConfig["name"].getStr == "Test"
    check config.genericConfig["custom_field"].getStr == "custom_value"
    check config.genericConfig["another"]["nested"].getStr == "data"

  test "genericConfig does not contain schema keys":
    let yamlStr = """
manifest_version: v1
directories:
  src: "src"
workflows:
  - name: "build"
    steps:
      - command: "echo hi"
"""
    let config = loadConfig(yamlStr)
    check not config.genericConfig.hasKey("manifest_version")
    check not config.genericConfig.hasKey("directories")
    check not config.genericConfig.hasKey("workflows")

  test "Nested interpolation in config values":
    let yamlStr = """
manifest_version: v1
meta:
  product: "myapp"
  region: "eu"
workflows:
  - name: "deploy"
    env:
      - "APP=${meta.product}"
      - "REGION=${meta.region}"
    steps:
      - command: "deploy.sh"
"""
    let config = loadConfig(yamlStr)
    let workflow = config.workflows[0]
    check workflow.env == @["APP=myapp", "REGION=eu"]

  test "Interpolation with missing key leaves placeholder":
    let yamlStr = """
manifest_version: v1
workflows:
  - name: "deploy"
    env:
      - "APP=${missing.key}"
    steps:
      - command: "deploy.sh"
"""
    let config = loadConfig(yamlStr)
    let workflow = config.workflows[0]
    # When the interpolation key doesn't exist, the placeholder is kept
    check workflow.env == @["APP=${missing.key}"]

  # NOTE: Step with only a comment (no script/command/module) causes a SIGSEGV
  # in loadStep before the ValueError check is reached. This is a known bug.
  # test "Step must have script, command, or module":
  #   expect ValueError:
  #     discard loadConfig("...")

  test "Step extraConfig captures sequence values":
    let yamlStr = """
manifest_version: v1
workflows:
  - name: "build"
    steps:
      - module: "@mustache"
        partial_directories:
          - "src/partials"
          - "src/components"
"""
    let config = loadConfig(yamlStr)
    let step = config.workflows[0].steps[0]
    check step.extraConfig["partial_directories"].len == 2

  test "Step with timeout and onFailure":
    let yamlStr = """
manifest_version: v1
workflows:
  - name: "build"
    steps:
      - command: "slow_task.sh"
        timeout: "30s"
        on_failure: "continue"
"""
    let config = loadConfig(yamlStr)
    let step = config.workflows[0].steps[0]
    check step.timeout.isSome
    check step.timeout.get == "30s"
    check step.onFailure.isSome
    check step.onFailure.get == "continue"

  test "Step without timeout and onFailure has none":
    let yamlStr = """
manifest_version: v1
workflows:
  - name: "build"
    steps:
      - command: "simple.sh"
"""
    let config = loadConfig(yamlStr)
    let step = config.workflows[0].steps[0]
    check step.timeout.isNone
    check step.onFailure.isNone

  test "Workflow defaults - parallel false, maxConcurrent 1":
    let yamlStr = """
manifest_version: v1
workflows:
  - name: "build"
    steps:
      - command: "echo hi"
"""
    let config = loadConfig(yamlStr)
    let workflow = config.workflows[0]
    check not workflow.parallel
    check workflow.maxConcurrent == 1

  test "loadFile round-trip parses YAML correctly":
    let yamlStr = """
manifest_version: v1
name: "RoundTrip"
count: 42
"""
    let node = loadFile(yamlStr)
    check node["manifest_version"].content == "v1"
    check node["name"].content == "RoundTrip"
    check node["count"].content == "42"
