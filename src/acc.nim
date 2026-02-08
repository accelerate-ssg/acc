import global_state
import logger
import config
import action/[build,test,clean,run,dev_server,init,run_workflow]

proc ctrl_c_handler() {.noconv.} =
  notice "Force quit."
  quit 0

proc main() =
  setControlCHook( ctrl_c_handler )
  init_logger()

  state.config = parseCliArgs()
  set_log_level( logger.LogLevel(ord(state.config.logLevel)) )
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
