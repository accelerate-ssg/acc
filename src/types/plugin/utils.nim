import os
import system
import tables
import re
import sequtils, sugar

import logger

let meta_keys = @["name","version","author","description","license"]

proc empty( table: Table[string, string] ):bool =
  not meta_keys.any( key => table.has_key( key ))

proc get_plugin_meta*( path: string ):Table[string, string] =
  var line: TaintedString
  var matches: array[2, string]
  var meta: Table[string, string]
  let regex = re("^\\s*(\\w+):\\s*\"(.+)\"$")

  if fileExists( path ):
    let file = open( path )
    defer: file.close()

    while file.read_line( line ):
      if match( line, regex, matches):
        meta[matches[0]] = matches[1]

  if meta.empty():
    debug "No meta found for ", path
  else:
    debug meta

  return meta

proc get_plugin_name*( path: string, default: string = "" ):string =
  let meta = get_plugin_meta( path )
  return meta.get_or_default( "name", default )
