{.used.}

import compiler/[ast, nimeval, renderer]
import strutils
import tables
import json

import logger
import global_state


proc path_contains( path:string ):bool =
  let
    test_value = state.current_plugin.config.get_or_default( "path_contains", "" )

    allow_any = test_value == "*"
    not_empty = not test_value.isEmptyOrWhitespace
    path_match = path.contains( test_value )

  return allow_any or ( not_empty and path_match )


proc content_starts_with( content:string ):bool =
  let test_value = state.current_plugin.config.get_or_default( "content_starts_with", "" )

  # Matches anything
  if test_value == "*":
    return true

  if test_value.is_empty_or_whitespace:
    return false

  return content.starts_with( test_value )


proc matches( path, content:string ):bool =
  return content_starts_with( content ) or
         path_contains( path )

proc for_each_member( node: JsonNode, callback: proc, path_prefix:string = "" ) =
  if node.kind == JObject:
    for key, content in node.pairs:
      content.for_each_member( callback, path_prefix & "." & key ):
  elif node.kind == JArray:
    for index, content in node.elems.pairs:
      content.for_each_member( callback, path_prefix & "[" & $index & "]" ):
  else:
    var
      content: string
    case node.kind:
      of JString:
        content = node.getStr
      of JInt:
        content = $node.getInt
      of JBool:
        content = $node.getBool
      of JFloat:
        content = $node.getFloat
      else:
        content = $node
    callback(path_prefix, content)


proc for_each_field*( interpreter: Interpreter, callback_proc: PSym ) =
  state.context.for_each_member(
    proc (path, content: string) =
      if matches( path, content ):
        warn path, " (or its content) matches."
        discard interpreter.callRoutine(
          callback_proc,
          [
            newStrNode( nkStrLit, path ),
            newStrNode( nkStrLit, content )
          ]
        )
  )


# Global registry export
state.registry["for_each_field"] = for_each_field
