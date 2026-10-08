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
  ## Each flush writes the whole log, so it has to replace what is there
  ## rather than append: a file flushed twice would hold two JSON objects
  ## back to back and parse as neither.
  let logJson = renderJsonSection(logger.root)
  target.stream.setPosition(0)
  target.stream.write(pretty(logJson))
  target.stream.flush()
