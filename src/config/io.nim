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

proc convertLegacyConfig(yaml: YamlNode, config: var Config) =
  ## Convert a pre-0.2 `config.yaml` (a flat `build:` list of plugins) to
  ## the workflow model, so existing sites build without a rewrite.
  ##
  ## Each legacy step becomes its own single-step workflow, chained by a
  ## `build` composition. That is not just packaging: the old engine
  ## recalculated the render state before *every* plugin, and acc2
  ## snapshots it once per workflow — so per-step workflows reproduce the
  ## legacy semantics exactly (content loaded by @yaml is visible to the
  ## router before the template step runs).
  let buildNode = safeGet(yaml, "build")
  if buildNode.isNone: return
  if buildNode.get.kind != ySequence:
    raise newException(ConfigShapeError, "'build' must be a list of steps")

  # Legacy sites also use the legacy path grammar in template file names
  # ({manufacturers.path} = group by attribute); route them accordingly.
  config.legacyPaths = true

  # Legacy directory defaults (DEFAULT_*_DIRECTORY in 0.1.x), with
  # `content_root` honoured. Note the destination default was "public",
  # not "build".
  let contentRoot = safeGet(yaml, "content_root")
  config.directories = Directories(
    src: "src",
    destination: "public",
    content: (if contentRoot.isSome and contentRoot.get.kind == yScalar:
                contentRoot.get.content
              else: "content"),
    config: ".acc",
    work: ".acc/work",
    scripts: "scripts",
    build: ".acc/build",
  )

  var stepNames: seq[string] = @[]
  for entry in buildNode.get.elems:
    if entry.kind != yMapping:
      raise newException(ConfigShapeError,
        "each entry under 'build' must be a mapping with a 'name'")
    let nameNode = safeGet(entry, "name")
    if nameNode.isNone or nameNode.get.kind != yScalar:
      raise newException(ConfigShapeError,
        "each entry under 'build' needs a string 'name'")
    let name = nameNode.get.content

    var step = Step(extraConfig: newJObject())
    if name.startsWith("@"):
      step.module = name
    else:
      step.script = name
    let cfgNode = safeGet(entry, "config")
    if cfgNode.isSome:
      if cfgNode.get.kind != yMapping:
        raise newException(ConfigShapeError,
          "'config' of build step '" & name & "' must be a mapping")
      for key, value in cfgNode.get.fields.pairs:
        if key.kind == yScalar and value.kind == yScalar:
          step.extraConfig[key.content] = newJString(value.content)

    let wfName = "step-" & $(stepNames.len + 1) & "-" &
      name.replace("@", "")
    stepNames.add(wfName)
    config.workflows.add(Workflow(
      name: wfName, maxConcurrent: 1, steps: @[step]))

  config.workflows.add(Workflow(
    name: "build", maxConcurrent: 1, workflows: stepNames))

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

  # Pre-0.2 configs declare a flat `build:` plugin list instead of
  # workflows — convert them so existing sites keep building.
  if config.workflows.len == 0:
    convertLegacyConfig(yaml, config)

  # Remove the schema config keys from the generic config object
  if config.genericConfig.hasKey("manifest_version"): config.genericConfig.delete("manifest_version")
  if config.genericConfig.hasKey("directories"): config.genericConfig.delete("directories")
  if config.genericConfig.hasKey("workflows"): config.genericConfig.delete("workflows")
  if config.genericConfig.hasKey("build"): config.genericConfig.delete("build")
  
  return config
