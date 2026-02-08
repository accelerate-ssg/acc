import os
import json
import strutils

import types/render_state



proc render_key_match*( context: JsonNode, partial: RenderStateItem ): seq[RenderStateItem] =
  result = @[]

  if context.kind == JArray:
    var
      index = 0
    for item in context:
      result.add( partial.init_render_state_item(
        output_path = partial.output_path / $index & ".html",
        item = item,
        items = context
      ))
      index+=1
  elif context.kind == JObject:
    for key in context.keys:
      result.add( partial.init_render_state_item(
        output_path = partial.output_path / key.strip() & ".html",
        item = context{key},
        items = context
      ))
