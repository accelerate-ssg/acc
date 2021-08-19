import compiler/[vmdef, vm, renderer]
import tables
import sequtils, sugar
import os
import osproc
import strutils

import logger
from global_state import state
import types/config/value_by_name

proc getFromContext*( args: VmArgs ) = {.gcsafe.}:
  var path = args.getString( 0 )
  var value:string

  debug "getting " & value & " from " & path

  if path.starts_with( "config.plugin." ):
    value = state.current_plugin.config.get_or_default( path[ 14..^1 ])
  elif path.starts_with( "config." ):
    value = state.config[ path[ 7..^1 ]]
  else:
    value = state.context.get_or_default( path[ 8..^1 ])

  args.setResult( value )

proc setInContext*( args: VmArgs ) = {.gcsafe.}:
  var path = args.getString( 0 )
  let value = args.getString( 1 )
  if path.starts_with( "config" ):
    error "Can't store value in ", path, ", config is read only. Did you mean \"context\"?"
  elif path.starts_with( "context" ):
    state.context[ path[ 8..^1 ]] = value
  else:
    state.context[ path ] = value
  debug "setting " & path & " to " & value

proc simpleReadFile*( args: VmArgs ) = {.gcsafe.}:
  var path:string = args.getString( 0 )
  if not path.isAbsolute:
    path = state.config.map["source_directory"] & "/" & path

  try:
    let content = read_file( path )
    args.setResult( content )
  except IOError:
    error "Could not read file ", path
  except:
    error "Unknown exception!"
    raise

proc execWithExitCode*( args: VmArgs ) = {.gcsafe.}:
  let command = args.getString( 0 )
  let exit_code = execShellCmd( command )
  args.setResult( exit_code )

proc execWithResults*( args: VmArgs ) = {.gcsafe.}:
  let command = args.getString( 0 )
  let output = execProcess( command )
  args.setResult( output )

proc simpleWriteFile*( args: VmArgs ) = {.gcsafe.}:
  let
    file_name = args.getString( 0 )
    text = args.getString( 1 )
  writeFile( file_name, text )
