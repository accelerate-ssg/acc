import json



proc node_to_string*(node: JsonNode): string =
  ## Renders a JSON node as the string used to name an output file.
  ## A missing node yields "" so callers can skip the element rather than
  ## dereferencing nil.
  if node.isNil:
    return ""

  case node.kind:
    of JNull:
      return ""
    of JString:
      return node.getStr
    of JInt:
      return $node.getInt
    of JFloat:
      return $node.getFloat
    of JBool:
      return $node.getBool
    else:
      return $node
