import os
import glob
import strutils
import sequtils
import times
import sets

import logger
import global_state
import run_plugins
import types/config/path_helpers

# TODO: Add support for the blacklist options.
proc build*( state: State ) =
  var
    blacklist:seq[ Glob ] = @[]

  let
    source_directory = state.config.source_directory
    destination_directory = state.config.destination_directory
    workspace_directory = state.config.workspace_directory
    plugins_directory = source_directory / "plugins"
    local_config_path = state.config.local_config_path
    current_directory = get_current_dir()

    build_is_in_subdirectory_of_source = destination_directory.starts_with( source_directory )
    config_is_in_subdirectory_of_source = local_config_path.starts_with( source_directory )
    

  if build_is_in_subdirectory_of_source:
    debug "Adding build/* to blacklist"
    blacklist.add( glob( "build/**/*" ))

  if config_is_in_subdirectory_of_source:
    let
      relative_config_path = relativePath( local_config_path, source_directory )
    debug "Adding " & relative_config_path & " to blacklist"
    blacklist.add( glob( relative_config_path ))

  if plugins_directory.dir_exists():
    debug "Adding plugins dir to blacklist"
    blacklist.add( glob( "plugins/**/*" ))

  if not workspace_directory.dir_exists():
    debug "Creating directory ", workspace_directory
    createDir( workspace_directory )

  for source_path in walkGlob( source_directory & "**/*" ):
    let
      relative_path = relativePath( source_path, source_directory )
      destination_path = workspace_directory / relative_path

    if blacklist.any_it( relative_path.matches( it )):
      continue

    destination_path.parentDir.createDir
    state.config.files.incl destination_path

    if not destination_path.file_exists() or source_path.file_newer(destination_path):
      debug "Copying ", source_path, " to ", destination_path
      copyFile( source_path, destination_path )

  set_current_dir( workspace_directory )

  run_plugins( state )

  set_current_dir( current_directory )
