## Decides which pages an engine renders in a selective build.
##
## Selective builds route everything and render little: the route
## calculation is cheap and is what reveals pages that appeared or
## disappeared, while rendering is what costs. The filter is computed at
## an engine step — after this build's loaders have recorded what the
## changed content files actually rewrote, so the invalidation query
## describes this reload's diff, not the previous one.
##
## Sources of pages to render:
##
##   changed templates      every page they expand to
##   changed content        the consumers invalidated by the files'
##                          loaders: "@page" consumers by output path,
##                          and whole engines whose "@step" consumer is
##                          stale (an engine that still reads the whole
##                          context cannot be narrowed)
##   route-set diff         pages that did not exist in the previous
##                          build; pages that ceased to exist have their
##                          output unlinked
##
## With no previous build to narrow against, everything renders.

import std/[sets, os, strutils, algorithm, sequtils]
import glob

import logger
import config
import state as state_module
import arena_context_store
import action/internal_functions/step_helpers

proc compute_stale(state: State) =
  ## The invalidation half, once per build.
  if state.render_filter_ready:
    return
  state.render_filter_ready = true

  if state.changed_content.len > 0 and not state.has_previous_build:
    notice "No previous build to narrow against; rendering everything."
    state.render_filter.all = true
    return

  var stale = initHashSet[uint32]()
  for path in state.changed_content:
    let label = "@load " & path
    if state.context.known_consumer(label):
      stale.incl(state.context.arena.invalidatedBy(state.context.consumer(label)))

  for id in stale:
    let label = state.context.consumer_label(id)
    if label.startsWith("@page "):
      state.render_filter.pages.incl(label[6 .. ^1])
    elif label.startsWith("@step "):
      state.render_filter.modules_all.incl(label[6 .. ^1])
    # "@router" staleness is covered by the route-set diff; "@load"
    # consumers are writers, not pages.

proc ensure_render_filter*(state: State, step: Step) =
  ## Prepare the filter for an engine step: the build-wide stale set,
  ## this step's pages from changed templates, and the route-set diff
  ## against the previous build restricted to this step's templates.
  state.compute_stale()

  let
    step_glob = step.glob()
    destination = state.config.directories.destination

  # Changed templates render all their pages.
  if state.changed_sources.len > 0:
    for item in state.render_state:
      if item.source_path in state.changed_sources:
        state.render_filter.pages.incl(item.output_path)

  # Route-set diff: compare this step's pages with the previous build's.
  # Runs for full builds too, so a deleted template's pages get unlinked.
  if state.context.previous_outputs.len > 0:
    var now = initHashSet[string]()
    for item in state.render_state:
      if item.source_path.matches(step_glob):
        now.incl(item.output_path)

    var before = initHashSet[string]()
    for (source, output) in state.context.previous_outputs:
      if source.matches(step_glob):
        before.incl(output)

    var added, removed: seq[string]
    for output in now:
      if output notin before:
        added.add(output)
    for output in before:
      if output notin now:
        removed.add(output)
    added.sort()
    removed.sort()

    if added.len > 0:
      notice "New page(s): ", added.join(", ")
      for output in added:
        state.render_filter.pages.incl(output)

    for output in removed:
      let path = destination / output
      if path.fileExists:
        removeFile(path)
        notice "Removed page: ", output
      state.removed_outputs.add(output)

  if not state.render_filter.all and state.changed_content.len > 0:
    var pages = toSeq(state.render_filter.pages)
    pages.sort()
    if step.module in state.render_filter.modules_all:
      notice "Rendering every ", step.module, " page: its step reads the whole context."
    else:
      notice "Rendering ", $pages.len, " page(s) for this change"
      debug "Pages: ", pages.join(", ")
