when defined(nimHasUsed):
  {.used.}

import json, locks, times, streams, sequtils, macros
import strutils, terminal, colors, options
import std/exitprocs

include logger/types

# Terminal color constants
const
  DARK_RED = Color( 0xff0000 )
  RED =      Color( 0xff5f5f )
  ORANGE =   Color( 0xffaf00 )
  YELLOW =   Color( 0xffd700 )
  GREEN =    Color( 0x5faf5f )
  BLUE =     Color( 0x5fafff )
  TEXT =     Color( 0xdadada )
  GREY =     Color( 0xa8a8a8 )
  BLACK =    Color( 0x000000 )

# Log level and parsing context state
when not defined(release):
  var log_level = lvlDebug
when defined(release):
  var log_level = lvlInfo

var parsing_context = "acc"

proc set_log_level*( level: LogLevel ) =
  log_level = level

proc get_log_level*(): LogLevel =
  return log_level

proc set_parsing_context*( context: string ) = {.gcsafe.}:
  parsing_context = context

proc get_parsing_context*(): string = {.gcsafe.}:
  parsing_context

# Colored output template - must be defined before templates.nim
template colored_printline*( color: Color, header: string, message: string, context: string = " in context \"" & get_parsing_context() & "\"\n" ) =
  stdout.set_background_color( BLACK )
  stdout.set_foreground_color( color )
  stdout.write header
  stdout.set_foreground_color( GREY )
  stdout.write ": "
  stdout.set_foreground_color( TEXT )
  stdout.write message
  stdout.set_foreground_color( GREY )
  stdout.write context

template posInfo*(): (string, int, int) =
  instantiationInfo(fullPaths = true)

template echo_with_line_info*( args: varargs[untyped] ) =
  let (filename, line, column) = instantiationInfo(fullPaths = true)
  let index = filename.rfind("/src/")
  let local_path = filename[index .. ^1]
  echo local_path, "(", line, ",", column, "): ", args

# Structured logger instance
var logger*: StructuredLogger

# Include formatters before core (core uses renderCliEntry)
include logger/formatters/cli
include logger/formatters/json
include logger/formatters/html

include logger/core
include logger/io
include logger/templates
include logger/macros

# Initialize the logger - backwards compat wrapper
proc init_logger*() =
  logger = initLogger("accelerate.json")

# Initialize on import
logger = initLogger("accelerate.json")

addExitProc(resetAttributes)
enableTrueColors()

when isMainModule and not defined(release):
  import unittest
  import os

  proc removeTimestamps(node: JsonNode) =
    if node.kind == JObject:
      if node.hasKey("timestamp"):
        node["timestamp"] = newJString("TIMESTAMP")
      for _, value in node:
        removeTimestamps(value)
    elif node.kind == JArray:
      for item in node:
        removeTimestamps(item)

  suite "Logger":
    setup:
      logger = initLogger(@[])  # No outputs for quiet tests

    test "Structured log with sections":
      log_section "First section":
        log(lvlInfo, "First log entry")
        log(lvlInfo, "Second log entry")
        log_section "Nested section":
          log(lvlInfo, "First nested log entry")
      log_section "Second section":
        log(lvlInfo, "First log entry")
      log(lvlInfo, "Root log entry")

      let actual = getFullLog()
      removeTimestamps(actual)
      let expected = parseJson("""
        {
          "name": "root",
          "entries": [
            {
              "level": "lvlInfo",
              "message": "Root log entry",
              "timestamp": "TIMESTAMP",
              "metadata": {}
            }
          ],
          "subsections": [
            {
              "name": "First section",
              "entries": [
                {
                  "level": "lvlInfo",
                  "message": "First log entry",
                  "timestamp": "TIMESTAMP",
                  "metadata": {}
                },
                {
                  "level": "lvlInfo",
                  "message": "Second log entry",
                  "timestamp": "TIMESTAMP",
                  "metadata": {}
                }
              ],
              "subsections": [
                {
                  "name": "Nested section",
                  "entries": [
                    {
                      "level": "lvlInfo",
                      "message": "First nested log entry",
                      "timestamp": "TIMESTAMP",
                      "metadata": {}
                    }
                  ],
                  "subsections": [],
                  "isOpen": false
                }
              ],
              "isOpen": false
            },
            {
              "name": "Second section",
              "entries": [
                {
                  "level": "lvlInfo",
                  "message": "First log entry",
                  "timestamp": "TIMESTAMP",
                  "metadata": {}
                }
              ],
              "subsections": [],
              "isOpen": false
            }
          ],
          "isOpen": true
        }
      """)
      assert actual == expected

    test "JSON file output":
      let tmpFile = getTempDir() / "test_logger.json"
      let jsonStream = newFileStream(tmpFile, fmWrite)
      logger = initLogger(@[
        OutputTarget(format: ofJson, stream: jsonStream, enabled: true)
      ])

      log(lvlInfo, "Test message")
      flushLog()

      # Close the stream so we can read the file
      jsonStream.close()
      let content = readFile(tmpFile)
      let parsed = parseJson(content)
      assert parsed["name"].getStr == "root"
      assert parsed["entries"].len == 1
      assert parsed["entries"][0]["message"].getStr == "Test message"
      removeFile(tmpFile)

    test "HTML output":
      let tmpFile = getTempDir() / "test_logger.html"
      let htmlStream = newFileStream(tmpFile, fmWrite)
      logger = initLogger(@[
        OutputTarget(format: ofHtml, stream: htmlStream, enabled: true)
      ])

      log_section "Build":
        log(lvlInfo, "Compiling")
        log(lvlWarn, "Deprecated API")
      log(lvlError, "Failed")
      flushLog()

      htmlStream.close()
      let content = readFile(tmpFile)
      assert content.contains("<!DOCTYPE html>")
      assert content.contains("Accelerate Build Report")
      assert content.contains("Compiling")
      assert content.contains("Deprecated API")
      assert content.contains("Failed")
      assert content.contains("level-warn")
      assert content.contains("level-error")
      removeFile(tmpFile)

    test "Multiple outputs simultaneously":
      let jsonFile = getTempDir() / "test_multi.json"
      let htmlFile = getTempDir() / "test_multi.html"
      let jsonStream = newFileStream(jsonFile, fmWrite)
      let htmlStream = newFileStream(htmlFile, fmWrite)
      logger = initLogger(@[
        OutputTarget(format: ofJson, stream: jsonStream, enabled: true),
        OutputTarget(format: ofHtml, stream: htmlStream, enabled: true)
      ])

      log(lvlInfo, "Multi-output test")
      flushLog()

      jsonStream.close()
      htmlStream.close()

      let jsonContent = parseJson(readFile(jsonFile))
      assert jsonContent["entries"][0]["message"].getStr == "Multi-output test"

      let htmlContent = readFile(htmlFile)
      assert htmlContent.contains("Multi-output test")

      removeFile(jsonFile)
      removeFile(htmlFile)
