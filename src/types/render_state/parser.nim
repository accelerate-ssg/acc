import json
import strutils, sequtils, re
import tables, sets
import logging

type
  ResolveResult = object
    path_atom: string
    context: JsonNode
    lastArrayItem: JsonNode
    item: JsonNode
    items: seq[JsonNode]

proc toString(node: JsonNode): string =
  ## Converts a JsonNode to its string representation.
  case node.kind
  of JString: return node.getStr
  of JInt, JFloat, JBool: return $node
  of JNull: return "null"
  else:
    warn "Unsupported node kind in toString: ", $node.kind
    return ""

proc splitPath(input: string): seq[string] =
  ## Splits the input path template into segments.
  let pattern = re"(\{[^}]+\}|[^{}]+)"
  return input.findAll(pattern).filterIt(it != "")

proc parseAtoms(segment: string): seq[string] =
  ## Parses a dynamic segment into atoms.
  return segment[1..^2].split('.')

proc resolveAtoms(context: JsonNode, atoms: seq[string], lastArrayItem: JsonNode): seq[ResolveResult] =
  ## Recursively resolves atoms in the context and returns possible path atoms.
  if atoms.len == 0:
    case context.kind
    of JArray:
      warn "Array of scalars found in context: ", $context
      for item in context:
        result.add(
          ResolveResult(
            path_atom: toString(item),
            context: lastArrayItem,
            lastArrayItem: lastArrayItem,
            items: @[lastArrayItem],
            item: item
          )
        )
    of JObject:
      warn "Object found in context: ", $context
      for (key, value) in context.pairs:
        result.add(
          ResolveResult(
            path_atom: key,
            context: value,
            lastArrayItem: lastArrayItem,
            item: lastArrayItem
          )
        )
    else:
      result.add(
        ResolveResult(
          path_atom: toString(context),
          context: lastArrayItem,
          lastArrayItem: lastArrayItem,
          item: lastArrayItem
        )
      )
  else:
    let atom = atoms[0]
    let restAtoms = atoms[1..^1]
    case context.kind
    of JArray:
      for item in context:
        if item.kind == JObject:
          # Update lastArrayItem since we're entering a new array item
          result = result & resolveAtoms(item, atoms, item)
        else:
          # Array of scalars
          warn "Array of scalars found in context: ", $context
          if restAtoms.len == 0:
            result.add(
              ResolveResult(
                path_atom: toString(item),
                context: lastArrayItem,
                lastArrayItem: lastArrayItem,
                items: @[lastArrayItem]
              )
            )
    of JObject:
      if context.hasKey(atom):
        result = result & resolveAtoms(context[atom], restAtoms, lastArrayItem)
      else:
        for (key, value) in context.pairs:
          if value.kind == JObject and value.hasKey(atom):
            result = result & resolveAtoms(value{atom}, restAtoms, lastArrayItem)
    else:
      warn "Unsupported context kind: ", $context.kind
  return result

proc processSegments(context: JsonNode, segments: seq[string], currentPath: string, item: JsonNode, items: seq[JsonNode], lastArrayItem: JsonNode, resultsTable: var Table[string, (JsonNode, seq[JsonNode])]) =
  ## Processes the segments of the path template recursively, accumulating results into resultsTable.
  if segments.len == 0:
    info "Generated path: ", currentPath
    if resultsTable.hasKey(currentPath):
      let (current_item, current_items) = resultsTable[currentPath]
      resultsTable[currentPath] = (current_item, current_items & items)
    else:
      resultsTable[currentPath] = (item, items)
  else:
    let segment = segments[0]
    let restSegments = segments[1..^1]
    info "Processing segment: ", segment, " with currentPath: ", currentPath
    if segment.startsWith("{") and segment.endsWith("}"):
      let atoms = parseAtoms(segment)
      let resolvedAtoms = resolveAtoms(context, atoms, lastArrayItem)
      for res in resolvedAtoms:
        let newPath = currentPath & res.path_atom
        info "New path after dynamic segment: ", newPath
        processSegments(res.context, restSegments, newPath, res.item, res.items, res.lastArrayItem, resultsTable)
    else:
      let newPath = currentPath & segment
      info "New path after static segment: ", newPath
      processSegments(context, restSegments, newPath, item, items, lastArrayItem, resultsTable)

