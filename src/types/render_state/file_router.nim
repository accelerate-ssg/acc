import json, strutils, sequtils, re, os

import logger
import types/render_state
import node_to_string
import indifferent_iterator
# Intentionally named to match the matcher it represents. Nim does not allow for non word characters in identifiers.
import ｛attribute_match｝
import ［array_match］
import （key_match）



let
  AttributeMatch = re"\{(.*?)\}"
  ArrayMatch = re"\[(.*?)\]"
  KeyMatch = re"\((.*?)\)"

proc parseDottedRef(raw: string): (string, string) =
  ## Splits a dotted reference like "manufacturers.path" into
  ## collection name ("manufacturers") and attribute ("path").
  let dot_pos = raw.find('.')
  if dot_pos >= 0:
    return (raw[0 ..< dot_pos], raw[dot_pos + 1 .. ^1])
  return ("", "")

proc resolveDynamicDirSegment(context: JsonNode, segment: string): seq[(string, JsonNode)] =
  ## Resolves a dynamic directory segment like {manufacturers.path} into
  ## a list of (resolved_path_value, item_context) pairs.
  let
    attr_bounds = segment.findBounds(re"\{(.*?)\}")
    key_bounds = segment.findBounds(re"\((.*?)\)")

  if attr_bounds != (-1,0):
    let raw = segment[attr_bounds[0]+1 .. attr_bounds[1]-1]
    let (collection_name, attribute_name) = parseDottedRef(raw)
    let col = if collection_name.len > 0: context{collection_name} else: nil
    if col == nil:
      return @[]
    for item in col.each():
      if item.kind == JObject:
        let attr = if attribute_name.len > 0: attribute_name else: raw
        let val = node_to_string(item{attr})
        if val != "":
          result.add((val, item))
  elif key_bounds != (-1,0):
    let raw = segment[key_bounds[0]+1 .. key_bounds[1]-1]
    let (collection_name, _) = parseDottedRef(raw)
    let col = if collection_name.len > 0: context{collection_name} else: nil
    if col == nil:
      return @[]
    if col.kind == JObject:
      for key, val in col.pairs:
        result.add((key, val))
    elif col.kind == JArray:
      for i, val in col.elems:
        result.add(($i, val))

proc isDynamic(segment: string): bool =
  segment.contains('{') or segment.contains('(') or segment.contains('[')

