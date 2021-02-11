from ../logger import LogLevel
import plugin

type
  Action* = enum
    ActionNone, ActionBuild, ActionTest, ActionClean, ActionRun

  Config* = object
    global_config_path*: string
    local_config_path*: string
    current_directory_path*: string
    source_directory*: string
    destination_directory*: string
    action*: Action
    log_level*: LogLevel
    blacklist*: string
    whitelist*: string
    keep*: bool

    name*: string
    domains*: seq[ string ]

    plugins*: seq[ Plugin ]
