import os

import logger
import global_state
import change_set
import action/run_workflow
import types/render_state/file_list

proc build*( state: State, source_files: seq[string] ) =
  ## Builds exactly the files the caller names. Each workflow still narrows this
  ## list by its own step globs, so a step only ever sees what it asked for.
  state.source_files = source_files

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

proc build*( state: State ) =
  ## A full build: every source file, less the blacklist and the partials.
  state.build( init_source_files( state.config ))

proc build*( state: State, changes: ChangeSet ) =
  ## Build what a change set implies: everything when the classifier says
  ## so, the named templates otherwise, and nothing when nothing changed.
  let decision = classify( state.config, changes )

  if decision.full:
    if decision.reason != "":
      notice "Rebuilding everything: ", decision.reason
    state.build()
  elif decision.sources.len == 0 and decision.removed_sources.len == 0:
    notice "No changes detected, nothing to build."
  else:
    state.build( decision.sources )
