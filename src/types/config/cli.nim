import system
from os import getAppDir, fileExists, dirExists, expandFilename, absolutePath, normalizedPath, `/`
import strutils
import docopt

import logger
from types/plugin/utils import get_plugin_name
import types/plugin
import types/config
from version import application_version

const
  help* = staticRead "help_message.txt"

proc set_key_if_exists( config: var Config, key: string, value: Value ) =
  let path = $value
  try:
    if path != "" and (fileExists( path ) or dirExists( path )):
      config.map[ key ] = absolutePath( normalizedPath( path )).expandFilename()
  except CatchableError:
    let
      e = getCurrentException()
      msg = getCurrentExceptionMsg()
    echo "Got exception ", repr(e), " with message ", msg

proc add_cli_options_to_config*( config: var Config ) =
  let version_string = "Accelerate " & application_version & ", built at " & CompileDate & " " & CompileTime & " using Nim " & NimVersion
  var args: Table[string, Value]
  args = docopt(help, version = version_string )

  debug $args, "cli_options"

  if args["build"] or args["dev"]:
    if args["--test"]:
      config.action = ActionTest
    else:
      config.action = if args["build"]: ActionBuild else: ActionDev

    config.set_key_if_exists( "blacklist", args["--exclude"] )
    config.set_key_if_exists( "local_config_path", args["--config"] )
    config.set_key_if_exists( "source_directory", args["SOURCE_DIR"] )

    if $args["--output"] == "SOURCE_DIR/build":
      config.map["destination_directory"] = config.map["source_directory"] / DEFAULT_BUILD_DIRECTORY
    else:
      config.map["destination_directory"] = $args["--output"]

    config.map["workspace_directory"] = config.map["destination_directory"] / DEFAULT_WORKSPACE_DIRECTORY

  if args["clean"]:
    config.action = ActionClean
    if args["keep"]: config.map["keep_artifacts"] = "true"

  if args["run"]:
    config.action = ActionRun
    for index, path in args["SCRIPT"]:
      var plugin = init_plugin()
      plugin.name = get_plugin_name( path, "Plugin" & $(index+1) )
      error plugin.name
      if plugin.name.starts_with('@'):
        plugin.function = plugin.name[1..^1]
      else:
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
