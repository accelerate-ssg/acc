import std/[json, os]
import yaml/[tojson, native, parser]
import logger
import glob

import global_state
import config
import action/internal_functions/[step_helpers, key_stack]

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
      context_node = newJArray()
      for jsonNode in json_nodes_seq:
        context_node.add(jsonNode)

    state.context{stack.atoms} = context_node
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

proc run*(step: Step) =
  let
    content_dir = state.config.directories.content
    glob = step.glob(content_dir / "**/*.{yml,yaml}")
    context_path_prefix = step.context_path_prefix("")

  stack.add_dotted_path(context_path_prefix)

  for file in walk_dir_rec(content_dir, relative = true):
    if file.matches(glob):
      notice "Parsing: ", file
      parse(content_dir / file, file)
