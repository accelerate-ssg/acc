import core/macros
import pure/collections/tables
import colors
import strutils

# Forward declarations of routines implemented in ./routines.nim
proc getFromContext*( path: string ): string = discard
proc setInContext*( path: string, value: string ) = discard

type
  LogLevel* = enum
    lvlAll,                   ## All levels active
    lvlDebug,                 ## Debug level and above are active
    lvlInfo,                  ## Info level and above are active
    lvlNotice,                ## Notice level and above are active
    lvlWarn,                  ## Warn level and above are active
    lvlError,                 ## Error level and above are active
    lvlFatal,                 ## Fatal level and above are active
    lvlNone                    ## No levels active; nothing is logged
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

const
  GREEN = Color( 0x55aa33 )
  TEXT = Color( 0xdddddd )
  GREY = Color( 0xaaaaaa )
  BLACK = Color( 0x000000 )

proc push_parsing_context*( context: string ) =
  parsing_context.add context

proc pop_parsing_context*() =
  if parsing_context.len > 1:
    discard parsing_context.pop

proc get_parsing_context*(): string =
  parsing_context[^1]

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

template debug( parts: varargs[string, `$`] ) =
  if log_level <= lvlDebug:
    let (filename, line, column) = instantiation_info(full_paths = true)

    echo "\u001b[32m[DEBUG]\u001b[37m: \u001b[37;1m" & parts.join("") & "\u001b[0m\u001b[37m in context \"" & get_parsing_context() & "\" from " & filename & "(" & $line & "," & $column & ")\u001b[0m"

proc ctx_set( path:string, value:string ) =
  setInContext( path, value )

proc ctx_get( path:string, kind: int ): int =
  debug "get int: ", path, "=", getFromContext( path )
  parseInt( getFromContext( path ))

proc ctx_get( path:string, kind: float ): float =
  parseFloat( getFromContext( path ))

proc ctx_get( path:string, kind: bool ): bool =
  parseBool( getFromContext( path ))

proc ctx_get( path:string, kind: any ): string =

  debug "get str: ", path, "=", getFromContext( path )
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
    result = quote do:
      ctx_set( `path`, $`val` )
  elif val.kind == nnkDotExpr:
    let path = unroll(val)
    result = quote do:
      `arg` = ctx_get( `path`, `arg` )
  else:
    result = quote do:
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
