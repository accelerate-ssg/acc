proc toJson*(section: LogSection): JsonNode =
  renderJsonSection(section)

proc getFullLog*(): JsonNode =
  withLock logger.lock:
    result = renderJsonSection(logger.root)

proc flushLog*() =
  for target in logger.outputs.mitems:
    if not target.enabled: continue
    # Every flush renders the whole log, so the target has to be *replaced*,
    # not appended to and not overwritten in place. Reopening with fmWrite
    # truncates, which matters because the render can shrink: the
    # clearClosedSections pass below drops closed sections, so a later flush
    # is often shorter than an earlier one, and rewinding alone would leave
    # the tail of the longer write behind — a file that parses as neither one
    # document nor two.
    #
    # A target constructed with a stream rather than a path cannot be
    # truncated through FileStream, so it is only rewound. The tests do that;
    # acc itself always configures a path.
    if target.path.len > 0:
      if target.stream != nil:
        try: target.stream.close() except CatchableError: discard
      target.stream = newFileStream(target.path, fmWrite)
    elif target.stream != nil:
      target.stream.setPosition(0)
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
