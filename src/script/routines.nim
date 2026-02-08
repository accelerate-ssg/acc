import "$nim"/compiler / [vmdef, vm, renderer]
import tables
import os
import osproc
import strutils
import json

import logger
import global_state
import types/config

proc context_get*( args: VmArgs ) = {.gcsafe.}:
  var path = args.getString( 0 )
  var value:string

  debug "getting " & value & " from " & path

  if path.starts_with( "config.plugin." ):
    value = state.current_plugin.config.get_or_default( path[ 14..^1 ])
  elif path.starts_with( "config." ):
    value = state.config[ path[ 7..^1 ]]
  else:
    let node = state.context{ path[ 8..^1 ]}
    value = $node

  args.setResult( value )

proc context_set_value( path:var string, node:JsonNode ) =
  if path.starts_with( "config" ):
    error "Can't store value in ", path, ", config is read only. Did you mean \"context\"?"
    return

  if path.starts_with( "context" ):
    path = path[ 8..^1 ]

  error path, ": ", $node
  state{ path } = node

proc context_set_bool*( args: VmArgs ) = {.gcsafe.}:
  var path  = args.getString( 0 )
  let value = args.getBool( 1 )
  context_set_value( path, newJBool( value ))

proc context_set_int*( args: VmArgs ) = {.gcsafe.}:
  var path  = args.getString( 0 )
  let value = args.getInt( 1 )
  context_set_value( path, newJInt( value ))

proc context_set_float*( args: VmArgs ) = {.gcsafe.}:
  var path  = args.getString( 0 )
  let value = args.getFloat( 1 )
  context_set_value( path, newJFloat( value ))

proc context_set_string*( args: VmArgs ) = {.gcsafe.}:
  var path  = args.getString( 0 )
  let value = args.getString( 1 )
  context_set_value( path, newJString( value ))



proc simpleReadFile*( args: VmArgs ) = {.gcsafe.}:
  var path:string = args.getString( 0 )
  if not path.isAbsolute:
    path = state.config.map["source_directory"] & "/" & path

  try:
    let content = read_file( path )
    args.setResult( content )
  except IOError:
    error "Could not read file ", path
  except CatchableError:
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

proc setParsingContext*( text: string ) =  {.gcsafe.}:
  logger.set_parsing_context( text )
