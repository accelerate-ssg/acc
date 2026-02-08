proc levelColor(level: LogLevel): Color =
  case level
  of lvlDebug: GREEN
  of lvlInfo, lvlNotice: BLUE
  of lvlWarn: ORANGE
  of lvlError: RED
  of lvlFatal: DARK_RED
  of lvlAll, lvlNone: TEXT

proc renderCliEntry*(entry: LogEntry) =
  let color = levelColor(entry.level)
  let label = case entry.level
    of lvlDebug: "[DEBUG]"
    of lvlInfo: "    [i]"
    of lvlNotice: " [INFO]"
    of lvlWarn: " [WARN]"
    of lvlError: "[ERROR]"
    of lvlFatal: "[FATAL]"
    of lvlAll, lvlNone: "      "

  stdout.setBackgroundColor(BLACK)
  stdout.setForegroundColor(color)
  stdout.write label
  stdout.setForegroundColor(GREY)
  stdout.write ": "
  stdout.setForegroundColor(TEXT)
  stdout.write entry.message
  stdout.setForegroundColor(GREY)
  stdout.write " in context \"" & get_parsing_context() & "\"\n"
