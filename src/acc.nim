import tables

import types/config
import global_state
import logger
import action/[build,test,clean,run]

proc ctrl_c_handler() {.noconv.} =
  notice "Force quit."
  warn "Incomplete artifacts might be left in the build directory ", state.config.destination_directory, "."
  quit 0

proc main() =
  setControlCHook( ctrl_c_handler )
  init_logger()

  case state.config.action:
  of ActionBuild: state.build()
  of ActionTest: state.test()
  of ActionClean: state.clean()
  of ActionRun: state.run()
  of ActionNone: discard

  quit(0)

when isMainModule:
  main()
