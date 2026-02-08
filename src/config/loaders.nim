const
  STEP_KNOWN_KEYS = ["comment", "script", "command", "module",
                     "arguments", "depends_on", "timeout", "on_failure"]

proc loadStep(step: YamlNode, config: Config): Step =
  result = Step(
    comment: safeInterpolateStr(step.safeGet("comment"), config),
    script: safeInterpolateStr(step.safeGet("script"), config),
    command: safeInterpolateStr(step.safeGet("command"), config),
    module: safeInterpolateStr(step.safeGet("module"), config),
    arguments: safeInterpolateSeq(step.safeGet("arguments"), config),
    dependsOn: safeInterpolateSeq(step.safeGet("depends_on"), config),
    timeout: some(safeInterpolateStr(step.safeGet("timeout"), config)),
    onFailure: some(safeInterpolateStr(step.safeGet("on_failure"), config)),
  )

  if result.timeout.get == "":
    result.timeout = none(string)
  if result.onFailure.get == "":
    result.onFailure = none(string)

  if result.script == "" and result.command == "" and result.module == "":
    raise newException(ValueError, "Step must have a script, command, or module field")

  # Collect unknown keys into extraConfig
  result.extraConfig = newJObject()
  if step.kind == yMapping and step.fields != nil:
    for key, value in step.fields[]:
      let keyStr = key.content
      if keyStr notin STEP_KNOWN_KEYS:
        case value.kind
        of yScalar:
          result.extraConfig[keyStr] = newJString(safeInterpolateStr(some(value), config))
        of ySequence:
          var arr = newJArray()
          for elem in value.elems:
            arr.add(newJString(safeInterpolateStr(some(elem), config)))
          result.extraConfig[keyStr] = arr
        of yMapping:
          # For nested objects, convert recursively via the YAML library
          try:
            result.extraConfig[keyStr] = parseJson($value)
          except:
            result.extraConfig[keyStr] = newJString($value)
        # yAnchor and yAlias are not supported

proc loadWorkflow(workflow: YamlNode, config: Config): Workflow =
  result = Workflow(
    name: safeInterpolateStr(safeGet(workflow, "name"), config),
    `if`: safeInterpolateStr(safeGet(workflow, "if"), config),
    env: safeInterpolateSeq(safeGet(workflow, "env"), config),
    parallel: if safeGet(workflow, "parallel").isSome: safeGet(workflow, "parallel").get.content == "true" else: false,
    maxConcurrent: if safeGet(workflow, "max_concurrent").isSome: safeGet(workflow, "max_concurrent").get.content.parseInt else: 1,
  )

  if safeGet(workflow, "steps").isSome:
    result.steps = safeGet(workflow, "steps").get.elems.mapIt(loadStep(it, config))

  if safeGet(workflow, "workflows").isSome:
    result.workflows = safeInterpolateSeq(safeGet(workflow, "workflows"), config)

proc loadDirectories(directories: YamlNode, config: Config): Directories =
  result = Directories(
    src: safeInterpolateStr(safeGet(directories, "src"), config),
    destination: safeInterpolateStr(safeGet(directories, "destination"), config),
    content: safeInterpolateStr(safeGet(directories, "content"), config),
    config: safeInterpolateStr(safeGet(directories, "config"), config),
    work: safeInterpolateStr(safeGet(directories, "work"), config),
    scripts: safeInterpolateStr(safeGet(directories, "scripts"), config),
    build: safeInterpolateStr(safeGet(directories, "build"), config)
  )

proc constructNode(events: var YamlStream): YamlNode =
  let event = events.next()
  let startMark = Mark(line: event.startPos.line, column: event.startPos.column)
  let endMark = Mark(line: event.endPos.line, column: event.endPos.column)

  case event.kind
  of yamlScalar:
    return YamlNode(kind: yScalar, tag: event.scalarProperties.tag, content: event.scalarContent,
                    startPos: startMark, endPos: endMark)
  of yamlStartSeq:
    var sequence = newSeq[YamlNode]()
    while events.peek().kind != yamlEndSeq:
      sequence.add(constructNode(events))
    discard events.next()
    return YamlNode(kind: ySequence, tag: event.seqProperties.tag, elems: sequence,
                    startPos: startMark, endPos: endMark)
  of yamlStartMap:
    var mapRef = new(Table[YamlNode, YamlNode])
    mapRef[] = initTable[YamlNode, YamlNode]()
    while events.peek().kind != yamlEndMap:
      let key = constructNode(events)
      let value = constructNode(events)
      mapRef[][key] = value
    discard events.next()
    return YamlNode(kind: yMapping, tag: event.mapProperties.tag, fields: mapRef,
                    startPos: startMark, endPos: endMark)
  of yamlAlias:
    raise newException(ValueError, "Aliases are not supported")
  else:
    raise newException(ValueError, "Unexpected YAML event: " & $event.kind)
