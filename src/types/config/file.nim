import std / os
import yaml, streams
import tables
import strutils

import logger
import types/config
import types/plugin
import types/config/DAG

type
  Section = enum
    None, Site, Build, Done

var
  events: YamlStream

proc parse_site_name(): string =
  let event = events.next
  return event.scalarContent

proc parse_site_domains(): seq[ string ] =
  var
    event = events.next
    domains: seq[ string ] = @[]
  while true:
    event = events.next
    if event.kind == yamlScalar: domains.add( event.scalarContent )
    if event.kind == yamlEndSeq: break
  return domains

proc parse_site_section( config: var Config ) =
  var
    event = events.next

  while event.kind != yamlEndMap:
    if event.kind == yamlScalar:
      case event.scalarContent:
      of "name":
        config.name = parse_site_name()
      of "domains":
        config.domains = parse_site_domains()
    event = events.next

proc parse_string_value( msg: string = "" ): string =
  var
    event: Event
  event = events.next
  assert event.kind == yamlScalar, $event.kind & " - " & msg
  return event.scalarContent

proc parse_string_sequence( msg: string = "" ): seq[ string ] =
  var
    event: Event
  result = @[]
  event = events.next
  while event.kind != yamlEndSeq:
    assert event.kind == yamlScalar, msg
    result.add event.scalarContent
    event = events.next

proc parse_string_string_map( msg: string = "" ): Table[ string, string ] =
  var
    event: Event
    name: string
    value: string
  result = initTable[string, string]()
  event = events.next
  while event.kind != yamlEndMap:
    assert event.kind == yamlScalar, msg
    name = event.scalarContent
    event = events.next
    assert event.kind == yamlScalar, msg
    value = event.scalarContent
    result[ name ] = value
    event = events.next

proc parse_plugin_config(): Plugin =
  var
    event: Event
  result = init_plugin()
  event = events.next
  while event.kind != yamlEndMap:
    if event.kind == yamlScalar:
      case event.scalarContent:
      of "name":
        result.name = parse_string_value( "The value of \"name\" should be a string" )
      of "script":
        result.script = parse_string_value( "The value of \"script\" should be a string" )
      of "before":
        event = events.next
        if event.kind == yamlScalar:
          result.before.add( event.scalarContent )
        elif event.kind == yamlStartSeq:
          result.before = parse_string_sequence( "The array of \"before\" should be strings" )
        else:
          assert false, "The value of \"before\" should be a string or array of strings"
      of "after":
        event = events.next
        if event.kind == yamlScalar:
          result.after.add( event.scalarContent )
        elif event.kind == yamlStartSeq:
          result.after = parse_string_sequence( "The array of \"after\" should be strings" )
        else:
          assert false, "The value of \"after\" should be a string or array of strings"
      of "config":
        event = events.next
        result.config = parse_string_string_map( "The map of \"config\" should be string: string" )
    event = events.next

proc parse_build_section( config: var Config ) =
  var
    event = events.next
    plugins: seq[ Plugin ] = @[]

  while event.kind != yamlEndSeq:
    if event.kind == yamlStartMap:
      plugins.add parse_plugin_config()
    event = events.next

  config.plugins = order( plugins )


proc add_yaml_config( config: var Config, file_name: string ) =
  var
    event: Event
    s = newFileStream( file_name )
    parser = initYamlParser()
    section = None

  events = parser.parse( s )

  while event.kind != yamlEndMap:
    if event.kind == yamlScalar:
      case event.scalarContent:
      of "site":
        parse_site_section( config )
      of "build":
        parse_build_section( config )
      else:
        discard
    event = events.next

proc add_global_yaml_to_config( config: var Config ):bool =
  if fileExists( config.global_config_path ):
    config.add_yaml_config( config.global_config_path )
    return true
  else:
    notice "Global config file \"", config.global_config_path ,"\" not found."
    return false

proc add_local_yaml_to_config( config: var Config ):bool =
  if fileExists( config.local_config_path ):
    config.add_yaml_config( config.source_directory / config.local_config_path )
    return true
  elif fileExists( config.source_directory / "config.yaml" ):
    config.add_yaml_config( config.source_directory / "config.yaml" )
    return true
  else:
    let paths = config.source_directory / "config.yaml" & "\n" & config.local_config_path
    warn "Local config file not found. Checked:\n", paths.indent(2)
    return false

proc add_yaml_to_config*( config: var Config ) =
  let
    global = add_global_yaml_to_config( config )
    local = add_local_yaml_to_config( config )

  if not (global or local):
    logger.error "No configuration file found. Build aborted."
    quit(-1)
