import json
import strutils

import logger
import types/render_state
import node_to_string
import indifferent_iterator



proc getNestedValue(node: JsonNode, path: string): JsonNode =
  var current = node

  for key in path.split("."):
    if isNil(current) or current.kind != JObject:
      return nil
    current = current.getOrDefault(key)
  return current

proc render_attribute_match*( context: JsonNode, attribute_name: string, partial: RenderStateItem ): seq[RenderStateItem] =
  result = @[]

  for v in context.each():
    debug "a"
    if v.kind == JObject:
      debug "b"
      let nestedValue = getNestedValue(v, attribute_name)

      if nestedValue != nil:
        let
          attribute = node_to_string(nestedValue)

        if attribute != "":
          result.add( partial.init_render_state_item(
            output_path = partial.output_path & "/" & attribute.strip() & ".html",
            item = v,
            items = context
          ))
      
