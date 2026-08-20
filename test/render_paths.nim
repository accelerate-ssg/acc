import json, strutils, sequtils, sugar, os, sets, unittest
import glob

import logger
import config
import types/render_state
import types/render_state/file_list
import types/render_state/file_router

# ============================================================================
# File Router Tests - all rendering path combinations
# ============================================================================

suite "Static template (no matcher)":

  test "root-level template gets .html extension":
    let ctx = %* {"about": {"title": "About Us"}}
    let results = ctx.calculate_render_state_items_for("about.mustache")
    check results.len == 1
    check results[0].output_path == "about.html"

  test "root-level template without matching context key gets full context as item":
    let ctx = %* {"other": {"title": "Other"}}
    let results = ctx.calculate_render_state_items_for("about.mustache")
    check results.len == 1
    check results[0].item == ctx

  test "template with empty context":
    let ctx = %* {}
    let results = ctx.calculate_render_state_items_for("index.mustache")
    check results.len == 1
    check results[0].output_path == "index.html"
    check results[0].item == ctx


suite "Multiple file extensions":

  test "non-mustache extensions also work":
    let ctx = %* {"page": {"title": "Test"}}
    let results = ctx.calculate_render_state_items_for("page.liquid")
    check results.len == 1
    check results[0].output_path == "page.html"

  test "html extension in source":
    let ctx = %* {"page": {"title": "Test"}}
    let results = ctx.calculate_render_state_items_for("page.html")
    check results.len == 1
    check results[0].output_path == "page.html"


# ============================================================================
# File List Tests
# ============================================================================

suite "File list - blacklisting":

  setup:
    let
      temp_dir = getTempDir() / "accelerate_render_paths_test"
      source_dir = temp_dir / "src"
      destination_dir = temp_dir / "public"
      nested_dest = source_dir / "public"
      content_dir = temp_dir / "content"
      config_dir = temp_dir / ".acc"

    createDir(source_dir)
    createDir(destination_dir)
    createDir(nested_dest)
    createDir(content_dir)
    createDir(config_dir)
    writeFile(source_dir / "index.mustache", "test")
    writeFile(source_dir / "style.css", "body{}")
    writeFile(nested_dest / "old.html", "old output")

  teardown:
    removeDir(temp_dir)

  test "destination dir outside source is not blacklisted":
    let blacklist = init_blacklist(source_dir, destination_dir, content_dir)
    # Only .acc is blacklisted
    check blacklist.len == 1

  test "destination dir inside source is blacklisted":
    let blacklist = init_blacklist(source_dir, nested_dest, content_dir)
    check blacklist.len == 2

  test "config dir inside source is blacklisted":
    let inner_config = source_dir / ".config"
    createDir(inner_config)
    let blacklist = init_blacklist(source_dir, destination_dir, inner_config)
    check blacklist.len == 2
    removeDir(inner_config)


suite "File list - glob filtering":

  test "step globs are collected from extraConfig":
    let steps: seq[Step] = @[
      Step(module: "@copy", extraConfig: %*{"glob": "**/*.css"}),
      Step(module: "@mustache", extraConfig: %*{"glob": "**/*.mustache"}),
    ]
    let globs = init_step_globs(steps)
    check globs.len == 2

  test "steps without glob are skipped":
    let steps: seq[Step] = @[
      Step(module: "@yaml"),
      Step(module: "@copy", extraConfig: %*{"glob": "**/*.css"}),
    ]
    let globs = init_step_globs(steps)
    check globs.len == 1

  test "step with nil extraConfig is handled":
    let steps: seq[Step] = @[
      Step(module: "@yaml", extraConfig: nil),
    ]
    let globs = init_step_globs(steps)
    check globs.len == 0


suite "File list - raw file discovery":

  setup:
    let
      temp_dir = getTempDir() / "accelerate_raw_list_test"
      source_dir = temp_dir / "src"
      sub_dir = source_dir / "sub"

    createDir(sub_dir)
    writeFile(source_dir / "a.txt", "a")
    writeFile(source_dir / "b.nim", "b")
    writeFile(sub_dir / "c.txt", "c")

  teardown:
    removeDir(temp_dir)

  test "discovers all files recursively":
    let files = init_raw_file_list(source_dir)
    check files.len == 3

  test "paths are relative to source directory":
    let files = init_raw_file_list(source_dir)
    check "a.txt" in files
    check "b.nim" in files
    check "sub/c.txt" in files or "sub\\c.txt" in files


