name: "JSON loader"
version: "0.1.0"
author: "Jonas Schubert Erlandsson"
description: "Load any JSON files found into context"
license: "MIT"

import json
import system
import sequtils

var
  key_stack:seq[ string ] = @[]
  content_root:string
  context_path_prefix:string

content_root <- config.content_root
context_path_prefix <- config.plugin.context_path_prefix

# Forward declaring to resolve the co-dependance between the procs
proc store_node( node:JsonNode )

proc store_value( node:JsonNode ) =
  var value:string

  case node.kind:
  of JString: value = node.getStr
  of JInt:    value = $node.getBiggestInt
  of JFloat:  value = $node.getFloat
  of JBool:   value = $node.getBool
  else: return

  set_in_context( key_stack.join("."), value )

proc store_array( node:JsonNode ) =
  for index, value in node.getElems:
    key_stack.add( "[" & $index & "]" )
    store_node( value )
    discard key_stack.pop

proc store_object( node:JsonNode ) =
  for name, value in node.getFields:
    key_stack.add( name )
    store_node( value )
    discard key_stack.pop

proc store_node( node:JsonNode ) =
  case node.kind:
  of JObject: store_object( node )
  of JArray: store_array( node )
  else: store_value( node )

proc add_path_prefix_to_key_stack( relative_path:string ) =
  var path = relative_path
  path.removePrefix( content_root & "/" )
  path.removeSuffix( ".json" )

  warn relative_path, " - ", path

  key_stack.add( context_path_prefix )
  for dir in path.split("/"):
    key_stack.add( dir )

proc for_each_file*( relative_path, absolute_path: string ):string =
  add_path_prefix_to_key_stack( relative_path )
  try:
    let content = read_file( absolute_path )
    let node = parse_json( content )
    store_node( node )
  except IOError:
    err "Error reading file ", relative_path
  except JsonParsingError:
    err "Error parsing file ", relative_path
  except:
    err "Unknown exception!"
    raise
  finally:
    key_stack.delete( 0, key_stack.len )
  return ""
