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

type ConfigShapeError* = object of ValueError
  ## A config value has the wrong YAML shape (mapping where a string was
  ## expected, etc.). Raised with a message naming the offending value so
  ## the CLI can report it instead of dying on a field-access defect.

proc describeKind(node: YamlNode): string =
  case node.kind
  of yScalar: "a string"
  of ySequence: "a list"
  of yMapping: "a mapping"
  else: "an alias"

proc safeGet(node: YamlNode, key: string): Option[YamlNode] =
  # Indexing a non-mapping is not a KeyError — guard the kind explicitly
  # or the lookup dies on a field-access defect instead of returning
  # "not present".
  if node.kind != yMapping:
    return none(YamlNode)
  try:
    return some(node[key])
  except KeyError:
    return none(YamlNode)

proc safeInterpolateStr(node: Option[YamlNode], config: Config, default: string = ""): string =
  if node.isSome:
    if node.get.kind != yScalar:
      raise newException(ConfigShapeError,
        "expected a string, got " & describeKind(node.get))
    interpolate(node.get.content, config)
  else:
    default

proc safeInterpolateSeq(node: Option[YamlNode], config: Config): seq[string] =
  if node.isSome:
    let n = node.get
    if n.kind != ySequence:
      raise newException(ConfigShapeError,
        "expected a list of strings, got " & describeKind(n))
    for item in n.elems:
      if item.kind != yScalar:
        raise newException(ConfigShapeError,
          "expected a list of strings, got a list containing " &
          describeKind(item))
    n.elems.mapIt(interpolate(it.content, config))
  else:
    @[]
