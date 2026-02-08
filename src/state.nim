import json

import config

type
  Path* = string

  RenderStateItem* = ref object
    source_path*: Path
    output_path*: Path
    render*: bool
    item*: JsonNode
    items*: JsonNode

  RenderState* = seq[RenderStateItem]

  ContextKeyFormatError* = object of ValueError
  ContextNodeAssignmentError* = object of ValueError

  State* = ref object
    context*: JsonNode
    config*: Config
    render_state*: RenderState
    current_step*: Step
    current_workflow*: Workflow

proc init_render_state_item*(
  source_path: Path,
  output_path: Path,
  render: bool = false,
  item: JsonNode = newJObject(),
  items: JsonNode = newJArray()
): RenderStateItem =
  RenderStateItem(
    source_path: source_path,
    output_path: output_path,
    render: render,
    item: item,
    items: items
  )

proc init_render_state_item*(
  render_state_item: RenderStateItem,
  output_path: Path = "",
  item: JsonNode,
  items: JsonNode
): RenderStateItem =
  init_render_state_item(
    source_path = render_state_item.source_path,
    output_path = output_path,
    render = render_state_item.render,
    item = item,
    items = items
  )
