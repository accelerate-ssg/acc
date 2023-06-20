import compiler/[nimeval, llstream, lineinfos, options, renderer, msgs]
import os
import strutils
import sets

import logger
import types/plugin
import script/routines
import action/internal_functions/[mustache_renderer, yaml_loader, markdown_renderer]
import global_state

# Read the filenames in ./callbacks at compile time
# const CT_callbacks_string = staticExec("ls -1 callbacks")

# macro importFolder() =
#   result = newStmtList()
#   for file in CT_callbacks_string.splitLines:
#     result.add(parseStmt("import script/callbacks/" & file[0..^5]))

# importFolder

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
    ],
    {}, # TSandboxFlags
    @[("nimscript", "true"),("debug", "true")],
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
    else:
      let
        line_number = int( info.line )
        relativ_line_number = line_number - api_implementation_lines

      notice "!!! ", msg, " @ ", toMsgFilename( config, info.fileIndex ), ":", relativ_line_number
  )

proc inject_api_implementation_lines( stream: PLLStream ) =
  let
    comment = "{.injected_line_count.}"
    index = stream.s.find( comment )

  stream.s[ index .. index + comment.len - 1 ] = $api_implementation_lines



proc run_function*( plugin: Plugin ) =

  debug "Running internal function"

  case plugin.function:
    of "mustache":
      mustache_renderer.run( plugin )
    of "yaml":
      yaml_loader.run( plugin )
    of "markdown":
      markdown_renderer.run( plugin )
    else:
      error "Unknown internal function \"", plugin.function, "\""



proc run_script*( plugin: Plugin ) =

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
  interpreter.implementRoutine( "*", script_name, "getFromContext", context_get )
  interpreter.implementRoutine( "*", script_name, "context_set_bool", context_set_bool )
  interpreter.implementRoutine( "*", script_name, "context_set_int", context_set_int )
  interpreter.implementRoutine( "*", script_name, "context_set_float", context_set_float )
  interpreter.implementRoutine( "*", script_name, "context_set_string", context_set_string )
  interpreter.implementRoutine( "*", script_name, "readFile", simpleReadFile )
  interpreter.implementRoutine( "*", script_name, "exec", execWithExitCode )
  interpreter.implementRoutine( "*", script_name, "exe", execWithResults )
  interpreter.implementRoutine( "*", script_name, "writeFile", simpleWriteFile )

  # Actually run the script, concatenated with the API implementation.
  let stream = llStreamOpen( api_implementation & script )
  defer: stream.llStreamClose()
  stream.inject_api_implementation_lines()
  interpreter.evalScript( stream )

  # TODO: Reimplement callbacks from script files.
  # Convert compile time list of files into list of callback proc names
  # const file_names = CT_callbacks_string.split("\n")
  # let callbacks = file_names.mapIt( it.splitFile.name )

  # Using that list of available callbacks, check for them in the script context
  # for callback in callbacks:
  #   let
  #     callback_proc = interpreter.selectRoutine( callback )

  #   if callback_proc != nil:
  #     let fun = state.registry[ callback ]
  #     fun( interpreter, callback_proc )

  interpreter.destroyInterpreter()



proc run*( plugin: Plugin ) =
    if plugin.function != "":
      run_function( plugin )
    else:
      run_script( plugin )
