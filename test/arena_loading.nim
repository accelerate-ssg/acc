## Tests for content loading into the arena-backed context: the YAML
## LoadProc, origin tagging, NodeId binding, and origin chaining when
## the markdown step rewrites loaded leaves.

import std/[unittest, json]

import types/context_store
import action/internal_functions/yaml_loader
import arena_context_store

suite "Arena loading - yamlLoad":
  test "single-document YAML loads as its node":
    var ctx = newContextStore()
    let node = yamlLoad(ctx.arena, "title: Home\ncount: 3\n", "content/index.yaml")
    check ctx.arena.kind(node) == nkObject
    check ctx.arena.getStr(ctx.arena.objGet(node, "title")) == "Home"
    check ctx.arena.getInt(ctx.arena.objGet(node, "count")) == 3

  test "multi-document YAML loads as an array":
    var ctx = newContextStore()
    let node = yamlLoad(ctx.arena, "---\na: 1\n---\nb: 2\n", "content/multi.yaml")
    check ctx.arena.kind(node) == nkArray
    check ctx.arena.arrLen(node) == 2

  test "JSON content parses through the YAML loader":
    var ctx = newContextStore()
    let node = yamlLoad(ctx.arena, """{"name": "from json", "list": [1, 2]}""", "content/data.json")
    check ctx.arena.getStr(ctx.arena.objGet(node, "name")) == "from json"
    check ctx.arena.arrLen(ctx.arena.objGet(node, "list")) == 2

  test "loaded nodes carry the file's origin":
    var ctx = newContextStore()
    let node = yamlLoad(ctx.arena, "title: Home\nnested:\n  deep: x\n", "content/index.yaml")
    let tagged = ctx.arena.nodesFrom("content/index.yaml")
    check node in tagged
    check ctx.arena.objGet(node, "title") in tagged
    check ctx.arena.objGet(ctx.arena.objGet(node, "nested"), "deep") in tagged
    let origin = ctx.arena.getOrigin(ctx.arena.getNodeOrigin(node))
    check origin.format == sfYaml

  test "two files stay separately attributed":
    var ctx = newContextStore()
    let a = yamlLoad(ctx.arena, "x: 1\n", "content/a.yaml")
    let b = yamlLoad(ctx.arena, "y: 2\n", "content/b.yaml")
    check a in ctx.arena.nodesFrom("content/a.yaml")
    check a notin ctx.arena.nodesFrom("content/b.yaml")
    check b in ctx.arena.nodesFrom("content/b.yaml")

suite "Arena loading - bindPath":
  test "binds a loaded subtree at a key path":
    var ctx = newContextStore()
    let node = yamlLoad(ctx.arena, "title: Post\n", "content/posts/first.yaml")
    ctx.bindPath(["posts", "first"], node)
    check ctx.getPath(["posts", "first", "title"]) == %"Post"
    # The bound node is the loaded node itself, not a copy.
    check ctx.arena.objGet(ctx.arena.objGet(ctx.root, "posts"), "first") == node

  test "intermediates created by binding are untagged":
    var ctx = newContextStore()
    let node = yamlLoad(ctx.arena, "v: 1\n", "content/deep.yaml")
    ctx.bindPath(["a", "b", "leaf"], node)
    let a = ctx.arena.objGet(ctx.root, "a")
    check ctx.arena.getNodeOrigin(a) == InvalidOriginId
    check a notin ctx.arena.nodesFrom("content/deep.yaml")

  test "rebinding replaces the subtree like a reload does":
    var ctx = newContextStore()
    let first = yamlLoad(ctx.arena, "v: 1\n", "content/f.yaml")
    ctx.bindPath(["f"], first)
    let second = yamlLoad(ctx.arena, "v: 2\n", "content/f.yaml")
    ctx.bindPath(["f"], second)
    check ctx.getPath(["f", "v"]) == %2

suite "Arena loading - origin chaining":
  test "a computed rewrite chains back to the loaded origin":
    var ctx = newContextStore()
    # Load content, bind it, then rewrite a leaf the way @markdown does.
    let node = yamlLoad(ctx.arena, "body-markdown: '[//]: # comment'\n", "content/page.yaml")
    ctx.bindPath(["page"], node)

    let computed = ctx.arena.registerOrigin(sfComputed, "@markdown")
    ctx.arena.pushOrigin(computed)
    ctx.setAccPath(["page", "body-markdown"], %"<p>rendered</p>")
    ctx.arena.popOrigin()

    let leaf = ctx.arena.objGet(node, "body-markdown")
    check ctx.arena.getStr(leaf) == "<p>rendered</p>"
    let history = ctx.arena.originHistory(leaf)
    check history.len == 2
    check ctx.arena.getOrigin(history[0]).format == sfComputed
    check ctx.arena.getOrigin(history[1]).format == sfYaml
    check ctx.arena.getSourcePath(ctx.arena.getOrigin(history[1]).sourceId) == "content/page.yaml"
    check ctx.arena.originDepth(leaf) == 1

  test "a rewrite without a loaded predecessor has plain computed origin":
    var ctx = newContextStore()
    ctx.setPlainPath(["untagged"], %"plain")
    let computed = ctx.arena.registerOrigin(sfComputed, "@markdown")
    ctx.arena.pushOrigin(computed)
    ctx.setAccPath(["fresh"], %"<p>new</p>")
    ctx.arena.popOrigin()
    let leaf = ctx.arena.objGet(ctx.root, "fresh")
    check ctx.arena.originHistory(leaf).len == 1
    check ctx.arena.getOrigin(ctx.arena.getNodeOrigin(leaf)).format == sfComputed
