import json
import sequtils
import sugar

import logger
import types/config
import types/render_state
import file_list
import file_router

proc calculate_render_state*( config: Config, context: JsonNode ): RenderState =
  let
    file_list = init_file_list( config )

  result = @[]

  for file in file_list:
    result = result.concat(
      context.calculate_render_state_items_for( file )
    )

  warn "[CALCULATE_RENDER_STATE]", $result.map( ( x ) => x.output_path )
