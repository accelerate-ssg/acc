import json

proc node_to_string*(node: JsonNode): string =
  case node.kind:
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
