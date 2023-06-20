import std/[os]
import global_state
import types/plugin
import logger
import glob
import mustache
import tables
import strutils
import sets

import types/config/path_helpers
import action/internal_functions/utils

proc search_dirs(plugin: Plugin): seq[string] =
  result = @["./"]
  if plugin.config.has_key("search_dirs"):
    for path in plugin.config["search_dirs"].split(','):
      result.add(path.strip)

proc glob(plugin: Plugin): Glob =
  result = glob("*.mustache")
  if plugin.config.has_key("glob"):
    result = glob(plugin.config["glob"])

proc render(context: Context, path: string): string =
  let
    template_file = readFile(path)

  result = template_file.render(context)

proc run*(plugin: Plugin) =
  var context = new_context(
    searchDirs = plugin.search_dirs(),
    values = state.context.toValues()
  )

  let glob = plugin.glob()

  for absolute_path in state.config.files:
    let
      relative_path = absolute_path.relative_path(state.config.workspace_directory)

    if relative_path.matches(glob):
      let
        relative = relative_path.split_file()
        file_name = relative.name.add_file_ext("html")
        destination_path = state.config.destination_directory / relative.dir / file_name
            
      notice "Rendering: ", absolute_path, " as ", destination_path
      write_file(destination_path, context.render(absolute_path))
