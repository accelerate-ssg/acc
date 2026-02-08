const
  supportsWindows = defined(windows)
  supportsMacOSX = defined(macosx)
  supportsLinux = defined(linux)

proc supportsWindowsFileNotifyAPI(): bool {.compileTime.} =
  when supportsWindows:
    echo "Windows File Notify API is supported (not on Windows)"
    result = true
  else:
    echo "Windows File Notify API is not supported"
    result = false

proc supportsFSEvent(): bool {.compileTime.} =
  when supportsMacOSX:
    const fsEventSupported = compiles:
      {.passL: "-framework CoreServices -framework CoreFoundation".}
      {.passC: "-x objective-c".}
      proc CFRunLoopRun() {.importc.}
    if fsEventSupported:
      echo "FSEvent is supported"
    else:
      echo "FSEvent is not supported"
    result = fsEventSupported
  else:
    echo "FSEvent is not supported (not on macOS)"
    result = false

proc supportsKqueue(): bool {.compileTime.} =
  when supportsMacOSX or defined(bsd):
    const kqueueSupported = compiles:
      proc kqueue(): cint {.importc, header: "<sys/event.h>".}
      proc kevent(kq: cint, changelist: pointer, nchanges: cint,
                  eventlist: pointer, nevents: cint, timeout: pointer): cint
                  {.importc, header: "<sys/event.h>".}
    if kqueueSupported:
      echo "Kqueue is supported"
    else:
      echo "Kqueue is not supported"
    result = kqueueSupported
  else:
    echo "Kqueue is not supported (not on macOS or BSD)"
    result = false

proc supportsInotify(): bool {.compileTime.} =
  when supportsLinux:
    const inotifySupported = compiles:
      import posix
      proc inotify_init(): cint {.importc, header: "<sys/inotify.h>".}
    if inotifySupported:
      echo "Inotify supported"
    else:
      echo "Inotify not supported"
    result = inotifySupported
  else:
    echo "Inotify is not supported (not on Linux)"
    result = false

proc chooseFileWatcherStrategy(): string {.compileTime.} =
  echo "Choosing file watcher strategy..."
  if supportsWindowsFileNotifyAPI():
    echo "Selected: Windows File Notify API"
    return "WindowsFileNotifyAPI"
  elif supportsFSEvent():
    echo "Selected: FSEvent"
    return "FSEvent"
  elif supportsKqueue():
    echo "Selected: Kqueue"
    return "Kqueue"
  elif supportsInotify():
    echo "Selected: Inotify"
    return "Inotify"
  else:
    echo "No valid file watcher found for this platform"
    return "Unsupported"

const FileWatcherStrategy* = chooseFileWatcherStrategy()
