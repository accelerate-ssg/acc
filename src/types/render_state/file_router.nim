import json, strutils, sequtils, re, os, unittest, sugar

import logger
import types/render_state
import parser

# Iterate over a JSON object and create paths for each key
proc calculate_render_state_items_for*(context: JsonNode, source_path: string): seq[RenderStateItem] =

  let paths = parse(context, source_path)

  for (path, item, items) in paths:
    let (output_path, filename, _) = split_file( path )
    result.add( init_render_state_item(
      source_path = source_path,
      output_path = output_path / filename.strip() & ".html",
      render = true,
      item = item,
      items = items
    ))



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
      actual = state.calculate_render_state_items_for("products/{products}.mustache").map( (item) => item.output_path )
      expected = [
        "products/luxe_locks.html",
        "products/style_sleek.html",
        "products/curl_care.html",
        "products/volume_boost.html",
      ]
    check actual == expected

  test "content key replacement, nested path":
    let
      actual = state.calculate_render_state_items_for("nested/path/{nested.path}.mustache").map( (item) => item.output_path )
      expected = [
        "nested/path/test.html",
      ]
    check actual == expected

  test "group on simple attribute":
    let
      actual = state.calculate_render_state_items_for("products/{products.name}.mustache").map( (item) => item.output_path )
      expected = [
        "products/Volume boost.html",
        "products/Curl care.html",
        "products/Style sleek.html",
        "products/Luxe locks.html"
      ]
    check actual == expected

  test "group on array":
    let
      actual = state.calculate_render_state_items_for("products/{products.categories}.mustache").map( (item) => item.output_path )
      expected = [
        "products/shampoo.html",
        "products/conditioner.html",
        "products/hair spray.html"
      ]
    check actual == expected

  test "single page":
    let
      actual = state.calculate_render_state_items_for("products/no_groups.mustache").map( (item) => item.output_path )
      expected = [
        "products/no_groups.html",
      ]
    check actual == expected