# Iterate over a JSON object and create paths for each key.
# original_source_path is the on-disk template path, used when dynamic directory
# segments are resolved (the output path changes but the source stays the same).
proc calculate_render_state_items_for*(context: JsonNode, source_path: string, original_source_path: string = ""): seq[RenderStateItem] =
  var
    local_context = context

  let
    tokens = source_path.split('/')
    (output_path, filename, _) = split_file( source_path )
    context_path = (if output_path.len > 0: output_path.split('/') else: @[])

    attribute_match = filename.findBounds( AttributeMatch )
    array_match = filename.findBounds( ArrayMatch )
    key_match = filename.findBounds( KeyMatch )

  result = @[]

  # Check for dynamic directory segments like {manufacturers.path} in the path.
  # These expand the template into multiple items, one per resolved value.
  # E.g. "produkter/{manufacturers.path}/{products.id}.mustache" expands
  # {manufacturers.path} into kubota, junkkari, etc. and for each, resolves
  # the products within that manufacturer's context.
  for i, token in context_path:
    if token.isDynamic:
      let resolved = resolveDynamicDirSegment(context, token)
      if resolved.len == 0:
        warn "Skipping Dynamic directory segment '", token, "' resolved to nothing."
        return
      # For each resolved value, reconstruct the path with the resolved value
      # and recurse with the item's context. Use the original last token (with
      # extension) since split_file strips extensions that interfere with
      # dotted notation like {products.id}.mustache.
      let
        prefix = context_path[0 ..< i].join("/")
        suffix_parts = context_path[i + 1 .. ^1]
        original_filename = tokens[^1]  # Last token preserves full filename with ext
      for (resolved_value, item_context) in resolved:
        let new_dir = if prefix.len > 0: prefix & "/" & resolved_value
                      else: resolved_value
        let remaining = if suffix_parts.len > 0: suffix_parts.join("/") & "/" & original_filename
                        else: original_filename
        let new_source_path = new_dir & "/" & remaining
        # Recurse with the item's context merged: the item becomes the local
        # context for further resolution
        var merged_context = context.copy()
        # Make the item available for nested lookups
        for key, val in item_context.pairs:
          merged_context[key] = val
        let orig = if original_source_path.len > 0: original_source_path else: source_path
        result = result.concat(
          merged_context.calculate_render_state_items_for(new_source_path, orig)
        )
      return

  # Check if the filename uses dotted notation like {collection.attribute},
  # [collection.attribute], or (collection.key). Dotted notation resolves the
  # first part from root context, decoupling URL structure from data structure.
  # E.g. "produkter/{manufacturers.path}.mustache" iterates root context
  # "manufacturers" and uses "path" as the attribute, outputting under "produkter/".
  var
    root_collection_name = ""
    resolved_attribute_name = ""

  if attribute_match != (-1,0):
    let raw = filename[attribute_match[0]+1 .. attribute_match[1]-1]
    (root_collection_name, resolved_attribute_name) = parseDottedRef(raw)

  elif array_match != (-1,0):
    let raw = filename[array_match[0]+1 .. array_match[1]-1]
    (root_collection_name, resolved_attribute_name) = parseDottedRef(raw)

  elif key_match != (-1,0):
    let raw = filename[key_match[0]+1 .. key_match[1]-1]
    (root_collection_name, resolved_attribute_name) = parseDottedRef(raw)

  # If dotted notation was used, resolve collection from root context
  if root_collection_name.len > 0:
    if context{root_collection_name} != nil:
      local_context = context{root_collection_name}
    else:
      warn "Skipping Root collection '", root_collection_name, "' doesn't exist in context."
      return
  else:
    # Standard traversal: follow the directory path through context.
    # A source_path of "shop/products/{slug}.mustache" will traverse the context
    # to "shop.products" and then render the template for each value in the
    # "shop.products" array/object.
    for token in context_path:
      local_context = local_context{token}
      if local_context == nil:
        warn "Skipping The path '", context_path.join("."), "' doesn't exist."
        return

  let
    effective_source_path = if original_source_path.len > 0: original_source_path else: source_path
    template_render_state_item = init_render_state_item(
      source_path = effective_source_path,
      output_path = output_path,
      render = true,
      item = ( if local_context.kind == JObject and local_context.has_key( filename ): local_context{filename} else: local_context),
      items = newJArray()
    )

  if key_match != (-1,0):
    # We have a key replacement template.
    # The filename part of the path will be replaced with the key/index for
    # each value in the array/object.
    return local_context.render_key_match( template_render_state_item )

  elif attribute_match != (-1,0):
    # We have an attribute match. The filename part of the path will be
    # replaced with the value of the named attribute for each value in the
    # array/object.
    let
      attribute_name = if resolved_attribute_name.len > 0: resolved_attribute_name
                       else: filename[attribute_match[0]+1 .. attribute_match[1]-1]

    return local_context.render_attribute_match( attribute_name, template_render_state_item )

  elif array_match != (-1,0):
    # We have an array match. The filename part of the path will be replaced
    # with the value of the named attribute for each unique value in that
    # attribute, collected from each value in the array/object.
    let
      attribute_name = if resolved_attribute_name.len > 0: resolved_attribute_name
                       else: filename[array_match[0]+1 .. array_match[1]-1]

    return local_context.render_array_match( attribute_name, template_render_state_item )

  else:
    # No key replacement template, no attribute match, no array match.
    # This is a single page template, just replace the extension and render.
    result.add( template_render_state_item.init_render_state_item(
      output_path = output_path / filename.strip() & ".html",
      item = template_render_state_item.item,
      items = template_render_state_item.items
    ) )

# Router behaviour is specified by test/path_router_spec.nim.
