import os
import json

import types/path
from types/config import MANIFEST_VERSION, ConfigNext, WorkflowKind, StepKind, ConditionalWorkflow, WorkflowStep, Workflow



proc load*( file: Path ): JsonNode =
  let
    absolute_path = file.to_absolute_path
    content = readFile( absolute_path )
    json = load_to_json( content )

  if json.kind != JObject:
    raise Exception( &"Config file $absolute_path has invalid format." )

  return json



proc any_missing( json: JsonNode, required_fields: seq[string] ): seq[ string ] =
  result = @[]
  for key in required_fields:
    if json[key] == nil:
      result.add( key )

proc raise_on_missing_fields( json: JsonNode, required_fields: seq[string] ) {.raises: [KeyError].} =
  let
    missing_fields = json.any_missing( required_fields )

  if missing_fields.len == 0:
    return
  elif missing_fields.len == 1:
    let
      missing_field = missing_fields[0]
    raise KeyError( &"Config is missing the required \"$missing_field\" field." )
  else:
    let
      sorted_fields = missing_fields.sorted()
      head = sorted_fields[0..-2]
      tail = sorted_fields[-1]
      missing_fields_string = "\"" & head.join( "\", \"" ) & "\" and \"" & tail & "\""
    raise KeyError( &"Config is missing the required $missing_fields_string fields." )

proc raise_on_wrong_kind( json: JsonNode, expected_kind: JsonKind ) {.raises: [KeyError].} =
  if json.kind != expected_kind:
    let 
      actual_kind_string = $(json.kind)[1..-1]
      expected_kind_string = $(expected_kind)[1..-1]
    raise KeyError( &"Config has invalid format. Actual is $actual_kind_string but expected $expected_kind_string." )

proc raise_unless_valid( json: JsonNode, expected_kind: JsonKind ) {.raises: [KeyError].} =
  if json == nil:
    let
      expected_kind_string = $(expected_kind)[1..-1]
    raise KeyError( &"Config has invalid format. Expected $expected_kind_string but got null." )
  else:
    raise_on_wrong_kind( json, expected_kind )




proc parse_environment_variables( json: JsonNode, workflow_name: WorkflowName ): Table[ string, string ] =
  raise_unless_valid( json, JObject )

  result = initTable[ string, string ]()

  for key, value in json:
    result[key] = $value

# ConditionalWorkflow* = ref object
#   name*: string
#   command*: string
#   regex*: Regex
#   workflows*: seq[ WorkflowName ]
proc parse_kWConditional( JsonNode ): ConditionalWorkflow =
  const
    REQUIRED_FIELDS = {"name", "condition", "steps"}

  raise_on_missing_fields( json, REQUIRED_FIELDS )

  result = ConditionalWorkflow()
  workflow.name = json["name"]
  workflow.condition = json["condition"]
  workflow.steps = parse_steps( json["steps"] )

  return workflow


proc parse_kWList( JsonNode ): WorkflowList =
  const
    REQUIRED_FIELDS = {"name", "workflows"}

  raise_on_missing_fields( json, REQUIRED_FIELDS )

  result = WorkflowList()
  result.name = json["name"]
  result.workflows = json["steps"].get_elems().map_it( it.get_str() )

# Workflow* = ref object
#   name*: WorkflowName
#   environment_variables*: Table[ string, string ]
#   case kind*: WorkflowKind
#   of kWConditional:
#     conditional_workflows*: seq[ ConditionalWorkflow ]
#   of kWList:
#     workflows*: seq[ WorkflowName ]
#   of kWStepped:
#     steps*: seq[ WorkflowStep ]
proc parse_workflow( json: JsonNode ): Workflow =
  const
    REQUIRED_FIELDS = {"name"}

  raise_on_missing_fields( json, REQUIRED_FIELDS )

  result = Workflow()
  result.name = json["name"]
  result.environment_variables = parse_environment_variables( json{"environment_variables"}, json["name"] )
  if json{"steps"} != nil:
    raise_on_wrong_kind( json["steps"], JArray )
    result.kind = kWStepped
    result.steps = parse_kWSteps( json["steps"] )
  elif json{"case"} != nil:
    raise_on_wrong_kind( json["case"], JArray )
    result.kind = kWConditional
    result.conditional_workflows = parse_kWConditional( json["case"] )
  elif json{"workflows"} != nil:
    result.kind = kWList
    result.workflows = parse_list_of_workflow_names( json["workflows"] )
  else:
    raise Exception( &"Workflow \"$result.name\" has no \"steps\", \"conditional_workflows\" or \"workflows\" field." )


proc load*( file: Path ): ConfigNext =
  const
    IGNORED_FIELDS = {"manifest_version", "directories", "workflows"}
  let
    json = load( file )
    config = init_config()

  if json{"manifest_version"} == nil:
    raise Exception( "Config file " & absolute_path & " has no manifest version." )
  if json["manifest_version"] != MANIFEST_VERSION:
    raise Exception( "Config file " & absolute_path & " has the wrong manifest version. Actual is " & json["manifest_version"] & ", but expected " & MANIFEST_VERSION )

  if json{"directories"} != nil:
    if json["directories"].kind != JObject:
      let 
        kind_string = $(json["directories"].kind)[1..-1]
      raise Exception( "\"directories\" field in config file " & file.to_absolute_path & " has invalid format. Actual is " & kind_string & ", but expected Object." )
    if json["directories"]{"source"} != nil:
      config.directories.source = json["directories"]["source"]
    if json["directories"]{"destination"} != nil:
      config.directories.destination = json["directories"]["destination"]
    if json["directories"]{"content"} != nil:
      config.directories.content = json["directories"]["content"]
    if json["directories"]{"workspace"} != nil:
      config.directories.workspace = json["directories"]["workspace"]
    if json["directories"]{"script"} != nil:
      config.directories.script = json["directories"]["script"]
    if json["directories"]{"build"} != nil:
      config.directories.build = json["directories"]["build"]

  if json{"workflows"} != nil:
    if json["workflows"].kind != JArray:
      let 
        kind_string = $(json["workflows"].kind)[1..-1]
      raise Exception( "\"workflows\" field in config file " & file.to_absolute_path & " has invalid format. Actual is " & kind_string & ", but expected Array." )
    for workflow in json["workflows"]:


  for key, value in json:
    if IGNORED_FIELDS.contains( key ):
      continue
    config.meta[key] = value
