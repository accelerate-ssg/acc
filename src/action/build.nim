import std/[os, json, times, options, strutils]

import logger
import global_state
import change_set
import action/run_workflow
import action/internal_functions/yaml_loader
import types/render_state/file_list

proc cache_file(state: State): string =
  if state.config.directories.work == "": ""
  else: state.config.directories.work / "context.cache"

proc load_context_cache*(state: State): Option[Time] =
  ## Continue from the persisted context of the previous build, if the
  ## cache is enabled and present. Returns the previous build's stamp.
  if not state.config.useCache or state.cache_file == "":
    return
  let loaded = loadCache(state.cache_file)
  if loaded.isSome:
    state.context = loaded.get.store
    state.has_previous_build = true
    registerContentLoaders()
    notice "Continuing from the cached context of the previous build."
    result = some(loaded.get.stamp)

proc save_context_cache*(state: State, stamp: Time) =
  if state.config.useCache and state.cache_file != "":
    state.context.saveCache(state.cache_file, stamp)

proc write_manifest(state: State) =
  ## What this build produced and retired — exactly what a deploy needs
  ## to transfer and delete.
  if state.config.directories.work == "":
    return
  let manifest = %*{
    "rendered": state.rendered_outputs,
    "removed": state.removed_outputs,
  }
  createDir(state.config.directories.work)
  writeFile(state.config.directories.work / "manifest.json", manifest.pretty)

proc build*( state: State, source_files: seq[string] ) =
  ## Builds exactly the files the caller names. Each workflow still narrows this
  ## list by its own step globs, so a step only ever sees what it asked for.
  state.source_files = source_files

  # Selective rendering state for this build: narrow only when there is
  # something to narrow by.
  state.render_filter = RenderFilter(
    all: state.changed_content.len == 0 and state.changed_sources.len == 0)
  state.render_filter_ready = false
  state.routed_outputs = @[]
  state.rendered_outputs = @[]
  state.removed_outputs = @[]

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

  try:
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
  finally:
    # Whatever happened, the next build narrows against this one and the
    # change lists are consumed.
    state.context.previous_outputs = state.routed_outputs
    state.has_previous_build = true
    state.changed_content = @[]
    state.changed_sources = @[]
    set_current_dir( current_directory )

  state.write_manifest()
  if state.rendered_outputs.len > 0 or state.removed_outputs.len > 0:
    notice "Rendered ", $state.rendered_outputs.len, " page(s), removed ",
      $state.removed_outputs.len

proc build*( state: State ) =
  ## A full build: every source file, less the blacklist and the partials.
  state.changed_content = @[]
  state.changed_sources = @[]
  state.build( init_source_files( state.config ))

proc build*( state: State, changes: ChangeSet ) =
  ## Build what a change set implies: everything when the classifier says
  ## so, nothing when nothing changed, and otherwise a selective build —
  ## routing everything, rendering the pages the changes reach.
  let decision = classify( state.config, changes )

  if decision.full:
    if decision.reason != "":
      notice "Rebuilding everything: ", decision.reason
    state.build()
    return

  if decision.sources.len == 0 and decision.content.len == 0 and
     decision.removed_sources.len == 0 and decision.removed_content.len == 0:
    notice "No changes detected, nothing to build."
    return

  for path in decision.removed_content:
    unload( path )

  state.changed_sources = decision.sources
  state.changed_content = decision.content & decision.removed_content
  if decision.removed_sources.len > 0:
    notice "Removed template(s): ", decision.removed_sources.join( ", " )
  state.build( init_source_files( state.config ))
