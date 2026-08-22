import std/[os, times]
import glob

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

  for absolute_path in walk_dir_rec( source_directory ):
    let
        relative_path = absolute_path.relative_path( source_directory )
        destination_path = destination_directory / relative_path

    if relative_path.matches(glob):
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
