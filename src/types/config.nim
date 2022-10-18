import tables

from ../logger import LogLevel
import plugin

type
  Path* = string
  Action* = enum
    ActionNone, ActionBuild, ActionTest, ActionClean, ActionRun

  Config* = object
    name*: string
    dns_name*: string
    domains*: seq[ string ]
    action*: Action
    log_level*: LogLevel
    map*: Table[ string, string ]
    plugins*: seq[ Plugin ]
    files*: seq[ Path ]
