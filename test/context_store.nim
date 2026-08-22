## Differential tests for the arena-backed ContextStore.
##
## The old implementations — the State-level `{}=`/`{}` from global_state
## (JsonNode-based, deleted in the same change that added this file) and
## std/json's `{}=` that yaml_loader used to hit — are copied here verbatim
## as reference oracles. Every test drives the oracle and the ContextStore
## with the same operations and requires identical resulting trees.

import std/[unittest, json, strutils, sets]
import re

import types/context_store
import arena_context_store

# --- Reference implementations (the pre-arena behavior) ---

proc refSetAcc(root: JsonNode, keys: openArray[string], value: JsonNode) =
  ## Verbatim copy of the old State-level `{}=` from global_state.nim,
  ## with `state.context` replaced by `root`.
  var node = root
  var matches: array[2, string]
  let last_key = keys.len-1
  let regexp = re"^(.+)\[(\d*)\]$"

  for i in 0..(last_key):
    if keys[i] == "": continue
    if keys[i].match( regexp, matches ):
      let key = matches[0]
      let index = if matches[1] != "": matches[1].parse_int else: node.len

      if not node.hasKey(key):
        node[key] = newJArray()

      node = node[key]

      while node.len < index:
        node.add( newJNull() )

      if i == last_key:
        node.add( value )
      else:
        if index >= node.len:
          node.add( newJObject())

      node = node[ index ]

    else:
      if i == last_key:
        node[keys[i]] = value
      else:
        if not node.hasKey(keys[i]):
          node[keys[i]] = newJObject()

      node = node[keys[i]]

proc refGet(root: JsonNode, keys: openArray[string]): JsonNode =
  ## Verbatim copy of the old State-level `{}`.
  result = root
  for key in keys:
    result = result{key}
    if result == nil or result.kind == JNull:
      return newJNull()

# std/json's `{}=` is the third oracle; it is called directly below.

# --- Harness ---

type
  OpKind = enum opAcc, opPlain
  Op = object
    kind: OpKind
    keys: seq[string]
    value: JsonNode

proc acc(path: string, value: JsonNode): Op =
  ## A dotted-path write, as markdown_renderer issues them via state{path}=.
  Op(kind: opAcc, keys: path.split('.'), value: value)

proc accKeys(keys: seq[string], value: JsonNode): Op =
  Op(kind: opAcc, keys: keys, value: value)

proc plain(keys: seq[string], value: JsonNode): Op =
  ## A plain-atom write, as yaml_loader issues them via state.context{atoms}=.
  Op(kind: opPlain, keys: keys, value: value)

proc runBoth(ops: openArray[Op]): tuple[reference: JsonNode, store: ContextStore] =
  result.reference = newJObject()
  result.store = newContextStore()
  for op in ops:
    case op.kind
    of opAcc:
      refSetAcc(result.reference, op.keys, op.value)
      result.store.setAccPath(op.keys, op.value)
    of opPlain:
      result.reference{op.keys} = op.value
      result.store.setPlainPath(op.keys, op.value)

proc checkSame(ops: openArray[Op]) =
  let (reference, store) = runBoth(ops)
  check store.toJson == reference

# --- Write parity ---

