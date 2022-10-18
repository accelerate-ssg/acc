import std / os
import tables
import re
import strutils

import logger
import types/config
import types/plugin
import types/config/[file, cli]

proc init_config*(): Config =
  result = Config()
  result.map = initTable[string, string]()
  result.map["global_config_path"] = get_home_dir() / ".acc/config.yaml"
  result.map["current_directory_path"] = get_current_dir()
  result.map["source_directory"] = ""
  result.map["destination_directory"] = ""
  result.map["workspace_directory"] = ""
  result.map["local_config_path"] = ""
  result.map["content_root"] = "content"
  result.map["keep_artifacts"] = "false"
  result.action = ActionNone
  result.log_level = lvlInfo
  result.dns_name = ""

  add_cli_options_to_config( result )

  case result.action:
  of ActionBuild, ActionTest:
    add_yaml_to_config( result )
    result.dns_name = result.name.toLowerAscii.multiReplace([
      (re"[^\w ]+", ""),    # Remove any non-word caharacters, like #€% etc
      (re"[^a-z0-9]+", "-") # Replace any non- letter or number sequence with -
    ])
    result.files = @[]
  else:
    discard

  debug $result, "config/load"
