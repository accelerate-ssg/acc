import system
from os import getAppDir, fileExists, dirExists, expandFilename, absolutePath, normalizedPath, `/`
import strformat
import strutils
import docopt

import logger
from types/plugin/utils import get_script_name
import types/plugin
import types/config
from version import application_version

const
  replacements = [
    "default_config", DEFAULT_CONFIG_PATH,
    "default_source_directory", DEFAULT_SOURCE_DIRECTORY,
    "default_destination_directory", DEFAULT_DESTINATION_DIRECTORY,
    "default_content_directory", DEFAULT_CONTENT_DIRECTORY,
    "default_workspace_directory", DEFAULT_WORKSPACE_DIRECTORY,
    "default_script_directory", DEFAULT_SCRIPT_DIRECTORY,
    "default_build_directory", DEFAULT_BUILD_DIRECTORY
  ]
  help = staticRead("help_message.txt") % replacements


proc set_key( config: var Config, key: string, path: string ) =
  try:
    if path != "":
      config.map[ key ] = absolutePath( normalizedPath( path ))
  except CatchableError:
    let
      e = getCurrentException()
      msg = getCurrentExceptionMsg()
    echo "Got exception ", repr(e), " with message ", msg


proc set_key_if_exists( config: var Config, key: string, value: Value|string ) =
  let path = $value
  if fileExists( path ) or dirExists( path ):
    set_key( config, key, path )


proc add_cli_options_to_config*( config: var Config ) =
  let
    version_string = "Accelerate " & application_version & ", built at " & CompileDate & " " & CompileTime & " using Nim " & NimVersion
    args: Table[string, Value] = docopt(help, version = version_string )
    root_dir = $args["ROOT_DIR"]

  debug $args, "cli_options"

  if args["init"]:
    config.action = ActionInit
    
    config.set_key_if_exists( "root_directory", root_dir )

    config.set_key( "source_directory", root_dir / DEFAULT_SOURCE_DIRECTORY )
    config.set_key( "destination_directory", root_dir / DEFAULT_DESTINATION_DIRECTORY )
    config.set_key( "content_directory", root_dir / DEFAULT_CONTENT_DIRECTORY )
    config.set_key( "workspace_directory", root_dir / DEFAULT_WORKSPACE_DIRECTORY )
    config.set_key( "local_config_path", root_dir / DEFAULT_CONFIG_PATH )
    config.set_key( "script_directory", root_dir / DEFAULT_SCRIPT_DIRECTORY )
    config.set_key( "build_directory", root_dir / DEFAULT_BUILD_DIRECTORY )

  if args["build"] or args["dev"]:
    if args["--test"]:
      config.action = ActionTest
    else:
      config.action = if args["build"]: ActionBuild else: ActionDev

    config.set_key_if_exists( "blacklist", args["--exclude"] )
    config.set_key_if_exists( "root_directory", root_dir )

    const config_mapping = [
      ("--src", "source_directory", DEFAULT_SOURCE_DIRECTORY),
      ("--destination", "destination_directory", DEFAULT_DESTINATION_DIRECTORY),
      ("--content", "content_directory", DEFAULT_CONTENT_DIRECTORY),
      ("--work", "workspace_directory", DEFAULT_WORKSPACE_DIRECTORY),
      ("--config", "local_config_path", DEFAULT_CONFIG_PATH),
      ("--script", "script_directory", DEFAULT_SCRIPT_DIRECTORY),
      ("--build", "build_directory", DEFAULT_BUILD_DIRECTORY)
    ]

    for (flag, key, default) in config_mapping:
      if ($args[flag]).starts_with("ROOT_DIR"):
        config.map[key] = absolute_path( root_dir / default )
      else:
        config.map[key] = absolute_path( root_dir / $args[flag] )

  if args["clean"]:
    config.action = ActionClean
    if args["keep"]: config.map["keep_artifacts"] = "true"

  if args["run"]:
    config.action = ActionRun
    for index, path in args["SCRIPT"]:
      var plugin = init_plugin()
      plugin.name = get_script_name( path, "Plugin" & $(index+1) )
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
