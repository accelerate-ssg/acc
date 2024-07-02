import os
import strutils
import times
import tables
import json

import sequtils
import sugar

import logger
import global_state
import script/run
import types/pretty_print
import types/config/path_helpers
import types/render_state/calculate


template with_debug( name: string, body: untyped) =
  # Debug header
  echo "--{ ", name, " }---------------------------------------------------"
  echo ""
  let old_state_context = state.context.deepCopy()
  let script_start_time = epoch_time()

  # Execute the provided code block
  body

  # Debug footer
  info "finished in ", format_float( epoch_time() - script_start_time, format = ffDecimal, precision = 2), " seconds."
  echo ""
  let state_context_diff = diff( state.context, old_state_context )
  echo ""



proc copy_files( state: State ) =
  let
    build_directory = state.config.build_directory
    source_directory = state.config.source_directory

  # Copy all legal source files to the build directory.
  for render_item in state.render_state:
    let
      source_path = source_directory / render_item.source_path
      destination_path = build_directory / render_item.source_path

    destination_path.parent_dir.create_dir

    if not destination_path.file_exists() or source_path.file_newer(destination_path):
      debug "Copying ", source_path, " to ", destination_path
      copy_file( source_path, destination_path )



proc run_plugins*( state: State ) =
  let
    script_directory = state.config.script_directory
  var
    missing_scripts: seq[ string ] = @[]

  # Loop through all the configured plugins and make sure we can actually find
  # the script file they use as their entrypoint
  for index, plugin in state.config.plugins:
    if file_exists( script_directory / plugin.script ):
      debug "Found in plugin dir ", script_directory / plugin.script
      state.config.plugins[ index ].script = script_directory / plugin.script
    elif file_exists( plugin.script ):
      debug "Found relative to execution dir ", plugin.script
    elif plugin.function != "":
      debug "Found function ", plugin.function
    else:
      missing_scripts.add( plugin.name & " (" & plugin.script & ")" )

  # If we failed to find any script then list the missing files and quit
  if missing_scripts.len > 0:
    error "Can't find the following script(s):\n", missing_scripts.join("\n").indent(4), "\n"
    notice "Build aborted"
    quit(-1)

  # All scripts available, loop through the plugins and run them
  #echo ""
  let start_time = epoch_time()
  for plugin in state.config.plugins:
    # with_debug( plugin.name ):
    #   state.current_plugin = plugin
    #   plugin.run()
    state.current_plugin = plugin
    state.render_state = calculate_render_state( state.config, state.context )
    copy_files( state )
    plugin.run()
    
  #echo "------------------------------------------------------------------"
  echo ""
  notice "Build finished in ", format_float( epoch_time() - start_time, format = ffDecimal, precision = 2), " seconds."
