const
  supportsWindows = defined(windows)
  supportsMacOSX = defined(macosx)
  supportsLinux = defined(linux)

template debugEcho(msg: string) =
  when not defined(release):
    echo msg

proc supportsWindowsFileNotifyAPI(): bool {.compileTime.} =
  when supportsWindows:
    debugEcho "Windows File Notify API is supported"
    result = true
  else:
    debugEcho "Windows File Notify API is not supported"
    result = false

proc supportsFSEvent(): bool {.compileTime.} =
  when supportsMacOSX:
    const fsEventSupported = compiles:
      {.passL: "-framework CoreServices -framework CoreFoundation".}
      {.passC: "-x objective-c".}
      proc CFRunLoopRun() {.importc.}
    if fsEventSupported:
      debugEcho "FSEvent is supported"
    else:
      debugEcho "FSEvent is not supported"
    result = fsEventSupported
  else:
    debugEcho "FSEvent is not supported (not on macOS)"
    result = false

proc supportsKqueue(): bool {.compileTime.} =
  when supportsMacOSX or defined(bsd):
    const kqueueSupported = compiles:
      proc kqueue(): cint {.importc, header: "<sys/event.h>".}
      proc kevent(kq: cint, changelist: pointer, nchanges: cint,
                  eventlist: pointer, nevents: cint, timeout: pointer): cint
                  {.importc, header: "<sys/event.h>".}
    if kqueueSupported:
      debugEcho "Kqueue is supported"
    else:
      debugEcho "Kqueue is not supported"
    result = kqueueSupported
  else:
    debugEcho "Kqueue is not supported (not on macOS or BSD)"
    result = false

proc supportsInotify(): bool {.compileTime.} =
  when supportsLinux:
    const inotifySupported = compiles:
      import posix
      proc inotify_init(): cint {.importc, header: "<sys/inotify.h>".}
    if inotifySupported:
      debugEcho "Inotify supported"
    else:
      debugEcho "Inotify not supported"
    result = inotifySupported
  else:
    debugEcho "Inotify is not supported (not on Linux)"
    result = false

proc chooseFileWatcherStrategy(): string {.compileTime.} =
  debugEcho "Choosing file watcher strategy..."
  if supportsWindowsFileNotifyAPI():
    debugEcho "Selected: Windows File Notify API"
    return "WindowsFileNotifyAPI"
  elif supportsFSEvent():
    debugEcho "Selected: FSEvent"
    return "FSEvent"
  elif supportsKqueue():
    debugEcho "Selected: Kqueue"
    return "Kqueue"
  elif supportsInotify():
    debugEcho "Selected: Inotify"
    return "Inotify"
  else:
    debugEcho "No valid file watcher found for this platform"
    return "Unsupported"

const FileWatcherStrategy* = chooseFileWatcherStrategy()
