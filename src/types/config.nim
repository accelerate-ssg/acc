import tables, strutils, sets

from ../logger import LogLevel
import plugin

const
  DEFAULT_BUILD_DIRECTORY* = "build"
  DEFAULT_WORKSPACE_DIRECTORY* = ".acc"
  DEFAULT_CONFIG_PATH* = ".acc/config.yaml"

type
  Path* = string
  Action* = enum
    ActionNone, ActionBuild, ActionTest, ActionClean, ActionRun, ActionDev

  Config* = object
    name*: string
    dns_name*: string
    domains*: seq[ string ]
    action*: Action
    log_level*: LogLevel
    map*: Table[ string, string ]
    plugins*: seq[ Plugin ]
    files*: HashSet[ Path ]

proc `[]`*( config: Config, field: string ):string =
  case field:
  of "name": return config.name
  of "dns_name": return config.dns_name
  of "domains": return config.domains.join(",")
  else:
    return config.map.get_or_default( field )
