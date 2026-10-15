## The `git_sha` Liquid filter: the short sha of the last commit that
## touched a file, for cache-busting asset URLs.
##
##   @import url("/assets/css/fonts.css?v={{ "src/assets/css/fonts.css" | git_sha }}");
##
## The path is a repository path, relative to the repository root like
## every path git prints, whichever directory of the repository the site
## lives in. A directory works too: its sha is the last commit touching
## anything inside it.
##
## The sha is of the last *commit*, so uncommitted edits to the file do
## not change it. And in a shallow clone every file's history ends at the
## clone's oldest commit, so files untouched since then all report that
## commit — still a valid cache key, just one that changes more often
## than the file does. Both are warned about where they can be detected.
##
## A page's output now depends on something outside the context, which
## the arena's read tracking cannot see. So each page records the files
## it looked up (`page_dependencies`), spelled as acc spells paths under
## the project root, and the render filter re-renders the page when a
## selective build changes one of them.

import std/[os, osproc, streams, strutils, tables]

import pitchfork/values

import logger

type
  GitLookup = object
    root: string
      ## The acc project root; git runs here.
    ready: bool
    prefix: string
      ## The project root's own path inside the repository ("" when the
      ## root is the repository root, "site/" when the site is a
      ## subdirectory), from `git rev-parse --show-prefix`.
    shas: Table[string, string]
      ## Repository path -> short sha, for the current build.

var
  lookup: GitLookup
  page_dependencies*: seq[string]
    ## The files the page being rendered looked up, as absolute paths
    ## under the project root. Reset by begin_page.

proc reset_git_lookup*(root: string) =
  ## Start a build: forget every sha, since commits may have landed since
  ## the last one (the dev server keeps one process across builds).
  lookup = GitLookup(root: root)

proc begin_page*() =
  page_dependencies = @[]

proc git(args: varargs[string]): tuple[output: string, exitCode: int] =
  ## Run git in the project root. Arguments go to git directly, not
  ## through a shell, so the `:(top)` pathspec needs no quoting on any
  ## platform.
  let process = startProcess("git", args = @["-C", lookup.root] & @args,
                             options = {poUsePath, poStdErrToStdOut})
  defer: process.close()
  result.output = process.outputStream.readAll()
  result.exitCode = process.waitForExit()

proc ensure_ready() =
  if lookup.ready:
    return

  let (output, code) = git("rev-parse", "--show-prefix", "--is-shallow-repository")
  if code != 0:
    raise newException(ValueError,
      "git_sha needs the site to be in a git repository, but git failed in " &
      lookup.root & ": " & output.strip)

  let lines = output.splitLines
  lookup.prefix = if lines.len > 0: lines[0].strip else: ""
  if lines.len > 1 and lines[1].strip == "true":
    warn "git_sha: the repository is a shallow clone, so files unchanged ",
      "since its oldest commit all report that commit's sha."
  lookup.ready = true

proc local_path(repo_path: string): string =
  ## A repository path spelled under the project root, the way the change
  ## set spells the files a build changed.
  normalizedPath(lookup.root / relativePath("/" & repo_path, "/" & lookup.prefix, '/'))

proc git_sha*(repo_path: string): string =
  ## The short sha of the last commit touching `repo_path`. Empty, with a
  ## warning, for a file that exists but has never been committed. Raises
  ## for a path that does not exist, or when there is no repository.
  let path = repo_path.strip.strip(trailing = false, chars = {'/'})
  if path == "":
    raise newException(ValueError, "git_sha needs a repository path, got an empty value")

  ensure_ready()

  # Recorded before the checks below, so a page that failed on a missing
  # file is re-rendered once the file appears.
  let local = local_path(path)
  page_dependencies.add(local)

  if path in lookup.shas:
    return lookup.shas[path]

  if not (local.fileExists or local.dirExists):
    raise newException(ValueError,
      "git_sha: no such file in the repository: " & path &
      " (paths are relative to the repository root)")

  # `:(top)` pins the pathspec to the repository root rather than to the
  # directory git runs in.
  let (output, code) = git("log", "-1", "--format=%h", "--", ":(top)" & path)
  if code != 0:
    raise newException(ValueError, "git_sha: git log failed for " & path &
      ": " & output.strip)

  # The sha is the last line; anything before it is a warning git wrote
  # to the merged stderr.
  let lines = output.strip.splitLines
  result = if lines.len > 0: lines[^1].strip else: ""
  if result == "":
    warn "git_sha: ", path, " has not been committed yet, so its sha renders empty."
  lookup.shas[path] = result

proc git_sha_filter(value: VMValue, args: varargs[VMValue]): VMValue =
  if args.len > 0:
    raise newException(ValueError, "git_sha takes no arguments")
  VMValue(kind: vmString, stringVal: git_sha(value.to_string))

register_filter("git_sha", git_sha_filter)
