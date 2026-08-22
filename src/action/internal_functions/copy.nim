import std/[os, times]
import glob

import global_state
import config
import action/internal_functions/step_helpers

proc run*(step: Step) =
  let
    glob = step.glob()
    source_directory = state.config.directories.src
    destination_directory = state.config.directories.destination

  for absolute_path in walk_dir_rec( source_directory ):
    let
        relative_path = absolute_path.relative_path( source_directory )
        destination_path = destination_directory / relative_path

    if relative_path.matches(glob):
      # Skip files already copied and unchanged since: same size and the
      # copy is at least as new as the source. On an asset-heavy site
      # this turns a rebuild's copy step from megabytes into nothing.
      if destination_path.file_exists and
         get_file_size(destination_path) == get_file_size(absolute_path) and
         destination_path.get_last_modification_time >= absolute_path.get_last_modification_time:
        continue

      if not destination_path.parent_dir.dir_exists():
        destination_path.parent_dir.create_dir()

      copy_file(absolute_path, destination_path)
