## Change sets: what a build should consider changed, and where such
## knowledge comes from.
##
## The build stage itself is source-agnostic — it processes the files the
## caller names. The strategies here are the callers' ways of finding out:
##
##   full    everything under the source tree; no baseline needed
##   git     the difference between a ref and the working tree, including
##           untracked files — the production build server's view, and
##           `acc build --using=git` locally
##   mtime   files newer than a timestamp — meaningful once a build can
##           load persisted state carrying the previous build's stamp
##
## The dev server is not a strategy: its file watcher pushes events, from
## which it assembles ChangeSets directly.
##
## classify() turns a change set into a build decision, shared by every
## consumer so CLI builds and dev rebuilds treat changes identically.

import std/[os, osproc, strutils, times]

import logger
import config
import types/render_state/file_list

type
  ChangeSet* = object
    ## Paths are absolute. `full` means there is no usable baseline and
    ## everything should be processed.
    full*: bool
    changed*: seq[string]
    removed*: seq[string]

  BuildDecision* = object
    ## What a change set means for a build.
    full*: bool
      ## Render everything: a config or partial change — anything whose
      ## effect the dependency tracking cannot see.
    reason*: string
      ## Why everything, when full is set.
    sources*: seq[string]
      ## Changed templates, source-relative: all their pages render.
    content*: seq[string]
      ## Changed content files, absolute: their loaders' write records
      ## decide which pages render.
    removed_content*: seq[string]
      ## Removed content files, absolute: unloaded before the build so
      ## their readers invalidate like any other change.
    removed_sources*: seq[string]
      ## Removed templates, source-relative: their pages vanish from the
      ## route set, and route-set diffing unlinks the outputs.

proc fullChangeSet*(): ChangeSet =
  ChangeSet(full: true)

proc gitChangeSet*(cfg: Config, since: string = "HEAD"): ChangeSet =
  ## Everything git reports as different between `since` and the working
  ## tree, plus untracked files. Runs in the project root; a repository
  ## is required.
  let root = cfg.directories.root

  let (diffOut, diffCode) = execCmdEx(
    "git -C " & quoteShell(root) & " diff --name-status -z -M " & quoteShell(since))
  if diffCode != 0:
    raise newException(ValueError,
      "git diff against '" & since & "' failed in " & root & ": " & diffOut.strip)

  var tokens = diffOut.split('\0')
  var i = 0
  while i < tokens.len:
    let status = tokens[i]
    if status.len == 0:
      inc i
      continue
    case status[0]
    of 'R', 'C':
      # Two paths follow: the old and the new name.
      if i + 2 < tokens.len:
        if status[0] == 'R':
          result.removed.add(root / tokens[i + 1])
        result.changed.add(root / tokens[i + 2])
      i += 3
    of 'D':
      if i + 1 < tokens.len:
        result.removed.add(root / tokens[i + 1])
      i += 2
    else:
      # A, M, T and friends: one path follows.
      if i + 1 < tokens.len:
        result.changed.add(root / tokens[i + 1])
      i += 2

  let (untrackedOut, untrackedCode) = execCmdEx(
    "git -C " & quoteShell(root) & " ls-files --others --exclude-standard -z")
  if untrackedCode == 0:
    for path in untrackedOut.split('\0'):
      if path.len > 0:
        result.changed.add(root / path)

proc mtimeChangeSet*(cfg: Config, since: Time): ChangeSet =
  ## Files under src and content modified after `since`. Removals cannot
  ## be seen this way — a manifest from persisted state will carry them.
  for dir in [cfg.directories.src, cfg.directories.content]:
    if dir != "" and dir.dirExists:
      for path in walkDirRec(dir):
        if path.getLastModificationTime > since:
          result.changed.add(path)

proc classify*(cfg: Config, change_set: ChangeSet): BuildDecision =
  ## Decide what a change set means. Template and content changes are
  ## selective — the render filter narrows them to pages. Only changes
  ## the dependency tracking cannot see (partials, config, anything else
  ## in the project) render everything.
  if change_set.full:
    return BuildDecision(full: true, reason: "full build requested")

  if change_set.changed.len == 0 and change_set.removed.len == 0:
    return BuildDecision(full: false)

  let
    src = cfg.directories.src
    content = cfg.directories.content

  for path in change_set.changed:
    if src != "" and path.isRelativeTo(src):
      let relative = path.relativePath(src)
      if cfg.is_partial(relative):
        return BuildDecision(full: true,
          reason: "partial changed: " & relative)
      result.sources.add(relative)
    elif content != "" and path.isRelativeTo(content):
      result.content.add(path)
    else:
      # Config, scripts, or anything else in the project.
      return BuildDecision(full: true,
        reason: "project file changed: " & path.extractFilename)

  for path in change_set.removed:
    if src != "" and path.isRelativeTo(src):
      result.removed_sources.add(path.relativePath(src))
    elif content != "" and path.isRelativeTo(content):
      result.removed_content.add(path)
    else:
      return BuildDecision(full: true,
        reason: "removed: " & path.extractFilename)
