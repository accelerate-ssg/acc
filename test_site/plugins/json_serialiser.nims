name: "JSON serialiser"
version: "0.1.0"
author: "Jonas Schubert Erlandsson"
description: "Dump entire state to JSON"
license: "MIT"

import json
import system
import sequtils
import tables

var
  context = %* {}
  ctxref = context
  workspace:string

workspace <- config.workspace_directory

proc for_each_field*( path, content: string ) =
  let
    atoms = path.split(".")

  ctxref = context

  if atoms.len > 1:
    for atom in atoms[0..^2]:
      try:
        ctxref = ctxref[ atom ]
      except KeyError:
        ctxref[ atom ] = %* {}
        ctxref = ctxref[ atom ]

  ctxref[ atoms[ ^1 ]] = %* content

  # TODO: Fix directory handling for cross platform
  writeFile( workspace & "/context.json", $context )