proc parse*(context: JsonNode, path: string): seq[(string, JsonNode, JsonNode)] =
  ## Parses the path template and generates a table mapping paths to contexts.
  let segments = splitPath(path)
  var resultsTable = initTable[string, (JsonNode, seq[JsonNode])]()
  processSegments(context, segments, "", newJNull(), @[], nil, resultsTable)
  for (path, value) in resultsTable.pairs:
    let (item, items) = value
    result.add((path, item, %items))

# Test cases
if isMainModule:
  let context = parseJson("""
  {
    "authors": [
      {
        "name": "Author1",
        "personal_info": {
          "names": {
            "full_name": "Author One"
          }
        },
        "books": [
          {
            "title": "Book1",
            "chapters": [
              { "number": 1 },
              { "number": 2 }
            ]
          },
          {
            "title": "Book2",
            "chapters": [
              { "number": 1 }
            ]
          }
        ]
      },
      {
        "name": "Author2",
        "personal_info": {
          "names": {
            "full_name": "Author Two"
          }
        },
        "books": [
          {
            "title": "Book3",
            "chapters": [
              { "number": 1 },
              { "number": 2 },
              { "number": 3 }
            ]
          }
        ]
      }
    ],
    "products": [
      {
        "slug": "product1",
        "name": "Product 1",
        "categories": ["cat1", "cat2"]
      },
      {
        "slug": "product2",
        "name": "Product 2",
        "categories": ["cat1"]
      }
    ],
    "manufacturers": {
      "Manufacturer1": {
        "products": [
          {
            "name": "Product1",
            "categories": ["catA", "catB"]
          },
          {
            "name": "Product2",
            "categories": ["catC"]
          }
        ]
      },
      "Manufacturer2": {
        "products": [
          {
            "name": "Product3",
            "categories": ["catB"]
          }
        ]
      }
    }
  }
  """)

  proc testParse(context: JsonNode, path: string, expected: seq[(string, JsonNode, seq[JsonNode])]) =
    let results = parse(context, path)
    let generatedPaths = results.mapIt(it[0])
    let expectedPaths = expected.mapIt(it[0])
    assert generatedPaths.toHashSet() == expectedPaths.toHashSet(),
      "Test failed for path: " & path & "\nExpected: " & $expected & "\nGot: " & $generatedPaths

    # For demonstration, print paths and associated contexts
    for (path, item, items) in results:
      echo "Path: ", path
      echo "Associated Contexts:"
      if not item.isNil:
        echo "Item: ", item.pretty()
      if items.len > 0:
        echo "Items:"
      for i in items:
        echo "   ", i.pretty()

  let no_items = seq[JsonNode](@[])

  #testParse(context, "{authors.name}.html", @["Author1.html", "Author2.html"])
  testParse(context, "{authors.name}/{books.title}.html", @[
    ("Author1/Book1.html", context{"authors","0","books","0"}, no_items), 
    ("Author1/Book2.html", context{"authors","0","books","1"}, no_items), 
    ("Author2/Book3.html", context{"authors","1","books","0"}, no_items)
  ])
  # testParse(context, "{authors.name}/{books.title}/chapter{chapters.number}.html", @[
  #   "Author1/Book1/chapter1.html",
  #   "Author1/Book1/chapter2.html",
  #   "Author1/Book2/chapter1.html",
  #   "Author2/Book3/chapter1.html",
  #   "Author2/Book3/chapter2.html",
  #   "Author2/Book3/chapter3.html"
  # ])
  # testParse(context, "{authors.personal_info.names.full_name}.html", @[
  #   "Author One.html",
  #   "Author Two.html"
  # ])
  # testParse(context, "products/{products.categories}.html", @[
  #   "products/cat1.html",
  #   "products/cat2.html"
  # ])
  # testParse(context, "{manufacturers.products.categories}.html", @[
  #   "catA.html",
  #   "catB.html",
  #   "catC.html"
  # ])
  # testParse(context, "{manufacturers}/{products.name}.html", @[
  #   "Manufacturer1/Product1.html",
  #   "Manufacturer1/Product2.html",
  #   "Manufacturer2/Product3.html"
  # ])



