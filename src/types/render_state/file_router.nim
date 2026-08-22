## Expands a parsed template path into the pages it produces.
##
## The template is parsed once, up front, and then expanded. Expansion only ever
## produces values, never new template text, so a data value containing braces
## or parentheses is inert.
##
## Expansion reads the context arena directly and never writes it: scopes and
## elements travel as NodeIds, so every read the router performs is visible to
## the access log when a consumer is pushed. The item, items and parent carried
## by a produced RenderStateItem are materialized JsonNode copies, as they
## effectively were before (parent was always a copy; item and items froze at
## the step boundary).
##
## Router behaviour is specified by test/path_router_spec.nim, which drives
## this implementation through the JsonNode compatibility overload.

import json, strutils, sets, tables
import std/options

import logger
import arena_context_store
import types/render_state
import types/context_store
import path_template
import node_to_string

type
  Frame = object
    ## Where a branch of the expansion currently stands.
    scope: seq[NodeId]
      ## What a . prefix resolves against, and what a literal template takes as
      ## its item. One element normally; several after a merged segment, because
      ## then the scope is the group rather than one element.
    elements: seq[NodeId]
      ## The elements the enclosing binding contributed.
    bound: JsonNode
      ## What a deeper binding reports as parent, carrying its own parent so
      ## templates can walk up. nil at the root, and nil once a segment has
      ## merged several elements, because then there is no single parent.
    bound_parent: JsonNode
      ## What a literal template at this level reports as parent.
    key: string


proc normalize(node: JsonNode): string =
  ## The single conversion used both to name a page and to compare in a filter,
  ## so a name and the filter that selects it can never disagree.
  node_to_string(node).strip()

proc normalize(arena: Arena, id: NodeId): string =
  case arena.kind(id)
  of nkNull: ""
  of nkString: arena.getStr(id).strip()
  of nkInt: ($arena.getInt(id)).strip()
  of nkFloat: ($arena.getFloat(id)).strip()
  of nkBool: ($arena.getBool(id)).strip()
  else: ($arena.toJson(id)).strip()

proc as_set(node: JsonNode): HashSet[string] =
  ## Both sides of a comparison become sets, a scalar being a set of one, so a
  ## foreign key holding "junkkari" or ["junkkari"] behaves the same way.
  result = initHashSet[string]()

  if node.isNil:
    return

  case node.kind
  of JArray:
    for element in node:
      if element.kind == JObject or element.kind == JArray:
        warn "Ignoring a non scalar value in a comparison: ", $element
      else:
        let text = normalize(element)
        if text.len > 0:
          result.incl(text)
  of JObject:
    warn "An object cannot be compared: ", $node
  of JNull:
    discard
  else:
    let text = normalize(node)
    if text.len > 0:
      result.incl(text)

proc as_set(arena: Arena, id: NodeId): HashSet[string] =
  result = initHashSet[string]()

  if id == InvalidNodeId:
    return

  case arena.kind(id)
  of nkArray:
    for element in arrItems(arena, id):
      if arena.kind(element) in {nkObject, nkArray}:
        warn "Ignoring a non scalar value in a comparison: ", $arena.toJson(element)
      else:
        let text = normalize(arena, element)
        if text.len > 0:
          result.incl(text)
  of nkObject:
    warn "An object cannot be compared: ", $arena.toJson(id)
  of nkNull:
    discard
  else:
    let text = normalize(arena, id)
    if text.len > 0:
      result.incl(text)

proc dig(node: JsonNode, path: seq[string]): JsonNode =
  result = node
  for atom in path:
    if result.isNil or result.kind != JObject:
      return nil
    result = result{atom}

proc dig(arena: Arena, id: NodeId, path: seq[string]): NodeId =
  result = id
  for atom in path:
    if result == InvalidNodeId or arena.kind(result) != nkObject:
      return InvalidNodeId
    result = arena.objGet(result, atom)

proc resolve_reference(frame: Frame, reference: Reference, source_path: string): JsonNode =
  case reference.kind
  of refKey:
    return %frame.key
  of refParent:
    if frame.bound.isNil:
      raise newException(ValueError,
        "$parent is not available in '" & source_path &
        "' because the enclosing segment merged several elements onto one page." &
        " Use $key, or bind a single element.")
    return dig(frame.bound, reference.path)

proc names_for(arena: Arena, element: NodeId, default_name: string,
               selector: Selector): seq[string] =
  result = @[]

  if selector.attribute.len == 0:
    return @[default_name]

  let value = dig(arena, element, selector.attribute)

  if value == InvalidNodeId:
    return @[]

  # An attribute names one page per scalar it holds, whether it holds one value
  # or a list of them. Naming has to tolerate shape the same way comparison
  # does, or a template breaks the day a customer's scalar arrives wrapped in an
  # array. The trailing [] stays available to say a list is expected, and warns
  # when it is not.
  if arena.kind(value) == nkArray:
    for entry in arrItems(arena, value):
      let text = normalize(arena, entry)
      if text.len > 0:
        result.add(text)
  else:
    if selector.flatten:
      warn "'", selector.attribute.join("."), "[]' expected a list but found ",
        $arena.toJson(value), ", naming it as a single value."

    let text = normalize(arena, value)
    if text.len > 0:
      result.add(text)

