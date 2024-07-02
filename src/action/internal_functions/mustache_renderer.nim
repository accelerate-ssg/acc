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
  result = @["./", state.config.source_directory]
  if plugin.config.has_key("search_dirs"):
    for path in plugin.config["search_dirs"].split(','):
      result.add(path.strip)
  for path in result:
    let
      file_path = path / "partials/main_nav.mustache" 

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

  let
    glob = plugin.glob()
    build_dir = state.config.build_directory

  for render_item in state.render_state:
    let
      absolute_path = build_dir / render_item.source_path

    if render_item.source_path.matches(glob):
      let
        destination_path = state.config.destination_directory / render_item.output_path

      if not destination_path.parentDir.dirExists():
        destination_path.parentDir.createDir()

      context["debug"] = proc (s: string, c: Context): string =
        return $c[ s.strip ]
      context["length"] = proc (s: string, c: Context): string =
        try:
          let
            value = c[ s ]
          case value.kind
          of vkInt,vkFloat32,vkFloat64,vkBool:
            return ""
          of vkString:
            return $value.vString.len
          of vkSeq:
            return $value.vSeq.len
          of vkTable:
            return $value.vTable.len
          else:
            return "0"
        except KeyError:
          return "0"
      context["item"] = render_item.item
      context["items"] = render_item.items


      write_file(destination_path, context.render(absolute_path))
