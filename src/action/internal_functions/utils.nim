import os
import glob
import tables
import strutils

import logger
import global_state
import types/config
import types/config/path_helpers

iterator each*( paths: openArray[Path] ): tuple[ absolute: string, relative: string ] =
  let
    root = state.config.workspace_directory()
    match_relative = state.current_plugin.config.get_or_default( "match_relative", "true" ) == "true"
    pattern = glob( state.current_plugin.config.get_or_default( "glob", "**/*" ))

  for path in paths:
    let
      absolute_path = path.string
      relative_path = relativePath( absolute_path, root )
      matches = if match_relative: relative_path.matches( pattern ) else: absolute_path.matches( pattern )

    if match_relative:
      warn relative_path, " matches ", state.current_plugin.config.get_or_default( "glob", "**/*" ), " = ", matches
    else:
      warn absolute_path, " matches ", state.current_plugin.config.get_or_default( "glob", "**/*" ), " = ", matches

    if matches:
      yield (absolute: absolute_path, relative: relative_path)
