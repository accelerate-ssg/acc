import compiler/[ast, nimeval, renderer]
import tables

import types/config
import types/config/init
import types/plugin

type
  State* = ref object
    context*: Table[ string, string ]
    config*: Config
    registry*: Table[ string, proc( interpreter: Interpreter, callback_proc: PSym ) ]
    current_plugin*: Plugin

var state* = State(
  config: init_config(),
  context: initTable[ string, string ](),
  registry: initTable[ string, proc( interpreter: Interpreter, callback_proc: PSym ) ](),
  current_plugin: Plugin()
)
