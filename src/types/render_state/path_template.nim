## Parses a template path into segments, once, before any expansion happens.
##
## Nothing in here looks at the context. A parsed template is inert data, so a
## value resolved during expansion can never be mistaken for a binding no matter
## which characters it happens to contain.
##
##   binding := "{" [ "." ] [ collection ] [ filter ] [ selector ] "}"
##
##   .            resolve inside the enclosing scope; omitted means the root
##   collection   dotted path to a collection
##   filter       "(" attribute.path = $reference ")"
##   selector     "[" attribute.path [ "[]" ] "]"
##   []           trailing, inside a selector: flatten an array attribute

import strutils, os
import std/options

type
  ReferenceKind* = enum
    refKey
    refParent

  Reference* = object
    kind*: ReferenceKind
    ## Fields after `parent`, so $parent.name is @["name"] and $parent is @[].
    path*: seq[string]

  Filter* = object
    attribute*: seq[string]
    reference*: Reference

  Selector* = object
    ## Empty means the element is named by its key, or its index in an array.
    attribute*: seq[string]
    flatten*: bool

  Binding* = object
    scoped*: bool
    ## Empty together with scoped means the enclosing scope itself.
    collection*: seq[string]
    filter*: Option[Filter]
    selector*: Selector

  Segment* = object
    prefix*: string
    binding*: Option[Binding]
    suffix*: string

  PathTemplate* = object
    segments*: seq[Segment]


proc split_dotted(text: string): seq[string] =
  if text.len == 0: @[]
  else: text.split('.')

proc matching_bracket(text: string, start: int, opening, closing: char): int =
  ## Index of the bracket closing the one at `start`, or -1. Counts depth so a
  ## selector may contain the [] that marks a flattened attribute.
  var depth = 0
  for index in start ..< text.len:
    if text[index] == opening:
      depth.inc
    elif text[index] == closing:
      depth.dec
      if depth == 0:
        return index
  return -1

proc parse_reference(raw: string): Reference =
  let text = raw.strip()

  if not text.startsWith("$"):
    raise newException(ValueError,
      "A filter compares against $key or $parent, got '" & raw & "'")

  let atoms = text[1 .. ^1].split('.')

  if atoms[0] == "key":
    if atoms.len > 1:
      raise newException(ValueError, "$key takes no fields, got '" & raw & "'")
    return Reference(kind: refKey, path: @[])

  if atoms[0] == "parent":
    return Reference(kind: refParent, path: atoms[1 .. ^1])

  raise newException(ValueError,
    "Unknown filter reference '" & raw & "', expected $key or $parent")

proc parse_selector(raw: string): Selector =
  var text = raw.strip()
  var flatten = false

  if text.endsWith("[]"):
    flatten = true
    text = text[0 .. ^3].strip()

  Selector(attribute: split_dotted(text), flatten: flatten)

proc parse_filter(raw: string): Filter =
  let separator = raw.find('=')

  if separator < 0:
    raise newException(ValueError,
      "A filter reads attribute = $reference, got '(" & raw & ")'")

  Filter(
    attribute: split_dotted(raw[0 ..< separator].strip()),
    reference: parse_reference(raw[separator + 1 .. ^1])
  )

proc parse_binding(raw: string): Binding =
  var text = raw.strip()
  var scoped = false

  if text.startsWith("."):
    scoped = true
    text = text[1 .. ^1].strip()

  var cursor = 0
  while cursor < text.len and text[cursor] notin {'(', '['}:
    cursor.inc

  let collection = split_dotted(text[0 ..< cursor].strip())
  var filter = none(Filter)
  var selector = Selector(attribute: @[], flatten: false)

  if cursor < text.len and text[cursor] == '(':
    let closing = matching_bracket(text, cursor, '(', ')')
    if closing < 0:
      raise newException(ValueError, "Unclosed ( in binding '{" & raw & "}'")
    filter = some(parse_filter(text[cursor + 1 ..< closing]))
    cursor = closing + 1

  if cursor < text.len and text[cursor] == '[':
    let closing = matching_bracket(text, cursor, '[', ']')
    if closing < 0:
      raise newException(ValueError, "Unclosed [ in binding '{" & raw & "}'")
    selector = parse_selector(text[cursor + 1 ..< closing])
    cursor = closing + 1

  if cursor < text.len:
    raise newException(ValueError,
      "Unexpected '" & text[cursor .. ^1] & "' in binding '{" & raw & "}'")

  if not scoped and collection.len == 0:
    raise newException(ValueError,
      "A binding needs a collection, or a leading . for the enclosing scope: '{" &
      raw & "}'")

  Binding(scoped: scoped, collection: collection, filter: filter, selector: selector)

proc parse_segment(raw: string): Segment =
  let opening = raw.find('{')

  if opening < 0:
    return Segment(prefix: raw, binding: none(Binding), suffix: "")

  let closing = matching_bracket(raw, opening, '{', '}')

  if closing < 0:
    raise newException(ValueError, "Unclosed { in path segment '" & raw & "'")

  let suffix = raw[closing + 1 .. ^1]

  if suffix.contains('{'):
    raise newException(ValueError,
      "A path segment carries at most one binding, got '" & raw & "'")

  Segment(
    prefix: raw[0 ..< opening],
    binding: some(parse_binding(raw[opening + 1 ..< closing])),
    suffix: suffix
  )

proc parse_path_template*(source_path: string): PathTemplate =
  ## The extension is dropped here; expansion appends .html instead.
  let
    (directory, filename, _) = source_path.split_file()
    bare = if directory.len > 0: directory & "/" & filename else: filename

  var segments: seq[Segment] = @[]

  for raw in bare.split('/'):
    if raw.len > 0:
      segments.add(parse_segment(raw))

  PathTemplate(segments: segments)
