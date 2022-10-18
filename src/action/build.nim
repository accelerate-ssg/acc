import os
import tables
import glob
import strutils
import sequtils

import logger
import global_state
import run_plugins
import types/config/path_helpers

proc add_all_files_to_state() =
  let root = state.config.workspace_directory()
  for absolute_path in walkDirRec( root ):
    debug "Adding ", absolute_path
    state.config.files.add absolute_path

# TODO: Add support for the blacklist options.
proc build*( state: State ) =
  var
    blacklist:seq[ Glob ] = @[]

  let
    source_directory = state.config.source_directory
    destination_directory = state.config.destination_directory
    workspace_directory = state.config.workspace_directory
    local_config_path = state.config.local_config_path

    build_is_in_subdirectory_of_source = destination_directory.starts_with( source_directory )
    config_is_in_subdirectory_of_source = local_config_path.starts_with( source_directory )

  if build_is_in_subdirectory_of_source:
    debug "Adding build dir to blacklist"
    blacklist.add( glob( "build/**/*" ))

  if config_is_in_subdirectory_of_source:
    debug "Adding config.yaml to blacklist"
    blacklist.add( glob( "config.yaml" ))

  debug "Adding plugins dir to blacklist"
  blacklist.add( glob( "plugins/**/*" ))

  debug "Creating directory ", workspace_directory
  createDir( workspace_directory )

  for path in walkGlob( source_directory & "**/*" ):
    let relative_path = relativePath( path, source_directory )
    if not blacklist.any_it( relative_path.matches( it )):
      let destination = workspace_directory / relative_path
      destination.parentDir.createDir
      debug "Copying ", path, " to ", destination
      copyFile( path, destination )

  add_all_files_to_state()

  set_current_dir( workspace_directory )

  run_plugins( state )
