proc renderJsonSection*(section: LogSection): JsonNode =
  result = %*{
    "name": section.name,
    "entries": section.entries.mapIt(%*{
      "level": $it.level,
      "message": it.message,
      "timestamp": it.timestamp.format("yyyy-MM-dd HH:mm:ss"),
      "metadata": it.metadata
    }),
    "subsections": section.subsections.mapIt(renderJsonSection(it)),
    "isOpen": section.isOpen
  }

proc flushJson*(logger: StructuredLogger, target: OutputTarget) =
  ## Writes the whole log. flushLog replaces the target's contents first —
  ## see the note there on why rewinding alone is not enough.
  let logJson = renderJsonSection(logger.root)
  target.stream.write(pretty(logJson))
  target.stream.flush()
