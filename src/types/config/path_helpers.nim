import os
import tables

import types/config

proc current_directory*( config: Config ):string =
  config.map["current_directory_path"]

proc root_directory*( config: Config ):string =
  config.map["root_directory"]

proc source_directory*( config: Config ):string =
  config.map["source_directory"]

proc destination_directory*( config: Config ):string =
  config.map["destination_directory"]

proc workspace_directory*( config: Config ):string =
  config.map["workspace_directory"]

proc build_directory*( config: Config ):string =
  config.map["build_directory"]

proc script_directory*( config: Config ):string =
  config.map["script_directory"]

proc content_directory*( config: Config ):string =
  config.map["content_directory"]
  
proc global_config_path*( config: Config ):string =
  return config.map["global_config_path"]

proc local_config_path*( config: Config ):string =
  if config.map["local_config_path"] != "":
    return config.map["local_config_path"]
  else:
    return config.source_directory() / DEFAULT_CONFIG_PATH
