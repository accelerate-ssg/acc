## A path relative to a site directory is written with `/` on every
## platform: it is matched against the globs in acc.yaml, split into routes
## and context keys, and turned into URLs, all of which assume `/`. Absolute
## paths stay native, since only the OS reads them.

import std/os
when defined(windows): import std/strutils
from glob as glob_lib import Glob

export Glob

proc portable*(path: string): string =
  when defined(windows): path.replace('\\', '/') else: path

proc relative_to*(path, base: string): string =
  path.relativePath(base).portable

proc normalized(path: string): string =
  ## The glob library collapses `./` and `//` in patterns and paths itself,
  ## but only on POSIX.
  when defined(windows): path.normalizedPath.portable else: path

proc glob*(pattern: string): Glob =
  ## The glob library defaults to DOS mode on Windows, where a pattern only
  ## matches `\` paths and ignores case.
  glob_lib.glob(pattern.normalized, isDos = false, ignoreCase = false)

proc matches*(path: string, pattern: Glob): bool =
  glob_lib.matches(path.normalized, pattern)

proc matches*(path, pattern: string): bool =
  path.matches(glob(pattern))

proc is_hidden(name: string): bool =
  name.len >= 2 and name[0] == '.' and name != ".."

iterator walk_relative*(directory: string): string =
  ## Every file below `directory`, relative to it. Dot-entries are skipped
  ## and directory links not followed, on Windows too, where the OS calls a
  ## file hidden by attribute and `.git` would otherwise be walked.
  var pending = @[""]
  while pending.len > 0:
    let relative = pending.pop
    for kind, name in walk_dir(directory / relative, relative = true):
      if name.is_hidden:
        continue
      let path = if relative.len == 0: name else: relative & "/" & name
      case kind
      of pcFile, pcLinkToFile: yield path
      of pcDir: pending.add(path)
      of pcLinkToDir: discard



when isMainModule:
  import std/[unittest, algorithm, sequtils]

  suite "portable paths":
    test "relative paths use / below nested directories":
      check (get_temp_dir() / "a" / "b" / "c.txt").relative_to(get_temp_dir()) == "a/b/c.txt"

    test "a glob matches / paths and is case sensitive":
      check "posts/a.mustache".matches(glob("**/*.mustache"))
      check not "posts/a.MUSTACHE".matches(glob("**/*.mustache"))

    test "./ and // are collapsed in patterns and paths":
      check "assets/css/main.css".matches(glob("./assets/**/*.css"))
      check "assets/css/main.css".matches(glob("assets//css/*.css"))
      check "./assets//main.css".matches(glob("assets/*.css"))

    when defined(windows):
      test "a native path is matched as its portable form":
        check portable(r"posts\a.mustache") == "posts/a.mustache"
        check r"posts\a.mustache".matches(glob("posts/*.mustache"))

  suite "walk_relative":
    setup:
      let root = get_temp_dir() / "acc_portable_path_test"
      create_dir(root / "posts")
      create_dir(root / ".git")
      write_file(root / "index.mustache", "")
      write_file(root / "posts" / "a.mustache", "")
      write_file(root / ".hidden", "")
      write_file(root / ".git" / "HEAD", "")

    teardown:
      remove_dir(root)

    test "yields nested files with / and skips dot-entries":
      check to_seq(walk_relative(root)).sorted == @["index.mustache", "posts/a.mustache"]
