import json

type
  Path* = string

  RenderStateItem* = ref object
    source_path*: Path
    output_path*: Path
    render*: bool
    item*: JsonNode
    items*: JsonNode
    ## The resolved name of the final dynamic segment, before the extension.
    ## For a page produced by several merged elements this is the shared name.
    key*: string
    ## The enclosing bound item, carrying its own parent, so templates can walk
    ## up with parent.parent. nil at the top level, and nil when the enclosing
    ## segment merged several elements into one page.
    parent*: JsonNode

  RenderState* = seq[RenderStateItem]

proc init_render_state_item*(
  source_path: Path,
  output_path: Path,
  render: bool = false,
  item: JsonNode = newJObject(),
  items: JsonNode = newJArray(),
  key: string = "",
  parent: JsonNode = nil
): RenderStateItem =
  result = RenderStateItem()
  result.source_path = source_path
  result.output_path = output_path
  result.render = render
  result.item = item
  result.items = items
  result.key = key
  result.parent = parent

proc init_render_state_item*(
  render_state_item: RenderStateItem,
  output_path: Path = "",
  item: JsonNode,
  items: JsonNode,
  key: string = "",
  parent: JsonNode = nil
): RenderStateItem =
  init_render_state_item(
    source_path = render_state_item.source_path,
    output_path = output_path,
         render = render_state_item.render,
           item = item,
          items = items,
            key = key,
         parent = parent
  )
