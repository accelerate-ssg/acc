## The build context, backed by an arena instead of a JsonNode tree.
##
## JsonNode remains the exchange currency at the boundaries: values come in
## as JsonNode (loaders, scripts) and go out as JsonNode (template engines,
## the render state calculation), while the tree between those boundaries
## lives in the arena. This is what later lets the arena track which
## consumer read which node, and answer what a changed file invalidates.
##
## Two write semantics exist because two did before:
##
##   setPlainPath — the std/json `{}=` behavior yaml_loader relied on when
##   state.context was a JsonNode: plain keys, missing intermediates become
##   objects, no array syntax, no empty-key skipping.
##
##   setAccPath — the State-level `{}=` behavior from global_state: `key[i]`
##   array syntax, empty atoms skipped, arrays padded with nulls up to the
##   index, missing intermediates vivified.
##
## Reads mirror the State-level `{}`: plain keys only, any miss or null
## yields JNull. Reads return materialized copies, never live views.

import std/[json, strutils, tables, streams, times, os, options]
import re

import logger
import arena_context_store

type
  ContextStore* = ref object
    arena*: Arena
    root*: NodeId
    ## Consumer registry: the arena tracks consumers as bare uint32 ids,
    ## these map them to human-meaningful labels — "@load <file>",
    ## "@router <workflow>", "@step <module>", one per render item later.
    consumer_names*: seq[string]
    consumer_ids: Table[string, uint32]
    ## The pages the previous build routed, as (source, output) pairs:
    ## what route-set diffing compares against to find pages that
    ## appeared or disappeared.
    previous_outputs*: seq[tuple[source: string, output: string]]

let path_regex = re"^(.+)\[(\d*)\]$"

proc newContextStore*(): ContextStore =
  new(result)
  result.arena = initArena()
  result.root = result.arena.newObj()
  result.consumer_names = @[]
  result.consumer_ids = initTable[string, uint32]()

proc consumer*(ctx: ContextStore, label: string): uint32 =
  ## Intern a consumer label. The same label always yields the same id.
  if label in ctx.consumer_ids:
    return ctx.consumer_ids[label]
  result = uint32(ctx.consumer_names.len)
  ctx.consumer_names.add(label)
  ctx.consumer_ids[label] = result

proc consumer_label*(ctx: ContextStore, id: uint32): string =
  ## The label behind a consumer id, for reporting.
  if int(id) < ctx.consumer_names.len:
    ctx.consumer_names[int(id)]
  else:
    "<unknown consumer " & $id & ">"

proc known_consumer*(ctx: ContextStore, label: string): bool =
  ## Whether the label has been interned, without interning it.
  label in ctx.consumer_ids

template untracked*(ctx: ContextStore, body: untyped) =
  ## Run body without attributing arena accesses to any consumer. For
  ## work that reads the arena on some consumer's behalf without being a
  ## dependency of the active one — like materializing compatibility
  ## copies whose real consumers record their own accesses.
  if ctx.arena.tracking != nil:
    let saved_consumers = ctx.arena.tracking.consumerStack
    ctx.arena.tracking.consumerStack = @[]
    try:
      body
    finally:
      ctx.arena.tracking.consumerStack = saved_consumers
  else:
    body

proc track*(ctx: ContextStore, label: string): uint32 =
  ## Begin attributing accesses to the labeled consumer: clears its
  ## previous records (a rerun replaces them) and pushes it. Pair with
  ## untrack.
  result = ctx.consumer(label)
  ctx.arena.clearTracking(result)
  ctx.arena.pushConsumer(result)

proc untrack*(ctx: ContextStore) =
  ctx.arena.popConsumer()

proc lenLike(ctx: ContextStore, id: NodeId): int =
  ## JsonNode.len semantics: objects and arrays are counted, scalars are 0.
  case ctx.arena.kind(id)
  of nkObject: ctx.arena.objLen(id)
  of nkArray: ctx.arena.arrLen(id)
  else: 0

proc bindPath*(ctx: ContextStore, keys: openArray[string], node: NodeId) =
  ## Bind an already-built arena subtree at a plain key path. Same
  ## traversal as std/json's `{}=`: plain keys, missing intermediates
  ## become objects, the last key is bound. Intermediates created here are
  ## deliberately untagged — they are shared structure, not content of
  ## whichever file happens to vivify them first.
  assert keys.len > 0, "bindPath needs at least one key"
  var target = ctx.root
  for i in 0 .. keys.len - 2:
    var child = ctx.arena.objGet(target, keys[i])
    if child == InvalidNodeId:
      child = ctx.arena.newObj()
      ctx.arena.objSet(target, keys[i], child)
    target = child
  # A rebind retires whatever was bound before, so readers holding
  # direct handles into the old subtree invalidate too.
  let previous = ctx.arena.objGet(target, keys[^1])
  if previous != InvalidNodeId and previous != node:
    ctx.arena.retireSubtree(previous)
  ctx.arena.objSet(target, keys[^1], node)

