import compiler/[ast, nimeval, renderer]
import strutils
import sequtils, sugar
import tables

import logger
import global_state


proc context_path_contains_segment( path:string ):bool =
  let
    test_value = state.current_plugin.config.get_or_default( "context_path_contains_segment", "" )

    context_path_atoms = test_value.split( "." )
    path_atoms = path.split( "." )

    allow_any = test_value == "*"
    not_empty = not test_value.isEmptyOrWhitespace
    path_match = path_atoms.all_it( context_path_atoms.contains( it ))

  return allow_any or ( not_empty and path_match )


proc context_path_contains_string( path:string ):bool =
  let
    test_value = state.current_plugin.config.get_or_default( "context_path_contains_string", "" )

    allow_any = test_value == "*"
    not_empty = not test_value.isEmptyOrWhitespace
    path_match = path.contains( test_value )

  return allow_any or ( not_empty and path_match )


proc content_starts_with( beginning:string ):bool =
  let
    test_value = state.current_plugin.config.get_or_default( "content_starts_with", "" )

    allow_any = test_value == "*"
    not_empty = not test_value.isEmptyOrWhitespace
    content_match = beginning.contains( test_value )

  return allow_any or ( not_empty and content_match )


proc matches( path, content:string ):bool =
  let
    len = state.current_plugin.config.get_or_default( "content_starts_with", "" ).len

  return content_starts_with( content[ 0 .. len-1 ] ) or
         context_path_contains_segment( path ) or
         context_path_contains_string( path )


proc for_each_field*( interpreter: Interpreter, callback_proc: PSym ) =
  var
    keys:seq[ string ] = @[]

  for path, content in state.context.pairs:
    if matches( path, content ):
      let
        response = interpreter.callRoutine(
          callback_proc,
          [
            newStrNode( nkStrLit, path ),
            newStrNode( nkStrLit, content )
          ]
        )


# Global registry export
state.registry["for_each_field"] = for_each_field
