import json
import re
import strutils
import sets
import sequtils

import "$nim"/compiler / [renderer]

import logger
import types/state as state_type
import types/config
import types/config/init
import types/render_state/calculate
import types/plugin

export State

var state* = State(
  config: init_config(),
  context: newJObject(),
  render_state: @[],
  #registry: initTable[ string, proc( interpreter: Interpreter, callback_proc: PSym ){.gcsafe, locks: 0.}](),
  current_plugin: Plugin()
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
  # If the types of the nodes are different, return the new context.
  if new_context.kind != old_context.kind:
    return old_context

  # Handle different types of JSON nodes (objects, arrays, and values).
  case new_context.kind
  of JObject:
    # Collect the keys of the new and old contexts.
    let keysNew = toSeq(new_context.keys())
    let keysOld = toSeq(old_context.keys())
    
    # Combine the key sets.
    let allKeys = keysNew.toHashSet + keysOld.toHashSet
    
    # Create a new JSON object for the result.
    result = newJObject()

    # Iterate through the combined key set.
    for key in allKeys:
      # If the key exists only in the old context, mark it as deleted.
      if not new_context.hasKey(key):
        result[key] = %"[DELETED]"
      
      # If the key exists only in the new context, add it to the result.
      elif not old_context.hasKey(key):
        result[key] = new_context[key]
      
      # If the key exists in both contexts, recursively compute the diff.
      else:
        let child_diff = diff(new_context[key], old_context[key])
        
        # Add the child diff to the result if it's not empty.
        if child_diff.kind != JNull:
          result[key] = child_diff

    # Set the result to a JSON null if there are no changes.
    if result.len == 0:
      result = newJNull()

  of JArray:
    # If the lengths of the arrays are different, return the new context.
    if new_context.len != old_context.len:
      return new_context

    # Create a new JSON array for the result.
    result = newJArray()

    # Iterate through the elements of the arrays.
    for i in 0 ..< new_context.len:
      # Compute the diff for each pair of elements recursively.
      let child_diff = diff(new_context[i], old_context[i])
      
      # Add the child diff to the result if it's not empty.
      if child_diff.kind != JNull:
        result.add(child_diff)

    # Set the result to a JSON null if there are no changes.
    if result.len == 0:
      result = newJNull()

  # Compare simple JSON values (strings, integers, floats, and booleans).
  of JString, JInt, JFloat, JBool:
    # If the values are different, return the new context.
    if new_context != old_context:
      return new_context
    
    # If the values are the same, return a JSON null.
    else:
      return newJNull()

  # For other types of JSON nodes, return a JSON null.
  else:
    return newJNull()
