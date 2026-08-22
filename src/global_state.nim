import json
import strutils

import state as state_module
import config

export state_module

var state* = State(
  config: Config(),
  context: newContextStore(),
  render_state: @[],
  source_files: @[],
  current_step: Step(),
  current_workflow: Workflow()
)

proc `{}=`*(state: State, keys: varargs[string], value: JsonNode) =
  state.context.setAccPath(keys, value)

proc `{}=`*(state: State, path: string, value: JsonNode) =
  state{ path.split('.') } = value

proc `{}`*(state: State, keys: varargs[string] ): JsonNode =
  state.context.getPath(keys)

proc `{}`*(state: State, path: string ): JsonNode =
  state{ path.split('.') }
