proc initLogger*(outputs: seq[OutputTarget]): StructuredLogger =
  result = StructuredLogger(
    root: LogSection(name: "root", isOpen: true),
    current: nil,
    outputs: outputs,
    flushCount: 0
  )
  result.current = result.root
  initLock(result.lock)

proc initLogger*(logFilePath: string): StructuredLogger =
  var outputs: seq[OutputTarget] = @[]

  # JSON output to file
  let jsonStream = newFileStream(logFilePath, fmWrite)
  if jsonStream != nil:
    outputs.add(OutputTarget(format: ofJson, stream: jsonStream, enabled: true))

  result = initLogger(outputs)

proc addOutput*(target: OutputTarget) =
  withLock logger.lock:
    logger.outputs.add(target)

proc log*(level: LogLevel, message: string, metadata: JsonNode = newJObject()) =
  withLock logger.lock:
    let entry = LogEntry(
      level: level,
      message: message,
      timestamp: getTime(),
      metadata: metadata
    )
    logger.current.entries.add(entry)

    # Real-time outputs (CLI)
    for target in logger.outputs:
      if target.enabled and target.format == ofCli:
        renderCliEntry(entry)

proc startSection*(name: string) =
  let newSection = LogSection(name: name, parent: logger.current, isOpen: true)
  logger.current.subsections.add(newSection)
  logger.current = newSection

proc endSection*() =
  if logger.current.parent != nil:
    logger.current.isOpen = false
    logger.current = logger.current.parent
