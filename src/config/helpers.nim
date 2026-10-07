proc getGenericConfig*(config: Config, path: varargs[string]): JsonNode =
  ## Walks the passthrough config by path. A segment addressing an array is
  ## its index, so `domains[0]` arrives here as @["domains", "0"] — see
  ## split_config_path.
  result = config.genericConfig
  for key in path:
    if result.kind == JObject and result.hasKey(key):
      result = result[key]
    elif result.kind == JArray:
      try:
        let index = key.parseInt
        if index < 0 or index >= result.len:
          return newJNull()
        result = result[index]
      except ValueError:
        return newJNull()
    else:
      return newJNull()

proc split_config_path*(path: string): seq[string] =
  ## Splits an interpolation path into the segments getGenericConfig walks.
  ## Dots separate object keys and a trailing `[n]` is an array index, so
  ## `domains[0]` becomes @["domains", "0"] and `a.b[1].c` becomes
  ## @["a", "b", "1", "c"]. Several indices in a row are allowed.
  result = @[]
  for atom in path.split("."):
    var name = atom
    var indices: seq[string] = @[]
    while name.len > 0 and name[^1] == ']':
      let open = name.rfind('[')
      if open < 0:
        break
      indices.insert(name[open + 1 ..< name.high], 0)
      name = name[0 ..< open]
    if name.len > 0:
      result.add(name)
    result.add(indices)

proc interpolate(value: string, config: Config): string =
  result = value
  for match in value.findAll(re"\$\{([^}]+)\}"):
    let path = split_config_path(match[2..^2])
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
