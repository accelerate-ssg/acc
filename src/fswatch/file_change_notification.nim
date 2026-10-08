import os

when defined(windows):
  import winlean

  # DWORD is int32 in winlean, so these are typed rather than 'u32 literals:
  # every one of them is either passed to a DWORD parameter or compared with
  # FILE_NOTIFY_INFORMATION.Action, and unsigned literals mismatch both.
  const
    FILE_NOTIFY_CHANGE_FILE_NAME: DWORD = 0x00000001
    FILE_NOTIFY_CHANGE_DIR_NAME: DWORD = 0x00000002
    FILE_NOTIFY_CHANGE_ATTRIBUTES: DWORD = 0x00000004
    FILE_NOTIFY_CHANGE_SIZE: DWORD = 0x00000008
    FILE_NOTIFY_CHANGE_LAST_WRITE: DWORD = 0x00000010

    FILE_LIST_DIRECTORY: DWORD = 0x00000001
    FILE_SHARE_READ: DWORD = 0x00000001
    FILE_SHARE_WRITE: DWORD = 0x00000002
    FILE_SHARE_DELETE: DWORD = 0x00000004
    OPEN_EXISTING: DWORD = 3
    FILE_FLAG_BACKUP_SEMANTICS: DWORD = 0x02000000

    FILE_ACTION_ADDED: DWORD = 0x00000001
    FILE_ACTION_REMOVED: DWORD = 0x00000002
    FILE_ACTION_MODIFIED: DWORD = 0x00000003
    FILE_ACTION_RENAMED_OLD_NAME: DWORD = 0x00000004
    FILE_ACTION_RENAMED_NEW_NAME: DWORD = 0x00000005

    NOTIFY_FILTER: DWORD = FILE_NOTIFY_CHANGE_FILE_NAME or
                           FILE_NOTIFY_CHANGE_DIR_NAME or
                           FILE_NOTIFY_CHANGE_ATTRIBUTES or
                           FILE_NOTIFY_CHANGE_SIZE or
                           FILE_NOTIFY_CHANGE_LAST_WRITE

  type
    WCHAR = Utf16Char

    FILE_NOTIFY_INFORMATION {.pure.} = object
      NextEntryOffset: DWORD
      Action: DWORD
      FileNameLength: DWORD
      FileName: UncheckedArray[WCHAR]

  proc ReadDirectoryChangesW(
    hDirectory: HANDLE, lpBuffer: pointer, nBufferLength: DWORD,
    bWatchSubtree: WINBOOL, dwNotifyFilter: DWORD, lpBytesReturned: ptr DWORD,
    lpOverlapped: pointer, lpCompletionRoutine: pointer
  ): WINBOOL {.stdcall, dynlib: "kernel32", importc.}

  proc wideStringToNim(ws: ptr UncheckedArray[WCHAR], byteLen: int): string =
    let charLen = byteLen div sizeof(WCHAR)
    result = newString(charLen * 3) # worst case UTF-8
    var pos = 0
    for i in 0 ..< charLen:
      let c = uint16(ws[i])
      if c < 0x80:
        result[pos] = char(c); inc pos
      elif c < 0x800:
        result[pos] = char(0xC0 or (c shr 6)); inc pos
        result[pos] = char(0x80 or (c and 0x3F)); inc pos
      else:
        result[pos] = char(0xE0 or (c shr 12)); inc pos
        result[pos] = char(0x80 or ((c shr 6) and 0x3F)); inc pos
        result[pos] = char(0x80 or (c and 0x3F)); inc pos
    result.setLen(pos)

  proc watchSingleDir(config: ptr WatcherConfig, watchPath: string, interestingEvents: set[EventKind]) =
    let wideDir = newWideCString(watchPath)
    let dirHandle = createFileW(
      wideDir,
      FILE_LIST_DIRECTORY,
      FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
      nil,
      OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS,
      Handle(0)
    )

    if dirHandle == INVALID_HANDLE_VALUE:
      echo "[fswatch] Failed to open directory: ", watchPath
      return

    var buffer = alloc0(4096)
    defer: dealloc(buffer)

    while true:
      var bytesReturned: DWORD
      if ReadDirectoryChangesW(
        dirHandle, buffer, 4096, WINBOOL(1),
        NOTIFY_FILTER,
        addr bytesReturned, nil, nil
      ) == 0:
        echo "[fswatch] ReadDirectoryChangesW failed"
        break

      if bytesReturned == 0:
        continue

      var pos = 0
      while pos < int(bytesReturned):
        let info = cast[ptr FILE_NOTIFY_INFORMATION](cast[int](buffer) + pos)
        let filename = wideStringToNim(addr info.FileName, int(info.FileNameLength))
        let fullPath = watchPath / filename

        case info.Action
        of FILE_ACTION_MODIFIED:
          if etModify in interestingEvents:
            config.channel[].send(Event(kind: etModify, path: fullPath))
        of FILE_ACTION_ADDED:
          if etCreate in interestingEvents:
            config.channel[].send(Event(kind: etCreate, path: fullPath))
        of FILE_ACTION_REMOVED:
          if etDelete in interestingEvents:
            config.channel[].send(Event(kind: etDelete, path: fullPath))
        of FILE_ACTION_RENAMED_OLD_NAME, FILE_ACTION_RENAMED_NEW_NAME:
          if etRename in interestingEvents:
            config.channel[].send(Event(kind: etRename, path: fullPath))
        else:
          discard

        if info.NextEntryOffset == 0:
          break
        pos += int(info.NextEntryOffset)

  type WatchArg = object
    ## An index rather than the Watch itself: the thread reads the path out
    ## of the shared config, so no string is copied into the thread payload.
    config: ptr WatcherConfig
    index: int

  proc watchThread(arg: WatchArg) {.thread.} =
    let w = arg.config.watches[arg.index]
    watchSingleDir(arg.config, w.path, w.kinds)

  proc watch*(config: ptr WatcherConfig) {.thread.} =
    ## One thread per configured path. watchSingleDir blocks in
    ## ReadDirectoryChangesW — which does handle recursion itself, via
    ## bWatchSubtree — so the paths cannot be serviced in sequence on one
    ## thread. Watching only watches[0], as this did, meant the dev server's
    ## source watch was observed and its content watch was not, so editing
    ## content never triggered a rebuild.
    if config.watches.len == 0:
      return

    # The last one runs here, so a single watch costs no extra thread.
    var threads = newSeq[Thread[WatchArg]](config.watches.len - 1)
    for index in 0 ..< config.watches.len - 1:
      createThread(threads[index], watchThread,
                   WatchArg(config: config, index: index))

    let last = config.watches.len - 1
    watchSingleDir(config, config.watches[last].path, config.watches[last].kinds)

    if threads.len > 0:
      joinThreads(threads)
