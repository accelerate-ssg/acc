proc loadFile*(config_file: string): YamlNode =
  ## Loads a YAML file and returns a YamlNode tree.
  var parser = initYamlParser()
  var events = parser.parse(config_file)

  # Skip the stream start event
  var e = events.next()
  if e.kind != yamlStartStream:
    raise newException(ValueError, "Invalid stream start")

  # Ensure we have a document
  if events.peek().kind != yamlStartDoc:
    raise newException(ValueError, "Invalid document start")
  discard events.next()

  # Construct the YamlNode
  result = constructNode(events)

  # Ensure we've reached the end of the stream
  e = events.next()
  if e.kind != yamlEndDoc:
    raise newException(ValueError, "Invalid document end: " & $e.kind )

  # Ensure we've reached the end of the stream
  e = events.next()
  if e.kind != yamlEndStream:
    raise newException(ValueError, "Invalid stream end: " & $e.kind )

proc loadConfig*(config_file: string): Config =
  let yaml = loadFile(config_file)
  
  var config = Config()
  
  config.genericConfig = loadToJson(config_file)[0]
  config.manifestVersion = safeInterpolateStr(safeGet(yaml, "manifest_version"), Config(genericConfig: newJObject()))
  
  # Plain control flow, not Options.map: the loaders raise
  # ConfigShapeError on malformed values, and an exception propagating
  # out of a .map closure segfaults here (nim 2.0.6/orc) instead of
  # unwinding — which is how a bad config crashed the binary rather
  # than reporting what was wrong.
  let directoriesNode = safeGet(yaml, "directories")
  if directoriesNode.isSome:
    if directoriesNode.get.kind != yMapping:
      raise newException(ConfigShapeError, "'directories' must be a mapping")
    config.directories = loadDirectories(directoriesNode.get, config)

  let workflowsNode = safeGet(yaml, "workflows")
  if workflowsNode.isSome:
    if workflowsNode.get.kind != ySequence:
      raise newException(ConfigShapeError, "'workflows' must be a list")
    for entry in workflowsNode.get.elems:
      config.workflows.add(loadWorkflow(entry, config))

  # Remove the schema config keys from the generic config object
  if config.genericConfig.hasKey("manifest_version"): config.genericConfig.delete("manifest_version")
  if config.genericConfig.hasKey("directories"): config.genericConfig.delete("directories")
  if config.genericConfig.hasKey("workflows"): config.genericConfig.delete("workflows")
  
  return config