suite "ContextStore - Acc-path write parity":
  test "simple dotted paths":
    checkSame([
      acc("site.name", %"Accodeing"),
      acc("site.domain", %"accodeing.com"),
      acc("counter", %42),
    ])

  test "overwrite and sibling":
    checkSame([
      acc("a.b", %1),
      acc("a.b", %2),
      acc("a.c", %3),
      acc("a", %"flattened"),
    ])

  test "leading dot yields an empty atom that is skipped":
    checkSame([
      acc(".pages.home", %"content"),
      acc(".pages.about", %"other"),
    ])

  test "array index syntax on intermediate atoms":
    checkSame([
      acc("posts[0].title", %"first"),
      acc("posts[0].body", %"hello"),
      acc("posts[1].title", %"second"),
    ])

  test "array index past the end pads with nulls":
    checkSame([
      acc("sparse[3].x", %1),
    ])

  test "array index as the last atom appends":
    checkSame([
      acc("list[0]", %"a"),
      acc("list[1]", %"b"),
      acc("list[5]", %"padded"),
    ])

  test "bare brackets use the enclosing node's length as index":
    # The old implementation resolved `key[]` against the length of the
    # node ENCLOSING the array — a quirk, ported faithfully.
    checkSame([
      acc("a", %1),
      acc("b", %2),
      accKeys(@["list[]"], %"appended"),
      accKeys(@["list[]"], %"again"),
    ])

  test "deep vivification":
    checkSame([
      acc("a.b.c.d.e.f", %"deep"),
    ])

  test "mixed arrays and objects":
    checkSame([
      acc("blog.posts[0].tags[0]", %"nim"),
      acc("blog.posts[0].tags[1]", %"arena"),
      acc("blog.posts[1].tags[0]", %"other"),
      acc("blog.title", %"The Blog"),
    ])

  test "structured values pass through unchanged":
    checkSame([
      acc("config", %*{"nested": {"deep": [1, 2, {"k": "v"}]}, "flag": true}),
      acc("config.extra", %"added below a loaded subtree"),
    ])

suite "ContextStore - Plain-path write parity":
  test "single atom, as a content file at the top level":
    checkSame([
      plain(@["index"], %*{"title": "Home"}),
    ])

  test "atoms with dots inside stay single keys":
    # content/front_matter.md.yaml loads under the literal key
    # "front_matter.md" — the plain path must NOT split it.
    checkSame([
      plain(@["front_matter.md"], %*{"body": "text"}),
    ])

  test "nested atoms vivify objects":
    checkSame([
      plain(@["pages", "sub", "leaf"], %*{"a": 1}),
      plain(@["pages", "other"], %2),
    ])

  test "plain write does not interpret bracket syntax":
    checkSame([
      plain(@["weird[0]"], %"literal key"),
    ])

  test "interleaved plain and acc writes":
    checkSame([
      plain(@["site"], %*{"name": "x"}),
      acc("site.tagline", %"welcome"),
      plain(@["site", "name"], %"y"),
      acc("posts[0].title", %"t"),
      plain(@["posts"], %"clobbered"),
    ])

# --- Read parity ---

suite "ContextStore - Read parity":
  proc populated(): tuple[reference: JsonNode, store: ContextStore] =
    runBoth([
      acc("site.name", %"Accodeing"),
      acc("site.empty", newJNull()),
      acc("posts[0].title", %"first"),
      acc("num", %7),
    ])

  proc checkRead(keys: seq[string]) =
    let (reference, store) = populated()
    check store.getPath(keys) == refGet(reference, keys)

  test "hit on a scalar":
    checkRead(@["site", "name"])

  test "hit on a subtree materializes it":
    checkRead(@["site"])

  test "miss yields null":
    checkRead(@["site", "missing"])
    checkRead(@["nowhere", "at", "all"])

  test "descending through a scalar yields null":
    checkRead(@["num", "deeper"])

  test "stored null yields null":
    checkRead(@["site", "empty"])

  test "array syntax is not interpreted on reads":
    checkRead(@["posts[0]", "title"])

  test "empty key is not skipped on reads":
    checkRead(@["", "site"])

  test "read returns a copy, not a view":
    let (_, store) = populated()
    let snapshot = store.getPath(@["site"])
    snapshot["name"] = %"mutated"
    check store.getPath(@["site", "name"]) == %"Accodeing"

suite "ContextStore - toJson":
  test "whole-tree materialization matches the reference":
    let (reference, store) = runBoth([
      acc("a.b", %1),
      acc("list[2]", %"x"),
      plain(@["k.with.dots"], %true),
    ])
    check store.toJson == reference

  test "empty store is an empty object":
    check newContextStore().toJson == newJObject()

