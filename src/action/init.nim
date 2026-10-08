import os

import logger
import global_state

const
  # The directories config_template declares, beside it so the two cannot
  # drift: init writes that template, so it has to create these. `config`
  # (.acc) needs no entry — createDir makes parents, and work, scripts and
  # build all sit inside it.
  scaffold_src = "src"
  scaffold_destination = "build"
  scaffold_content = "content"
  scaffold_work = ".acc/work"
  scaffold_scripts = ".acc/scripts"
  scaffold_build = ".acc/build"

  config_template = """---
manifest_version: v1
name: ""
domains: []

directories:
  src: "src"
  destination: "build"
  content: "content"
  config: ".acc"
  work: ".acc/work"
  scripts: ".acc/scripts"
  build: ".acc/build"

workflows:
  - name: "build"
    steps:
      - comment: "Copy static assets"
        module: "@copy"
        glob: "**/*.{jpg,jpeg,png,gif,svg,webp,ico}"
      - comment: "Render templates"
        module: "@mustache"
        glob: "**/*.mustache"
"""

proc is_empty( path: string ): bool =
  result = true
  for file in path.walk_dir:
    # A stale structured-log artifact: older binaries dropped a 0-byte
    # accelerate.json into the cwd on every invocation, which made
    # `acc init .` fail here against a file acc itself had written.
    if file.path.splitPath.tail == "accelerate.json": continue
    result = false
    break

proc init*( state: State ) =
  let root = state.config.directories.root
  info "Initializing new project in ", root

  # Initializing a directory that does not exist yet is fine — create it
  # rather than failing later at the config write.
  if root != "" and not root.dir_exists:
    root.create_dir

  if root == "" or root.is_empty:
    # Defaults, not state.config.directories: `acc init` runs before any
    # config is read, so every field there is empty and all six guards used
    # to skip — the scaffold wrote acc.yaml and created none of the
    # directories it declares. A field is still honoured when something has
    # set it, so a future caller that does load a config keeps control.
    let dirs = state.config.directories
    proc dir(configured, fallback: string): string =
      if configured != "": configured else: fallback
    for relative in [
      dir(dirs.src, scaffold_src),
      dir(dirs.destination, scaffold_destination),
      dir(dirs.content, scaffold_content),
      dir(dirs.work, scaffold_work),
      dir(dirs.scripts, scaffold_scripts),
      dir(dirs.build, scaffold_build)
    ]:
      (root / relative).createDir

    let config_path = root / "acc.yaml"
    try:
      config_path.writeFile( config_template )
      notice "Created configuration file: ", config_path
    except IOError as e:
      error "Failed to create configuration file: ", e.msg
      quit(1)
  else:
    error "Directory is not empty. Please choose an empty directory."
    quit(1)
