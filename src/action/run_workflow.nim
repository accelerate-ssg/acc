import os, osproc, json, strutils, times, options

import logger
import global_state
import config
import modules/script_runner/[types, loader, runner]
import action/internal_functions/[copy, yaml_loader, markdown_renderer]
import plugins/registry
import types/render_state/calculate

const dynlibExts = [".dll", ".so", ".dylib"]

proc initScriptRunners*() =
  ## Scan script_runners/ directory and load available dynamic script runners.
  let runnersDir = "script_runners"
  if not runnersDir.dirExists:
    debug "No script_runners/ directory found"
    return

  for kind, path in walkDir(runnersDir):
    if kind in {pcFile, pcLinkToFile}:
      let ext = splitFile(path).ext.toLowerAscii
      if ext in dynlibExts:
        let resolvedPath = if kind == pcLinkToFile: expandSymlink(path) else: path
        if loadScriptRunner(resolvedPath):
          notice "Loaded script runner: ", path
        else:
          warn "Failed to load script runner: ", path

proc findWorkflow*(config: Config, name: string): Workflow =
  for wf in config.workflows:
    if wf.name == name:
      return wf
  raise newException(KeyError, "Workflow not found: " & name)

proc evaluateCondition*(condition: string): bool =
  if condition == "":
    return true
  let exitCode = execCmd("test " & condition)
  return exitCode == 0

proc setWorkflowEnv(workflow: Workflow) =
  for envEntry in workflow.env:
    let parts = envEntry.split('=', 1)
    if parts.len == 2:
      putEnv(parts[0].strip, parts[1].strip)

proc runModuleStep(step: Step, state: State) =
  let moduleName = step.module.strip
  let name = if moduleName.startsWith("@"): moduleName[1..^1] else: moduleName
  notice "Running module: ", name

  # Check plugin registry first (template engines)
  if hasEngine(name):
    let engine = getEngine(name)
    engine.run(step, state)
    return

  # Built-in modules
  case name:
  of "copy":
    copy.run(step)
  of "yaml":
    yaml_loader.run(step)
  of "markdown":
    markdown_renderer.run(step)
  else:
    error "Unknown module: ", name

proc runCommandStep(step: Step, state: State) =
  let command = step.command
  notice "Running command: ", command

  let exitCode = execCmd(command)
  if exitCode != 0:
    let msg = "Command failed with exit code " & $exitCode & ": " & command
    if step.onFailure.isSome and step.onFailure.get == "continue":
      warn msg
    else:
      raise newException(OSError, msg)

proc runScriptStep(step: Step, state: State) =
  let scriptPath = step.script
  notice "Running script: ", scriptPath

  let resolvedPath = if scriptPath.isAbsolute: scriptPath
                     else: state.config.directories.scripts / scriptPath

  if not resolvedPath.fileExists:
    error "Script not found: ", resolvedPath
    return

  let ext = resolvedPath.splitFile.ext.toLowerAscii
  case ext:
  of ".nims":
    notice "NimScript execution not yet connected to new workflow engine"
  else:
    let scriptRunner = getScriptRunnerForFile(resolvedPath)
    if scriptRunner != nil:
      let scriptContent = readFile(resolvedPath)
      try:
        scriptRunner.create()
        # Scripts receive a materialized JsonNode snapshot of the context
        # and mutate it in place through the pointer, as they always have.
        # The mutations are merged back into the store after the run.
        let contextJson = state.context.toJson
        let contextPtr = cast[pointer](contextJson)
        let result = scriptRunner.eval(scriptContent, contextPtr)
        state.context.applyScriptChanges(contextJson)
        debug "Script result: ", $result
      except JSException as e:
        error "JavaScript error in ", resolvedPath, ": ", e.msg
        if e.stacktrace != "":
          error e.stacktrace
      except CatchableError as e:
        error "Error running script ", resolvedPath, ": ", e.msg
      finally:
        scriptRunner.destroy()
    else:
      error "No script runner available for extension: ", ext

proc runStep*(step: Step, state: State) =
  if step.comment != "":
    info step.comment

  state.current_step = step

  let startTime = cpuTime()

  let kind = step.stepKind
  case kind:
  of "module":
    runModuleStep(step, state)
  of "command":
    runCommandStep(step, state)
  of "script":
    runScriptStep(step, state)
  else:
    error "Unknown step kind: ", kind

  let elapsed = cpuTime() - startTime
  debug "Step completed in ", $(elapsed * 1000).int, "ms"

proc runWorkflow*(state: State, workflow: Workflow, depth: int = 0) =
  let indent = "  ".repeat(depth)
  notice indent, "Workflow: ", workflow.name

  # Evaluate condition
  if not evaluateCondition(workflow.`if`):
    info indent, "Condition not met, skipping: ", workflow.`if`
    return

  # Set environment variables
  setWorkflowEnv(workflow)

  state.current_workflow = workflow

  if workflow.isComposition:
    # Run referenced workflows in sequence
    for workflowName in workflow.workflows:
      let childWorkflow = findWorkflow(state.config, workflowName)
      runWorkflow(state, childWorkflow, depth + 1)

  elif workflow.isLeaf:
    # Calculate render state for this workflow's steps
    state.render_state = calculate_render_state(state.config, workflow.steps, state.context.toJson, state.source_files)

    # Run steps
    for step in workflow.steps:
      runStep(step, state)

  else:
    warn indent, "Workflow '", workflow.name, "' has no steps or sub-workflows"

proc runWorkflowByName*(state: State, name: string) =
  let workflow = findWorkflow(state.config, name)
  runWorkflow(state, workflow)

proc runAllWorkflows*(state: State) =
  for workflow in state.config.workflows:
    runWorkflow(state, workflow)
