type
  EventKind* = enum
    etCreate, etModify, etDelete, etRename, etAttributeChange, etOther

  Event* = object
    case kind*: EventKind
    of etOther:
      eventName: string
    of etCreate, etModify, etDelete, etRename, etAttributeChange:
      discard
    path*: string

  WatcherCallback* = proc(event: Event) {.closure, gcsafe.}

  Watch* = object
    path*: string
    kinds*: set[EventKind] = {etCreate, etModify, etDelete, etRename}
    including*: seq[string] = @["**/*"]
    excluding*: seq[string] = @[]

  WatcherConfig* = object
    watches*: seq[Watch]
    channel*: ptr Channel[Event]
    callback*: WatcherCallback
