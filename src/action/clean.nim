import os
import tables

import global_state
import logger

proc clean*( global_state: State ) =
  let destination_directory = state.config.map["destination_directory"]
  let workspace_directory = state.config.map["workspace_directory"]
  let keep_artifacts = state.config.map["keep_artifacts"] == "true"

  workspace_directory.removeDir
  
  if not keep_artifacts:
    destination_directory.removeDir
