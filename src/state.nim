import json

import config
import types/render_state
export render_state

type
  ContextKeyFormatError* = object of ValueError
  ContextNodeAssignmentError* = object of ValueError

  State* = ref object
    context*: JsonNode
    config*: Config
    render_state*: RenderState
    current_step*: Step
    current_workflow*: Workflow
