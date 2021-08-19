import compiler/[ast, nimeval, renderer]
import os
import glob
import tables
import strutils
import sequtils, sugar

import logger
import global_state
import types/config/paths

proc for_each_file*( interpreter: Interpreter, callback_proc: PSym ) =
  var
    new_files:seq[ string ] = @[]

  let
    root = state.config.workspace_directory()
    match_relative = state.current_plugin.config.get_or_default( "match_relative", "true" ) == "true"
    pattern = glob( state.current_plugin.config.get_or_default( "glob", "**/*" ))

  for absolute_path in state.config.files:
    let
      relative_path = relativePath( absolute_path, root )
      matches = if match_relative: relative_path.matches( pattern ) else: absolute_path.matches( pattern )

    if match_relative:
      warn relative_path, " matches ", state.current_plugin.config.get_or_default( "glob", "**/*" ), " = ", matches
    else:
      warn absolute_path, " matches ", state.current_plugin.config.get_or_default( "glob", "**/*" ), " = ", matches 

    if matches:
      let
        response = interpreter.callRoutine(
          callback_proc,
          [
            newStrNode( nkStrLit, relative_path ),
            newStrNode( nkStrLit, absolute_path )
          ]
        )
        clean_response = (response.strVal).string
        paths = clean_response.split(",").mapIt( it.strip )

      for path in paths:
        if not ( path.is_empty_or_whitespace or path.contains( relative_path )) and file_exists( path ):
          new_files.add path

  for path in new_files:
    state.config.files.add( path )
  state.config.files = state.config.files.deduplicate

# Global registry export
state.registry["for_each_file"] = for_each_file
