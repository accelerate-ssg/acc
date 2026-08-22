import std/[os, json, strutils, tables]
import global_state
import config
import logger
import glob
import mustache

import action/internal_functions/step_helpers

proc render(context: Context, path: string): string =
  let
    template_file = readFile(path)
  result = template_file.render(context)

proc run*(step: Step) =
  var context = new_context(
    searchDirs = step.search_dirs(),
    values = state.context.toJson.toValues()
  )

  let
    glob = step.glob("*.mustache")
    build_dir = state.config.directories.build

  for render_item in state.render_state:
    let
      absolute_path = build_dir / render_item.source_path

    if render_item.source_path.matches(glob):
      let
        destination_path = state.config.directories.destination / render_item.output_path

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
