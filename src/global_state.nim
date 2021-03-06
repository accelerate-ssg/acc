import tables

import types/config
import types/config/init

type
  State* = ref object
    context*: Table[ string, string ]
    config*: Config

var globalState* = State(
  config: init_config(),
  context: initTable[ string, string ]()
)
