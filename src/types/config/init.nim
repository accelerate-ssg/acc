import std / os
import tables

import logger
import types/config
import types/plugin
import types/config/[file, cli]

proc init_config*(): Config =
  result = Config()
  result.global_config_path = get_home_dir() / ".acc/config.yaml"
  result.current_directory_path = get_current_dir()
  result.source_directory = result.current_directory_path
  result.destination_directory = result.source_directory / "build"
  result.local_config_path = result.source_directory / "config.yaml"
  result.action = ActionNone
  result.log_level = lvlInfo

  add_cli_options_to_config( result )

  case result.action:
  of ActionBuild, ActionTest:
    add_yaml_to_config( result )
  else:
    discard

  debug $result, "config/load"
