from os import fileExists, dirExists, absolutePath, normalizedPath, `/`
import strutils
import docopt

import logger
from types/plugin/utils import get_plugin_name
import types/plugin
import types/config

const
  help* = staticRead "help_message.txt"

proc set_key_if_exists( config: var Config, key: string, value: Value ) =
  let path = $value
  try:
    if path != "" and (fileExists( path ) or dirExists( path )):
      config.map[ key ] = absolutePath( normalizedPath( path ))
  except:
    let
      e = getCurrentException()
      msg = getCurrentExceptionMsg()
    echo "Got exception ", repr(e), " with message ", msg

proc add_cli_options_to_config*( config: var Config ) =
  let version = "Accelerate 0.1.0, built at " & CompileDate & " " & CompileTime & " using Nim " & NimVersion
  var args: Table[string, Value]
  args = docopt(help, version = version )

  debug $args, "cli_options"

  if args["build"]:
    if args["--test"]:
      config.action = ActionTest
    else:
      config.action = ActionBuild

    config.set_key_if_exists( "blacklist", args["--exclude"] )
    config.set_key_if_exists( "local_config_path", args["--config"] )
    config.set_key_if_exists( "source_directory", args["SOURCE_DIR"] )

    if $args["--output"] == "SOURCE_DIR/build":
      config.map["destination_directory"] = config.map["source_directory"] / "build"
    else:
      config.map["destination_directory"] = $args["--output"]

    config.map["workspace_directory"] = config.map["destination_directory"] / ".acc"

  if args["clean"]:
    config.action = ActionClean
    if args["keep"]: config.map["keep_artifacts"] = "true"

  if args["run"]:
    config.action = ActionRun
    for index, path in args["SCRIPT"]:
      var plugin = init_plugin()
      plugin.name = get_plugin_name( path, "Plugin" & $(index+1) )
      plugin.script = path
      config.plugins.add( plugin )
    config.set_key_if_exists( "source_directory", args["--directory"] )

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
