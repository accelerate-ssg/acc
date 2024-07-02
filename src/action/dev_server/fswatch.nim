import libfswatch
import asyncdispatch
import threadpool
import terminal

type
  fsw_monitor_type* = enum
    system_default_monitor_type = 0,
    fsevents_monitor_type,
    kqueue_monitor_type,
    inotify_monitor_type,
    windows_monitor_type,
    poll_monitor_type,
    fen_monitor_type

export fsw_cevent, fsw_handle

proc monitor(
  path: string,
  callback: proc(event: fsw_cevent, event_num: cuint),
  verbose = false,
  monitor_type: fsw_monitor_type = system_default_monitor_type
) {.thread.} = 
  var
    monitor: ptr fsw_handle

  enableTrueColors()
  fsw_set_verbose( verbose )

  if fsw_init_library() != 0:
    # fatal "[FSWATCH]", "Error init library"
    stdout.writeLine("[FSWATCH] Error init library")
    stdout.flushFile()
    quit(QuitFailure)

  stdout.writeLine("[FSWATCH] Library initialized")
  stdout.flushFile()
  monitor = fsw_init_session( monitor_type.cint )
  stdout.writeLine("[FSWATCH] Monitor created")
  stdout.flushFile()

  if monitor.fsw_add_path( path ) != 0:
    # fatal "[FSWATCH]", "Error adding path"
    stdout.writeLine("[FSWATCH] Error adding path")
    stdout.flushFile()
    quit(QuitFailure)

  stdout.writeLine("[FSWATCH] Path added")
  stdout.flushFile()

  if monitor.fsw_set_callback(callback) != 0:
    # fatal "[FSWATCH]", "Error setting callback"
    stdout.writeLine("[FSWATCH] Error setting callback")
    stdout.flushFile()
    quit(QuitFailure)

  stdout.writeLine("[FSWATCH] Callback set")
  stdout.flushFile()

  # Tweak for faster response time.
  # Currently 100ms, .1s.
  if monitor.fsw_set_latency( 0.1 ) != 0:
    # fatal "[FSWATCH]", "Error setting latency"
    stdout.writeLine("[FSWATCH] Error setting latency")
    stdout.flushFile()
    quit(QuitFailure)

  stdout.writeLine("[FSWATCH] Latency set")
  stdout.flushFile()

  if monitor.fsw_start_monitor() != 0:
    # fatal "[FSWATCH]", "Error starting monitor"
    stdout.writeLine("[FSWATCH] Error starting monitor")
    stdout.flushFile()
    quit(QuitFailure)

  # fatal "[FSWATCH]", "Started monitoring"
  stdout.writeLine("[FSWATCH] Started monitoring")
  stdout.flushFile()

proc watch*(
  path: string,
  callback: proc(event: fsw_cevent, event_num: cuint),
  verbose = true,
  monitor_type: fsw_monitor_type = system_default_monitor_type
) {.async.} = 
  spawn monitor(path, callback, verbose, monitor_type)

  await newFuture[void]()
