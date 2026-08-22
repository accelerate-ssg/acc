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

import std/[json, strutils]
import re

import logger
import arena_context_store

type
  ContextStore* = ref object
    arena*: Arena
    root*: NodeId

let path_regex = re"^(.+)\[(\d*)\]$"

proc newContextStore*(): ContextStore =
  new(result)
  result.arena = initArena()
  result.root = result.arena.newObj()

proc lenLike(ctx: ContextStore, id: NodeId): int =
  ## JsonNode.len semantics: objects and arrays are counted, scalars are 0.
  case ctx.arena.kind(id)
  of nkObject: ctx.arena.objLen(id)
  of nkArray: ctx.arena.arrLen(id)
  else: 0

proc setPlainPath*(ctx: ContextStore, keys: openArray[string], value: JsonNode) =
  ## Port of std/json's `{}=`: plain keys, missing intermediates become
  ## objects, the last key is assigned.
  assert keys.len > 0, "setPlainPath needs at least one key"
  var node = ctx.root
  for i in 0 .. keys.len - 2:
    var child = ctx.arena.objGet(node, keys[i])
    if child == InvalidNodeId:
      child = ctx.arena.newObj()
      ctx.arena.objSet(node, keys[i], child)
    node = child
  ctx.arena.objSet(node, keys[^1], ctx.arena.fromJson(value))

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

proc `$`*(ctx: ContextStore): string =
  $ctx.toJson

proc `{}=`*(ctx: ContextStore, keys: varargs[string], value: JsonNode) =
  ## Same call shape yaml_loader used when the context was a JsonNode,
  ## with the same (std/json) semantics.
  ctx.setPlainPath(keys, value)

proc `{}`*(ctx: ContextStore, keys: varargs[string]): JsonNode =
  ctx.getPath(keys)
