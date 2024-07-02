import tables, strutils, sets

from logger import LogLevel
import plugin

const
  DEFAULT_SOURCE_DIRECTORY* = "src"
  DEFAULT_DESTINATION_DIRECTORY* = "public"
  DEFAULT_CONTENT_DIRECTORY* = "content"
  DEFAULT_WORKSPACE_DIRECTORY* = ".acc"
  DEFAULT_CONFIG_PATH* = "config.yaml"
  DEFAULT_SCRIPT_DIRECTORY* = "scripts"
  DEFAULT_BUILD_DIRECTORY* = DEFAULT_WORKSPACE_DIRECTORY & "/build"
  MANIFEST_VERSION* = "v1"

type
  Path* = string
  WorkflowName* = string
  Action* = enum
    ActionNone, ActionBuild, ActionTest, ActionClean, ActionRun, ActionDev, ActionInit
  WorkflowKind* = enum
    kWConditional, kWList, kWStepped
  StepKind* = enum
    kSCommand, kSScript

  Config* = object
    name*: string
    dns_name*: string
    domains*: seq[ string ]
    action*: Action
    log_level*: LogLevel
    map*: Table[ string, string ]
    plugins*: seq[ Plugin ]
    files*: HashSet[ Path ]
  
#   ConditionalWorkflow* = ref object
#     name*: string
#     command*: string
#     regex*: Regex
#     workflows*: seq[ WorkflowName ]

#   WorkflowStep* = ref object
#     comment*: string
#     case kind*: StepKind
#     of kSCommand:
#       command*: string
#       arguments*: seq[ string ]
#     of kSScript:
#       script_path*: Path

#   Workflow* = ref object
#     name*: WorkflowName
#     environment_variables*: Table[ string, string ]
#     case kind*: WorkflowKind
#     of kWConditional:
#       conditional_workflows*: seq[ ConditionalWorkflow ]
#     of kWList:
#       workflows*: seq[ WorkflowName ]
#     of kWStepped:
#       steps*: seq[ WorkflowStep ]

#   ConfigNext* = object
#     directories*: object
#       source*: Path
#       destination*: Path
#       content*: Path
#       workspace*: Path
#       script*: Path
#       build*: Path
#     scripts*: seq[ Script ]
#     log_level*: LogLevel
#     exclude*: seq[ Path ]
#     meta*: Table[ string, JsonNode ]
#     workflows*: seq[ Workflow ]

# proc init_config*(): ConfigNext =
#   result = ConfigNext(
#     directories: object(
#       source: DEFAULT_SOURCE_DIRECTORY,
#       destination: DEFAULT_DESTINATION_DIRECTORY,
#       content: DEFAULT_CONTENT_DIRECTORY,
#       workspace: DEFAULT_WORKSPACE_DIRECTORY,
#       script: DEFAULT_SCRIPT_DIRECTORY,
#       build: DEFAULT_BUILD_DIRECTORY
#     ),
#     scripts: @[],
#     log_level: LogLevel.Info,
#     exclude: @[],
#     meta: initTable[ string, JsonNode ]()
#   )

proc `[]`*( config: Config, field: string ):string =
  case field:
  of "name": return config.name
  of "dns_name": return config.dns_name
  of "domains": return config.domains.join(",")
  else:
    return config.map.get_or_default( field )
