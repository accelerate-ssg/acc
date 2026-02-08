import os, strutils, sequtils

import glob

import ./types

{.passL: "-framework CoreServices -framework CoreFoundation".}

type
  FSEventStreamRef = pointer
  CFStringRef = pointer
  CFArrayRef = pointer
  CFRunLoopRef = pointer
  CFAbsoluteTime = cdouble
  FSEventStreamEventFlags = cuint
  FSEventStreamEventId = culonglong

  FSEventStreamCallback = proc (
    streamRef: FSEventStreamRef,
    clientCallBackInfo: pointer,
    numEvents: csize_t,
    eventPaths: ptr pointer,
    eventFlags: ptr FSEventStreamEventFlags,
    eventIds: ptr FSEventStreamEventId
  ) {.cdecl.}

  FSEventStreamContext = object
    version: cint
    info: pointer
    retain: pointer
    release: pointer
    copyDescription: pointer

  WatcherContext = ref object
    config: ptr WatcherConfig
    streamRef: FSEventStreamRef

proc FSEventStreamCreate(
  allocator: pointer,
  callback: FSEventStreamCallback,
  context: ptr FSEventStreamContext,
  pathsToWatch: CFArrayRef,
  sinceWhen: FSEventStreamEventId,
  latency: CFAbsoluteTime,
  flags: cuint
): FSEventStreamRef {.importc.}

proc FSEventStreamScheduleWithRunLoop(
  streamRef: FSEventStreamRef,
  runLoop: CFRunLoopRef,
  runLoopMode: CFStringRef
) {.importc.}

proc FSEventStreamStart(streamRef: FSEventStreamRef): bool {.importc.}

proc CFRunLoopRun() {.importc.}
proc CFRunLoopGetCurrent(): CFRunLoopRef {.importc.}

proc CFStringCreateWithCString(
  alloc: pointer, cStr: cstring, encoding: cuint
): CFStringRef {.importc.}

proc CFArrayCreate(
  allocator: pointer, values: ptr pointer, numValues: csize_t, callbacks: pointer
): CFArrayRef {.importc.}

const
  kCFStringEncodingUTF8: cuint = 0x08000100
  kCFRunLoopDefaultMode = "kCFRunLoopDefaultMode"
  kFSEventStreamCreateFlagNoDefer = 0x00000002
  kFSEventStreamCreateFlagFileEvents = 0x00000010
  kFSEventStreamEventIdSinceNow: FSEventStreamEventId = 0xFFFFFFFFFFFFFFFF'u64

  kFSEventStreamEventFlagItemCreated = 0x00000100
  kFSEventStreamEventFlagItemModified = 0x00001000
  kFSEventStreamEventFlagItemRemoved = 0x00000200
  kFSEventStreamEventFlagItemRenamed = 0x00000800

proc shouldWatch(path: string, watch: Watch): bool =
  let relativePath = path.relativePath(watch.path)
  watch.including.anyIt(relativePath.matches(it)) and 
  not watch.excluding.anyIt(relativePath.matches(it))

proc eventCallback(
  streamRef: FSEventStreamRef,
  clientCallBackInfo: pointer,
  numEvents: csize_t,
  eventPaths: ptr pointer,
  eventFlags: ptr FSEventStreamEventFlags,
  eventIds: ptr FSEventStreamEventId
) {.cdecl.} =
  let
    ctx = cast[WatcherContext](clientCallBackInfo)
    paths = cast[ptr UncheckedArray[cstring]](eventPaths)
    flags = cast[ptr UncheckedArray[FSEventStreamEventFlags]](eventFlags)

  for i in 0 ..< numEvents:
    let path = $paths[i]
    
    # Find matching watch for this path
    var matchingWatch: Watch

    for watch in ctx.config.watches:
      echo "Checking watch: ", watch.path
      if path.startsWith(watch.path) and shouldWatch(path, watch):
        matchingWatch = watch
        echo "Matching watch for path: ", path
        break
      else:
        echo "No matching watch for path: ", path
    
    if matchingWatch.path == "":
      continue

    let 
      eventFlags = flags[i]
      interestingEvents = matchingWatch.kinds
    var event = Event(path: path)

    # Map FSEvent flags to our event types
    if (eventFlags and kFSEventStreamEventFlagItemModified) != 0 and etModify in interestingEvents:
      event.kind = etModify
    elif (eventFlags and kFSEventStreamEventFlagItemCreated) != 0 and etCreate in interestingEvents:
      event.kind = etCreate
    elif (eventFlags and kFSEventStreamEventFlagItemRemoved) != 0 and etDelete in interestingEvents:
      event.kind = etDelete
    elif (eventFlags and kFSEventStreamEventFlagItemRenamed) != 0 and etRename in interestingEvents:
      event.kind = etRename
    else:
      continue

    ctx.config.channel[].send(event)

proc newWatcherContext(config: ptr WatcherConfig): WatcherContext =
  new(result)
  result.config = config

proc setupWatches(ctx: WatcherContext): bool =
  var paths: seq[CFStringRef] = @[]
  var pathPtrs: seq[pointer] = @[]
  
  # Create CFString for each watch path
  for watch in ctx.config.watches:
    let cfStr = CFStringCreateWithCString(nil, watch.path.cstring, kCFStringEncodingUTF8)
    if cfStr.isNil:
      echo "Failed to create CFString for path: ", watch.path
      return false
    paths.add(cfStr)
    pathPtrs.add(cast[pointer](cfStr))

  let pathsToWatch = CFArrayCreate(nil, addr pathPtrs[0], csize_t(paths.len), nil)
  if pathsToWatch.isNil:
    echo "Failed to create CFArray"
    return false

  var context: FSEventStreamContext
  context.version = 0
  context.info = cast[pointer](ctx)
  context.retain = nil
  context.release = nil
  context.copyDescription = nil

  ctx.streamRef = FSEventStreamCreate(
    nil,
    eventCallback,
    addr context,
    pathsToWatch,
    kFSEventStreamEventIdSinceNow,
    0,
    cuint(kFSEventStreamCreateFlagNoDefer or kFSEventStreamCreateFlagFileEvents)
  )

  if ctx.streamRef.isNil:
    echo "Failed to create FSEvent stream"
    return false

  let runLoop = CFRunLoopGetCurrent()
  if runLoop.isNil:
    echo "Failed to get current run loop"
    return false

  let runLoopMode = CFStringCreateWithCString(nil, kCFRunLoopDefaultMode, kCFStringEncodingUTF8)
  if runLoopMode.isNil:
    echo "Failed to create run loop mode string"
    return false

  FSEventStreamScheduleWithRunLoop(ctx.streamRef, runLoop, runLoopMode)

  if not FSEventStreamStart(ctx.streamRef):
    echo "Failed to start FSEvent stream"
    return false

  return true

proc watch*(watchPtr: ptr WatcherConfig) {.thread.} =
  let ctx = newWatcherContext(watchPtr)
  
  if not setupWatches(ctx):
    return

  echo "Started watching directories..."
  CFRunLoopRun()
