import json, strutils, sequtils, re, os, unittest, sugar

import logger
import types/render_state
# Intentionally named to match the matcher it represents. Nim does not allow for non word characters in identifiers.
import ｛attribute_match｝ 
import ［array_match］
import （key_match）



let
  AttributeMatch = re"\{(.*?)\}"
  ArrayMatch = re"\[(.*?)\]"
  KeyMatch = re"\((.*?)\)"

# Iterate over a JSON object and create paths for each key
proc calculate_render_state_items_for*(context: JsonNode, source_path: string): seq[RenderStateItem] =
  var
    local_context = context

  let
    tokens = source_path.split('/')
    #(output_path, filename) = split_path( source_path )
    (output_path, filename, _) = split_file( source_path )
    context_path = (if output_path.len > 0: output_path.split('/') else: @[])

    attribute_match = filename.findBounds( AttributeMatch )
    array_match = filename.findBounds( ArrayMatch )
    key_match = filename.findBounds( KeyMatch )
    
  result = @[]

  # Traverse the context along the path given by the source path.
  # A source_path of "shop/products/{slug}.mustache" will traverse the context
  # to "shop.products" and then render the template for each value in the
  # "shop.products" array/object.
  for token in context_path:
    local_context = local_context{token}
    if local_context == nil:
      warn "Skipping The path '", context_path.join("."), "' doesn't exist."
      return

  let
    template_render_state_item = init_render_state_item(
      source_path = source_path,
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
      attribute_name = filename[attribute_match[0]+1 .. attribute_match[1]-1]

    return local_context.render_attribute_match( attribute_name, template_render_state_item )

  elif array_match != (-1,0):
    # We have an array match. The filename part of the path will be replaced
    # with the value of the named attribute for each unique value in that
    # attribute, collected from each value in the array/object.
    let
      attribute_name = filename[array_match[0]+1 .. array_match[1]-1]

    return local_context.render_array_match( attribute_name, template_render_state_item )

  else:
    # No key replacement template, no attribute match, no array match.
    # This is a single page template, just replace the extension and render.
    result.add( template_render_state_item.init_render_state_item(
      output_path = output_path / filename.strip() & ".html",
      item = template_render_state_item.item,
      items = template_render_state_item.items
    ) )



suite "file based routing tests":

  setup:
    let state = %*
      {
        "nested": {
          "path": {
            "test": {
              "name": "nested path",
            }
          }
        },
        "products": {
          "luxe_locks": {
            "name": "Luxe locks",
            "categories": ["conditioner"],
          },
          "style_sleek": {
            "name": "Style sleek",
            "categories": ["shampoo"],
          },
          "curl_care": {
            "name": "Curl care",
            "categories": ["shampoo","conditioner"],
          },
          "volume_boost": {
            "name": "Volume boost",
            "categories": ["hair spray"],
          },
        }
      }

  test "content key replacement":
    let
      actual = state.calculate_render_state_items_for("src/products/().mustache").map( (item) => item.output_path )
      expected = [
        "build/products/luxe_locks.html",
        "build/products/style_sleek.html",
        "build/products/curl_care.html",
        "build/products/volume_boost.html",
      ]
    check actual == expected

  test "content key replacement, nested path":
    let
      actual = state.calculate_render_state_items_for("src/nested/path/().mustache").map( (item) => item.output_path )
      expected = [
        "build/nested/path/test.html",
      ]
    check actual == expected

  test "group on simple attribute":
    let
      actual = state.calculate_render_state_items_for("src/products/{name}.mustache").map( (item) => item.output_path )
      expected = [
        "build/products/Luxe locks.html",
        "build/products/Style sleek.html",
        "build/products/Curl care.html",
        "build/products/Volume boost.html",
      ]
    check actual == expected

  test "group on array":
    let
      actual = state.calculate_render_state_items_for("src/products/[categories].mustache").map( (item) => item.output_path )
      expected = [
        "build/products/conditioner.html",
        "build/products/shampoo.html",
        "build/products/hair spray.html",
      ]
    check actual == expected

  test "single page":
    let
      actual = state.calculate_render_state_items_for("src/products/no_groups.mustache").map( (item) => item.output_path )
      expected = [
        "build/products/no_groups.html",
      ]
    check actual == expected