suite "ContextStore - Script write-back":
  proc seeded(): ContextStore =
    result = newContextStore()
    result.setAccPath(["site", "name"], %"Accodeing")
    result.setAccPath(["site", "visits"], %10)
    result.setAccPath(["tags[0]"], %"a")
    result.setAccPath(["tags[1]"], %"b")

  test "scalar change is applied in place":
    let store = seeded()
    let titleId = store.arena.objGet(store.arena.objGet(store.root, "site"), "name")
    var snapshot = store.toJson
    snapshot["site"]["name"] = %"Renamed"
    store.applyScriptChanges(snapshot)
    check store.toJson == snapshot
    # In-place: the node kept its identity.
    check store.arena.objGet(store.arena.objGet(store.root, "site"), "name") == titleId

  test "added nested keys are applied":
    let store = seeded()
    var snapshot = store.toJson
    snapshot["site"]["new"] = %*{"deep": [1, 2]}
    snapshot["fresh"] = %true
    store.applyScriptChanges(snapshot)
    check store.toJson == snapshot

  test "array append is applied":
    let store = seeded()
    var snapshot = store.toJson
    snapshot["tags"].add(%"c")
    store.applyScriptChanges(snapshot)
    check store.toJson == snapshot

  test "kind change rebinds":
    let store = seeded()
    var snapshot = store.toJson
    snapshot["site"]["visits"] = %"ten"
    snapshot["tags"] = %*{"now": "an object"}
    store.applyScriptChanges(snapshot)
    check store.toJson == snapshot

  test "array shrink rebinds to the shorter array":
    let store = seeded()
    var snapshot = store.toJson
    snapshot["tags"] = %*["only"]
    store.applyScriptChanges(snapshot)
    check store.toJson == snapshot

  test "unchanged subtrees keep their NodeIds":
    let store = seeded()
    let siteId = store.arena.objGet(store.root, "site")
    var snapshot = store.toJson
    snapshot["other"] = %1
    store.applyScriptChanges(snapshot)
    check store.arena.objGet(store.root, "site") == siteId

  test "deleted keys linger":
    let store = seeded()
    var snapshot = store.toJson
    snapshot.delete("tags")
    store.applyScriptChanges(snapshot)
    check store.getPath(["tags", "", ""]) == newJNull()  # shape unchanged below
    check store.toJson.hasKey("tags")

  test "nil and non-object snapshots are ignored":
    let store = seeded()
    let before = store.toJson
    store.applyScriptChanges(nil)
    store.applyScriptChanges(%"scalar")
    check store.toJson == before

suite "ContextStore - Consumers":
  test "labels intern to stable ids":
    let store = newContextStore()
    let a = store.consumer("@load a.yaml")
    let b = store.consumer("@load b.yaml")
    check a != b
    check store.consumer("@load a.yaml") == a
    check store.consumer_label(a) == "@load a.yaml"
    check store.consumer_label(999) == "<unknown consumer 999>"

  test "track attributes accesses and clears on rerun":
    let store = newContextStore()
    let writer = store.track("@load f.yaml")
    store.setPlainPath(["f"], %*{"v": 1})
    store.untrack()
    check store.arena.writeSet(writer).len > 0

    # A reader consumer touches the loaded value.
    let reader = store.track("@page f.html")
    discard store.getPath(["f", "v"])
    store.untrack()

    # The reader is stale when the file's loader rewrites its nodes.
    discard store.track("@load f.yaml")
    store.setPlainPath(["f"], %*{"v": 2})
    store.untrack()
    let stale = store.arena.invalidatedBy(store.consumer("@load f.yaml"))
    check reader in stale

    # Re-tracking replaced the loader's first-run records.
    check store.arena.writeSet(writer).len > 0

  test "unrelated readers stay valid":
    let store = newContextStore()
    discard store.track("@load a.yaml")
    store.setPlainPath(["a"], %*{"v": 1})
    store.untrack()
    discard store.track("@load b.yaml")
    store.setPlainPath(["b"], %*{"v": 1})
    store.untrack()

    let readerA = store.track("@page a.html")
    discard store.getPath(["a", "v"])
    store.untrack()
    let readerB = store.track("@page b.html")
    discard store.getPath(["b", "v"])
    store.untrack()

    discard store.track("@load a.yaml")
    store.setPlainPath(["a"], %*{"v": 2})
    store.untrack()

    let stale = store.arena.invalidatedBy(store.consumer("@load a.yaml"))
    check readerA in stale
    check readerB notin stale
