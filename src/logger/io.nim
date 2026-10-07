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
  ## Best effort, because this runs as an exit proc: a logger whose streams a
  ## caller already closed, or a half-built section tree, must not turn
  ## process shutdown into a crash. Nothing useful can be reported at this
  ## point anyway — the console target has already printed everything.
  if logger == nil or logger.root == nil:
    return
  try:
    flushLog()
  except CatchableError:
    discard
  for target in logger.outputs.mitems:
    if target.stream != nil:
      try:
        target.stream.close()
      except CatchableError:
        discard
      # Cleared, not just closed: a closed FileStream is still non-nil, and
      # writing to one is a segfault rather than a catchable error.
      target.stream = nil
