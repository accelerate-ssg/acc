import posix, asyncdispatch, tables

import ./types

const
  IN_MODIFY = 0x00000002
  IN_ATTRIB = 0x00000004
  IN_CLOSE_WRITE = 0x00000008
  IN_MOVED_FROM = 0x00000040
  IN_MOVED_TO = 0x00000080
  IN_CREATE = 0x00000100
  IN_DELETE = 0x00000200
  IN_RECURSIVE = 0x00000001

type
  InotifyEvent {.pure, final.} = object
    wd: cint
    mask: uint32
    cookie: uint32
    len: uint32
    name: array[0, char]

  WatchedItem = object
    path: string
    originalWatch: Watch
    wd: cint

  WatcherContext = ref object
    fd: cint
    watchedItems: TableRef[cint, WatchedItem]

proc inotify_init(): cint {.importc, header: "<sys/inotify.h>".}
proc inotify_add_watch(fd: cint, pathname: cstring, mask: uint32): cint {.importc, header: "<sys/inotify.h>".}



proc newWatcherContext(): WatcherContext =
  new(result)
  result.watchedItems = newTable[cint, WatchedItem]()
  result.fd = inotify_init()
  if result.fd < 0:
    raise newException(OSError, "Failed to initialize inotify")



proc watchDirectory*(dir: string): Future[void] {.async.} =
  let fd = inotify_init()
  if fd < 0:
    raise newException(OSError, "Failed to initialize inotify")

  let wd = inotify_add_watch(fd, dir, IN_MODIFY or IN_ATTRIB or IN_CLOSE_WRITE or
                             IN_MOVED_FROM or IN_MOVED_TO or IN_CREATE or IN_DELETE)
  if wd < 0:
    raise newException(OSError, "Failed to add watch")



proc setupWatches(ctx: WatcherContext, watches: seq[Watch]) =
  for watch in watches:
    let wd = inotify_add_watch(ctx.fd, watch.path.cstring, IN_RECURSIVE or IN_MODIFY or IN_ATTRIB or 
                              IN_CLOSE_WRITE or IN_MOVED_FROM or IN_MOVED_TO or IN_CREATE or IN_DELETE)
    if wd < 0:
      echo "Failed to add watch for path: ", watch.path
      continue
      
    echo "Watching directory: ", watch.path
    ctx.watchedItems[wd] = WatchedItem(
      path: watch.path,
      originalWatch: watch,
      wd: wd
    )

  if ctx.watchedItems.len == 0:
    echo "No directories to watch"



proc watch*(watchPtr: ptr WatcherConfig) {.thread.} =
  var buffer = alloc0(4096)

  defer:
    dealloc(buffer)
  let ctx = newWatcherContext()
  setupWatches(ctx, watchPtr.watches)

  while true:
    let length = read(ctx.fd, buffer, 4096)
    if length < 0:
      raise newException(OSError, "Failed to read events")

    var pos = 0
    while pos < length:
      let event = cast[ptr InotifyEvent](cast[int](buffer) + pos)
      let name = $cast[cstring](addr event.name)
      echo "Changed: ", name
      if (event.mask and IN_MODIFY) != 0:
        echo "File was modified"
      if (event.mask and IN_ATTRIB) != 0:
        echo "Metadata changed"
      if (event.mask and IN_MOVED_FROM) != 0:
        echo "File was moved from watched directory"
      if (event.mask and IN_MOVED_TO) != 0:
        echo "File was moved into watched directory"
      if (event.mask and IN_CREATE) != 0:
        echo "File was created"
      if (event.mask and IN_DELETE) != 0:
        echo "File was deleted"
      pos += sizeof(InotifyEvent) + int(event.len)
