## Tests for change-set strategies and the classifier that turns a
## change set into a build decision.

import std/[unittest, os, osproc, times, json, sequtils, strutils]

import config
import change_set

proc scratchRepo(): string =
  ## A throwaway git repository with a site-shaped tree and one commit.
  result = getTempDir() / "acc_change_set_test"
  removeDir(result)
  createDir(result / "src" / "partials")
  createDir(result / "content")
  writeFile(result / "src" / "index.mustache", "one")
  writeFile(result / "src" / "about.mustache", "two")
  writeFile(result / "src" / "partials" / "head.mustache", "head")
  writeFile(result / "content" / "site.yaml", "name: x")
  writeFile(result / "acc.yaml", "manifest_version: v1")
  for cmd in [
    "git -C " & result & " init -q",
    "git -C " & result & " add .",
    "git -C " & result & " -c user.email=t@t -c user.name=t commit -qm base",
  ]:
    doAssert execCmd(cmd) == 0

proc siteConfig(root: string): Config =
  result = Config()
  result.directories.root = root
  result.directories.src = root / "src"
  result.directories.content = root / "content"
  # A step declaring the partials directory, so is_partial works.
  result.workflows = @[Workflow(
    name: "build",
    steps: @[Step(
      module: "@mustache",
      extraConfig: %*{"partial_directories": ["src/partials"]},
    )],
  )]

suite "Change sets - git strategy":
  test "clean tree yields an empty change set":
    let root = scratchRepo()
    let cs = gitChangeSet(siteConfig(root))
    check cs.changed.len == 0
    check cs.removed.len == 0
    check not cs.full

  test "modified, untracked and deleted files are reported":
    let root = scratchRepo()
    writeFile(root / "src" / "index.mustache", "changed")
    writeFile(root / "src" / "fresh.mustache", "new page")
    removeFile(root / "src" / "about.mustache")

    let cs = gitChangeSet(siteConfig(root))
    check (root / "src" / "index.mustache") in cs.changed
    check (root / "src" / "fresh.mustache") in cs.changed
    check (root / "src" / "about.mustache") in cs.removed

  test "renames report the old name removed and the new one changed":
    let root = scratchRepo()
    doAssert execCmd("git -C " & root &
      " mv src/about.mustache src/about-us.mustache") == 0
    let cs = gitChangeSet(siteConfig(root))
    check (root / "src" / "about.mustache") in cs.removed
    check (root / "src" / "about-us.mustache") in cs.changed

  test "an unknown ref raises":
    let root = scratchRepo()
    expect ValueError:
      discard gitChangeSet(siteConfig(root), "no-such-ref")

suite "Change sets - mtime strategy":
  test "only files newer than the stamp are reported":
    let root = scratchRepo()
    let stamp = getTime()
    sleep(1100)  # mtime granularity
    writeFile(root / "src" / "index.mustache", "newer")
    let cs = mtimeChangeSet(siteConfig(root), stamp)
    check (root / "src" / "index.mustache") in cs.changed
    check not cs.changed.anyIt(it.endsWith("about.mustache"))

suite "Change sets - classifier":
  let root = scratchRepo()
  let cfg = siteConfig(root)

  test "a full set means a full build":
    check classify(cfg, fullChangeSet()).full

  test "an empty set means nothing to do":
    let decision = classify(cfg, ChangeSet())
    check not decision.full
    check decision.sources.len == 0

  test "template changes narrow to those sources":
    let decision = classify(cfg, ChangeSet(changed: @[
      root / "src" / "index.mustache",
      root / "src" / "about.mustache",
    ]))
    check not decision.full
    check decision.sources == @["index.mustache", "about.mustache"]

  test "a partial change rebuilds everything":
    let decision = classify(cfg, ChangeSet(changed: @[
      root / "src" / "partials" / "head.mustache",
    ]))
    check decision.full
    check "partial" in decision.reason

  test "a content change is selective":
    let decision = classify(cfg, ChangeSet(changed: @[
      root / "content" / "site.yaml",
    ]))
    check not decision.full
    check decision.content == @[root / "content" / "site.yaml"]
    check decision.sources.len == 0

  test "a project file change rebuilds everything":
    check classify(cfg, ChangeSet(changed: @[root / "acc.yaml"])).full

  test "removed sources are reported but do not force a full build":
    let decision = classify(cfg, ChangeSet(
      changed: @[root / "src" / "index.mustache"],
      removed: @[root / "src" / "about.mustache"],
    ))
    check not decision.full
    check decision.sources == @["index.mustache"]
    check decision.removed_sources == @["about.mustache"]

  test "a removed content file is unloaded selectively":
    let decision = classify(cfg, ChangeSet(removed: @[root / "content" / "site.yaml"]))
    check not decision.full
    check decision.removed_content == @[root / "content" / "site.yaml"]
