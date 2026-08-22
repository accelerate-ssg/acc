import json

import arena_context_store

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
    ## The context nodes behind item: none renders as null, one is the item
    ## itself, several are a merged group. Lets a consumer of this page be
    ## tied to the data that produced it, and lets engines re-materialize
    ## live data instead of the routing-time copy.
    item_nodes*: seq[NodeId]
    ## The context nodes behind items.
    items_nodes*: seq[NodeId]

  RenderState* = seq[RenderStateItem]

proc init_render_state_item*(
  source_path: Path,
  output_path: Path,
  render: bool = false,
  item: JsonNode = newJObject(),
  items: JsonNode = newJArray(),
  key: string = "",
  parent: JsonNode = nil,
  item_nodes: seq[NodeId] = @[],
  items_nodes: seq[NodeId] = @[]
): RenderStateItem =
  result = RenderStateItem()
  result.source_path = source_path
  result.output_path = output_path
  result.render = render
  result.item = item
  result.items = items
  result.key = key
  result.parent = parent
  result.item_nodes = item_nodes
  result.items_nodes = items_nodes

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
