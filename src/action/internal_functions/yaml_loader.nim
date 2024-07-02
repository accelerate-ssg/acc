import std/[json, tables, strutils, sets, os]
import yaml/[tojson, native, parser]
import logger
import glob

import global_state
import types/plugin
import types/config
import types/config/path_helpers
import action/internal_functions/[utils, config, key_stack]

var stack = newKeyStack()

proc parse(absolute_path: string, relative_path: string) =
  stack.mark()
  stack.add_file_path(relative_path)
  try:
    let
      content = readFile(absolute_path)
      json_nodes_seq = loadToJson(content)

    var context_node: JsonNode = json_nodes_seq[0]

    if json_nodes_seq.len > 1:
      context_node = newJArray() # Create a new JSON array node
      for jsonNode in json_nodes_seq: # Add the elements from the sequence to the array
        context_node.add(jsonNode)

    state.context{stack.atoms} = context_node # Store the JsonNode in the state
  except IOError:
    fatal "Error reading file ", absolute_path
    raise
  except OSError:
    fatal "Error opening file ", absolute_path
    raise
  except YamlParserError:
    fatal "Error parsing file ", absolute_path
    raise
  except YamlConstructionError:
    fatal "Error constructing node tree ", absolute_path
    raise
  except CatchableError:
    fatal "Unknown exception!"
    raise
  finally:
    stack.clear()

proc run*(plugin: Plugin) =
  let glob = plugin.glob( DEFAULT_CONTENT_DIRECTORY / "**/*.{yml,yaml}")
  let context_path_prefix = plugin.context_path_prefix("")
  stack.add_dotted_path( context_path_prefix )

  warn "plugin.config: ", plugin.config
  warn "plugin: ", plugin

  for file in walk_dir_rec( state.config.content_directory, relative = true ):
    if file.matches(glob):
      notice "Parsing: ", file
      parse( state.config.content_directory / file, file )