proc setPlainPath*(ctx: ContextStore, keys: openArray[string], value: JsonNode) =
  ## Port of std/json's `{}=`: plain keys, missing intermediates become
  ## objects, the last key is assigned.
  ctx.bindPath(keys, ctx.arena.fromJson(value))

proc setAccPath*(ctx: ContextStore, keys: openArray[string], value: JsonNode) =
  ## Faithful port of the State-level `{}=` from global_state, including
  ## its quirks: a bare `key[]` resolves the index against the length of
  ## the node enclosing the array, and an indexed last key appends after
  ## padding rather than assigning in place.
  var node = ctx.root
  var matches: array[2, string]
  let last_key = keys.len - 1

  for i in 0 .. last_key:
    if keys[i] == "": continue

    if keys[i].match(path_regex, matches):
      let key = matches[0]
      let index = if matches[1] != "": matches[1].parse_int else: ctx.lenLike(node)

      var next = ctx.arena.objGet(node, key)
      if next == InvalidNodeId:
        notice "Didn't find key \"", key, "\" in the context, creating an array for it"
        next = ctx.arena.newArr()
        ctx.arena.objSet(node, key, next)
      node = next

      while ctx.lenLike(node) < index:
        ctx.arena.arrPush(node, ctx.arena.newNull())

      if i == last_key:
        ctx.arena.arrPush(node, ctx.arena.fromJson(value))
      else:
        if index >= ctx.lenLike(node):
          ctx.arena.arrPush(node, ctx.arena.newObj())

      node = ctx.arena.arrGet(node, index)

    else:
      if i == last_key:
        ctx.arena.objSet(node, keys[i], ctx.arena.fromJson(value))
      else:
        if ctx.arena.objGet(node, keys[i]) == InvalidNodeId:
          ctx.arena.objSet(node, keys[i], ctx.arena.newObj())

      node = ctx.arena.objGet(node, keys[i])

proc getPath*(ctx: ContextStore, keys: openArray[string]): JsonNode =
  ## Faithful port of the State-level `{}` read: plain keys, any miss,
  ## non-object intermediate or null yields JNull. The result is a
  ## materialized copy of the subtree, not a view into the arena.
  var node = ctx.root
  for key in keys:
    if ctx.arena.kind(node) != nkObject:
      return newJNull()
    let child = ctx.arena.objGet(node, key)
    if child == InvalidNodeId or ctx.arena.kind(child) == nkNull:
      return newJNull()
    node = child
  ctx.arena.toJson(node)

proc toJson*(ctx: ContextStore): JsonNode =
  ## Materialize the whole context as a JsonNode tree.
  ctx.arena.toJson(ctx.root)

proc mergeNode(ctx: ContextStore, id: NodeId, j: JsonNode,
               strict_keys: bool): bool =
  ## Reconcile an arena node with a JsonNode in place where possible, so
  ## unchanged nodes keep their identity and produce no write records.
  ## Returns false when the caller must rebind instead: the kind changed
  ## or an array shrank.
  ##
  ## strict_keys decides what an object whose key set or key order
  ## differs means: content reloads rebind it (removals and reordering
  ## must take effect, and a fresh build must be indistinguishable),
  ## script write-back merges what is there and lets removed keys linger.
  let k = ctx.arena.kind(id)
  case j.kind
  of JString:
    if k != nkString: return false
    if ctx.arena.getStr(id) != j.getStr: ctx.arena.setStr(id, j.getStr)
    true
  of JInt:
    if k != nkInt: return false
    if ctx.arena.getInt(id) != j.getInt: ctx.arena.setInt(id, j.getInt)
    true
  of JFloat:
    if k != nkFloat: return false
    if ctx.arena.getFloat(id) != j.getFloat: ctx.arena.setFloat(id, j.getFloat)
    true
  of JBool:
    if k != nkBool: return false
    if ctx.arena.getBool(id) != j.getBool: ctx.arena.setBool(id, j.getBool)
    true
  of JNull:
    k == nkNull
  of JObject:
    if k != nkObject: return false
    if strict_keys:
      # The key sequence must match exactly; otherwise this container is
      # rebound wholesale. Additions, removals and reorderings all land
      # here — element-level precision is for value changes.
      if ctx.arena.objLen(id) != j.len: return false
      var index = 0
      for key in j.keys:
        if ctx.arena.objGetKey(id, index) != key: return false
        inc index
    for key, val in j:
      let child = ctx.arena.objGet(id, key)
      if child == InvalidNodeId or not ctx.mergeNode(child, val, strict_keys):
        if child != InvalidNodeId:
          ctx.arena.retireSubtree(child)
        ctx.arena.objSet(id, key, ctx.arena.fromJson(val))
    true
  of JArray:
    if k != nkArray: return false
    let existing = ctx.arena.arrLen(id)
    if j.len < existing: return false
    for i in 0 ..< existing:
      let element = ctx.arena.arrGet(id, i)
      if not ctx.mergeNode(element, j[i], strict_keys):
        # One element changed shape: rebind that slot, not the array.
        ctx.arena.retireSubtree(element)
        ctx.arena.arrSet(id, i, ctx.arena.fromJson(j[i]))
    for i in existing ..< j.len:
      ctx.arena.arrPush(id, ctx.arena.fromJson(j[i]))
    true

