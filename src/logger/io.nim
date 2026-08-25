proc toJson*(section: LogSection): JsonNode =
  renderJsonSection(section)

proc getFullLog*(): JsonNode =
  withLock logger.lock:
    result = renderJsonSection(logger.root)

proc flushLog*() =
  for target in logger.outputs.mitems:
    if not target.enabled: continue
    # File-backed targets open on first flush (see OutputTarget.path).
    if target.stream == nil and target.path.len > 0:
      target.stream = newFileStream(target.path, fmWrite)
    case target.format
    of ofJson:
      if target.stream != nil:
        flushJson(logger, target)
    of ofHtml:
      if target.stream != nil:
        flushHtml(logger, target)
    of ofCli:
      discard  # CLI is real-time, nothing to flush

  inc(logger.flushCount)

  # Clear closed sections
  proc clearClosedSections(section: LogSection) =
    section.subsections = section.subsections.filterIt(it.isOpen)
    for subsection in section.subsections:
      clearClosedSections(subsection)

  clearClosedSections(logger.root)

proc closeLogger*() =
  if logger != nil:
    flushLog()
    for target in logger.outputs:
      if target.stream != nil:
        target.stream.close()
