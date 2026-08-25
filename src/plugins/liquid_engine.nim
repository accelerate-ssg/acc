import std/[os, json, strutils, tables]
import glob

import global_state
import config
import state as state_module
import logger
import plugins/shared_types
import action/internal_functions/step_helpers
import render_filter
import arena_context_store
import liquid_lib

proc load_partials(step: Step, config: Config): Table[string, string] =
  ## Load partial template files from the source directory and any
  ## additional configured partial_directories.
  result = initTable[string, string]()

  var dirs: seq[string] = @[]

  # Always include the source directory
  dirs.add(config.directories.src)

  # Add any explicitly configured partial directories
  if not step.extraConfig.isNil and step.extraConfig.hasKey("partial_directories"):
    for dir_node in step.extraConfig["partial_directories"]:
      dirs.add(config.directories.root / dir_node.getStr)

  for dir in dirs:
    if dir.dirExists:
      for path in walkDirRec(dir):
        if path.endsWith(".html") or path.endsWith(".liquid"):
          let name = path.relativePath(dir)
          result[name] = readFile(path)

proc overlay_for(arena: Arena, nodes: seq[NodeId]): VMValue =
  ## The routing convention: no nodes renders as null, one node is the
  ## value itself, several are a merged group.
  case nodes.len
  of 0:
    VMValue(kind: vmNull)
  of 1:
    wrap_arena_node(arena, nodes[0])
  else:
    var group = VMValue(kind: vmArray)
    for node in nodes:
      group.arrayVal.add(wrap_arena_node(arena, node))
    group

proc run(step: Step, state: State) =
  let
    stepGlob = step.glob("*.liquid")
    src_dir = state.config.directories.src
    partials = load_partials(step, state.config)

  # Compile each template once, however many pages it expands to.
  var compiled = initTable[string, CompiledTemplate]()

  # A page that fails to render is logged and skipped so the rest of the
  # site still builds; the failures surface as one error at the end of
  # the step, so a build still fails overall.
  var failed: seq[string] = @[]

  state.ensure_render_filter(step)

  for render_item in state.render_state:
    if render_item.source_path.matches(stepGlob) and
       state.should_render(render_item, step.module):
      let destination_path = state.config.directories.destination / render_item.output_path

      if not destination_path.parentDir.dirExists:
        destination_path.parentDir.createDir

      # One consumer per page: the template reads the context lazily
      # through the arena, so this page's recorded reads are exactly the
      # data it depends on.
      discard state.context.track("@page " & render_item.output_path)
      try:
        if render_item.source_path notin compiled:
          let absolute_path = src_dir / render_item.source_path
          compiled[render_item.source_path] = compile_template(readFile(absolute_path))

        var overlays = initTable[string, VMValue]()
        overlays["item"] = overlay_for(state.context.arena, render_item.item_nodes)
        var items = VMValue(kind: vmArray)
        for node in render_item.items_nodes:
          items.arrayVal.add(wrap_arena_node(state.context.arena, node))
        overlays["items"] = items

        let output = compiled[render_item.source_path].render(
          state.context.arena, state.context.root, overlays, partials)
        writeFile(destination_path, output)
        state.rendered_outputs.add(render_item.output_path)
      except CatchableError as e:
        error "Failed rendering ", render_item.source_path, " -> ",
          render_item.output_path, ": ", e.msg
        failed.add(render_item.output_path)
      finally:
        state.context.untrack()

  if failed.len > 0:
    raise newException(ValueError, $failed.len & " page(s) failed to render: " &
      failed.join(", "))

let plugin* = TemplateEnginePlugin(
  name: "liquid",
  extensions: @[".liquid"],
  run: run
)
