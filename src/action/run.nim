import logger
import global_state
import action/run_workflow

proc run*( state: State ) =
  let workflow_name = state.config.runWorkflow
  if workflow_name == "":
    error "No workflow specified. Use: acc run <workflow_name>"
    return

  notice "Running workflow: ", workflow_name
  try:
    runWorkflowByName(state, workflow_name)
  except KeyError:
    error "Workflow '", workflow_name, "' not found in config"
