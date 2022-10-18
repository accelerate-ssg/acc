import os
import strutils
import times
import tables
import json

import logger
import global_state
import script/run

proc run_plugins*( state: State ) =
  var missing_scripts: seq[ string ] = @[]

  # Loop through all the configured plugins and make sure we can actually find
  # the script file tkey use as their entrypoint
  echo ""
  for index, plugin in state.config.plugins:
    if file_exists( state.config.map["source_directory"] / plugin.script ):
      debug "Found source dir relative ", state.config.map["source_directory"] / plugin.script
      state.config.plugins[ index ].script = state.config.map["source_directory"] / plugin.script
    elif file_exists( plugin.script ):
      debug "Found exec relative ", plugin.script
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
  echo ""
  let start_time = epoch_time()
  for plugin in state.config.plugins:
    state.current_plugin = plugin
    info "Running ", plugin.name
    let plugin_start_time = epoch_time()
    plugin.run()
    info plugin.name, " finished in ", format_float( epoch_time() - plugin_start_time, format = ffDecimal, precision = 2), " seconds."
    echo ""
    fatal $state.context
  echo ""
  notice "Build finished in ", format_float( epoch_time() - start_time, format = ffDecimal, precision = 2), " seconds."
