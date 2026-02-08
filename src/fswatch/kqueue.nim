import posix, os, tables, sequtils
import std/kqueue as stdkqueue
import glob

import ./types

type
  WatchedItem = object
    path: string
    isDir: bool
    originalWatch: Watch  # Reference to the original Watch object

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
    echo "Failed to open path: ", path
    return
  echo if isDir: "Watching directory: " else: "Watching file: ", path
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

  if ctx.watchedItems.len == 0:
    echo "No files or directories to watch"



proc watch*(config: ptr WatcherConfig) {.thread.} =
  let
    ctx = newWatcherContext()
    config: WatcherConfig = config[]

  setupWatches(ctx, config.watches)

  var events = newSeq[Kevent](32)

  while true:
    let number_of_events = kevent(ctx.kq, nil, 0, addr events[0], 32, nil)
    
    if number_of_events < 0:
      raise newException(OSError, "Error in kevent")
    else:
      for i in 0 ..< number_of_events:
        let
          flags = events[i].fflags
          file_descriptor = events[i].ident.cint
          
        if not ctx.watchedItems.hasKey(file_descriptor):
          continue

        let
          item = ctx.watchedItems[file_descriptor]
          event = Event(path: item.path)
          interresting_events = item.originalWatch.kinds

        if (flags and NOTE_WRITE) != 0 and interresting_events.contains(etModify):
          event.kind = etModify
        elif (flags and NOTE_RENAME) != 0 and interresting_events.contains(etRename):
          event.kind = etRename
        elif (flags and NOTE_DELETE) != 0 and interresting_events.contains(etDelete):
          event.kind = etDelete
        elif (flags and NOTE_ATTRIB) != 0 and interresting_events.contains(etAttributeChange):
          event.kind = etAttributeChange
        elif (flags and NOTE_EXTEND) != 0 and interresting_events.contains(etCreate): 
          event.kind = etOther
        else:
          continue

        config.channel[].send(event)

        # Check for new subdirectories and files
        if item.isDir and (flags and NOTE_WRITE) != 0:
          for kind, subpath in walkDir(item.path):
            if not ctx.watchedItems.values.toSeq.anyIt(it.path == subpath) and shouldWatch(subpath, item.originalWatch):
              ctx.addWatch(subpath, kind == pcDir, item.originalWatch)
