## Expands a parsed template path into the pages it produces.
##
## The template is parsed once, up front, and then expanded. Expansion only ever
## produces values, never new template text, so a data value containing braces
## or parentheses is inert.
##
## Router behaviour is specified by test/path_router_spec.nim.

import json, strutils, sets, tables
import std/options

import logger
import types/render_state
import path_template
import node_to_string

type
  Frame = object
    ## Where a branch of the expansion currently stands.
    scope: JsonNode
      ## What a . prefix resolves against, and what a literal template takes as
      ## its item. After a merged segment this is the group, not one element.
    elements: seq[JsonNode]
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

proc dig(node: JsonNode, path: seq[string]): JsonNode =
  result = node
  for atom in path:
    if result.isNil or result.kind != JObject:
      return nil
    result = result{atom}

iterator entries(node: JsonNode): (string, JsonNode) =
  ## Yields the name an element takes when there is no selector, and the element.
  if node.kind == JObject:
    for key, value in node:
      yield (key, value)
  elif node.kind == JArray:
    var index = 0
    for value in node:
      yield ($index, value)
      index.inc

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

proc names_for(element: JsonNode, default_name: string, selector: Selector): seq[string] =
  result = @[]

  if selector.attribute.len == 0:
    return @[default_name]

  let value = dig(element, selector.attribute)

  if value.isNil:
    return @[]

  # An attribute names one page per scalar it holds, whether it holds one value
  # or a list of them. Naming has to tolerate shape the same way comparison
  # does, or a template breaks the day a customer's scalar arrives wrapped in an
  # array. The trailing [] stays available to say a list is expected, and warns
  # when it is not.
  if value.kind == JArray:
    for entry in value:
      let text = normalize(entry)
      if text.len > 0:
        result.add(text)
  else:
    if selector.flatten:
      warn "'", selector.attribute.join("."), "[]' expected a list but found ",
        $value.kind, ", naming it as a single value."

    let text = normalize(value)
    if text.len > 0:
      result.add(text)

proc source_for(context: JsonNode, frame: Frame, binding: Binding): JsonNode =
  if binding.scoped:
    if binding.collection.len == 0: frame.scope
    else: dig(frame.scope, binding.collection)
  else:
    dig(context, binding.collection)

proc group_elements(
  frame: Frame,
  binding: Binding,
  source: JsonNode,
  source_path: string
): OrderedTable[string, seq[JsonNode]] =
  ## Filters, names, and groups. Elements landing on the same name merge, which
  ## is all that grouping is. Insertion order is kept so the output order
  ## follows the order of the data.
  result = initOrderedTable[string, seq[JsonNode]]()

  for default_name, element in source.entries:
    if binding.filter.isSome:
      let
        filter = binding.filter.get()
        left = as_set(dig(element, filter.attribute))
        right = as_set(resolve_reference(frame, filter.reference, source_path))

      if (left * right).len == 0:
        continue

    for name in names_for(element, default_name, binding.selector):
      if result.hasKey(name):
        result[name].add(element)
      else:
        result[name] = @[element]

proc join_path(prefix, addition: string): string =
  if prefix.len > 0: prefix & "/" & addition
  else: addition

proc calculate_render_state_items_for*(
  context: JsonNode,
  source_path: string
): seq[RenderStateItem] =
  result = @[]

  let template_path = parse_path_template(source_path)

  if template_path.segments.len == 0:
    return

  var frontier = @[(
    "",
    Frame(
      scope: context,
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
          result.add(init_render_state_item(
            source_path = source_path,
            output_path = joined & ".html",
            render = true,
            item = frame.scope,
            items = if frame.elements.len > 0: %frame.elements else: newJArray(),
            key = frame.key,
            parent = frame.bound_parent
          ))
        else:
          next.add((joined, frame))

        continue

      let
        binding = segment.binding.get()
        source = source_for(context, frame, binding)

      if source.isNil or (source.kind != JObject and source.kind != JArray):
        warn "Skipping '", source_path, "': no collection '",
          binding.collection.join("."), "' to expand."
        continue

      for name, elements in group_elements(frame, binding, source, source_path):
        let
          joined = join_path(path_so_far, segment.prefix & name & segment.suffix)
          single = elements.len == 1

        if is_last:
          result.add(init_render_state_item(
            source_path = source_path,
            output_path = joined & ".html",
            render = true,
            item = if single: elements[0] else: newJNull(),
            items = %elements,
            key = name,
            parent = frame.bound
          ))
        else:
          var bound: JsonNode = nil

          if single:
            bound = elements[0].copy()
            if not frame.bound.isNil:
              bound["parent"] = frame.bound

          next.add((joined, Frame(
            scope: if single: elements[0] else: %elements,
            elements: elements,
            bound: bound,
            bound_parent: frame.bound,
            key: name
          )))

    frontier = next
