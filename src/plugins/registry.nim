import tables, strutils

import logger
import plugins/shared_types

export shared_types

var engines = initTable[string, TemplateEnginePlugin]()

proc registerEngine*(name: string, plugin: TemplateEnginePlugin) =
  engines[name] = plugin
  notice "Registered template engine: ", name

proc getEngine*(name: string): TemplateEnginePlugin =
  ## Look up an engine by module name (e.g. "mustache", "liquid").
  ## Raises KeyError if not found.
  let key = if name.startsWith("@"): name[1..^1] else: name
  if key in engines:
    return engines[key]
  raise newException(KeyError, "No template engine registered for: " & name)

proc hasEngine*(name: string): bool =
  let key = if name.startsWith("@"): name[1..^1] else: name
  key in engines

proc registeredEngines*(): seq[string] =
  result = @[]
  for name in engines.keys:
    result.add(name)
