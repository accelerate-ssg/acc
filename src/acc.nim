import json
import std/[times, options]

import global_state
import logger
import config
import change_set
import action/[build,test,clean,run,dev_server,init,run_workflow]
import action/internal_functions/yaml_loader
import types/render_state/file_list
import plugins/registry
import plugins/mustache_engine
import plugins/liquid_engine

proc ctrl_c_handler() {.noconv.} =
  notice "Force quit."
  quit 0

proc showMe(aspect: string) =
  case aspect:
  of "config":
    echo pretty(%state.config)
  of "files":
    # The leaf named "build" is the one whose file list is interesting.
    # Taking the first leaf unconditionally picked whatever happened to be
    # declared earliest — a content sync or preprocess workflow, whose steps
    # carry no glob — and reported an empty list for a config that routes
    # hundreds of pages. Fall back to the first leaf only if there is no
    # "build".
    var steps: seq[Step] = @[]
    for wf in state.config.workflows:
      if wf.isLeaf and wf.name == "build":
        steps = wf.steps
        break
    if steps.len == 0:
      for wf in state.config.workflows:
        if wf.isLeaf:
          steps = wf.steps
          break
    if steps.len > 0:
      let files = init_file_list(state.config, steps, init_source_files(state.config))
      echo pretty(%*files)
    else:
      echo "[]"
  else:
    echo "Unknown --show-me aspect: \"" & aspect & "\""
    echo "Available: config, files"
  quit(0)

proc main() =
  setControlCHook( ctrl_c_handler )
  init_logger()

  state.config = parseCliArgs()
  set_log_level( logger.LogLevel(ord(state.config.logLevel)) )

  # Register built-in template engines
  registerEngine("mustache", mustache_engine.plugin)
  registerEngine("liquid", liquid_engine.plugin)

  # Register content loaders on the context's arena
  registerContentLoaders()

  if state.config.showMe != "":
    showMe(state.config.showMe)

  initScriptRunners()

  case state.config.action:
  of ActionDev: state.dev_server()
  of ActionBuild:
    let stamp = getTime()

    # Cached by default: pick up where the last build left off, so the
    # loader merges instead of rebuilding, selective builds know what the
    # previous build read, and mtime has a baseline.
    let cached_stamp = state.load_context_cache()

    case state.config.changeStrategy
    of "", "full":
      state.build()
    of "git":
      state.build(gitChangeSet(state.config, state.config.changeSince))
    of "mtime":
      if cached_stamp.isNone:
        error "--using=mtime compares against a cached previous build, and there is none yet."
        quit(1)
      state.build(mtimeChangeSet(state.config, cached_stamp.get))
    else:
      error "Unknown change strategy: ", state.config.changeStrategy,
        " (expected full, git or mtime)"
      quit(1)

    state.save_context_cache(stamp)
  of ActionTest: state.test()
  of ActionClean: state.clean()
  of ActionRun: state.run()
  of ActionInit: state.init()
  of ActionNone: discard

  quit(0)

when isMainModule:
  main()
