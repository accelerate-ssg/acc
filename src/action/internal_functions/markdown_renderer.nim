import std/[os]
import global_state
import types/plugin
import logger
import glob
import mustache
import tables
import strutils
import json
import markdown

proc path_contains( path:string ):bool =
  let
    test_value = state.current_plugin.config.get_or_default( "path_contains", "-markdown." )

    allow_any = test_value == "*"
    not_empty = not test_value.isEmptyOrWhitespace
    path_match = path.contains( test_value )

  return allow_any or ( not_empty and path_match )


proc content_starts_with( content:string ):bool =
  let test_value = state.current_plugin.config.get_or_default( "content_starts_with", "[//]:" )

  # Matches anything
  if test_value == "*":
    return true

  if test_value.is_empty_or_whitespace:
    return false

  return content.starts_with( test_value )


proc matches( path, content:string ):bool =
  return content_starts_with( content ) or
         path_contains( path )

proc for_each_matching_member( node: JsonNode, callback: proc, current_dotted_path:string = "" ) =

  proc callback_if_matches( path:string, content:string ) =
    if matches( path, content ):
      callback( path, content )

  if node.kind == JObject:
    for key, content in node.pairs:
      content.for_each_matching_member( callback_if_matches, current_dotted_path & "." & key ):
  elif node.kind == JArray:
    for index, content in node.elems.pairs:
      content.for_each_matching_member( callback_if_matches, current_dotted_path & "[" & $index & "]" ):
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
    callback_if_matches(current_dotted_path, content)

proc render(path, content: string) =
  let html = markdown( content )
  state{ path } = newJString( html )

proc run*(plugin: Plugin) =
  state.context.for_each_matching_member(
    proc (path, content: string) =
      let html = markdown( content )
      #debug "Markdown: " & path & " -> " & html
      state{ path } = newJString( html )
  )
