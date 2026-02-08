import winlean, asyncdispatch, encodings

type
  WCHAR = Utf16Char
  LPWSTR = ptr UncheckedArray[WCHAR]
  LPCWSTR = ptr UncheckedArray[WCHAR]

const
  FILE_NOTIFY_CHANGE_FILE_NAME = 0x00000001
  FILE_NOTIFY_CHANGE_DIR_NAME = 0x00000002
  FILE_NOTIFY_CHANGE_ATTRIBUTES = 0x00000004
  FILE_NOTIFY_CHANGE_SIZE = 0x00000008
  FILE_NOTIFY_CHANGE_LAST_WRITE = 0x00000010
  FILE_NOTIFY_CHANGE_LAST_ACCESS = 0x00000020
  FILE_NOTIFY_CHANGE_CREATION = 0x00000040
  FILE_NOTIFY_CHANGE_SECURITY = 0x00000100

  FILE_LIST_DIRECTORY = 0x00000001
  FILE_SHARE_READ = 0x00000001
  FILE_SHARE_WRITE = 0x00000002
  FILE_SHARE_DELETE = 0x00000004
  OPEN_EXISTING = 3
  FILE_FLAG_BACKUP_SEMANTICS = 0x02000000
  FILE_FLAG_OVERLAPPED = 0x40000000

type
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

proc watchDirectory*(dir: string): Future[void] {.async.} =
  let wideDir = newWideCString(dir)
  let dirHandle = createFileW(
    wideDir,
    FILE_LIST_DIRECTORY,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
    nil,
    OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OVERLAPPED,
    0
  )

  if dirHandle == INVALID_HANDLE_VALUE:
    raise newException(OSError, "Failed to open directory")

  var buffer = alloc0(4096)
  var bytesReturned: DWORD
  var overlapped: OVERLAPPED

  while true:
    if ReadDirectoryChangesW(
      dirHandle, buffer, 4096, WINBOOL(1),
      FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_DIR_NAME or
      FILE_NOTIFY_CHANGE_ATTRIBUTES or FILE_SHARE_WRITE or
      FILE_NOTIFY_CHANGE_LAST_WRITE,
      addr bytesReturned, addr overlapped, nil
    ) == 0:
      raise newException(OSError, "ReadDirectoryChangesW failed")

    var pos = 0
    while pos < int(bytesReturned):
      let info = cast[ptr FILE_NOTIFY_INFORMATION](cast[int](buffer) + pos)
      let filenameLen = int(info.FileNameLength) div sizeof(WCHAR)
      var filename = newString(filenameLen)
      copyMem(addr filename[0], addr info.FileName[0], filenameLen * sizeof(WCHAR))
      echo "Changed: ", filename.convert(srcEncoding = "utf-16")
      if info.NextEntryOffset == 0:
        break
      pos += int(info.NextEntryOffset)

    await sleepAsync(100)  # Small delay to prevent tight loop
