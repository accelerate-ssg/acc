import os
import strutils
import times

import logger
import global_state
import script/run

proc run_plugins*( global_state: State ) =
  var missing_scripts: seq[ string ] = @[]

  # Loop through all the configured plugins and make sure we can actually find
  # the script file tkey use as their entrypoint
  echo ""
  for index, plugin in global_state.config.plugins:
    if file_exists( global_state.config.source_directory / plugin.script ):
      debug "Found ", global_state.config.source_directory / plugin.script
      global_state.config.plugins[ index ].script = global_state.config.source_directory / plugin.script
    elif file_exists( plugin.script ):
      debug "Found ", plugin.script
    else:
      missing_scripts.add( plugin.name & " (" & plugin.script & ")" )

  # If we failed to find any script then list the missing files and quit
  if missing_scripts.len > 0:
    error "Can't find the following script(s):\n", missing_scripts.join("\n").indent(4)
    notice "Build aborted"
    quit(-1)

  # All scripts available, loop through the plugins and run them
  echo ""
  let start_time = epoch_time()
  for plugin in global_state.config.plugins:
    info "Running ", plugin.name
    let plugin_start_time = epoch_time()
    plugin.run()
    info plugin.name, " finished in ", format_float( epoch_time() - plugin_start_time, format = ffDecimal, precision = 2), " seconds."
  echo ""
  notice "Build finished in ", format_float( epoch_time() - start_time, format = ffDecimal, precision = 2), " seconds."
