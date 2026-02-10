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
      actual = state.calculate_render_state_items_for("products/().mustache").map( (item) => item.output_path )
      expected = [
        "products/luxe_locks.html",
        "products/style_sleek.html",
        "products/curl_care.html",
        "products/volume_boost.html",
      ]
    check actual == expected

  test "content key replacement, nested path":
    let
      actual = state.calculate_render_state_items_for("nested/path/().mustache").map( (item) => item.output_path )
      expected = [
        "nested/path/test.html",
      ]
    check actual == expected

  test "group on simple attribute":
    let
      actual = state.calculate_render_state_items_for("products/{name}.mustache").map( (item) => item.output_path )
      expected = [
        "products/Luxe locks.html",
        "products/Style sleek.html",
        "products/Curl care.html",
        "products/Volume boost.html",
      ]
    check actual == expected

  test "group on array":
    let
      actual = state.calculate_render_state_items_for("products/[categories].mustache").map( (item) => item.output_path )
      expected = [
        "products/conditioner.html",
        "products/shampoo.html",
        "products/hair spray.html",
      ]
    check actual == expected

  test "single page":
    let
      actual = state.calculate_render_state_items_for("products/no_groups.mustache").map( (item) => item.output_path )
      expected = [
        "products/no_groups.html",
      ]
    check actual == expected

  # Tests ported from acc v0.1.1 bug fixes:

  test "static template gets item from matching context key":
    let ctx = %* { "about": { "name": "About Us" } }
    let results = ctx.calculate_render_state_items_for("about.mustache")
    check results.len == 1
    check results[0].output_path == "about.html"
    check results[0].item{"name"}.getStr == "About Us"

  test "static template with no matching context key has null item":
    let ctx = %* { "other": { "name": "Other" } }
    let results = ctx.calculate_render_state_items_for("about.mustache")
    check results.len == 1
    check results[0].item == ctx

  test "nested static template looks up base name in context":
    let ctx = %* { "pages": { "about": { "name": "About Us" } } }
    let results = ctx.calculate_render_state_items_for("pages/about.mustache")
    check results.len == 1
    check results[0].output_path == "pages/about.html"
    check results[0].item{"name"}.getStr == "About Us"

  test "dynamic template with object-based collection populates item":
    let ctx = %* { "products": { "widget": { "name": "Widget" } } }
    let results = ctx.calculate_render_state_items_for("products/().mustache")
    check results.len == 1
    check results[0].output_path == "products/widget.html"
    check results[0].item{"name"}.getStr == "Widget"

  test "dynamic template with array-based collection populates item":
    let ctx = %* { "products": [ { "slug": "widget", "name": "Widget" } ] }
    let results = ctx.calculate_render_state_items_for("products/{slug}.mustache")
    check results.len == 1
    check results[0].output_path == "products/widget.html"
    check results[0].item{"name"}.getStr == "Widget"

  test "deeply nested path looks up base name in context":
    let ctx = %* { "a": { "b": { "c": { "about": { "name": "About Us" } } } } }
    let results = ctx.calculate_render_state_items_for("a/b/c/about.mustache")
    check results.len == 1
    check results[0].output_path == "a/b/c/about.html"
    check results[0].item{"name"}.getStr == "About Us"

  test "static template with scalar context value":
    let ctx = %* { "count": 42 }
    let results = ctx.calculate_render_state_items_for("count.mustache")
    check results.len == 1
    check results[0].item.getInt == 42

  test "empty context does not crash":
    let ctx = %* {}
    let results = ctx.calculate_render_state_items_for("about.mustache")
    check results.len == 1
    check results[0].item == ctx
