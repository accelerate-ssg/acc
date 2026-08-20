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
    ## Candidate source files for this build, relative to the source directory.
    ## The caller decides what goes in here: a full build passes everything, a
    ## dev rebuild passes only what changed, and a caching layer or a git diff
    ## can later pass whatever it considers stale. Each workflow still narrows
    ## this list by its own step globs.
    source_files*: seq[string]
    current_step*: Step
    current_workflow*: Workflow
