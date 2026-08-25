import os

import logger
import global_state

const
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
    let dirs = state.config.directories
    if dirs.src != "": (root / dirs.src).createDir
    if dirs.destination != "": (root / dirs.destination).createDir
    if dirs.work != "": (root / dirs.work).createDir
    if dirs.build != "": (root / dirs.build).createDir
    if dirs.scripts != "": (root / dirs.scripts).createDir
    if dirs.content != "": (root / dirs.content).createDir

    let config_path = root / "acc.yaml"
    try:
      config_path.writeFile( config_template )
      notice "Created configuration file: ", config_path
    except IOError as e:
      error "Failed to create configuration file: ", e.msg
  else:
    error "Directory is not empty. Please choose an empty directory."
