import logger
import global_state

proc run*( state: State ) =
  let workflow_name = state.config.runWorkflow
  if workflow_name == "":
    error "No workflow specified. Use: acc run <workflow_name>"
    return

  notice "Running workflow: ", workflow_name
  # TODO: implement workflow execution engine
  warn "Workflow execution not yet implemented"
