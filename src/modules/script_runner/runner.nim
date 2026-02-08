import json
import types

proc name*(lib: ScriptRunnerLib): string =
  lib.cachedName

proc supportedExtensions*(lib: ScriptRunnerLib): seq[string] =
  lib.cachedExtensions

proc create*(lib: ScriptRunnerLib) =
  if lib.vtable.create == nil:
    raise newException(ValueError, "Script runner " & lib.name & " does not support creating instances")
  lib.vtable.create()

proc destroy*(lib: ScriptRunnerLib) =
  if lib.vtable.destroy == nil:
    raise newException(ValueError, "Script runner " & lib.name & " does not support destroying instances")
  lib.vtable.destroy()

proc eval*(lib: ScriptRunnerLib, script: string, context: pointer): JsonNode =
  if lib.vtable.eval == nil:
    raise newException(ValueError, "Script runner " & lib.name & " does not support evaluating scripts")
  let
    resultCstr = lib.vtable.eval(script.cstring, context)
    resultString = if resultCstr != nil: $resultCstr else: ""

  try:
    if resultString == "":
      result = newJNull()
    else:
      result = parseJson(resultString)
  except JsonParsingError:
    result = newJString(resultString)
