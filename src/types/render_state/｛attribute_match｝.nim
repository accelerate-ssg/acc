import json
import strutils

import logger
import types/render_state
import node_to_string
import indifferent_iterator



proc render_attribute_match*( context: JsonNode, attribute_name: string, partial: RenderStateItem ): seq[RenderStateItem] =
  result = @[]

  for v in context.each():
    if v.kind == JObject:
      let
        attribute = node_to_string(v{attribute_name})

      if attribute != "":
        result.add( partial.init_render_state_item(
          output_path = partial.output_path & "/" & attribute.strip() & ".html",
          item = v,
          items = context
        ))
    
