import std/[json, os]
import yaml/[tojson, native, parser]
import logger
import glob

import global_state
import config
import arena_context_store
import action/internal_functions/[step_helpers, key_stack]

proc yamlLoad*(arena: var Arena, data: string, path: string): NodeId =
  ## Arena LoadProc for YAML content. NimYAML parses a superset of JSON,
  ## so this also serves .json files matched by @yaml step globs, exactly
  ## as the pre-arena loader did. Multi-document files load as an array.
  ## Every created node is tagged with the file's origin.
  let oid = arena.registerOrigin(sfYaml, path)
  arena.pushOrigin(oid)
  try:
    let json_nodes_seq = loadToJson(data)
    if json_nodes_seq.len == 1:
      result = arena.fromJson(json_nodes_seq[0])
    else:
      result = arena.newArr(initialCap = json_nodes_seq.len)
      for json_node in json_nodes_seq:
        arena.arrPush(result, arena.fromJson(json_node))
  finally:
    arena.popOrigin()

proc registerContentLoaders*() =
  ## Register the content loaders on the context's arena, so changed
  ## files can later be reloaded by extension without going through a
  ## step. YAML handles .json too — see yamlLoad.
  state.context.arena.registerLoader("yaml", @[".yml", ".yaml", ".json"], yamlLoad)

proc parse(stack: var KeyStack, absolute_path: string, relative_path: string) =
  stack.mark()
  stack.add_file_path(relative_path)
  # One consumer per file: its write set is what a change to this file
  # invalidates.
  discard state.context.track("@load " & absolute_path)
  try:
    let content = readFile(absolute_path)
    let node = yamlLoad(state.context.arena, content, absolute_path)
    state.context.bindPath(stack.atoms, node)
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
    state.context.untrack()
    stack.clear()

proc run*(step: Step) =
  let
    content_dir = state.config.directories.content
    glob = step.glob(content_dir / "**/*.{yml,yaml}")
    context_path_prefix = step.context_path_prefix("")

  # The stack is local to this run, so a configured prefix lives exactly
  # as long as the run — a second build in the same process (dev server
  # rebuilds) starts from a fresh stack instead of stacking the prefix
  # twice.
  var stack = newKeyStack()
  stack.add_dotted_path(context_path_prefix)

  for file in walk_dir_rec(content_dir, relative = true):
    if file.matches(glob):
      notice "Parsing: ", file
      stack.parse(content_dir / file, file)
