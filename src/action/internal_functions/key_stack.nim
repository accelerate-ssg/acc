import std/[os, strutils]

import global_state

type
  KeyStack* = object
    atoms*: seq[string]
    marks: seq[int]

proc newKeyStack*(): KeyStack =
  result.atoms = @[]
  result.marks = @[]

proc mark*(key_stack:var KeyStack): void =
  key_stack.marks.add( key_stack.atoms.len )

proc clear*(key_stack:var KeyStack): void =
  let start = key_stack.marks.pop
  key_stack.atoms.setLen(start)

proc add_path*( key_stack:var KeyStack, path:string, separator:string = "/" ) =
  if path.len == 0:
    return

  for path_atom in path.split(separator):
    key_stack.atoms.add( path_atom )

proc add_file_path*( key_stack:var KeyStack, original_path:string ) =
  let content_root = state.config.directories.content
  var path = original_path
  let (_, _, extension) = splitFile(path)
  
  path.remove_prefix( content_root & "/" )
  path.remove_suffix( extension )

  key_stack.add_path( path )

proc add_dotted_path*( key_stack:var KeyStack, path:string ) =
  key_stack.add_path( path, "." )

template `$`*( key_stack:KeyStack ): string =
  key_stack.atoms.join( "." )
