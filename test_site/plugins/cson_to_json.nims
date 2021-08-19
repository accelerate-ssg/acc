name: "CSON to JSON"
version: "0.1.0"
author: "Jonas Schubert Erlandsson"
description: "Convert CSON files to JSON"
license: "MIT"

var
  destination_directory:string
  command:string

destination_directory <- config.destination_directory
command <- config.plugin.command

if command.isEmptyOrWhitespace: command = "cson2json"

proc for_each_file*( relative_path, absolute_path: string ): string =
  let destination_path = absolute_path.replace( ".cson", ".json" )

  warn "heeader lines ", LINE_COUNT

  try:
    let exit_code = exec( command & " " & absolute_path & " > " & destination_path )
    if exit_code != 0:
      let relative_destination_path = relative_path.replace( ".cson", ".json" )
      warn command, " ", relative_path, " > ", relative_destination_path, " failed with exit code ", exit_code
    return destination_path
  except OSError:
    err "Executing cson2json on ", relative_path, " failed."
  except:
    err "Unknown exception occurred."
    raise
