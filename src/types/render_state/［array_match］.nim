import os
import json
import sequtils
import strutils

import logger
import types/render_state
import node_to_string
import indifferent_iterator


# Extract all unique values from a JSON array
proc extract_unique_array_values(context: JsonNode, key: string): seq[JsonNode] =
  ## This function traverses the provided `context` and returns a sequence of 
  ## unique string values for the provided `key`. The function assumes that the
  ## `key` maps to an array in the JSON object.
  ##
  runnableExamples:
    let context = %*
      [
        {
          "name": "Luxe locks",
          "categories": ["conditioner"],
        },
        {
          "name": "Style sleek",
          "categories": ["shampoo"],
        },
        {
          "name": "Curl care",
          "categories": ["shampoo","conditioner"],
        },
        {
          "name": "Volume boost",
          "categories": ["hair spray"],
        }
      ]

    assert extract_unique_array_values(context, "categories").sorted == ["conditioner", "hair spray", "shampoo"]
    assert extract_unique_array_values(context, "name").sorted == ["Curl care", "Luxe locks", "Style sleek", "Volume boost"]

  result = @[]

  for json_node in context.each:
    for value in json_node{key}:
      result.add value

  return result.deduplicate()



proc filter_items_on( context: JsonNode, attribute_name: string, attribute_value: JsonNode ): JsonNode =
  result = newJArray()

  for item in context.each:
    if item{attribute_name} != nil and item{attribute_name}.kind == JArray and item{attribute_name}.len > 0:
      if item{attribute_name}.contains(attribute_value):
        result.add item



proc render_array_match*( context: JsonNode, attribute_name: string, partial: RenderStateItem ): seq[RenderStateItem] =
  result = @[]

  var
    filtered_nodes = newJArray()

  for item in context.each:
    if item{attribute_name} != nil and item{attribute_name}.kind == JArray and item{attribute_name}.len > 0:
      filtered_nodes.add item

  if filtered_nodes.getElems.len == 0:
    warn "Skipping file: ", partial.source_path, "\n" , "Could not find array attribute: ", attribute_name, " in context path '", partial.source_path.replace("/", ".") ,"' or attribute was nil/empty for all items in that path."
    return result

  let
    unique_values = extract_unique_array_values(filtered_nodes, attribute_name)

  for json_value in unique_values:
    let
      string_value = node_to_string(json_value)
      items = context.filter_items_on(attribute_name, json_value)

    result.add( partial.init_render_state_item(
      output_path = partial.output_path / "index.html",
      item = json_value,
      items = items,
    ))
