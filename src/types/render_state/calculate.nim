import sequtils
import sugar

import logger
import config
import types/render_state
import types/context_store
import file_list
import file_router

proc calculate_render_state*( cfg: Config, steps: seq[Step], store: ContextStore, source_files: seq[string] ): RenderState =
  let
    file_list = init_file_list( cfg, steps, source_files )

  result = @[]

  # One shared root-item copy per calculation — see RootItemCache.
  let root_cache = newRootItemCache()

  for file in file_list:
    # add, not concat: concat builds a fresh seq holding everything routed
    # so far on every file, which is quadratic in the number of pages.
    result.add(
      store.calculate_render_state_items_for( file,
        legacy_paths = cfg.legacyPaths, root_cache = root_cache )
    )

  warn "[CALCULATE_RENDER_STATE]", $result.map( ( x ) => x.output_path )
