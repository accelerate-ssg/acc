# Run any named script or scripts.
import global_state
import run_plugins

proc run*( global_state: State ) = run_plugins( global_state )
