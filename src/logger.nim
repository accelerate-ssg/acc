import strutils
import terminal
import colors
import options
import std/exitprocs

type
  LogLevel* = enum
    lvlAll,                   ## All levels active
    lvlDebug,                 ## Debug level and above are active
    lvlInfo,                  ## Info level and above are active
    lvlNotice,                ## Notice level and above are active
    lvlWarn,                  ## Warn level and above are active
    lvlError,                 ## Error level and above are active
    lvlFatal,                 ## Fatal level and above are active
    lvlNone                   ## No levels active; nothing is logged
  Segment = object
    background_color: Option[ Color ]
    foreground_color: Option[ Color ]
    text: string

when not defined(release):
  var log_level = lvlDebug
when defined(release):
  var log_level = lvlInfo

var parsing_context = "acc"
proc set_parsing_context*( context: string )
proc get_parsing_context*(): string

const
  DARK_RED = Color( 0xff2222 )
  RED =      Color( 0xff5555 )
  ORANGE =   Color( 0xeb9b34 )
  YELLOW =   Color( 0xf5e02a )
  GREEN =    Color( 0x55aa33 )
  BLUE =     Color( 0x3dbef5 )
  TEXT =     Color( 0xdddddd )
  GREY =     Color( 0xaaaaaa )
  BLACK =    Color( 0x000000 )

template s( bg: Option[ Color ], fg: Option[ Color ], txt: string ): Segment =
  Segment( background_color: bg, foreground_color: fg, text: txt )

template colored_printline( color: Color, header: string, message: string, context: string = " (" & get_parsing_context() & ")\n" ) =
  stdout.set_background_color( BLACK )
  stdout.set_foreground_color( color )
  stdout.write header
  stdout.set_foreground_color( GREY )
  stdout.write ": "
  stdout.set_foreground_color( TEXT )
  stdout.write message
  stdout.set_foreground_color( GREY )
  stdout.write context


template notice*( parts: varargs[string, `$`] ) =
  if log_level <= lvlNotice:
    colored_printline( BLUE, " [INFO]", parts.join( "" ));

template info*( parts: varargs[string, `$`] ) =
  if log_level <= lvlInfo:
    colored_printline( BLUE, "    [i]", parts.join( "" ));

template warn*( parts: varargs[string, `$`] ) =
  if log_level <= lvlWarn:
    colored_printline( ORANGE, " [WARN]", parts.join( "" ));

template error*( parts: varargs[string, `$`] ) =
  if log_level <= lvlError:
    colored_printline( RED, "[ERROR]", parts.join( "" ));

template fatal*( parts: varargs[string, `$`] ) =
  if log_level <= lvlError:
    colored_printline( DARK_RED, "[FATAL]", parts.join( "" ));

template debug*( parts: varargs[string, `$`] ) =
  if log_level <= lvlDebug:
    let (filename, line, column) = instantiation_info(full_paths = true)
    let index = filename.rfind("/src/")
    let path = filename[index .. ^1]
    let context = get_parsing_context()
    let context_string = " in context \"$#\" from $#($#,$#)\n"

    colored_printline(
      GREEN,
      "[DEBUG]",
      parts.join( "" ),
      context_string % [context,path,$line,$column]
    )

template posInfo*(): (string, int, int) =
  instantiationInfo(fullPaths = true)

template echo_with_line_info*( args: varargs[untyped] ) =
  let (filename, line, column) = instantiationInfo(fullPaths = true)
  let index = filename.rfind("/src/")
  let local_path = filename[index .. ^1]
  echo local_path, "(", line, ",", column, "): ", args

proc set_log_level*( level: LogLevel ) =
  log_level = level

proc get_log_level*(): LogLevel =
  return log_level

proc set_parsing_context*( context: string ) = {.gcsafe.}:
  parsing_context = context

proc get_parsing_context*(): string = {.gcsafe.}:
  parsing_context

proc init_logger*() = discard

addExitProc(resetAttributes)
enableTrueColors()
