import os

import logger
import global_state
import action/run_workflow

proc build*( state: State ) =
  let
    build_dir = state.config.directories.build
    dest_dir = state.config.directories.destination
    current_directory = get_current_dir()

  if build_dir != "" and not build_dir.dir_exists():
    debug "Creating directory ", build_dir
    create_dir( build_dir )

  if dest_dir != "" and not dest_dir.dir_exists():
    debug "Creating directory ", dest_dir
    create_dir( dest_dir )

  notice "Building..."

  # Find and run the "build" workflow, or run all workflows if none named "build"
  var found = false
  for wf in state.config.workflows:
    if wf.name == "build":
      runWorkflow(state, wf)
      found = true
      break

  if not found:
    if state.config.workflows.len > 0:
      info "No 'build' workflow found, running all workflows"
      runAllWorkflows(state)
    else:
      warn "No workflows defined in config"

  set_current_dir( current_directory )
