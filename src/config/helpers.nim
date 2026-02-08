proc getGenericConfig*(config: Config, path: varargs[string]): JsonNode =
  result = config.genericConfig
  for key in path:
    if result.kind == JObject and result.hasKey(key):
      result = result[key]
    else:
      return newJNull()

proc interpolate(value: string, config: Config): string =
  result = value
  for match in value.findAll(re"\$\{([^}]+)\}"):
    let path = match[2..^2].split(".")
    let replacement = config.getGenericConfig(path).getStr(match)
    result = result.replace(match, replacement)

proc interpolateJsonNode(node: JsonNode, config: Config): JsonNode =
  case node.kind
  of JString:
    result = newJString(interpolate(node.getStr, config))
  of JObject:
    result = newJObject()
    for key, value in node.pairs:
      result[key] = interpolateJsonNode(value, config)
  of JArray:
    result = newJArray()
    for item in node.items:
      result.add(interpolateJsonNode(item, config))
  else:
    result = node

proc safeGet(node: YamlNode, key: string): Option[YamlNode] =
  try:
    return some(node[key])
  except KeyError:
    return none(YamlNode)

proc safeInterpolateStr(node: Option[YamlNode], config: Config, default: string = ""): string =
  if node.isSome:
    interpolate(node.get.content, config)
  else:
    default

proc safeInterpolateSeq(node: Option[YamlNode], config: Config): seq[string] =
  if node.isSome:
    node.get.elems.mapIt(interpolate(it.content, config))
  else:
    @[]
