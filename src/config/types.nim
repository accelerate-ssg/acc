type
  Action* = enum
    ActionNone, ActionBuild, ActionDev, ActionTest,
    ActionClean, ActionRun, ActionInit

  LogLevel* = enum
    lvlAll, lvlDebug, lvlInfo, lvlNotice,
    lvlWarn, lvlError, lvlFatal, lvlNone

  Step* = object
    ## Accepted and not yet implemented: `dependsOn` and `timeout` are
    ## parsed, validated and serialized, but run_workflow.nim runs steps in
    ## declaration order and never times one out. A config setting either is
    ## silently inert — on purpose, so a config written for a later version
    ## still loads, but it means neither can be relied on today.
    comment*: string
    script*: string
    command*: string
    module*: string
    arguments*: seq[string]
    dependsOn*: seq[string]      ## accepted, not yet implemented
    timeout*: Option[string]     ## accepted, not yet implemented
    onFailure*: Option[string]   ## "continue" turns a failed step into a
                                 ## warning; any other value, or none, lets
                                 ## the failure stop the workflow
    extraConfig*: JsonNode

  Workflow* = object
    ## Accepted and not yet implemented: `parallel` and `maxConcurrent` are
    ## parsed and serialized, but a composition runs its sub-workflows in
    ## sequence regardless. Same caveat as the Step settings above.
    name*: string
    `if`*: string
    env*: seq[string]
    parallel*: bool              ## accepted, not yet implemented
    maxConcurrent*: int          ## accepted, not yet implemented
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
    legacyPaths*: bool        ## Set by the pre-0.2 config converter: route
                              ## templates with the legacy path grammar,
                              ## where `{a.b}` falls back to grouping
                              ## collection `a` by attribute `b` when no
                              ## context node exists at path `a.b`.
    action*: Action
    logLevel*: LogLevel
    runWorkflow*: string
    showMe*: string
    ## How `acc build` finds out what changed: "full" (default), "git",
    ## or "mtime" once persisted state carries a baseline.
    changeStrategy*: string
    ## Baseline git ref for changeStrategy "git".
    changeSince*: string
    ## Load the persisted context before building and save it after.
    useCache*: bool
    ## Dev server port from `--port`. When unset the server takes the
    ## first free port at or above the default, so several sites can be
    ## served at once; an explicit value is used as given or not at all.
    devPort*: Option[int]
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
