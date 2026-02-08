import std/[os]
import types/plugin
import glob
import strutils
import tables

import global_state
import types/config/path_helpers
import action/internal_functions/utils



proc glob(plugin: Plugin): Glob =
  result = glob("*.mustache")
  if plugin.config.has_key("glob"):
    result = glob(plugin.config["glob"])

proc run*(plugin: Plugin) =
  let
    glob = plugin.glob()
    source_directory = state.config.source_directory
    destination_directory = state.config.destination_directory

  for absolute_path in walk_dir_rec( source_directory ):
    let
        relative_path = absolute_path.relative_path( source_directory )
        destination_path = destination_directory / relative_path

    if relative_path.matches(glob):
      if not destination_path.parent_dir.dir_exists():
        destination_path.parent_dir.create_dir()

      copy_file(absolute_path, destination_path)
