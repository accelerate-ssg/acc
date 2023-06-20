import sequtils, sugar

import ../../logger
import ../plugin

# TODO: https://nim-lang.org/blog/2020/04/03/version-120-released.html#capture
# to get rid of the workaround compiler flag

when isMainModule:
  set_log_level( lvlDebug )
  set_parsing_context( "dag.nim" )

type
  DependencyError* = object of ValueError
  RawNode = object
    self: string
    before: seq[ string ]
    after: seq[ string ]
  Node = object
    self: string
    after: seq[ string ]

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
      let dependency_name = dep
      let dependants = nodes.filter( node => node.after.find( dependency_name ) != -1 )
      let list = dependants.map_it( it.self )
      raise newException(DependencyError, "Plugin(s) " & $list & " depends on \"after\" " & $dep & " but that plugin is not configured")

proc ensure_no_missing_before_dependencies( nodes: seq[ RawNode ]) =
  var deps: seq[ string ] = @[]
  let names = nodes.map_it( it.self )

  for node in nodes:
    deps = deps & node.before

  for dep in deps:
    if names.find( dep ) == -1:
      let dependency_name = dep
      let dependants = nodes.filter( node => node.before.find( dependency_name ) != -1 )
      let list = dependants.map_it( it.self )
      raise newException(DependencyError, "Plugin(s) " & $list & " depends on \"before\" " & $dep & " but that plugin is not configured")

# Helper proc to handle duplicate plugin configurations
proc handle_duplicate_plugin_configurations(raw_nodes: seq[RawNode], unsorted: var seq[Node]) =
  for index, raw_node in raw_nodes:
    let new_node = Node(self: raw_node.self, after: raw_node.after)
    let index = unsorted.find(new_node)
    if index != -1:
      warn("Duplicate plugin configuration found for " & raw_node.self)
      let node = unsorted[index]
      let after = (node.after & new_node.after).deduplicate()
      unsorted[index] = Node(self: node.self, after: after)
    else:
      unsorted.add(new_node)

# Helper proc to convert before conditions to after conditions
proc convert_before_to_after_conditions(raw_nodes: seq[RawNode], unsorted: var seq[Node]) =
  for raw_node in raw_nodes:
    for dep in raw_node.before:
      let index = unsorted.find(Node(self: dep, after: @[]))
      let node = unsorted[index]
      let after = (node.after & @[raw_node.self]).deduplicate()
      unsorted[index] = Node(self: node.self, after: after)

# Helper proc to add nodes with no dependencies to the sorted list
proc add_nodes_without_dependencies(unsorted: var seq[Node], sorted: var seq[Node]) =
  for node in unsorted:
    if node.after.len == 0:
      sorted.add(node)
      for i, n in unsorted:
        unsorted[i].after = n.after.filter_it(it != node.self)

# Helper proc to remove added nodes from the unsorted list
proc remove_added_nodes_from_unsorted(done_index: int, unsorted: var seq[Node], sorted: var seq[Node]) =
  for node in sorted[done_index..^1]:
    let index = unsorted.find(node)
    unsorted.del(index)

proc order*(plugins: seq[Plugin]): seq[Plugin] =
  var
    raw_nodes: seq[RawNode]
    unsorted: seq[Node]
    sorted: seq[Node]

  raw_nodes = plugins.map(plugin => RawNode(self: plugin.name, after: plugin.after, before: plugin.before))

  raw_nodes.ensure_no_missing_after_dependencies()
  raw_nodes.ensure_no_missing_before_dependencies()

  handle_duplicate_plugin_configurations(raw_nodes, unsorted)
  convert_before_to_after_conditions(raw_nodes, unsorted)

  var done_index = 0
  while unsorted.len != 0:
    add_nodes_without_dependencies(unsorted, sorted)
    remove_added_nodes_from_unsorted(done_index, unsorted, sorted)

    if done_index == sorted.len:
      raise newException(DependencyError, "Dependencies contain unresolvable relations. No strict ordering is possible.")

    done_index = sorted.len

  var final_list: seq[Plugin] = @[]
  for node in sorted:
    let node_name = node.self
    let plugin = plugins.filter(plugin => plugin.name == node_name)[0]
    final_list.add(plugin)

  return final_list

when isMainModule:
  proc `==`(a: Plugin, b: string): bool =
    a.name == b

  proc `==`(a: seq[Plugin], b: seq[string]): bool =
    if a.len != b.len:
      return false

    for i in 0..<a.len:
      if not (a[i] == b[i]):
        return false

    return true


  let test1 = @[
    Plugin( name: "A", before: @[], after: @[]),
    Plugin( name: "B", before: @[], after: @["D"]),
    Plugin( name: "C", before: @["A"], after: @["D"]),
    Plugin( name: "D", before: @[], after: @[])
  ]

  let actual1 = order( test1 )
  let expected1 = @["D", "B", "C", "A"]
  assert actual1 == expected1, "Simple order not fullfilled! Expected " & $expected1 & " got " & $actual1



  let test2 = @[
    Plugin( name: "A", before: @["B"], after: @[]),
    Plugin( name: "B", before: @["A"], after: @[])
  ]

  try:
    echo order( test2 )
  except DependencyError:
    let msg = getCurrentExceptionMsg()
    assert msg == "Dependencies contain unresolvable relations. No strict ordering is possible.", "Dependency loop not detected!"



  let test3 = @[ Plugin( name: "A", before: @["C"], after: @[]) ]
  try:
    echo order( test3 )
  except DependencyError:
    let msg = getCurrentExceptionMsg()
    assert msg == "Plugin(s) @[\"A\"] depends on \"before\" C but that plugin is not configured", "Unfullfilled before dependancy not detected!"



  let test4 = @[ Plugin( name: "A", before: @[], after: @["C"]) ]
  try:
    echo order( test4 )
  except DependencyError:
    let msg = getCurrentExceptionMsg()
    assert msg == "Plugin(s) @[\"A\"] depends on \"after\" C but that plugin is not configured", "Unfullfilled after dependancy not detected!"



  let test5 = @[
    Plugin( name: "A", before: @["C"], after: @["B"]),
    Plugin( name: "A", before: @["C"], after: @[]),
    Plugin( name: "B", before: @[], after: @[]),
    Plugin( name: "C", before: @[], after: @[])
  ]

  let actual5 = order( test5 )
  let expected5 = @["B", "A", "C"]
  assert actual5 == expected5, "Double incoming dependency not being deduped correctly! Expected " & $expected5 & " got " & $actual5
