{.used.}

import compiler/[ast, nimeval, renderer]
import os
import tables
import strutils
import sequtils

import global_state
import action/internal_functions/utils

proc for_each_file*( interpreter: Interpreter, callback_proc: PSym ) =
  var
    new_files:seq[ string ] = @[]

  for (absolute, relative) in state.config.files.each:
      let
        response = interpreter.callRoutine(
          callback_proc,
          [
            newStrNode( nkStrLit, relative.string ),
            newStrNode( nkStrLit, absolute.string )
          ]
        )
        clean_response = (response.strVal).string
        paths = clean_response.split(",").mapIt( it.strip )

      for path in paths:
        if not ( path.is_empty_or_whitespace or path.contains( relative.string )) and file_exists( path ):
          new_files.add path

  for path in new_files:
    state.config.files.add( path )
  # TODO: Implement the files map as a set
  state.config.files = state.config.files.deduplicate

# Global registry export
state.registry["for_each_file"] = for_each_file
