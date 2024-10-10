import json

from types/config import Path

type
  RenderStateItem* = ref object
    source_path*: Path
    output_path*: Path
    render*: bool
    item*: JsonNode
    items*: JsonNode

  RenderState* = seq[
    RenderStateItem
  ]

proc init_render_state_item*(
  source_path: Path,
  output_path: Path,
  render: bool = false,
  item: JsonNode = newJObject(),
  items: JsonNode = newJArray()
): RenderStateItem =
  result = RenderStateItem()
  result.source_path = source_path
  result.output_path = output_path
  result.render = render
  result.item = item
  result.items = items

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
