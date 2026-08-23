import std/sets

import config
import types/render_state
import types/context_store
export render_state
export context_store

type
  ContextKeyFormatError* = object of ValueError
  ContextNodeAssignmentError* = object of ValueError

  RenderFilter* = object
    ## Which pages the engines should render this build.
    all*: bool
      ## Everything — full builds, and selective builds with nothing to
      ## narrow against.
    pages*: HashSet[string]
      ## Otherwise: output paths to render.
    modules_all*: HashSet[string]
      ## Engine modules whose step consumer is stale as a whole — they
      ## render every page of theirs. This is how an engine that still
      ## reads the whole context (mustache) stays correct under a
      ## selective build.

  State* = ref object
    context*: ContextStore
    config*: Config
    render_state*: RenderState
    ## Candidate source files for this build, relative to the source directory.
    ## Routing always runs over all of them; what actually renders is decided
    ## by render_filter.
    source_files*: seq[string]
    current_step*: Step
    current_workflow*: Workflow

    # ── Selective rendering ──
    ## Content files this build reloaded (absolute). Their loaders' fresh
    ## write records are what the render filter is computed from.
    changed_content*: seq[string]
    ## Templates this build changed (source-relative). All their pages render.
    changed_sources*: seq[string]
    ## Whether a previous build's records exist to narrow against — from a
    ## loaded cache or an earlier build in this process.
    has_previous_build*: bool
    ## Computed lazily at the first engine step; see render_filter.nim.
    render_filter*: RenderFilter
    render_filter_ready*: bool

    # ── Build outcome ──
    ## (source_path, output_path) of every page the route calculation
    ## produced this build, across workflows.
    routed_outputs*: seq[tuple[source: string, output: string]]
    ## Output paths written this build, and outputs unlinked because their
    ## page ceased to exist — together, the deploy manifest.
    rendered_outputs*: seq[string]
    removed_outputs*: seq[string]

proc should_render*(state: State, item: RenderStateItem, module: string): bool =
  ## Whether an engine should render this page under the current filter.
  state.render_filter.all or
    module in state.render_filter.modules_all or
    item.output_path in state.render_filter.pages
