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
  ## No output target by default, whatever path is named.
  ##
  ## A file target used to be registered here, with its stream opened lazily
  ## so that merely importing the module did not drop a 0-byte
  ## accelerate.json into whatever directory acc ran from — which also made
  ## `acc init .` fail its own empty-directory check (49c3fde). Lazy opening
  ## hid that, but only because nothing ever flushed; now that closeLogger
  ## runs at exit, an enabled file target would write that file again.
  ##
  ## So the default is console only, and a file is something a caller asks
  ## for with addOutput. The parameter is kept for the existing callers.
  discard logFilePath
  result = initLogger(newSeq[OutputTarget]())

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
