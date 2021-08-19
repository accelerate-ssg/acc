import sequtils, sugar
import options

import logger
import types/plugin

# TODO: https://nim-lang.org/blog/2020/04/03/version-120-released.html#capture
# to get rid of the workaround compiler flag

when isMainModule:
  log_level = lvlDebug
  parsing_context = "dag.nim"

type
  DependencyError* = object of ValueError
  RawNode = object
    self: string
    before: seq[ string ]
    after: seq[ string ]
  Node = object
    self: string
    after: seq[ string ]

proc `==`( a: Node, b: RawNode ): bool =
  a.self == b.self

proc `==`( a: Node, b: Node ): bool =
  a.self == b.self

proc find( list: seq[Node], node: Node ): int =
  var index: int = -1
  for idx, item in list:
    if item == node:
      index = idx
      break

  return index

proc ensure_no_missing_after_dependencies( nodes: seq[ RawNode ]) =
  var deps: seq[ string ] = @[]
  let names = nodes.map_it( it.self )

  for node in nodes:
    deps = deps & node.after

  for dep in deps:
    if names.find( dep ) == -1:
      let dependants = nodes.filter( node => node.after.find( dep ) != -1 )
      let list = dependants.map_it( it.self )
      raise newException(DependencyError, "Plugin(s) " & $list & " depends on \"after\" " & $dep & " but that plugin is not configured")

proc ensure_no_missing_before_dependencies( nodes: seq[ RawNode ]) =
  var deps: seq[ string ] = @[]
  let names = nodes.map_it( it.self )

  for node in nodes:
    deps = deps & node.before

  for dep in deps:
    if names.find( dep ) == -1:
      let dependants = nodes.filter( node => node.before.find( dep ) != -1 )
      let list = dependants.map_it( it.self )
      raise newException(DependencyError, "Plugin(s) " & $list & " depends on \"before\" " & $dep & " but that plugin is not configured")

proc order*( plugins: seq[ Plugin ]): seq[ Plugin ] =
  var
    raw_nodes: seq[ RawNode ]
    unsorted: seq[ Node ]
    sorted: seq[ Node ]

  raw_nodes = plugins.map( plugin => RawNode( self: plugin.name, after: plugin.after, before: plugin.before ))

  raw_nodes.ensure_no_missing_after_dependencies()
  raw_nodes.ensure_no_missing_before_dependencies()

  # Copy all nodes to unsorten and add after condition
  for index, raw_node in raw_nodes:
    let new_node = Node( self: raw_node.self, after: raw_node.after )
    let index = unsorted.find( new_node )
    if index != -1:
      warn( "Duplicate plugin configuration found for " & raw_node.self )
      let node = unsorted[index]
      let after = (node.after & new_node.after).deduplicate()
      unsorted[index] = Node( self: node.self, after: after )
    else:
      unsorted.add( new_node )

  # convert before condition A->B to after condition A<-B
  for raw_node in raw_nodes:
    for dep in raw_node.before:
      let index = unsorted.find( Node( self: dep, after: @[] ))
      let node = unsorted[ index ]
      let after = (node.after & @[ raw_node.self ]).deduplicate()
      unsorted[ index ] = Node( self: node.self, after: after )

  var done_index = 0;

  while unsorted.len != 0:
    for node in unsorted:
      if node.after.len == 0: ## If the node has no dependencies
        sorted.add( node )    ## Add to sorted set
        for i, n in unsorted: ## For every node in the unsorted set
          unsorted[i].after = n.after.filter_it( it != node.self ) ## Remove the node we just added from deps

    for node in sorted[done_index..^1]: ## For all the newly added nodes
      let index = unsorted.find( node ) ## Find the node position
      unsorted.del( index ) ## And delete the node

    if done_index == sorted.len: ## If we haven't added any new nodes this pass
      raise newException(DependencyError, "Dependencies contain unresolvable relations. No strict ordering is possible.")
    done_index = sorted.len ## Update position for next itteration

  var final_list:seq[ Plugin ] = @[]

  for node in sorted:
    let plugin = plugins.filter( plugin => plugin.name == node.self )[0]
    final_list.add( plugin )

  return final_list

when isMainModule:
  let test1 = @[
    RawNode( self: "A", before: @[], after: @[]),
    RawNode( self: "B", before: @[], after: @["D"]),
    RawNode( self: "C", before: @["A"], after: @["D"]),
    RawNode( self: "D", before: @[], after: @[])
  ]

  let actual1 = order( test1 )
  let expected1 = @["D", "B", "C", "A"]
  assert actual1 == expected1, "Simple order not fullfilled! Expected " & $expected1 & " got " & $actual1



  let test2 = @[
    RawNode( self: "A", before: @["B"], after: @[]),
    RawNode( self: "B", before: @["A"], after: @[])
  ]

  try:
    echo order( test2 )
  except DependencyError:
    let msg = getCurrentExceptionMsg()
    assert msg == "Dependencies contain unresolvable relations. No strict ordering is possible.", "Dependency loop not detected!"



  let test3 = @[ RawNode( self: "A", before: @["C"], after: @[]) ]
  try:
    echo order( test3 )
  except DependencyError:
    let msg = getCurrentExceptionMsg()
    assert msg == "Plugin(s) @[\"A\"] depends on \"before\" C but that plugin is not configured", "Unfullfilled before dependancy not detected!"



  let test4 = @[ RawNode( self: "A", before: @[], after: @["C"]) ]
  try:
    echo order( test4 )
  except DependencyError:
    let msg = getCurrentExceptionMsg()
    assert msg == "Plugin(s) @[\"A\"] depends on \"after\" C but that plugin is not configured", "Unfullfilled after dependancy not detected!"



  let test5 = @[
    RawNode( self: "A", before: @["C"], after: @["B"]),
    RawNode( self: "A", before: @["C"], after: @[]),
    RawNode( self: "B", before: @[], after: @[]),
    RawNode( self: "C", before: @[], after: @[])
  ]

  let actual5 = order( test5 )
  let expected5 = @["B", "A", "C"]
  assert actual5 == expected5, "Double incoming dependency not being deduped correctly! Expected " & $expected5 & " got " & $actual5
