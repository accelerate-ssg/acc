import os
import glob
import strutils
import sequtils
import times
import sets
import tables
import unittest
import sugar

import logger
from types/config import Config, Path
from types/plugin import Plugin
import types/config/path_helpers

# Initializes a blacklist of file paths that should be ignored during file listing.
# The blacklist currently includes paths to the build directory, the local config file,
# and the plugins directory if these paths are subdirectories of the source directory.
proc init_blacklist(
  source_directory: Path,
  destination_directory: Path,
  local_config_path: Path
): seq[ Glob ] =
  let
    destination_is_child_of_source = destination_directory.starts_with( source_directory )
    local_config_is_child_of_source = local_config_path.starts_with( source_directory )
    relative_plugins_path = source_directory / "plugins"
    relative_accelerate_directory = source_directory / ".acc"

  result = @[]

  if destination_is_child_of_source:
    let
      relative_destination_path = relativePath( destination_directory, source_directory )

    if relative_destination_path != "." and destination_directory.dir_exists():
      debug "Adding " & relative_destination_path & "/* to blacklist"
      result.add( glob( relative_destination_path & "/**/*" ))

  if local_config_is_child_of_source:
    let
      relative_config_path = relativePath( local_config_path, source_directory )
    if relative_config_path != "." and local_config_path.dir_exists():
      debug "Adding " & relative_config_path & "/* to blacklist"
      result.add( glob( relative_config_path & "/**/*" ))

  if relative_plugins_path.dir_exists():
    debug "Adding " & relative_plugins_path & "/* to blacklist"
    result.add( glob( relative_plugins_path & "/**/*" ))

  result.add( glob( relative_accelerate_directory & "/**/*" ))



# Initializes a raw list of files from the source directory.
proc init_raw_file_list( source_directory: Path ): HashSet[ Path ] =  
  result = init_hash_set[Path]()

  for source_path in walk_glob( source_directory & "**/*" ):
    let
      relative_path = relative_path( source_path, source_directory )

    result.incl relative_path



# Collect all the globs from the plugins' config files.
proc init_script_globs( plugins: seq[ Plugin ] ): seq[ Glob ] =
  result = @[]

  for plugin in plugins:
    if plugin.config.hasKey("glob"):
      result.add( glob( plugin.config["glob"] ))


# Filters a list of files by a list of globs and a blacklist.
proc filter( file_list: HashSet[ Path ], globs: seq[ Glob ], blacklist: seq[ Glob ] ): seq[ Path ] =
  result = @[]

  for file_path in file_list:
    if globs.any_it( file_path.matches( it )):
      if blacklist.any_it( file_path.matches( it )):
        continue

      result.add( file_path )



# Returns a list of unique, relative paths to all files in the source directory
# that match any plugin's glob and is not in the blacklist.
proc init_file_list*( config: Config ): seq[ Path ] =
  let
    globs = init_script_globs(
      config.plugins
    )
    blacklist = init_blacklist(
      config.source_directory,
      config.destination_directory,
      config.local_config_path
    )
    raw_file_list = init_raw_file_list(
      config.source_directory
    )
  
  result = raw_file_list.filter( globs, blacklist )

  warn "[FILTERED FILE LIST]", $result



suite "File handling tests":

  setup:
    let
      temp_dir = get_temp_dir() / "accelerate_test"
      source_dir = temp_dir / "src"
      destination_dir = temp_dir / "public"
      nested_destination_dir = source_dir / "public"
      content_dir = temp_dir / "content"
      accelerate_dir = temp_dir / ".acc"
      plugins_dir = accelerate_dir / "plugins"
      build_dir = accelerate_dir / "build"

      plugins: seq[Plugin] = @[
        Plugin(name: "TestPlugin", script: "script", function: "function", after: @[], before: @[], config: {"glob": "*.nim"}.toTable),
      ]

    createDir( source_dir )
    createDir( destination_dir )
    createDir( nested_destination_dir )
    createDir( content_dir )
    createDir( accelerate_dir )
    createDir( plugins_dir )
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

  test "init_script_globs":
    let
      globs = init_script_globs(plugins)
    check globs.len == 1
    check globs[0].pattern == "*.nim"

  test "filter":
    let
      blacklist = init_blacklist(source_dir, destination_dir, content_dir)
      globs = init_script_globs(plugins)
      file_list = init_raw_file_list(source_dir)
      filtered_list = filter(file_list, globs, blacklist)
    check filtered_list.len == 1
    check filtered_list[0] == "test.nim"