proc lookupPath*(ctx: ContextStore, keys: openArray[string]): NodeId =
  ## The node bound at a plain key path, or InvalidNodeId.
  result = ctx.root
  for key in keys:
    if ctx.arena.kind(result) != nkObject:
      return InvalidNodeId
    result = ctx.arena.objGet(result, key)
    if result == InvalidNodeId:
      return InvalidNodeId

proc mergePath*(ctx: ContextStore, keys: openArray[string], value: JsonNode) =
  ## Bind value at a plain key path, merging into the existing subtree
  ## when one is there: unchanged nodes keep their NodeIds and produce
  ## no write records, so reloading a file invalidates only the readers
  ## of what actually changed in it.
  let existing = ctx.lookupPath(keys)
  if existing == InvalidNodeId or not ctx.mergeNode(existing, value, strict_keys = true):
    ctx.bindPath(keys, ctx.arena.fromJson(value))

proc applyScriptChanges*(ctx: ContextStore, j: JsonNode) =
  ## Merge mutations a script made to a materialized snapshot back into
  ## the store. Values are updated in place where the shape allows, so
  ## untouched subtrees keep their NodeIds; kind changes and shrunken
  ## arrays rebind wholesale. Keys the script deleted linger, matching
  ## how re-loading a shrunken content file has always behaved.
  if j == nil or j.kind != JObject:
    return
  for key, val in j:
    let child = ctx.arena.objGet(ctx.root, key)
    if child == InvalidNodeId or not ctx.mergeNode(child, val, strict_keys = false):
      ctx.arena.objSet(ctx.root, key, ctx.arena.fromJson(val))

proc `$`*(ctx: ContextStore): string =
  $ctx.toJson

# ─── Cache ───────────────────────────────────────────────────────────

const ContextCacheMagic = 0x41434343'u32  # "ACCC"
const ContextCacheVersion = 2'u32

proc writeStr(s: Stream, v: string) =
  s.write(uint32(v.len))
  if v.len > 0:
    s.writeData(unsafeAddr v[0], v.len)

proc readStr(s: Stream): string =
  let len = int(s.readUint32())
  result = newString(len)
  if len > 0:
    if s.readData(addr result[0], len) != len:
      raise newException(IOError, "truncated")

proc saveCache*(ctx: ContextStore, path: string, stamp: Time) =
  ## Persist the context — tree, origins, access log, consumer labels,
  ## the previous build's routed pages — with the build stamp that
  ## mtime-based change detection compares against.
  createDir(path.parentDir)
  let s = newFileStream(path, fmWrite)
  defer: s.close()
  s.write(ContextCacheMagic)
  s.write(ContextCacheVersion)
  s.write(int64(stamp.toUnix))
  s.write(uint32(ctx.root))
  s.write(uint32(ctx.consumer_names.len))
  for name in ctx.consumer_names:
    s.writeStr(name)
  s.write(uint32(ctx.previous_outputs.len))
  for (source, output) in ctx.previous_outputs:
    s.writeStr(source)
    s.writeStr(output)
  ctx.arena.saveArena(s)

proc loadCache*(path: string): Option[tuple[store: ContextStore, stamp: Time]] =
  ## Load a persisted context. A missing, corrupt or version-mismatched
  ## cache is reported and ignored — the cache is always regenerable.
  if not path.fileExists:
    return
  try:
    let s = newFileStream(path, fmRead)
    defer: s.close()
    if s.readUint32() != ContextCacheMagic:
      warn "Ignoring context cache with unknown format: ", path
      return
    let version = s.readUint32()
    if version != ContextCacheVersion:
      warn "Ignoring context cache from format version ", $version
      return
    let stamp = fromUnix(s.readInt64())
    let root = NodeId(s.readUint32())
    var names: seq[string] = @[]
    for i in 0 ..< int(s.readUint32()):
      names.add(s.readStr())
    var outputs: seq[tuple[source: string, output: string]] = @[]
    for i in 0 ..< int(s.readUint32()):
      let source = s.readStr()
      let output = s.readStr()
      outputs.add((source, output))
    let store = ContextStore(arena: loadArena(s), root: root,
                             previous_outputs: outputs)
    for name in names:
      discard store.consumer(name)
    result = some((store, stamp))
  except CatchableError as e:
    warn "Ignoring unreadable context cache: ", e.msg

proc `{}=`*(ctx: ContextStore, keys: varargs[string], value: JsonNode) =
  ## Same call shape yaml_loader used when the context was a JsonNode,
  ## with the same (std/json) semantics.
  ctx.setPlainPath(keys, value)

proc `{}`*(ctx: ContextStore, keys: varargs[string]): JsonNode =
  ctx.getPath(keys)
