import config
import state as state_module

type
  TemplateEngineRunProc* = proc(step: Step, state: State) {.nimcall.}

  TemplateEnginePlugin* = object
    name*: string
    extensions*: seq[string]  ## File extensions this engine handles (e.g. @[".mustache"])
    run*: TemplateEngineRunProc
