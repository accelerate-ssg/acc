import compiler/[nimeval, llstream, lineinfos, options, renderer]
import os
import strutils
import macros
import sequtils
import tables

import logger
import types/plugin
import script/routines
import global_state

# Read the filenames in ./callbacks at compile time
const CT_callbacks_string = staticExec("ls -1 callbacks")

# Macro for splitting the string by \n and importing the separated files
macro import_callbacks(): untyped =
  let files = CT_callbacks_string.splitLines
  result = newStmtList()
  for file in files:
    result.add(parseStmt("import script/callbacks/" & file[0..^5]))

# Ignore warnings about this not being used, it is technically correct, but
# there is initialisation code that needs to run before we can call it
# dynamically further down. And I didn't want to turn off the warning for the
# entire module, since you can't turn it off locally.
import_callbacks()

const
  api_implementation = staticRead "script/api_impl.nim"
  api_implementation_lines = api_implementation.countLines() + 2

proc initInterpreter(script_name: string): Interpreter =
  let nim_lib_root_path = findNimStdLibCompileTime()

  result = createInterpreter(
    script_name,
    [
      nim_lib_root_path,
      parentDir(currentSourcePath),
      nim_lib_root_path / "pure",
      nim_lib_root_path / "pure" / "collections",
      nim_lib_root_path / "core",
      nim_lib_root_path / "strutils",
      nim_lib_root_path / "system",
      "core / api"
    ]
  )

proc set_error_handler( interpreter: Interpreter, script_path: string ) =
  interpreter.registerErrorHook( proc (config: ConfigRef; info: TLineInfo;
                         msg: string; severity: Severity) {.gcsafe.} =
    if severity == Error and config.errorCounter >= config.errorMax:
      let
        line_number = int( info.line )
        relativ_line_number = line_number - api_implementation_lines

      if relativ_line_number > 0:
        error "Script error in ", script_path, "(", relativ_line_number, ", ", info.col, ")\n", indent( msg, 2 )
        when defined(release): quit(-1)
      else:
        debug "Script error in API implementation (", line_number, ", ", info.col, ") while running", script_path, "\n", indent( msg, 2 )
    elif severity == Warning:
      warn msg
  )

proc inject_api_implementation_lines( stream: PLLStream ) =
  let
    comment = "{.injected_line_count.}"
    index = stream.s.find( comment )

  stream.s[ index .. index + comment.len - 1 ] = $api_implementation_lines

proc run*( plugin: Plugin ) =

  debug "Running ", plugin.name, " from ", plugin.script

  notice "Files:"
  for file in state.config.files:
    info "  ", file

  let
    script_path = plugin.script
    script_name = script_path.splitFile.name
    interpreter = initInterpreter( script_path )
    script =      readFile( script_path )

  interpreter.set_error_handler( script_path )

  # Register script -> runtime functions to interact with the state. These are
  # wrapped by templates in the API implementation that is appended to the
  # scripts
  interpreter.implementRoutine( "*", script_name, "getFromContext", getFromContext )
  interpreter.implementRoutine( "*", script_name, "setInContext", setInContext )
  interpreter.implementRoutine( "*", script_name, "readFile", simpleReadFile )
  interpreter.implementRoutine( "*", script_name, "exec", execWithExitCode )
  interpreter.implementRoutine( "*", script_name, "exe", execWithResults )
  interpreter.implementRoutine( "*", script_name, "writeFile", simpleWriteFile )

  # Actually run the script, concatenated with the API implementation.
  let stream = llStreamOpen( api_implementation & script )
  defer: stream.llStreamClose()
  stream.inject_api_implementation_lines()
  interpreter.evalScript( stream )

  # Convert compile time list of files into list of callback proc names
  const file_names = CT_callbacks_string.split("\n")
  let callbacks = file_names.mapIt( it.splitFile.name )

  # Using that list of available callbacks, check for them in the script context
  echo ""
  debug "Checking for callbacks:"
  for callback in callbacks:
    let callback_proc = interpreter.selectRoutine( callback )
    if callback_proc == nil:
      debug "Did not find ", callback
    else:
      let fun = state.registry[ callback ]
      fun( interpreter, callback_proc )

  # for sym in i.exportedSymbols:
  #   let val = i.getGlobalValue(sym)
  #   doAssert val.kind in {nkStrLit..nkTripleStrLit}
  #   echo sym.name.s , " = ", val.strVal

  interpreter.destroyInterpreter()
