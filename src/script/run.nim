import compiler/[ast, nimeval, llstream, lineinfos, options, renderer]
import os
import strutils

import logger
import types/plugin
import script/routines
import global_state

const
  declarations = staticRead "script/api_impl.nim"

proc initInterpreter(script_name: string): Interpreter =
  let std = findNimStdLibCompileTime()

  result = createInterpreter(
    script_name,
    [
      std,
      parentDir(currentSourcePath),
      std / "pure",
      std / "pure" / "collections",
      std / "core",
      std / "strutils",
      std / "system",
      "core / api"
    ]
  )

proc set_error_handler( interpreter: Interpreter, script_path: string ) =
  interpreter.registerErrorHook( proc (config: ConfigRef; info: TLineInfo;
                         msg: string; severity: Severity) {.gcsafe.} =
    if severity == Error and config.errorCounter >= config.errorMax:
      let
        line_number = int(info.line)
        header_lines = declarations.countLines() + 1
        relativ_line_number = line_number - header_lines

      if relativ_line_number > 0:
        error "Script error in ", script_path, "(", relativ_line_number, ", ", info.col, ")\n", indent( msg, 2 )
        quit(-1)
      else:
        debug "Script error in ", script_path, "(", line_number, ", ", info.col, ")\n", indent( msg, 2 )
    elif severity == Warning:
      warn msg
  )

proc run*( plugin: Plugin ) =

  debug "Running ", plugin.name, " from ", plugin.script

  let
    script_path = plugin.script
    script_name = script_path.splitFile.name
    interpreter = initInterpreter( script_path )
    script_string = readFile( script_path )

  interpreter.set_error_handler( script_path )

  # Register script -> runtime functions to interact with the state. These are
  # wrapped by templates in the API implementation that is appended to the
  # scripts
  interpreter.implementRoutine( "*", script_name, "getFromContext", getFromContext )
  interpreter.implementRoutine( "*", script_name, "setInContext", setInContext )

  # Actually run the script, concatenated with the API implementation.
  interpreter.evalScript( llStreamOpen( declarations & script_string ))

  # Temporary implementation of a call TO a script defined proc. These have to
  # be declared as stubs in the API implementation part.
  let foreignProc = interpreter.selectRoutine("for_each_file")
  if foreignProc == nil:
    warn "Did not find for_each_file"
  else:
    for path in walkDirRec( state.config.source_directory ):
      discard interpreter.callRoutine(foreignProc, [newStrNode( nkStrLit, path )])

  # for sym in i.exportedSymbols:
  #   let val = i.getGlobalValue(sym)
  #   doAssert val.kind in {nkStrLit..nkTripleStrLit}
  #   echo sym.name.s , " = ", val.strVal

  interpreter.destroyInterpreter()
