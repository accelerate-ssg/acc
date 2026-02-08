import os

import logger
import global_state

proc build*( state: State ) =
  let
    build_dir = state.config.directories.build
    current_directory = get_current_dir()

  if build_dir != "" and not build_dir.dir_exists():
    debug "Creating directory ", build_dir
    create_dir( build_dir )

  if build_dir != "":
    set_current_dir( build_dir )

  notice "Building..."
  # TODO: implement workflow execution engine
  warn "Build workflow execution not yet implemented"

  set_current_dir( current_directory )
