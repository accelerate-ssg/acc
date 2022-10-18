import compiler/[ast, nimeval, renderer]
import tables
import json
import re
import strutils

import logger
import types/config
import types/config/init
import types/plugin

type
  ContextKeyFormatError* = object of ValueError
  ContextNodeAssignmentError* = object of ValueError
  State* = ref object
    context*: JsonNode
    config*: Config
    registry*: Table[ string, proc( interpreter: Interpreter, callback_proc: PSym ) ]
    current_plugin*: Plugin

var state* = State(
  config: init_config(),
  context: newJObject(),
  registry: initTable[ string, proc( interpreter: Interpreter, callback_proc: PSym ) ](),
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

# state{ ["test","value[0]"] } = %41
# state{ ["test","value[]"] } = %42
# state{ "test.value[5].inner" } = %43
