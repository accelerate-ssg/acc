import json

import config
import plugin
import render_state

type
  ContextKeyFormatError* = object of ValueError
  ContextNodeAssignmentError* = object of ValueError
  State* = ref object
    context*: JsonNode
    config*: Config
    render_state*: RenderState
    #registry*: Table[ string, proc( interpreter: Interpreter, callback_proc: PSym ){.gcsafe, locks: 0.}]
    current_plugin*: Plugin
