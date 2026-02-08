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
