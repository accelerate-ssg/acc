import os
import glob
import strutils
import sequtils
import sets
import json

import logger
import config

# Initializes a blacklist of file paths that should be ignored during file listing.
# The blacklist currently includes paths to the build directory, the local config file,
# and the plugins directory if these paths are subdirectories of the source directory.
proc init_blacklist*(
  source_directory: string,
  destination_directory: string,
  config_directory: string
): seq[ Glob ] =
  let
    destination_is_child_of_source = destination_directory.starts_with( source_directory )
    config_is_child_of_source = config_directory.starts_with( source_directory )
    relative_accelerate_directory = source_directory / ".acc"

  result = @[]

  if destination_is_child_of_source:
    let
      relative_destination_path = relativePath( destination_directory, source_directory )

    if relative_destination_path != "." and destination_directory.dir_exists():
      debug "Adding " & relative_destination_path & "/* to blacklist"
      result.add( glob( relative_destination_path & "/**/*" ))

  if config_is_child_of_source:
    let
      relative_config_path = relativePath( config_directory, source_directory )
    if relative_config_path != "." and config_directory.dir_exists():
      debug "Adding " & relative_config_path & "/* to blacklist"
      result.add( glob( relative_config_path & "/**/*" ))

  result.add( glob( relative_accelerate_directory & "/**/*" ))



# Initializes a raw list of files from the source directory.
proc init_raw_file_list*( source_directory: string ): HashSet[ string ] =
  result = init_hash_set[string]()

  for source_path in walk_glob( source_directory & "**/*" ):
    let
      relative_path = relative_path( source_path, source_directory )

    result.incl relative_path



# Collect all the globs from the workflow steps.
proc init_step_globs*( steps: seq[ Step ] ): seq[ Glob ] =
  result = @[]

  for step in steps:
    if step.extraConfig != nil and step.extraConfig.hasKey("glob"):
      result.add( glob( step.extraConfig["glob"].getStr ))


# Filters a list of files by a list of globs and a blacklist.
proc filter*( file_list: HashSet[ string ], globs: seq[ Glob ], blacklist: seq[ Glob ] ): seq[ string ] =
  result = @[]

  for file_path in file_list:
    if globs.any_it( file_path.matches( it )):
      if blacklist.any_it( file_path.matches( it )):
        continue

      result.add( file_path )



# Collects the directories holding partials, as declared by the steps that use
# them. A partial is an input to another template rather than a page of its own,
# so it is kept out of the candidate source files.
proc init_partial_globs*( cfg: Config ): seq[ Glob ] =
  result = @[]

  for workflow in cfg.workflows:
    for step in workflow.steps:
      if step.extraConfig == nil or not step.extraConfig.hasKey( "partial_directories" ):
        continue

      for directory_node in step.extraConfig[ "partial_directories" ]:
        let directory = cfg.directories.root / directory_node.getStr

        if not directory.starts_with( cfg.directories.src ):
          continue

        let relative_path = relativePath( directory, cfg.directories.src )

        if relative_path != ".":
          debug "Adding " & relative_path & "/* to the partial directories"
          result.add( glob( relative_path & "/**/*" ))



# True when a source relative path sits inside a declared partial directory.
proc is_partial*( cfg: Config, file_path: string ): bool =
  cfg.init_partial_globs().any_it( file_path.matches( it ))



# Every file in the source directory that a build could care about: the whole
# tree, less the blacklist and less any declared partial directory.
#
# This is what a full build passes as its candidate list. Callers wanting a
# narrower build - a dev rebuild, a diff driven rebuild - pass their own list
# instead of calling this.
proc init_source_files*( cfg: Config ): seq[ string ] =
  let
    blacklist = init_blacklist(
      cfg.directories.src,
      cfg.directories.destination,
      cfg.directories.config
    )
    partial_globs = init_partial_globs( cfg )
    raw_file_list = init_raw_file_list(
      cfg.directories.src
    )

  result = @[]

  for file_path in raw_file_list:
    if blacklist.any_it( file_path.matches( it )):
      continue

    if partial_globs.any_it( file_path.matches( it )):
      continue

    result.add( file_path )



# Narrows the caller's candidate files to those this workflow's steps ask for.
# The blacklist is applied again here so a caller supplied list cannot smuggle
# in the build or config directories.
proc init_file_list*( cfg: Config, steps: seq[ Step ], source_files: seq[ string ] ): seq[ string ] =
  let
    globs = init_step_globs( steps )
    blacklist = init_blacklist(
      cfg.directories.src,
      cfg.directories.destination,
      cfg.directories.config
    )

  result = @[]

  for file_path in source_files:
    if not globs.any_it( file_path.matches( it )):
      continue

    if blacklist.any_it( file_path.matches( it )):
      continue

    result.add( file_path )

  warn "[FILTERED FILE LIST]", $result



when not defined(release):
  import unittest

  suite "File handling tests":

    setup:
      let
        temp_dir = get_temp_dir() / "accelerate_test"
        source_dir = temp_dir / "src"
        destination_dir = temp_dir / "public"
        nested_destination_dir = source_dir / "public"
        content_dir = temp_dir / "content"
        accelerate_dir = temp_dir / ".acc"
        build_dir = accelerate_dir / "build"

      createDir( source_dir )
      createDir( destination_dir )
      createDir( nested_destination_dir )
      createDir( content_dir )
      createDir( accelerate_dir )
      createDir( build_dir )
      writeFile( source_dir / "test.nim", "test file" )
      writeFile( source_dir / "test.txt", "test file" )

    teardown:
      removeDir( temp_dir )

    test "init_blacklist":
      let
        blacklist = init_blacklist(source_dir, destination_dir, content_dir)
      check blacklist.len == 1

    test "init_blacklist":
      let
        blacklist = init_blacklist(source_dir, nested_destination_dir, content_dir)
      check blacklist.len == 2

    test "init_raw_file_list":
      let
        file_list = init_raw_file_list(source_dir)
      check file_list.len == 2

    test "init_step_globs":
      let
        steps: seq[Step] = @[
          Step(module: "@copy", extraConfig: %*{"glob": "*.nim"}),
        ]
        globs = init_step_globs(steps)
      check globs.len == 1
      check globs[0].pattern == "*.nim"

    test "filter":
      let
        steps: seq[Step] = @[
          Step(module: "@copy", extraConfig: %*{"glob": "*.nim"}),
        ]
        blacklist = init_blacklist(source_dir, destination_dir, content_dir)
        globs = init_step_globs(steps)
        file_list = init_raw_file_list(source_dir)
        filtered_list = filter(file_list, globs, blacklist)
      check filtered_list.len == 1
      check filtered_list[0] == "test.nim"
