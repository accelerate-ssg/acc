import os
import tables

import types/config

proc source_directory*( config: Config ):string =
  if config.map["source_directory"] != "":
    return config.map["source_directory"]
  else:
    return config.map["current_directory_path"]

proc destination_directory*( config: Config ):string =
  if config.map["destination_directory"] != "":
    return config.map["destination_directory"]
  else:
    return config.source_directory() / DEFAULT_BUILD_DIRECTORY

proc workspace_directory*( config: Config ):string =
  if config.map["workspace_directory"] != "":
    return config.map["workspace_directory"]
  else:
    return config.destination_directory() / DEFAULT_WORKSPACE_DIRECTORY

proc global_config_path*( config: Config ):string =
  return config.map["global_config_path"]

proc local_config_path*( config: Config ):string =
  if config.map["local_config_path"] != "":
    return config.map["local_config_path"]
  else:
    return config.source_directory() / DEFAULT_CONFIG_PATH
