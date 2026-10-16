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

const SHA_LENGTH* = 7

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

proc git_sha*(repo_path: string): string =
  ## The short sha of `repo_path` in the checked-out commit. Empty, with
  ## a warning, for a file that exists but is not in that commit. Raises
  ## for a path that does not exist, or when there is no repository.
  let path = repo_path.strip.replace('\\', '/').strip(trailing = false, chars = {'/'})
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

  # `HEAD:<path>` names the path from the repository root, not from the
  # directory git runs in. --verify --quiet prints nothing and exits 1
  # when the path is not in HEAD (or there is no HEAD yet).
  let (output, code) = git("rev-parse", "--verify", "--quiet", "HEAD:" & path)
  let sha = output.strip
  if code == 0 and sha.len >= SHA_LENGTH:
    result = sha[0 ..< SHA_LENGTH]
  else:
    warn "git_sha: ", path, " is not in the checked-out commit, so its sha renders empty."
    result = ""
  lookup.shas[path] = result

proc git_sha_filter(value: VMValue, args: varargs[VMValue]): VMValue =
  if args.len > 0:
    raise newException(ValueError, "git_sha takes no arguments")
  VMValue(kind: vmString, stringVal: git_sha(value.to_string))

register_filter("git_sha", git_sha_filter)
