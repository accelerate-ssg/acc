type
  Action* = enum
    ActionNone, ActionBuild, ActionDev, ActionTest,
    ActionClean, ActionRun, ActionInit

  LogLevel* = enum
    lvlAll, lvlDebug, lvlInfo, lvlNotice,
    lvlWarn, lvlError, lvlFatal, lvlNone

  Step* = object
    comment*: string
    script*: string
    command*: string
    module*: string
    arguments*: seq[string]
    dependsOn*: seq[string]
    timeout*: Option[string]
    onFailure*: Option[string]
    extraConfig*: JsonNode

  Workflow* = object
    name*: string
    `if`*: string
    env*: seq[string]
    parallel*: bool
    maxConcurrent*: int
    steps*: seq[Step]
    workflows*: seq[string]

  Directories* = object
    root*: string
    src*: string
    destination*: string
    content*: string
    config*: string
    work*: string
    scripts*: string
    build*: string

  Config* = object
    manifestVersion*: string
    action*: Action
    logLevel*: LogLevel
    runWorkflow*: string
    showMe*: string
    ## How `acc build` finds out what changed: "full" (default), "git",
    ## or "mtime" once persisted state carries a baseline.
    changeStrategy*: string
    ## Baseline git ref for changeStrategy "git".
    changeSince*: string
    directories*: Directories
    workflows*: seq[Workflow]
    genericConfig*: JsonNode

proc stepKind*(step: Step): string =
  if step.module != "": return "module"
  if step.script != "": return "script"
  if step.command != "": return "command"
  return "unknown"

proc isLeaf*(workflow: Workflow): bool =
  workflow.steps.len > 0

proc isComposition*(workflow: Workflow): bool =
  workflow.workflows.len > 0
