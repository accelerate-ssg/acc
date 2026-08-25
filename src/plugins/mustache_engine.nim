import std/[os, json, strutils, tables]
import glob
import mustache_lib

import global_state
import config
import state as state_module
import logger
import plugins/shared_types
import action/internal_functions/step_helpers
import render_filter

proc load_partials(step: Step, config: Config): Table[string, string] =
  ## Load the partials a template can reference, keyed the way it
  ## references them. Templates name partials relative to a search
  ## directory and without the extension — `{{> partials/head}}` from
  ## the source root, or `{{> head}}` from the partials directory
  ## itself — so every search directory contributes its own key for the
  ## same file. The first directory listed wins a collision, matching
  ## the search order it describes.
  result = initTable[string, string]()

  var dirs = @[config.directories.src]
  for dir in step.search_dirs():
    dirs.add(if dir.isAbsolute: dir else: config.directories.root / dir)
  if not step.extraConfig.isNil and step.extraConfig.hasKey("partial_directories"):
    for dir_node in step.extraConfig["partial_directories"]:
      dirs.add(config.directories.root / dir_node.getStr)

  for dir in dirs:
    if dir.dirExists:
      for path in walkDirRec(dir):
        if path.endsWith(".mustache"):
          let name = path.relativePath(dir).changeFileExt("")
          if name notin result:
            result[name] = readFile(path)

proc run(step: Step, state: State) =
  let
    stepGlob = step.glob("*.mustache")
    src_dir = state.config.directories.src
    partials = load_partials(step, state.config)

  # Materialize the context once for the whole step; item and items are
  # the only per-page keys, and rebinding them on the same tree is cheap.
  var context = state.context.toJson

  var failed: seq[string] = @[]

  # Compile each template once, however many pages it expands to.
  var compiled = initTable[string, CompiledTemplate]()

  state.ensure_render_filter(step)

  for render_item in state.render_state:
    let absolute_path = src_dir / render_item.source_path

    if render_item.source_path.matches(stepGlob) and
       state.should_render(render_item, step.module):
      let destination_path = state.config.directories.destination / render_item.output_path

      if not destination_path.parentDir.dirExists():
        destination_path.parentDir.createDir()

      context["item"] = render_item.item
      context["items"] = render_item.items

      # A page that fails to render is logged and skipped so the rest of
      # the site still builds; the failures surface as one error at the
      # end of the step, so a build still fails overall.
      try:
        if render_item.source_path notin compiled:
          compiled[render_item.source_path] = compile_template(readFile(absolute_path))
        write_file(destination_path,
                   compiled[render_item.source_path].render(context, partials))
        state.rendered_outputs.add(render_item.output_path)
      except CatchableError as e:
        error "Failed rendering ", render_item.source_path, " -> ",
          render_item.output_path, ": ", e.msg
        failed.add(render_item.output_path)

  if failed.len > 0:
    raise newException(ValueError, $failed.len & " page(s) failed to render: " &
      failed.join(", "))

let plugin* = TemplateEnginePlugin(
  name: "mustache",
  extensions: @[".mustache"],
  run: run
)
