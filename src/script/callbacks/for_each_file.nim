{.used.}

import compiler/[ast, nimeval, renderer]
import os
import tables
import strutils
import sequtils

import global_state
import action/internal_functions/utils

proc for_each_file*( interpreter: Interpreter, callback_proc: PSym ){.gcsafe, locks: 0.} =
  var
    new_files:seq[ string ] = @[]

  for absolute_path in state.config.files:
    let
      relative_path = absolute_path.relative_to(state.config.workspace_directory)
      response = interpreter.callRoutine(
        callback_proc,
        [
          newStrNode( nkStrLit, relative_path.string ),
          newStrNode( nkStrLit, absolute_path.string )
        ]
      )
      clean_response = (response.strVal).string
      paths = clean_response.split(",").mapIt( it.strip )

    for path in paths:
      if not ( path.is_empty_or_whitespace or path.contains( relative.string )) and file_exists( path ):
        state.config.files.incl( path )

# Global registry export
#state.registry["for_each_file"] = for_each_file
