import os
import strutils

import logger
import global_state
import types/config/path_helpers

const
 config_template = staticRead("init/config_template.txt")

proc is_empty( path: string ): bool =
  result = true
  for file in path.walk_dir:
    result = false
    break

proc init*( state: State ) =
  info "Initializing new project"
  if state.config.root_directory.is_empty:
    state.config.source_directory.create_dir
    state.config.destination_directory.create_dir
    state.config.workspace_directory.create_dir
    state.config.build_directory.create_dir
    state.config.script_directory.create_dir
    state.config.content_directory.create_dir
  
    try:
      state.config.local_config_path.write_file( config_template )
    except IOError as e:
      logger.error "Failed to create configuration file: ", e.msg
  else:
    logger.error "Destination directory is not empty. Please choose an empty directory to initialize a new project."


