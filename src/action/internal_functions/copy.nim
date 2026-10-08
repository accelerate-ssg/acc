import std/[os, times, sets]
import glob

import logger

import global_state
import config
import action/internal_functions/step_helpers

when defined(macosx):
  proc clonefile(src, dst: cstring, flags: uint32): cint
    {.importc, header: "<sys/clonefile.h>".}

proc copy_asset(source, destination: string) =
  ## Copy one asset. On APFS this is a copy-on-write clone: a metadata
  ## operation that moves no data, so even a from-scratch copy of a
  ## large asset tree costs almost nothing. Falls back to a regular copy
  ## when cloning is unsupported (other filesystems, other platforms).
  when defined(macosx):
    if destination.file_exists:
      remove_file(destination)  # clonefile refuses to overwrite
    if clonefile(source.cstring, destination.cstring, 0) == 0:
      return
  copy_file(source, destination)

proc run*(step: Step) =
  let
    glob = step.glob()
    source_directory = state.config.directories.src
    destination_directory = state.config.directories.destination

  # The assets that should exist after this step, whether or not it had to
  # write them. This is the route set the next build diffs against, which is
  # a different question from rendered_outputs below: that is what this build
  # actually transferred.
  var present: HashSet[string]

  for absolute_path in walk_dir_rec( source_directory ):
    let
        relative_path = absolute_path.relative_path( source_directory )
        destination_path = destination_directory / relative_path

    if relative_path.matches(glob):
      present.incl(relative_path)
      state.routed_outputs.add((relative_path, relative_path))
      # Skip files already copied and unchanged since: same size and the
      # copy is at least as new as the source. On an asset-heavy site
      # this turns a rebuild's copy step from megabytes into nothing.
      if destination_path.file_exists and
         get_file_size(destination_path) == get_file_size(absolute_path) and
         destination_path.get_last_modification_time >= absolute_path.get_last_modification_time:
        continue

      if not destination_path.parent_dir.dir_exists():
        destination_path.parent_dir.create_dir()

      copy_asset(absolute_path, destination_path)
      # A copied asset is an output like a rendered page, so it belongs in
      # the build manifest. Recorded after the skip above, which means the
      # manifest stays a delta: an asset that did not need copying is not
      # one a deploy needs to transfer.
      state.rendered_outputs.add(relative_path)

  # The same route-set diff render_filter does for pages, which copied assets
  # never got: this loop only ever visits files that still exist, and a build
  # does not clean the destination first, so a deleted asset stayed on disk
  # and stayed deployed — the serving image is built from the whole
  # directory — while being absent from removed_outputs.
  for (source, output) in state.context.previous_outputs:
    # source == output identifies a pair this step recorded. The others have
    # to be skipped: routed_outputs is filled from the whole workflow's
    # render_state (run_workflow.nim:195), and for a copy-only workflow the
    # router still maps every asset to a phantom `.html` name it will never
    # write — matching those on source alone reported 27 non-existent
    # removals on a site with 27 assets.
    if source != output or not source.matches(glob) or output in present:
      continue
    let stale = destination_directory / output
    if stale.fileExists:
      removeFile(stale)
      notice "Removed asset: ", output
    state.removed_outputs.add(output)
