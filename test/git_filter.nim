## Tests for the git_sha Liquid filter and the file dependencies it
## records for selective builds.

import std/[unittest, os, osproc, strutils, json, tables, times, options]

import pitchfork/liquid_lib
import plugins/git_filter
import types/context_store

proc run(command: string): string =
  let (output, code) = execCmdEx(command)
  doAssert code == 0, command & ": " & output
  output.strip

proc commit(repo, message: string) =
  discard run("git -C " & repo & " add -A")
  discard run("git -C " & repo & " -c user.email=t@t -c user.name=t commit -qm " &
              quoteShell(message))

proc sha_of(repo, path: string): string =
  run("git -C " & repo & " log -1 --format=%h -- " & quoteShell(path))

proc scratchRepo(): string =
  ## Two commits: fonts.css in the first, main.css in the second, so the
  ## two files have different shas and neither is just HEAD's.
  result = getTempDir() / "acc_git_filter_test"
  removeDir(result)
  createDir(result / "site" / "src" / "assets")
  createDir(result / "shared")
  discard run("git -C " & getTempDir() & " init -q " & result)
  writeFile(result / "site" / "src" / "assets" / "fonts.css", "fonts")
  writeFile(result / "shared" / "logo.svg", "<svg/>")
  commit(result, "fonts")
  writeFile(result / "site" / "src" / "assets" / "main.css", "main")
  commit(result, "main")

suite "git_sha":
  setup:
    let repo = scratchRepo()
    reset_git_lookup(repo)
    begin_page()

  test "a file reports the last commit touching it, not HEAD":
    check git_sha("site/src/assets/fonts.css") == sha_of(repo, "site/src/assets/fonts.css")
    check git_sha("site/src/assets/fonts.css") != sha_of(repo, ".")
    check git_sha("site/src/assets/main.css") == sha_of(repo, ".")

  test "the filter renders the sha in a Liquid template":
    let output = render("""{{ "site/src/assets/fonts.css" | git_sha }}""", newJObject())
    check output == sha_of(repo, "site/src/assets/fonts.css")

  test "a leading slash is accepted":
    check git_sha("/site/src/assets/fonts.css") == sha_of(repo, "site/src/assets/fonts.css")

  test "a directory reports the last commit inside it":
    check git_sha("site/src/assets") == sha_of(repo, "site/src/assets/main.css")

  test "a new commit is seen after a reset":
    let before = git_sha("site/src/assets/fonts.css")
    writeFile(repo / "site" / "src" / "assets" / "fonts.css", "fonts v2")
    commit(repo, "fonts v2")
    # Cached within a build...
    check git_sha("site/src/assets/fonts.css") == before
    # ...fresh in the next one.
    reset_git_lookup(repo)
    check git_sha("site/src/assets/fonts.css") == sha_of(repo, "site/src/assets/fonts.css")
    check git_sha("site/src/assets/fonts.css") != before

  test "an uncommitted file renders empty instead of failing":
    writeFile(repo / "site" / "src" / "assets" / "new.css", "new")
    check git_sha("site/src/assets/new.css") == ""

  test "a missing file fails the page":
    expect ValueError:
      discard git_sha("site/src/assets/typo.css")

  test "an empty path fails the page":
    expect ValueError:
      discard render("""{{ undefined_variable | git_sha }}""", newJObject())

  test "arguments are rejected":
    expect ValueError:
      discard render("""{{ "site/src/assets/fonts.css" | git_sha: 8 }}""", newJObject())

  test "outside a repository the page fails":
    let outside = getTempDir() / "acc_git_filter_not_a_repo"
    createDir(outside)
    writeFile(outside / "a.css", "a")
    reset_git_lookup(outside)
    # GIT_CEILING_DIRECTORIES stops git finding a repository the temp
    # directory itself might sit in.
    putEnv("GIT_CEILING_DIRECTORIES", getTempDir())
    defer: delEnv("GIT_CEILING_DIRECTORIES")
    expect ValueError:
      discard git_sha("a.css")

suite "git_sha dependencies":
  setup:
    let repo = scratchRepo()
    begin_page()

  test "paths are recorded under the project root":
    reset_git_lookup(repo)
    discard git_sha("site/src/assets/fonts.css")
    check page_dependencies == @[normalizedPath(repo / "site" / "src" / "assets" / "fonts.css")]

  test "a site in a subdirectory still takes repository paths":
    let root = repo / "site"
    reset_git_lookup(root)
    check git_sha("site/src/assets/fonts.css") == sha_of(repo, "site/src/assets/fonts.css")
    check git_sha("shared/logo.svg") == sha_of(repo, "shared/logo.svg")
    # Spelled the way the change set spells files under the root.
    check page_dependencies == @[
      normalizedPath(root / "src" / "assets" / "fonts.css"),
      normalizedPath(repo / "shared" / "logo.svg"),
    ]

  test "a lookup that fails is still recorded":
    reset_git_lookup(repo)
    expect ValueError:
      discard git_sha("site/src/assets/typo.css")
    check page_dependencies.len == 1

  test "begin_page starts a fresh list":
    reset_git_lookup(repo)
    discard git_sha("site/src/assets/fonts.css")
    begin_page()
    check page_dependencies.len == 0

  test "dependencies survive the context cache":
    let store = newContextStore()
    store.file_dependencies["assets/main.css.html"] = @["/site/src/assets/fonts.css"]
    let cache = repo / "context.cache"
    store.saveCache(cache, getTime())
    let loaded = loadCache(cache)
    check loaded.isSome
    check loaded.get.store.file_dependencies ==
      {"assets/main.css.html": @["/site/src/assets/fonts.css"]}.toTable
