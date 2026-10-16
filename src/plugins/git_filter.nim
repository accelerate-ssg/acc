## The `git_sha` Liquid filter: a file's short sha in the checked-out
## commit, for cache-busting asset URLs.
##
##   @import url("/assets/css/fonts.css?v={{ "src/assets/css/fonts.css" | git_sha }}");
##
## The path is a repository path, relative to the repository root like
## every path git prints, whichever directory of the repository the site
## lives in. A directory works too, giving its tree's sha.
##
## The sha is the file's own object id at HEAD (`git rev-parse
## HEAD:<path>`): it changes exactly when a commit changes the file's
## content, and it is read from the checked-out tree alone, so a shallow
## clone gives the same answer as a full one. Uncommitted edits do not
## change it. It is always the first SHA_LENGTH characters of the full
## id rather than git's `--short`, whose length grows with the number of
## objects in the repository and so would differ between a shallow and a
## full clone of the same commit.
##
## Dependency tracking goes through the arena like any content. Each
## file's sha is a string node in the context store's detached `files`
## object, written by that file's own consumer, `@file <absolute path>`.
## The filter reads the node while the page's consumer is active, so the
## page records the read. A selective build refreshes the shas of the
## files it changed (refresh_git_files) before the render filter asks the
## arena what those writers invalidated; a sha that did not change is not
## written, so its readers stay valid.

# Imported by the Liquid engine for the filter it registers, not for a symbol.
{.used.}

import std/[os, osproc, streams, strutils, tables]

import pitchfork/values
import arena_context_store

import logger
import types/context_store

type
  GitLookup = object
    root: string
      ## The acc project root; git runs here.
    store: ContextStore
    ready: bool
    prefix: string
      ## The project root's own path inside the repository ("" when the
      ## root is the repository root, "site/" when the site is a
      ## subdirectory), from `git rev-parse --show-prefix`.
    shas: Table[string, string]
      ## Absolute path -> short sha, resolved once per build.

const SHA_LENGTH* = 7

var lookup: GitLookup

proc reset_git_lookup*(store: ContextStore, root: string) =
  ## Start a build: forget every resolved sha, since commits may have
  ## landed since the last one (the dev server keeps one process across
  ## builds). The arena keeps the previous values to compare against.
  lookup = GitLookup(root: root, store: store)

proc file_label*(path: string): string =
  ## The consumer that writes a file's sha.
  "@file " & path

proc git(args: varargs[string]): tuple[output: string, exitCode: int] =
  ## Run git in the project root. Arguments go to git directly, not
  ## through a shell, so no argument needs quoting on any platform.
  let process = startProcess("git", args = @["-C", lookup.root] & @args,
                             options = {poUsePath, poStdErrToStdOut})
  defer: process.close()
  result.output = process.outputStream.readAll()
  result.exitCode = process.waitForExit()

proc ensure_ready() =
  if lookup.ready:
    return

  let (output, code) = git("rev-parse", "--show-prefix")
  if code != 0:
    raise newException(ValueError,
      "git_sha needs the site to be in a git repository, but git failed in " &
      lookup.root & ": " & output.strip)

  lookup.prefix = output.strip
  lookup.ready = true

proc local_path(repo_path: string): string =
  ## A repository path spelled under the project root, the way the change
  ## set spells the files a build changed.
  normalizedPath(lookup.root / relativePath("/" & repo_path, "/" & lookup.prefix, '/'))

proc repo_path_of(local: string): string =
  ## The inverse: an absolute path under the project root as a repository
  ## path.
  normalizedPath(lookup.prefix & relativePath(local, lookup.root, '/')).replace('\\', '/')

proc store_sha(local, sha: string) =
  ## Write the sha into the arena under the file's own consumer — but only
  ## when it differs from what is there, so an unchanged sha invalidates
  ## nothing.
  let ctx = lookup.store
  var existing = InvalidNodeId
  var previous = ""
  ctx.untracked:
    existing = ctx.arena.objGet(ctx.files, local)
    if existing != InvalidNodeId and ctx.arena.kind(existing) == nkString:
      previous = ctx.arena.getStr(existing)

  if existing != InvalidNodeId and previous == sha:
    # Nothing to write, but the writer's records from the last change are
    # still in the log, and invalidatedBy would report those again. A
    # content reload clears its writer the same way before it merges.
    if ctx.known_consumer(file_label(local)):
      ctx.arena.clearTracking(ctx.consumer(file_label(local)))
    return

  discard ctx.track(file_label(local))
  try:
    if existing != InvalidNodeId and ctx.arena.kind(existing) == nkString:
      ctx.arena.setStr(existing, sha)
    else:
      ctx.arena.objSet(ctx.files, local, ctx.arena.newStr(sha))
  finally:
    ctx.untrack()

proc resolve(local, repo_path: string): string =
  ## The file's sha for this build, from git the first time it is asked
  ## for and stored in the arena. Empty for a path that does not exist or
  ## is not in the checked-out commit.
  if local in lookup.shas:
    return lookup.shas[local]

  if local.fileExists or local.dirExists:
    # `HEAD:<path>` names the path from the repository root, not from the
    # directory git runs in. --verify --quiet prints nothing and exits 1
    # when the path is not in HEAD (or there is no HEAD yet).
    let (output, code) = git("rev-parse", "--verify", "--quiet", "HEAD:" & repo_path)
    let sha = output.strip
    if code == 0 and sha.len >= SHA_LENGTH:
      result = sha[0 ..< SHA_LENGTH]
    else:
      warn "git_sha: ", repo_path, " is not in the checked-out commit, so its sha renders empty."

  lookup.shas[local] = result
  store_sha(local, result)

proc refresh_git_files*(paths: openArray[string]) =
  ## Re-resolve the shas of files a selective build changed or removed,
  ## before the render filter queries what their writers invalidated.
  ## Only files some page has looked up have a writer, so the rest cost
  ## nothing.
  for path in paths:
    let local = normalizedPath(path)
    if not lookup.store.known_consumer(file_label(local)):
      continue
    try:
      ensure_ready()
    except ValueError:
      # No repository any more: the pages reading these shas fail when
      # they render, with the reason.
      return
    discard resolve(local, repo_path_of(local))

proc git_sha*(repo_path: string): string =
  ## The short sha of `repo_path` in the checked-out commit, read from the
  ## arena so the active consumer (the page) records the dependency.
  ## Empty, with a warning, for a file that exists but is not in that
  ## commit. Raises for a path that does not exist, or when there is no
  ## repository.
  let path = repo_path.strip.replace('\\', '/').strip(trailing = false, chars = {'/'})
  if path == "":
    raise newException(ValueError, "git_sha needs a repository path, got an empty value")

  ensure_ready()
  let local = local_path(path)
  discard resolve(local, path)

  # Stored even for a missing file, so the page has a read to invalidate
  # once the file appears.
  let ctx = lookup.store
  result = ctx.arena.getStr(ctx.arena.objGet(ctx.files, local))

  if not (local.fileExists or local.dirExists):
    raise newException(ValueError,
      "git_sha: no such file in the repository: " & path &
      " (paths are relative to the repository root)")

proc git_sha_filter(value: VMValue, args: varargs[VMValue]): VMValue =
  if args.len > 0:
    raise newException(ValueError, "git_sha takes no arguments")
  VMValue(kind: vmString, stringVal: git_sha(value.to_string))

register_filter("git_sha", git_sha_filter)
