proc `%`*(d: Directories): JsonNode =
  %* {
    "root": d.root,
    "src": d.src,
    "destination": d.destination,
    "content": d.content,
    "config": d.config,
    "work": d.work,
    "scripts": d.scripts,
    "build": d.build
  }

proc `%`*(s: Step): JsonNode =
  result = %* {
    "kind": s.stepKind,
    "comment": s.comment,
  }
  if s.module != "": result["module"] = %s.module
  if s.script != "": result["script"] = %s.script
  if s.command != "": result["command"] = %s.command
  if s.arguments.len > 0: result["arguments"] = %s.arguments
  if s.dependsOn.len > 0: result["depends_on"] = %s.dependsOn
  if s.timeout.isSome: result["timeout"] = %s.timeout.get
  if s.onFailure.isSome: result["on_failure"] = %s.onFailure.get
  if s.extraConfig != nil and s.extraConfig.len > 0:
    result["extra_config"] = s.extraConfig

proc `%`*(w: Workflow): JsonNode =
  result = %* {
    "name": w.name,
    "parallel": w.parallel,
    "max_concurrent": w.maxConcurrent,
  }
  if w.`if` != "": result["if"] = % w.`if`
  if w.env.len > 0: result["env"] = %w.env
  if w.steps.len > 0:
    result["steps"] = newJArray()
    for s in w.steps: result["steps"].add(%s)
  if w.workflows.len > 0: result["workflows"] = %w.workflows

proc `%`*(c: Config): JsonNode =
  result = %* {
    "manifest_version": c.manifestVersion,
    "action": $c.action,
    "log_level": $c.logLevel,
    "directories": %c.directories,
  }
  if c.runWorkflow != "": result["run_workflow"] = %c.runWorkflow
  if c.workflows.len > 0:
    result["workflows"] = newJArray()
    for w in c.workflows: result["workflows"].add(%w)
  if c.genericConfig != nil and c.genericConfig.len > 0:
    result["generic_config"] = c.genericConfig
