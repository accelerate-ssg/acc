import std / os
import tables
import re
import strutils

import logger
import types/config
import types/config/[file, cli]

proc init_config*(): Config =
  result = Config()
  result.map = initTable[string, string]()
  result.map["global_config_path"] = get_home_dir() / DEFAULT_CONFIG_PATH
  result.map["current_directory_path"] = get_current_dir()
  result.map["root_directory"] = ""
  result.map["source_directory"] = ""
  result.map["destination_directory"] = ""
  result.map["workspace_directory"] = ""
  result.map["local_config_path"] = ""
  result.map["script_directory"] = ""
  result.map["content_directory"] = ""
  result.map["keep_artifacts"] = "false"
  result.action = ActionNone
  result.log_level = lvlInfo
  result.dns_name = ""

  add_cli_options_to_config( result )

  case result.action:
  of ActionBuild, ActionDev, ActionTest:
    add_yaml_to_config( result )
    result.dns_name = result.name.toLowerAscii.multiReplace([
      (re"[^\w ]+", ""),    # Remove any non-word characters, like #€% etc
      (re"[^a-z0-9]+", "-") # Replace any non-letter or number sequence with "-"
    ])
  else:
    discard
