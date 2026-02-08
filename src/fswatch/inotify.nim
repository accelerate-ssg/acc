import posix, os, tables, sequtils

import glob

const
  IN_MODIFY = 0x00000002'u32
  IN_ATTRIB = 0x00000004'u32
  IN_CLOSE_WRITE = 0x00000008'u32
  IN_MOVED_FROM = 0x00000040'u32
  IN_MOVED_TO = 0x00000080'u32
  IN_CREATE = 0x00000100'u32
  IN_DELETE = 0x00000200'u32
  IN_ALL_EVENTS = IN_MODIFY or IN_ATTRIB or IN_CLOSE_WRITE or
                  IN_MOVED_FROM or IN_MOVED_TO or IN_CREATE or IN_DELETE

type
  InotifyEvent {.pure, final.} = object
    wd: cint
    mask: uint32
    cookie: uint32
    len: uint32
    # name follows as variable-length data

  WatchedItem = object
    path: string
    originalWatch: Watch

  WatcherContext = ref object
    fd: cint
    watchedItems: TableRef[cint, WatchedItem]

proc inotify_init(): cint {.importc, header: "<sys/inotify.h>".}
proc inotify_add_watch(fd: cint, pathname: cstring, mask: uint32): cint {.importc, header: "<sys/inotify.h>".}

proc shouldWatch(path: string, watch: Watch): bool =
  let relativePath = path.relativePath(watch.path)
  watch.including.anyIt(relativePath.matches(it)) and
  not watch.excluding.anyIt(relativePath.matches(it))

proc newWatcherContext(): WatcherContext =
  new(result)
  result.watchedItems = newTable[cint, WatchedItem]()
  result.fd = inotify_init()
  if result.fd < 0:
    raise newException(OSError, "Failed to initialize inotify")

proc addWatch(ctx: WatcherContext, path: string, originalWatch: Watch) =
  let wd = inotify_add_watch(ctx.fd, path.cstring, IN_ALL_EVENTS)
  if wd < 0:
    return
  ctx.watchedItems[wd] = WatchedItem(path: path, originalWatch: originalWatch)

proc watchRecursively(ctx: WatcherContext, watch: Watch) =
  if dirExists(watch.path):
    ctx.addWatch(watch.path, watch)
    for kind, subpath in walkDir(watch.path):
      if kind == pcDir:
        watchRecursively(ctx, Watch(path: subpath, including: watch.including,
                                    excluding: watch.excluding, kinds: watch.kinds))

proc setupWatches(ctx: WatcherContext, watches: seq[Watch]) =
  for watch in watches:
    watchRecursively(ctx, watch)

proc watch*(config: ptr WatcherConfig) {.thread.} =
  let ctx = newWatcherContext()
  setupWatches(ctx, config.watches)

  var buffer = newSeq[byte](4096)

  while true:
    let length = read(ctx.fd, addr buffer[0], buffer.len)
    if length < 0:
      raise newException(OSError, "Failed to read inotify events")

    var pos = 0
    while pos < length:
      let event = cast[ptr InotifyEvent](addr buffer[pos])
      let wd = event.wd

      if ctx.watchedItems.hasKey(wd):
        let
          item = ctx.watchedItems[wd]
          interestingEvents = item.originalWatch.kinds

        # Build full path from watched directory + event name
        let name = if event.len > 0:
                     $cast[cstring](cast[int](addr buffer[pos]) + sizeof(InotifyEvent))
                   else: ""
        let fullPath = if name != "": item.path / name else: item.path

        if shouldWatch(fullPath, item.originalWatch):
          if (event.mask and IN_MODIFY) != 0 and etModify in interestingEvents:
            config.channel[].send(Event(kind: etModify, path: fullPath))
          elif (event.mask and IN_CREATE) != 0 and etCreate in interestingEvents:
            config.channel[].send(Event(kind: etCreate, path: fullPath))
            # Watch newly created subdirectories
            if dirExists(fullPath):
              ctx.addWatch(fullPath, item.originalWatch)
          elif (event.mask and IN_DELETE) != 0 and etDelete in interestingEvents:
            config.channel[].send(Event(kind: etDelete, path: fullPath))
          elif (event.mask and (IN_MOVED_FROM or IN_MOVED_TO)) != 0 and etRename in interestingEvents:
            config.channel[].send(Event(kind: etRename, path: fullPath))
          elif (event.mask and IN_ATTRIB) != 0 and etAttributeChange in interestingEvents:
            config.channel[].send(Event(kind: etAttributeChange, path: fullPath))

      pos += sizeof(InotifyEvent) + int(event.len)
