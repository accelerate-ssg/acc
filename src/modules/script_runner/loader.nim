import dynlib, tables, os, strutils, sequtils
import types

var scriptRunners*: Table[string, ScriptRunnerLib]
var extensionMap*: Table[string, string]

proc loadScriptRunner*(libPath: string): bool =
  echo "Loading: ", libPath
  let lib = loadLib(libPath)

  if lib == nil:
    echo "Failed to load script runner library: ", libPath
    return false

  var vtable: ScriptRunnerVTable
  vtable.name = cast[proc (): cstring {.cdecl.}](symAddr(lib, "name"))
  vtable.supportedExtensions = cast[proc (): cstring {.cdecl.}](symAddr(lib, "supportedExtensions"))
  vtable.create = cast[proc () {.cdecl.}](symAddr(lib, "create"))
  vtable.destroy = cast[proc () {.cdecl.}](symAddr(lib, "destroy"))
  vtable.eval = cast[proc (script: cstring, context: pointer): cstring {.cdecl.}](symAddr(lib, "eval"))

  if vtable.name != nil and vtable.supportedExtensions != nil and
     vtable.create != nil and vtable.destroy != nil and vtable.eval != nil:

    let
      nameStr = $vtable.name()
      extStr = $vtable.supportedExtensions()
      extensions = extStr.split(',').mapIt(it.strip)

    var runner = ScriptRunnerLib(
      lib: lib,
      vtable: vtable,
      cachedName: nameStr,
      cachedExtensions: extensions
    )

    scriptRunners[nameStr] = runner

    for ext in extensions:
      extensionMap[ext] = nameStr

    echo "Loaded script runner: ", nameStr
    echo "Supported extensions: ", extensions
    return true
  else:
    echo "Failed to load all required functions from script runner library"
    echo "   name: ", vtable.name != nil
    echo "   supportedExtensions: ", vtable.supportedExtensions != nil
    echo "   create: ", vtable.create != nil
    echo "   destroy: ", vtable.destroy != nil
    echo "   eval: ", vtable.eval != nil

    unloadLib(lib)

  return false

proc unloadAllScriptRunners*() =
  for name, runner in scriptRunners:
    unloadLib(runner.lib)
  scriptRunners.clear()
  extensionMap.clear()

proc getScriptRunnerForFile*(filePath: string): ScriptRunnerLib =
  let ext = splitFile(filePath).ext.toLowerAscii
  let extNoDot = if ext.startsWith("."): ext[1..^1] else: ext
  if extNoDot in extensionMap:
    let runnerName = extensionMap[extNoDot]
    if runnerName in scriptRunners:
      return scriptRunners[runnerName]
  return nil
