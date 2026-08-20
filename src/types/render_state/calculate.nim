import json
import sequtils
import sugar

import logger
import config
import types/render_state
import file_list
import file_router

proc calculate_render_state*( cfg: Config, steps: seq[Step], context: JsonNode, source_files: seq[string] ): RenderState =
  let
    file_list = init_file_list( cfg, steps, source_files )

  result = @[]

  for file in file_list:
    result = result.concat(
      context.calculate_render_state_items_for( file )
    )

  warn "[CALCULATE_RENDER_STATE]", $result.map( ( x ) => x.output_path )
