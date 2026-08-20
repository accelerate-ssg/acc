import json

import global_state
import logger
import config
import action/[build,test,clean,run,dev_server,init,run_workflow]
import types/render_state/file_list
import plugins/registry
import plugins/mustache_engine
import acc_liquid

proc ctrl_c_handler() {.noconv.} =
  notice "Force quit."
  quit 0

proc showMe(aspect: string) =
  case aspect:
  of "config":
    echo pretty(%state.config)
  of "files":
    # Find the build workflow (or first workflow with steps)
    var steps: seq[Step] = @[]
    for wf in state.config.workflows:
      if wf.isLeaf:
        steps = wf.steps
        break
    if steps.len > 0:
      let files = init_file_list(state.config, steps, init_source_files(state.config))
      echo pretty(%*files)
    else:
      echo "[]"
  else:
    echo "Unknown --show-me aspect: \"" & aspect & "\""
    echo "Available: config, files"
  quit(0)

proc main() =
  setControlCHook( ctrl_c_handler )
  init_logger()

  state.config = parseCliArgs()
  set_log_level( logger.LogLevel(ord(state.config.logLevel)) )

  # Register built-in template engines
  registerEngine("mustache", mustache_engine.plugin)
  registerEngine("liquid", acc_liquid.plugin)

  if state.config.showMe != "":
    showMe(state.config.showMe)

  initScriptRunners()

  case state.config.action:
  of ActionDev: state.dev_server()
  of ActionBuild: state.build()
  of ActionTest: state.test()
  of ActionClean: state.clean()
  of ActionRun: state.run()
  of ActionInit: state.init()
  of ActionNone: discard

  quit(0)

when isMainModule:
  main()
