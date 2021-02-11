# This is the complex, typed, state that I made. I'm not sure if we should use
# it at all though ... Using a simple string:string map for now and let's see
# if we run into some cases where that is not enough...

import strutils
import sequtils, sugar
import tables
import re

import types/config

type
  ContextKeyFormatError* = object of ValueError
  ContextNodeAssignmentError* = object of ValueError
  ContextValueKind* = enum
    kindString, kindInt, kindFloat, kindBool, kindList, kindPath, kindURL,
    kindFile, kindDir, kindNil, kindOther

  ContextValue* = object
    case kind*: ContextValueKind
    of kindNil, kindOther: nil
    of kindString, kindURL, kindPath, kindFile, kindDir:
      valueString*: string
    of kindInt:
      valueInt*: int
    of kindFloat:
      valueFloat*: float
    of kindBool:
      valueBool*: bool
    of kindList:
      valueList*: seq[ ContextValue ]

  ContextNodeKind* = enum
    kindObjectNode, kindValueNode
  ContextNode* = object
    case kind*: ContextNodeKind
    of kindObjectNode:
      children*: seq[ ContextNode ]
    of kindValueNode:
      value*: ContextValue
    name*: string
    source*: string

  State* = object
    config*: Config
    context*: ContextNode

proc init_node( name: string, source: string = "" ): ContextNode =
  if not name.match( re"^[a-z]+[_\-\w\d]*$" ):
    raise newException(ContextKeyFormatError, "invalid format for key \"" & name & "\"")

  ContextNode(
    kind: kindObjectNode,
    name: name,
    children: @[],
    source: source
  )

proc init_node( value: ContextValue, name: string, source: string = "" ): ContextNode =
  if not name.match( re"^[a-z]+[_\-\w\d]*$" ):
    raise newException(ContextKeyFormatError, "invalid format for key \"" & name & "\"")

  ContextNode(
    kind: kindValueNode,
    name: name,
    value: value,
    source: source
  )

proc init_context_value( value: string ): ContextValue =
  ContextValue( kind: kindString, valueString: value )

proc init_context_value( value: int ):ContextValue =
  ContextValue( kind: kindInt, valueInt: value )

proc init_context_value( value: float ):ContextValue =
  ContextValue( kind: kindFloat, valueFloat: value )

proc init_context_value( value: bool ):ContextValue =
  ContextValue( kind: kindBool, valueBool: value )

proc init_context_value( value: seq[any] ):ContextValue =
  let list = value.map( el => init_context_value( el ))
  ContextValue( kind: kindList, valueList: list )

proc init_context_value( value: type(nil) ):ContextValue =
  ContextValue( kind: kindNil )

proc init_context_value( value: any ):ContextValue =
  echo ""
  echo "Unknown type:" & $value.type
  echo ""
  ContextValue( kind: kindOther )

proc add*( node: var ContextNode, name: string, source: string = "" ) =
  if node.kind != kindObjectNode:
    raise newException(ContextNodeAssignmentError, "node \"" & node.name & "\" already has a value and can't take children")

  node.children.add(
    init_node(
      name = name,
      source = source
    )
  )

proc add*( node: var ContextNode, name: string, value: any, source: string = "" ) =
  if node.kind != kindObjectNode:
    raise newException(ContextNodeAssignmentError, "node \"" & node.name & "\" already has a value and can't take children")

  node.children.add(
    init_node(
      name = name,
      value = init_context_value( value ),
      source = source
    )
  )

proc `$`*(value: ContextValue): string =
  case value.kind:
  of kindNil:
    "nil"
  of kindOther:
    "unknown"
  of kindString, kindURL, kindPath, kindFile, kindDir:
    value.valueString
  of kindInt:
    $value.valueInt
  of kindFloat:
    $value.valueFloat
  of kindBool:
    $value.valueBool
  of kindList:
    "[ " & value.valueList.map( e => $e ).join(", ") & " ]"

proc `$`*(node: ContextNode): string =
  if node.kind == kindObjectNode:
    result = node.name & ":"
    result.add indent( node.children.map( child => "\n" & $child ).join(""), 2 )
  else:
    result = node.name & ": " & $node.value

proc init_state*(): State =
  result = State()
  result.config = init_config()
  result.config.load()
  result.context = ContextNode( name: "context", source: "Accelerate" )
