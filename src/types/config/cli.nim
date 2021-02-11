from os import fileExists, dirExists, absolutePath, normalizedPath, `/`
import strutils
import docopt

import logger
from types/plugin/utils import get_plugin_name
import types/plugin
import types/config

const
  help* = staticRead "help_message.txt"

proc set_path_if_exists( property: var string, value: Value ) =
  let path = $value
  try:
    if path != "" and (fileExists( path ) or dirExists( path )):
      property = absolutePath( normalizedPath( path ))
  except:
    let
      e = getCurrentException()
      msg = getCurrentExceptionMsg()
    echo "Got exception ", repr(e), " with message ", msg

proc add_cli_options_to_config*( config: var Config ) =
  let version = "Accelerate 0.1.0, built at " & CompileDate & " " & CompileTime & " using Nim " & NimVersion
  let args = docopt(help, version = version)

  if args["build"] or args["test"]:
    config.action = ActionBuild

    set_path_if_exists( config.blacklist, args["--exclude"] )
    set_path_if_exists( config.whitelist, args["--include"] )
    set_path_if_exists( config.local_config_path, args["--config"] )
    set_path_if_exists( config.source_directory, args["SOURCE_DIR"] )
    if $args["--output"] == "SOURCE_DIR/build":
      config.destination_directory = config.source_directory / "build"
    else:
      config.destination_directory = $args["--output"]

  if args["test"]:
    config.action = ActionTest

  if args["clean"]:
    config.action = ActionClean
    if args["keep"]: config.keep = true

  if args["run"]:
    config.action = ActionRun
    for index, path in args["SCRIPT"]:
      var plugin = init_plugin()
      plugin.name = get_plugin_name( path, "Plugin" & $(index+1) )
      plugin.script = path
      config.plugins.add( plugin )
    set_path_if_exists( config.source_directory, args["--directory"] )

  case toLowerAscii( $args["--log"] ):
    of "all":
      config.log_level = lvlAll
    of "debug":
      config.log_level = lvlDebug
    of "info":
      config.log_level = lvlInfo
    of "warning":
      config.log_level = lvlWarn
    of "error":
      config.log_level = lvlError
    of "fatal":
      config.log_level = lvlFatal
    of "silent":
      config.log_level = lvlNone

  when defined(release):
    set_log_level( config.log_level )

  debug $args, "cli_options"
