const LINE_COUNT = {.injected_line_count.}

import system
import core/macros
import pure/collections/tables
import strutils
import sequtils

## Forward declarations of routines implemented in ./routines.nim
proc getFromContext*( path: string ): string = discard
proc setInContext*( path: string, value: string ) = discard
proc readFile*( path: string ): string = discard
proc exec*( command: string ): int = discard
proc exe*( command: string ): string = discard
proc writeFile*( file_name, text: string ) = discard

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
  License = enum
    None,
    Propriatary,
    GPL2,
    GPL3,
    MIT
  Meta = object
    name: string
    version: string
    author: string
    authors: seq[ string ]
    description: string
    license: License

var
  parsing_context: seq[ string ] = @[]
  log_level: LogLevel = lvlDebug
  meta: Meta = Meta(
    name: "",
    version: "0.1.0",
    author: "",
    authors: @[],
    description: "",
    license: None
  )

# Context stack
proc push_parsing_context*( context: string ) =
  parsing_context.add context

proc pop_parsing_context*() =
  if parsing_context.len > 1:
    discard parsing_context.pop

proc get_parsing_context*(): string =
  parsing_context.join(" - ")

# Meta data
template with_context( context: string, body: untyped ) =
  push_parsing_context( context )
  body
  pop_parsing_context()

template name( body: untyped ) =
  meta.name = $body
  push_parsing_context( meta.name )

template version( body: untyped ) =
  meta.version = $body

template author( body: untyped ) =
  meta.author = $body

template authors( body: untyped ) =
  if not type(body) is seq[ string ]:
    echo "The authors field must be a sequence of strings. For a single author use the \"author\" field instead."
  else:
    meta.authors = body

template description( body: untyped ) =
  meta.description = body

template license( body: untyped ) =
  if not type(body) is License:
    echo "The licence field must be one of the License enum values."
  else:
    meta.name = body

## Log functions
const
  DARK_RED = "\e[38;5;196m" # 0xff0000
  RED =      "\e[38;5;203m" # 0xff5f5f
  ORANGE =   "\e[38;5;214m" # 0xffaf00
  YELLOW =   "\e[38;5;220m" # 0xffd700
  GREEN =    "\e[38;5;71m"  # 0x5faf5f
  BLUE =     "\e[38;5;75m"  # 0x5fafff
  TEXT =     "\e[38;5;253m" # 0xdadada
  GREY =     "\e[38;5;248m" # 0xa8a8a8
  BLACK =    "\e[38;5;16m"  # 0x000000
  RESET =    "\u001b[0m"

template colored_printline( color: string, header: string, message: string, context: string = " \"" & get_parsing_context() & "\"" ) =
  echo "\u001b[40m" & color & header & GREY & ": " & TEXT & message & RESET & GREY & context & RESET & "\n"

template notice*( parts: varargs[string, `$`] ) =
  if log_level <= lvlNotice:
    colored_printline( BLUE, " [INFO]", parts.join( "" ));

template info*( parts: varargs[string, `$`] ) =
  if log_level <= lvlInfo:
    colored_printline( BLUE, "    [i]", parts.join( "" ));

template warn*( parts: varargs[string, `$`] ) =
  if log_level <= lvlWarn:
    colored_printline( ORANGE, " [WARN]", parts.join( "" ));

template err*( parts: varargs[string, `$`] ) =
  if log_level <= lvlError:
    colored_printline( RED, "[ERROR]", parts.join( "" ));

template fatal*( parts: varargs[string, `$`] ) =
  if log_level <= lvlError:
    colored_printline( DARK_RED, "[FATAL]", parts.join( "" ));

template debug*( parts: varargs[string, `$`] ) =
  if log_level <= lvlDebug:
    let (filename, line, column) = instantiation_info(full_paths = true)
    let index = filename.rfind("/src/")
    var path:string
    let context = get_parsing_context()
    let context_string = " in context \"$#\" from $#($#,$#)"

    if index == -1:
      path = filename
    else:
      path = filename[index .. ^1]


    colored_printline(
      GREEN,
      "[DEBUG]",
      parts.join( "" ),
      context_string % [context,path,$(line - LINE_COUNT),$column]
    )

## Context manipulation
proc ctx_set( path:string, value:any ) =
  setInContext( path, $value )

proc ctx_get( path:string, kind:int ): int =
  parseInt( getFromContext( path ))

proc ctx_get( path:string, kind:float ): float =
  parseFloat( getFromContext( path ))

proc ctx_get( path:string, kind:bool ): bool =
  parseBool( getFromContext( path ))

proc ctx_get( path:string, kind:any ): string =
  getFromContext( path )

proc unroll( val: NimNode ): string =
    if val.kind == nnkIdent:
      return val.strVal
    elif val.kind == nnkDotExpr:
      return unroll(val[0]) & "." & unroll(val[1])
    else:
      echo val.treeRepr

macro `->`(val: untyped, arg: untyped ): untyped =
  if arg.kind == nnkDotExpr:
    let path = unroll(arg)
    quote do:
      ctx_set( `path`, $`val` )
  elif val.kind == nnkDotExpr:
    let path = unroll(val)
    quote do:
      `arg` = ctx_get( `path`, `arg` )
  else:
    quote do:
      `arg` = `val`

macro `<-`(arg: untyped, val: untyped ): untyped =
  if arg.kind == nnkDotExpr:
    let path = unroll(arg)
    result = quote do:
      ctx_set( `path`, $`val` )
  elif val.kind == nnkDotExpr:
    let path = unroll(val)
    result = quote do:
      `arg` = ctx_get( `path`, `arg` )
  else:
    result = quote do:
      `arg` = `val`
