import tables
import strutils
import strformat
import json
import terminal
import colors
import sets

import plugin
import config
import types/state

proc pretty*( plugin: Plugin, spaces: int = 0 ): string =
  var config_strings: seq[string] = @[]
  for key, value in plugin.config.pairs:
    config_strings.add( &"{key}: {value}" )

  result = &"""{{
  name: { plugin.name }
  script: { plugin.script }
  function: { plugin.function }
  after: [{ plugin.after.join( ", " ) }]
  before: [{ plugin.before.join( ", " ) }]
  config: {{
    { config_strings.join( ",\n    " ) }
  }}
}}"""
  var lines = result.splitLines()

  for index in 1 ..< lines.len:
    lines[index] = repeat(' ', spaces) & lines[index]

  result = lines.join("\n")



proc pretty*(config: Config, spaces: int = 0 ): string =
  var map_strings: seq[string] = @[]
  for key, value in config.map.pairs:
    map_strings.add( &"{key}: {value}" )

  var script_strings: seq[string] = @[]
  for plugin in config.plugins:
    script_strings.add( plugin.pretty(spaces + 2) )

  var file_strings: seq[string] = @[]
  for file in config.files:
    file_strings.add( file )

  result= &"""{{
  name: {config.name}
  dns_name: {config.dns_name}
  domains: {config.domains}
  action: {config.action}
  log_level: {config.log_level}
  {map_strings.join( "\n  " )}
  plugins: [
    {script_strings.join( ",\n  " )}
  ]
  files: [
    {file_strings.join( ",\n    " )}
  ]
}}"""

  var lines = result.splitLines()

  for index in 1 ..< lines.len:
    lines[index] = repeat(' ', spaces) & lines[index]

  result = lines.join("\n")



proc pretty*(state: State): string =
  &"""
{{
  config: {state.config.pretty(2)}
  context: {state.context.pretty()}
}}
  """

  #registry: {$state.registry}
  #current_plugin: {$state.current_plugin}

template pretty_print*( state: State ) =
  if get_log_level() <= lvlDebug:
    stdout.set_background_color( Color(0x000000) )
    stdout.set_foreground_color( Color(0xff00ff) )
    stdout.write "\n=={ global state }============================================\n\n"
    stdout.set_foreground_color( Color(0xeeeeee) )
    stdout.write state.pretty()
    stdout.set_foreground_color( Color(0xff00ff) )
    stdout.write "\n==============================================================\n"
