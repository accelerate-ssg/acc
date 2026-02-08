import posix, os, tables, sequtils
import std/kqueue as stdkqueue
import glob

type
  WatchedItem = object
    path: string
    isDir: bool
    originalWatch: Watch

  WatcherContext = ref object
    watchedItems: TableRef[cint, WatchedItem]
    kq: cint

proc newWatcherContext(): WatcherContext =
  new(result)
  result.watchedItems = newTable[cint, WatchedItem]()
  result.kq = kqueue()
  if result.kq < 0:
    raise newException(OSError, "Failed to create kqueue")

proc addWatch(ctx: WatcherContext, path: string, isDir: bool, originalWatch: Watch) =
  let fd = open(path, O_RDONLY)
  if fd < 0:
    return
  ctx.watchedItems[fd] = WatchedItem(path: path, isDir: isDir, originalWatch: originalWatch)

  var change: Kevent
  EV_SET(addr change, uint(fd), EVFILT_VNODE,
         EV_ADD or EV_ENABLE or EV_CLEAR,
         NOTE_WRITE or NOTE_EXTEND or NOTE_RENAME or NOTE_DELETE or NOTE_ATTRIB,
         0, nil)
  discard kevent(ctx.kq, addr change, 1, nil, 0, nil)

proc shouldWatch(path: string, watch: Watch): bool =
  let relativePath = path.relativePath(watch.path)
  watch.including.anyIt(relativePath.matches(it)) and
  not watch.excluding.anyIt(relativePath.matches(it))

proc watchRecursively(ctx: WatcherContext, watch: Watch) =
  if dirExists(watch.path):
    ctx.addWatch(watch.path, true, watch)
    for kind, subpath in walkDir(watch.path):
      if kind == pcDir:
        watchRecursively(ctx, Watch(path: subpath, including: watch.including,
                               excluding: watch.excluding))
      elif kind == pcFile and shouldWatch(subpath, watch):
        ctx.addWatch(subpath, false, watch)

proc setupWatches(ctx: WatcherContext, watches: seq[Watch]) =
  for watch in watches:
    watchRecursively(ctx, watch)

proc removeWatch(ctx: WatcherContext, fd: cint) =
  discard close(fd)
  ctx.watchedItems.del(fd)

proc watch*(config: ptr WatcherConfig) {.thread.} =
  let ctx = newWatcherContext()
  setupWatches(ctx, config.watches)

  var events = newSeq[Kevent](32)

  while true:
    let numEvents = kevent(ctx.kq, nil, 0, addr events[0], 32, nil)

    if numEvents < 0:
      raise newException(OSError, "Error in kevent")

    for i in 0 ..< numEvents:
      let
        flags = events[i].fflags
        fd = events[i].ident.cint

      if not ctx.watchedItems.hasKey(fd):
        continue

      let
        item = ctx.watchedItems[fd]
        interestingEvents = item.originalWatch.kinds

      if (flags and NOTE_WRITE) != 0 and etModify in interestingEvents:
        config.channel[].send(Event(kind: etModify, path: item.path))
      elif (flags and NOTE_RENAME) != 0 and etRename in interestingEvents:
        config.channel[].send(Event(kind: etRename, path: item.path))
      elif (flags and NOTE_DELETE) != 0 and etDelete in interestingEvents:
        config.channel[].send(Event(kind: etDelete, path: item.path))
        ctx.removeWatch(fd)
        continue
      elif (flags and NOTE_ATTRIB) != 0 and etAttributeChange in interestingEvents:
        config.channel[].send(Event(kind: etAttributeChange, path: item.path))
      elif (flags and NOTE_EXTEND) != 0 and etOther in interestingEvents:
        config.channel[].send(Event(kind: etOther, path: item.path, eventName: "extend"))

      # Check for new subdirectories and files
      if item.isDir and (flags and NOTE_WRITE) != 0:
        for kind, subpath in walkDir(item.path):
          if not ctx.watchedItems.values.toSeq.anyIt(it.path == subpath) and shouldWatch(subpath, item.originalWatch):
            ctx.addWatch(subpath, kind == pcDir, item.originalWatch)
