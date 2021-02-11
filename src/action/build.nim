import global_state
import run_plugins

proc build*( global_state: State ) = run_plugins( global_state )
