import std/[os]
import global_state
import types/plugin
import logger
import glob
import mustache
import tables
import strutils
import json

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

# proc add( context: var Value, path: string, value: string ) =
#   var current = context
#   for part in path.split('.'):
#     let
#       last = path.ends_with( part )
#
#     if current.has_key( part ):
#       current = current[ part ]
#     elif last:
#       current[ part ] = Value(kind: vkString, vString: value )
#     else:
#       current[ part ] = Value(kind: vkTable, vTable: @[] )
#       current = current[ part ]

#proc load( context: var Context, global_context: Table[string, string] ) =
#  context.values = global_context

proc convert(node: JsonNode): Table[string, Value] =
  result = initTable[string, Value]()
  for key, val in node.pairs:
    result[key] = val.castValue
  #result = Value(kind: vkTable, vTable: vTable)

proc run*(plugin: Plugin) =
  var context = new_context(
    searchDirs = plugin.search_dirs(),
    values = state.context.toValues()
  )

  let glob = plugin.glob()

  #context.load( state.context )

  for (absolute, relative) in state.config.files.each:
    if relative.matches(glob):
      let
        original = split_file(relative)
        new_name = state.config.map["destination_directory"] / original.dir /
            add_file_ext(original.name, "html")
      notice "Rendering: ", absolute, " as ", new_name
      write_file(new_name, context.render(absolute))