suite "File list - filter":

  test "filter matches only specified globs":
    let
      files = ["a.txt", "b.nim", "c.css", "d.mustache"].toHashSet
      globs = @[glob("*.mustache"), glob("*.css")]
      blacklist: seq[Glob] = @[]
      result = filter(files, globs, blacklist)
    check result.len == 2
    check "d.mustache" in result
    check "c.css" in result

  test "blacklisted files are excluded":
    let
      files = ["a.mustache", "public/old.html", "b.mustache"].toHashSet
      globs = @[glob("**/*")]
      blacklist = @[glob("public/**/*")]
      result = filter(files, globs, blacklist)
    check result.len == 2
    check "public/old.html" notin result

  test "empty globs matches nothing":
    let
      files = ["a.txt", "b.nim"].toHashSet
      globs: seq[Glob] = @[]
      blacklist: seq[Glob] = @[]
      result = filter(files, globs, blacklist)
    check result.len == 0


# ============================================================================
# Caller supplied source files
#
# The candidate file list is an input, not something the router discovers. A
# full build passes everything; a dev rebuild passes only what changed; a diff
# driven rebuild will pass whatever it considers stale. Each workflow still
# narrows that list by its own step globs.
# ============================================================================

suite "File list - caller supplied candidates":

  setup:
    let cfg = Config(
      directories: Directories(
        root: "/site",
        src: "/site/src",
        destination: "/site/public",
        config: "/site/.acc"
      )
    )

    proc render_steps(): seq[Step] =
      var step = Step()
      step.extraConfig = %* { "glob": "**/*.mustache" }
      @[step]

  test "the workflow narrows the caller's list by its step globs":
    let
      candidates = @["index.mustache", "style.css", "about.mustache"]
      result = init_file_list(cfg, render_steps(), candidates)

    check result.len == 2
    check "index.mustache" in result
    check "about.mustache" in result
    check "style.css" notin result

  test "a single changed file is a valid candidate list":
    let result = init_file_list(cfg, render_steps(), @["about.mustache"])

    check result == @["about.mustache"]

  test "a changed file the steps do not want yields nothing to render":
    let result = init_file_list(cfg, render_steps(), @["notes.txt"])

    check result.len == 0

  test "an empty candidate list renders nothing":
    let candidates: seq[string] = @[]

    check init_file_list(cfg, render_steps(), candidates).len == 0

  test "the blacklist still applies to a caller supplied list":
    # A caller must not be able to smuggle the destination directory back in.
    # The blacklist only covers directories that exist, so these are real.
    let
      temp_dir = getTempDir() / "accelerate_candidates_test"
      source_dir = temp_dir / "src"
      nested_destination = source_dir / "public"

    createDir(nested_destination)

    let
      real_cfg = Config(
        directories: Directories(
          root: temp_dir,
          src: source_dir,
          destination: nested_destination,
          config: temp_dir / ".acc"
        )
      )
      candidates = @["index.mustache", "public/stale.mustache"]
      result = init_file_list(real_cfg, render_steps(), candidates)

    check "index.mustache" in result
    check "public/stale.mustache" notin result

    removeDir(temp_dir)


suite "File list - partial directories":

  setup:
    var partial_step = Step()
    partial_step.extraConfig = %* {
      "glob": "**/*.liquid",
      "partial_directories": [ "src/partials" ]
    }

    let cfg = Config(
      directories: Directories(
        root: "/site",
        src: "/site/src",
        destination: "/site/public",
        config: "/site/.acc"
      ),
      workflows: @[
        Workflow( name: "render", steps: @[ partial_step ] )
      ]
    )

  test "a declared partial directory becomes an exclusion glob":
    check cfg.init_partial_globs().len == 1

  test "files inside a partial directory are recognised as partials":
    check cfg.is_partial("partials/head.liquid")
    check cfg.is_partial("partials/nested/menu.liquid")

  test "ordinary pages are not partials":
    check not cfg.is_partial("index.liquid")
    check not cfg.is_partial("blog/post.liquid")

  test "a config declaring no partial directories has no exclusions":
    let bare = Config(
      directories: Directories(root: "/site", src: "/site/src"),
      workflows: @[]
    )

    check bare.init_partial_globs().len == 0
    check not bare.is_partial("partials/head.liquid")
