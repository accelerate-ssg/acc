import os

import global_state
import logger

proc clean*( state: State ) =
  let work_dir = state.config.directories.work
  let build_dir = state.config.directories.build
  let dest_dir = state.config.directories.destination

  if work_dir != "":
    work_dir.removeDir
    notice "Removed work directory: ", work_dir

  if build_dir != "":
    build_dir.removeDir
    notice "Removed build directory: ", build_dir

  if dest_dir != "":
    dest_dir.removeDir
    notice "Removed destination directory: ", dest_dir
