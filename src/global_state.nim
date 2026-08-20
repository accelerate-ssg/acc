import json
import re
import strutils
import sets
import sequtils

import logger
import state as state_module
import config

export State

var state* = State(
  config: Config(),
  context: newJObject(),
  render_state: @[],
  source_files: @[],
  current_step: Step(),
  current_workflow: Workflow()
)

proc `{}=`*(state: State, keys: varargs[string], value: JsonNode) =
  var node = state.context
  var matches: array[2, string]
  let last_key = keys.len-1
  let regexp = re"^(.+)\[(\d*)\]$"

  for i in 0..(last_key):
    if keys[i] == "": continue
    if keys[i].match( regexp, matches ):
      let key = matches[0]
      let index = if matches[1] != "": matches[1].parse_int else: node.len

      if not node.hasKey(key):
        notice "Didn't find key \"", key, "\" in ", $state.context
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


proc `{}=`*(state: State, path: string, value: JsonNode) =
  state{ path.split('.') } = value

proc `{}`*(state: State, keys: varargs[string] ): JsonNode =
  result = state.context

  for key in keys:
    result = result{key}
    if result == nil or result.kind == JNull:
      return newJNull()

proc `{}`*(state: State, path: string ): JsonNode =
  state{ path.split('.') }


proc diff*(new_context, old_context: JsonNode): JsonNode =
  if new_context.kind != old_context.kind:
    return old_context

  case new_context.kind
  of JObject:
    let keysNew = toSeq(new_context.keys())
    let keysOld = toSeq(old_context.keys())
    let allKeys = keysNew.toHashSet + keysOld.toHashSet
    result = newJObject()

    for key in allKeys:
      if not new_context.hasKey(key):
        result[key] = %"[DELETED]"
      elif not old_context.hasKey(key):
        result[key] = new_context[key]
      else:
        let child_diff = diff(new_context[key], old_context[key])
        if child_diff.kind != JNull:
          result[key] = child_diff

    if result.len == 0:
      result = newJNull()

  of JArray:
    if new_context.len != old_context.len:
      return new_context

    result = newJArray()
    for i in 0 ..< new_context.len:
      let child_diff = diff(new_context[i], old_context[i])
      if child_diff.kind != JNull:
        result.add(child_diff)

    if result.len == 0:
      result = newJNull()

  of JString, JInt, JFloat, JBool:
    if new_context != old_context:
      return new_context
    else:
      return newJNull()

  else:
    return newJNull()