proc source_entries(arena: Arena, frame: Frame, root: NodeId,
                    binding: Binding): tuple[found: bool, entries: seq[(string, NodeId)]] =
  ## Resolves the binding's collection and lists its entries: the name an
  ## element takes when there is no selector, and the element. A merged scope
  ## with no collection path is the group itself.
  result = (false, @[])

  var source = InvalidNodeId
  if binding.scoped:
    if binding.collection.len == 0:
      if frame.scope.len > 1:
        # The merged group acts as the collection.
        result.found = true
        for index, element in frame.scope:
          result.entries.add(($index, element))
        return
      source = frame.scope[0]
    else:
      # Digging into a merged scope finds nothing, as before: there is no
      # single object to resolve the path against.
      if frame.scope.len == 1:
        source = dig(arena, frame.scope[0], binding.collection)
  else:
    source = dig(arena, root, binding.collection)

  if source == InvalidNodeId:
    return

  case arena.kind(source)
  of nkObject:
    result.found = true
    for key, value in objPairs(arena, source):
      result.entries.add((key, value))
  of nkArray:
    result.found = true
    var index = 0
    for value in arrItems(arena, source):
      result.entries.add(($index, value))
      index.inc
  else:
    discard

proc group_elements(
  arena: Arena,
  frame: Frame,
  binding: Binding,
  entries: seq[(string, NodeId)],
  source_path: string
): OrderedTable[string, seq[NodeId]] =
  ## Filters, names, and groups. Elements landing on the same name merge, which
  ## is all that grouping is. Insertion order is kept so the output order
  ## follows the order of the data.
  result = initOrderedTable[string, seq[NodeId]]()

  for (default_name, element) in entries:
    if binding.filter.isSome:
      let
        filter = binding.filter.get()
        left = as_set(arena, dig(arena, element, filter.attribute))
        right = as_set(resolve_reference(frame, filter.reference, source_path))

      if (left * right).len == 0:
        continue

    for name in names_for(arena, element, default_name, binding.selector):
      if result.hasKey(name):
        result[name].add(element)
      else:
        result[name] = @[element]

proc join_path(prefix, addition: string): string =
  if prefix.len > 0: prefix & "/" & addition
  else: addition

proc materialize(arena: Arena, nodes: seq[NodeId]): JsonNode =
  ## A scope: one node is itself, several are the group as an array, none
  ## is null.
  case nodes.len
  of 0:
    result = newJNull()
  of 1:
    result = arena.toJson(nodes[0])
  else:
    result = newJArray()
    for node in nodes:
      result.add(arena.toJson(node))

proc materialize_all(arena: Arena, nodes: seq[NodeId]): JsonNode =
  ## An element list: always an array, however many there are.
  result = newJArray()
  for node in nodes:
    result.add(arena.toJson(node))

proc calculate_render_state_items_for*(
  store: ContextStore,
  source_path: string
): seq[RenderStateItem] =
  result = @[]

  let template_path = parse_path_template(source_path)

  if template_path.segments.len == 0:
    return

  var frontier = @[(
    "",
    Frame(
      scope: @[store.root],
      elements: @[],
      bound: nil,
      bound_parent: nil,
      key: ""
    )
  )]

  for index, segment in template_path.segments:
    let is_last = index == template_path.segments.high
    var next: seq[(string, Frame)] = @[]

    for (path_so_far, frame) in frontier:

      if segment.binding.isNone:
        let joined = join_path(path_so_far, segment.prefix)

        if is_last:
          # The materialized item/items are compatibility copies for
          # engines that still take JsonNode — not a dependency of the
          # routing itself, so they are built unattributed. The nodes
          # carry the real identity.
          var item_json, items_json: JsonNode
          store.untracked:
            item_json = materialize(store.arena, frame.scope)
            items_json = materialize_all(store.arena, frame.elements)
          result.add(init_render_state_item(
            source_path = source_path,
            output_path = joined & ".html",
            render = true,
            item = item_json,
            items = items_json,
            key = frame.key,
            parent = frame.bound_parent,
            item_nodes = frame.scope,
            items_nodes = frame.elements
          ))
        else:
          next.add((joined, frame))

        continue

      let
        binding = segment.binding.get()
        (found, entries) = source_entries(store.arena, frame, store.root, binding)

      if not found:
        warn "Skipping '", source_path, "': no collection '",
          binding.collection.join("."), "' to expand."
        continue

      for name, elements in group_elements(store.arena, frame, binding, entries, source_path):
        let
          joined = join_path(path_so_far, segment.prefix & name & segment.suffix)
          single = elements.len == 1

        if is_last:
          var item_json, items_json: JsonNode
          store.untracked:
            item_json = if single: store.arena.toJson(elements[0]) else: newJNull()
            items_json = materialize_all(store.arena, elements)
          result.add(init_render_state_item(
            source_path = source_path,
            output_path = joined & ".html",
            render = true,
            item = item_json,
            items = items_json,
            key = name,
            parent = frame.bound,
            item_nodes = if single: elements else: @[],
            items_nodes = elements
          ))
        else:
          var bound: JsonNode = nil

          if single:
            # Stays tracked: $parent references resolve against this copy
            # during deeper routing, so the element it captures is a real
            # routing dependency.
            bound = store.arena.toJson(elements[0])
            if not frame.bound.isNil:
              bound["parent"] = frame.bound

          next.add((joined, Frame(
            scope: elements,
            elements: elements,
            bound: bound,
            bound_parent: frame.bound,
            key: name
          )))

    frontier = next

proc calculate_render_state_items_for*(
  context: JsonNode,
  source_path: string
): seq[RenderStateItem] =
  ## JsonNode compatibility overload: loads the context into a transient
  ## arena and routes against it. This is the entry point the router spec
  ## drives, so the spec exercises the arena implementation unchanged.
  var store = newContextStore()
  if not context.isNil:
    store.root = store.arena.fromJson(context)
  store.calculate_render_state_items_for(source_path)
