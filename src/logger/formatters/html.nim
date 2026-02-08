const HTML_HEADER = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Accelerate Build Report</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'SF Mono', 'Menlo', 'Monaco', monospace; background: #1a1a2e; color: #dadada; padding: 24px; line-height: 1.5; }
  h1 { color: #5fafff; margin-bottom: 16px; font-size: 18px; }
  .timestamp { color: #a8a8a8; font-size: 12px; }
  .section { margin-left: 20px; border-left: 2px solid #333; padding-left: 12px; margin-bottom: 8px; }
  details { margin-bottom: 4px; }
  summary { cursor: pointer; color: #5fafff; font-weight: bold; padding: 4px 0; }
  summary:hover { color: #87d7ff; }
  .entry { padding: 2px 0; }
  .level { display: inline-block; width: 70px; font-weight: bold; }
  .level-debug { color: #5faf5f; }
  .level-info, .level-notice { color: #5fafff; }
  .level-warn { color: #ffaf00; }
  .level-error { color: #ff5f5f; }
  .level-fatal { color: #ff0000; font-weight: bold; }
  .message { color: #dadada; }
  .metadata { color: #a8a8a8; font-size: 12px; }
</style>
</head>
<body>
<h1>Accelerate Build Report</h1>
"""

const HTML_FOOTER = """
</body>
</html>"""

proc levelClass(level: LogLevel): string =
  case level
  of lvlDebug: "level-debug"
  of lvlInfo: "level-info"
  of lvlNotice: "level-notice"
  of lvlWarn: "level-warn"
  of lvlError: "level-error"
  of lvlFatal: "level-fatal"
  of lvlAll, lvlNone: "level-info"

proc levelLabel(level: LogLevel): string =
  case level
  of lvlDebug: "DEBUG"
  of lvlInfo: "INFO"
  of lvlNotice: "NOTICE"
  of lvlWarn: "WARN"
  of lvlError: "ERROR"
  of lvlFatal: "FATAL"
  of lvlAll: "ALL"
  of lvlNone: ""

proc escapeHtml(s: string): string =
  result = s
  result = result.replace("&", "&amp;")
  result = result.replace("<", "&lt;")
  result = result.replace(">", "&gt;")
  result = result.replace("\"", "&quot;")

proc renderHtmlEntry(entry: LogEntry): string =
  let cls = levelClass(entry.level)
  let label = levelLabel(entry.level)
  let ts = entry.timestamp.format("HH:mm:ss")
  let meta = if entry.metadata.len > 0: " <span class=\"metadata\">" & escapeHtml($entry.metadata) & "</span>" else: ""
  result = "<div class=\"entry\">" &
    "<span class=\"timestamp\">" & ts & "</span> " &
    "<span class=\"level " & cls & "\">" & label & "</span> " &
    "<span class=\"message\">" & escapeHtml(entry.message) & "</span>" &
    meta & "</div>\n"

proc renderHtmlSection*(section: LogSection, depth: int = 0): string =
  if depth == 0:
    result = HTML_HEADER
    for entry in section.entries:
      result.add renderHtmlEntry(entry)
    for sub in section.subsections:
      result.add renderHtmlSection(sub, depth + 1)
    result.add HTML_FOOTER
  else:
    result = "<div class=\"section\">\n"
    result.add "<details" & (if section.isOpen: " open" else: "") & ">\n"
    result.add "<summary>" & escapeHtml(section.name) & "</summary>\n"
    for entry in section.entries:
      result.add renderHtmlEntry(entry)
    for sub in section.subsections:
      result.add renderHtmlSection(sub, depth + 1)
    result.add "</details>\n</div>\n"

proc flushHtml*(logger: StructuredLogger, target: OutputTarget) =
  let html = renderHtmlSection(logger.root)
  target.stream.write(html)
  target.stream.flush()
