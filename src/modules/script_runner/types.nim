import dynlib

type
  JSException* = object of CatchableError
    stacktrace*: string

  ScriptRunnerLib* = ref object
    lib*: LibHandle
    vtable*: ScriptRunnerVTable
    cachedName*: string
    cachedExtensions*: seq[string]

  ScriptRunnerVTable* = object
    name*: proc (): cstring {.cdecl.}
    supportedExtensions*: proc (): cstring {.cdecl.}
    create*: proc () {.cdecl.}
    destroy*: proc () {.cdecl.}
    eval*: proc (script: cstring, context: pointer): cstring {.cdecl.}
