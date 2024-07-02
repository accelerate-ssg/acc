import os
import glob
import strutils
import sequtils
import times

import logger
import global_state
import run_plugins
import types/config/path_helpers

# TODO: Add support for the blacklist options.
proc build*( state: State ) =
  let
    build_directory = state.config.build_directory
    source_directory = state.config.source_directory
    current_directory = get_current_dir()

  if not build_directory.dir_exists():
    debug "Creating directory ", build_directory
    create_dir( build_directory )

  set_current_dir( build_directory )

  run_plugins( state )

  set_current_dir( current_directory )
