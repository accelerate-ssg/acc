import std/[json, os, strutils]
import yaml/[tojson, native, parser]
import logger
import glob

import global_state
import config
import arena_context_store
import action/internal_functions/[step_helpers, key_stack]
import page_context

proc yamlToJson*(data: string): JsonNode =
  ## Parse YAML content. NimYAML parses a superset of JSON, so this also
  ## serves .json files matched by @yaml step globs, exactly as the
  ## pre-arena loader did. Multi-document files parse as an array.
  let json_nodes_seq = loadToJson(data)
  if json_nodes_seq.len == 1:
    json_nodes_seq[0]
  else:
    var docs = newJArray()
    for json_node in json_nodes_seq:
      docs.add(json_node)
    docs

proc jsonToJson*(data: string): JsonNode =
  ## Parse JSON content with std/json, which is about twice as fast as
  ## routing it through NimYAML. JSON is a YAML subset, so the trees agree:
  ## verified over every .json file in the hosted sites (519 files, 5.6 MB)
  ## with no difference, and over the edge cases the two parsers could
  ## disagree on — duplicate keys, int/float typing, exponents, unicode
  ## escapes, BOM, top-level scalars and arrays.
  ##
  ## Two cases do differ, and only one needs handling. An empty or
  ## whitespace-only file is an empty YAML stream, which yamlToJson renders
  ## as an empty array, while std/json raises; that is preserved below so a
  ## content file that loads today keeps loading. (The other: an integer too
  ## large for int64 raises in NimYAML and parses in std/json, which is the
  ## permissive direction and needs no special case.)
  if data.strip.len == 0:
    return newJArray()
  parseJson(data)

proc contentToJson*(path, data: string): JsonNode =
  ## Route by extension: .json takes the fast path, everything else is YAML.
  if path.toLowerAscii.endsWith(".json"): jsonToJson(data) else: yamlToJson(data)

proc yamlLoad*(arena: var Arena, data: string, path: string): NodeId =
  ## Arena LoadProc for YAML content: a fresh subtree, every created node
  ## tagged with the file's origin.
  let oid = arena.registerOrigin(sfYaml, path)
  arena.pushOrigin(oid)
  try:
    result = arena.fromJson(contentToJson(path, data))
  finally:
    arena.popOrigin()

proc registerContentLoaders*() =
  ## Register the content loaders on the context's arena, so changed
  ## files can later be reloaded by extension without going through a
  ## step. One registration covers all three extensions; yamlLoad routes
  ## .json to std/json internally via contentToJson.
  state.context.arena.registerLoader("yaml", @[".yml", ".yaml", ".json"], yamlLoad)

proc parse(stack: var KeyStack, absolute_path: string, relative_path: string) =
  stack.mark()
  stack.add_file_path(relative_path)
  # The render pass binds these keys per page, so a file loaded at one of
  # them is shadowed in every template. Loading it anyway keeps the build
  # working for anything reading it by a longer path, but the file is not
  # reachable under its own name.
  if stack.atoms.len == 1 and stack.atoms[0] in RESERVED_CONTEXT_KEYS:
    warn "Content file ", relative_path, " binds the reserved context key '",
      stack.atoms[0], "'; templates will see the value the render pass ",
      "sets there instead. Rename the file or nest it under a directory."
  # One consumer per file: its write set is what a change to this file
  # invalidates. Loading merges into any subtree already bound at the
  # path, so on a reload only the nodes that actually changed in the
  # file register as written — one edited post implicates one post's
  # readers, not the whole file's.
  discard state.context.track("@load " & absolute_path)
  let origin = state.context.arena.registerOrigin(sfYaml, absolute_path)
  state.context.arena.pushOrigin(origin)
  try:
    let content = readFile(absolute_path)
    state.context.mergePath(stack.atoms, contentToJson(absolute_path, content))
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
    state.context.arena.popOrigin()
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

proc unload*(absolute_path: string) =
  ## A content file was removed: bind null where it was loaded, under its
  ## own loader consumer, so everything that read it invalidates exactly
  ## like a change would. The path is resolved the way run() would have
  ## loaded it, including any configured context_path_prefix.
  let content_dir = state.config.directories.content
  if content_dir == "" or not absolute_path.isRelativeTo(content_dir):
    return
  let relative_path = absolute_path.relativePath(content_dir)

  var prefix = ""
  for workflow in state.config.workflows:
    for step in workflow.steps:
      if step.module in ["@yaml", "yaml"]:
        prefix = step.context_path_prefix("")

  var stack = newKeyStack()
  stack.add_dotted_path(prefix)
  stack.add_file_path(relative_path)

  if state.context.lookupPath(stack.atoms) == InvalidNodeId:
    return

  notice "Unloading removed content: ", relative_path
  discard state.context.track("@load " & absolute_path)
  try:
    state.context.bindPath(stack.atoms, state.context.arena.newNull())
  finally:
    state.context.untrack()
