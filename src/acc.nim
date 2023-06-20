import tables

import types/config
import global_state
import logger
import action/[build,test,clean,run,dev_server]
import types/pretty_print

proc ctrl_c_handler() {.noconv.} =
  notice "Force quit."
  warn "Incomplete artifacts might be left in the build directory ", state.config.map["destination_directory"], "."
  quit 0

proc main() =
  setControlCHook( ctrl_c_handler )
  init_logger()

  debug state.config.pretty()

  case state.config.action:
  of ActionDev: state.dev_server()
  of ActionBuild: state.build()
  of ActionTest: state.test()
  of ActionClean: state.clean()
  of ActionRun: state.run()
  of ActionNone: discard

  quit(0)

when isMainModule:
  main()
