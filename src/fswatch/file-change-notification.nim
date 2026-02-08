import os

when defined(windows):
  import winlean

  const
    FILE_NOTIFY_CHANGE_FILE_NAME = 0x00000001'u32
    FILE_NOTIFY_CHANGE_DIR_NAME = 0x00000002'u32
    FILE_NOTIFY_CHANGE_ATTRIBUTES = 0x00000004'u32
    FILE_NOTIFY_CHANGE_SIZE = 0x00000008'u32
    FILE_NOTIFY_CHANGE_LAST_WRITE = 0x00000010'u32

    FILE_LIST_DIRECTORY = 0x00000001'u32
    FILE_SHARE_READ = 0x00000001'u32
    FILE_SHARE_WRITE = 0x00000002'u32
    FILE_SHARE_DELETE = 0x00000004'u32
    OPEN_EXISTING = 3'u32
    FILE_FLAG_BACKUP_SEMANTICS = 0x02000000'u32

    FILE_ACTION_ADDED = 0x00000001'u32
    FILE_ACTION_REMOVED = 0x00000002'u32
    FILE_ACTION_MODIFIED = 0x00000003'u32
    FILE_ACTION_RENAMED_OLD_NAME = 0x00000004'u32
    FILE_ACTION_RENAMED_NEW_NAME = 0x00000005'u32

    NOTIFY_FILTER = FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_DIR_NAME or
                    FILE_NOTIFY_CHANGE_ATTRIBUTES or FILE_NOTIFY_CHANGE_SIZE or
                    FILE_NOTIFY_CHANGE_LAST_WRITE

  type
    WCHAR = Utf16Char
    LPCWSTR = ptr UncheckedArray[WCHAR]

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

  proc createFileW(lpFileName: LPCWSTR, dwDesiredAccess: DWORD,
                   dwShareMode: DWORD, lpSecurityAttributes: pointer,
                   dwCreationDisposition: DWORD, dwFlagsAndAttributes: DWORD,
                   hTemplateFile: HANDLE): HANDLE {.stdcall, dynlib: "kernel32", importc: "CreateFileW".}

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
      cast[LPCWSTR](wideDir),
      FILE_LIST_DIRECTORY,
      FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
      nil,
      OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS,
      0
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

  proc watch*(config: ptr WatcherConfig) {.thread.} =
    # Watch all configured paths (ReadDirectoryChangesW handles recursion via bWatchSubtree=1)
    # For simplicity, watch the first path only; multi-path would need multiple threads
    if config.watches.len > 0:
      let w = config.watches[0]
      watchSingleDir(config, w.path, w.kinds)
