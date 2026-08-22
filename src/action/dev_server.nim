import asynchttpserver, asyncdispatch, os, strutils, ws, atomics, random, sequtils, locks, json, terminal
import std/[sets, algorithm]

import global_state
import logger
import build
import fswatch
import arena_context_store
import types/render_state/file_list

import dev_server/mime_types

const
  reload_script = static_read "dev_server/force_reload.js"
  file_not_found = static_read "dev_server/file_not_found.html"
  chars = {'A'..'F','0'..'9'}.toSeq

var
  reload_flag: Atomic[bool]
  wait_time = 10
  websocket: WebSocket
  lock: Lock
  build_running = false

proc generate_id() : string =
  result = ""
  for i in 0..7:
    result.add(chars[rand(15)])

proc html_tree_from_dir(dir: string, path_prefix: string = "/"): string =
  result = "<ul>\n"

  for path in walk_files(dir & "/*"):
    let
      file_name = path.substr(dir.len + 1)
      url = path_prefix & file_name

    result.add "<li class=\"file\"><span>📄 <a href=\"" & url & "\">" & file_name & "</a></span></li>\n"

  for dir_path in walk_dir(dir):
    if not dir_path.path.dir_exists:
      continue
    let relative_path = dir_path.path.substr(dir.len + 1)
    result.add "<li class=\"directory\"><input type=\"checkbox\"/><span>" & relative_path & "</span>\n"
    result.add html_tree_from_dir(dir_path.path, path_prefix & relative_path & "/")
    result.add "</li>\n"

  result.add "</ul>\n"

proc set_websocket(ws: WebSocket) {.gcsafe.} =
  {.cast(gcsafe).}:
    lock.acquire()
    if websocket != nil and websocket.ready_state == Open:
      websocket.close()
      debug "Closing old socket connection."
    websocket = ws
    lock.release()

proc process_websocket(request: Request) {.async.} =
  let
    id = generate_id()
    old_parsing_context = get_parsing_context()

  set_parsing_context("process_websocket, " & id)

  try:
    var ws = await new_web_socket(request)
    debug "Socket connection established. ID: ", $id
    set_websocket( ws )
    async_check ws.send("connect")
    while ws.ready_state == Open:
      let reload = reload_flag.exchange(false)
      if not reload:
        await sleep_async(wait_time)
        continue
      if ws.ready_state != Open:
        debug "Connection not open, not sending reload signal"
        continue

      debug "Change detected, sending reload signal through ID: ", $id
      await ws.send("reload")
      debug "Signal sent."
      let ack = await ws.receive_str_packet()
      if ack == "reloading":
        debug "Acknowledgment received. Closing socket Id: ", $id
        ws.close()
    debug "Socket connection closed. ID: ", $id
  except WebSocketClosedError:
    debug "Socket error while closing. ID: ", $id
  except WebSocketProtocolMismatchError:
    debug "Socket tried to use an unknown protocol. ID: ", $id, ", exception: ", get_current_exception_msg()
  except WebSocketError:
    debug "Unexpected socket error. ID: ", $id, ", exception: ", get_current_exception_msg()
  finally:
    set_parsing_context(old_parsing_context)

proc context_as_json(): string {.gcsafe.} =
  {.cast(gcsafe).}:
    result = $state.context

proc process_request( request: Request, root_dir: string, source_root: string ) {.async, gcsafe.} =
  warn "Got request"

  var
    path: string
    status = Http200
    content = ""
    headers = {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store"
    }.newHttpHeaders()
    existing_file = fileExists(path)

  let
    about_context = request.url.path == "/about:context"
    paths = [
      root_dir / request.url.path,
      root_dir / request.url.path / "index.html",
      root_dir / request.url.path & ".html",
      source_root / request.url.path
    ]

  for local_path in paths:
    path = local_path
    existing_file = fileExists(path)
    if existing_file:
      warn "Found: ", path
      break;
    else:
      warn "Didn't find: ", path

  if about_context:
    headers["content-type"] = "application/json; charset=utf-8"
    content = context_as_json()
  elif existing_file:
    let
      ext = split_file(path.to_lower()).ext
      mime_type = mime_types.get_or_default(ext)

    content = read_file(path)
    headers["content-type"] = mime_type & "; charset=utf-8"

    if ext == ".html" or ext == ".htm":
      content = "<script>" & reload_script & "</script>" & content
  else:
    let
      file_tree = html_tree_from_dir(root_dir)

    content = file_not_found.replace("{reload_script}", reload_script).replace("{file_tree}", file_tree).replace("{file_tree_root}", root_dir.absolute_path )
    status = Http404

  await request.respond(status, content, headers)

proc handle_request( root_dir: string, source_root: string ): (proc( request: Request) {.async, gcsafe.}) =
  warn "Starting up web request handler"
  return proc(request: Request) {.async, gcsafe.} =
    if request.url.path == "/ws":
      warn "[Websocket request]"
      await process_websocket(request)
    else:
      warn "[HTTP request]"
      await process_request(request, root_dir, source_root)

proc file_change_callback(event: Event) {.gcsafe.} =
  {.cast(gcsafe).}:
    let old_parsing_context = get_parsing_context()
    enableTrueColors()

    try:
      set_parsing_context("file_system_change_monitor {.thread.}")
      if build_running == true:
        debug "Change detected, but a build is already running"
        return

      build_running = true
      debug "Change detected: ", event.path

      let
        source_root = absolutePath( state.config.directories.src )
        changed_path = absolutePath( event.path )
        relative_path = relativePath( changed_path, source_root )

      # Shadow mode: when the changed file is one the loader tracked, report
      # what the access log says a selective rebuild would cover — without
      # acting on it yet. Once the sets have proven themselves against real
      # editing sessions, this query replaces the blanket rebuilds below.
      let load_label = "@load " & changed_path
      if state.context.known_consumer( load_label ):
        let stale = state.context.arena.invalidatedBy( state.context.consumer( load_label ))
        var labels: seq[string] = @[]
        for id in stale:
          labels.add( state.context.consumer_label( id ))
        labels.sort()
        notice "[shadow] ", changed_path.extract_filename,
          " would invalidate ", $labels.len, " consumer(s): ", labels.join( ", " )

      # A file outside the source tree, or one that other templates include,
      # can affect any page. Until there is a dependency graph to consult,
      # those rebuild everything; anything else rebuilds only itself.
      if relative_path.starts_with( ".." ):
        debug "Changed file is outside the source directory, rebuilding everything"
        build( state )
      elif state.config.is_partial( relative_path ):
        debug "A partial changed, rebuilding everything: ", relative_path
        build( state )
      else:
        debug "Rebuilding only: ", relative_path
        build( state, @[ relative_path ] )

      reload_flag.store(true)
      build_running = false

    except CatchableError:
      debug "Exception in file_change_callback"
    finally:
      set_parsing_context(old_parsing_context)

proc dev_server*( state: State ) =
  var server = new_async_http_server()

  let
    current_dir = get_current_dir()
    dest_dir = state.config.directories.destination
    src_dir = state.config.directories.src
    server_root_dir = if dest_dir != "": relative_path(dest_dir, current_dir) else: current_dir
    source_root = if src_dir != "": relative_path(src_dir, current_dir) else: current_dir
    port = 1331

  randomize()
  init_lock(lock)
  reload_flag.store(true)

  info "╔══════════════════════════════════════════════════════╗"
  info "║  Starting development server at http://0.0.0.0:" & $port & "  ║"
  info "╚══════════════════════════════════════════════════════╝"

  build( state )

  # Set up file watcher using native fswatch
  var channel: Channel[Event]
  channel.open()

  # Watch content alongside the sources: a content edit lands in the
  # callback's outside-the-source-tree branch and rebuilds everything,
  # while the shadow query reports what a selective rebuild would cover.
  var watches = @[
    Watch(path: src_dir)
  ]
  if state.config.directories.content != "" and
     state.config.directories.content.dirExists:
    watches.add(Watch(path: state.config.directories.content))

  var watcherConfig = newWatcherConfig(watches, file_change_callback, channel)

  # Spawn the platform-specific file watcher thread
  var watcherThread: Thread[ptr WatcherConfig]
  createThread(watcherThread, watch, addr watcherConfig)

  # Poll the channel for file change events and invoke the callback
  proc pollFileChanges(channel: ptr Channel[Event], callback: WatcherCallback) {.async.} =
    while true:
      let (hasData, event) = channel[].tryRecv()
      if hasData:
        callback(event)
      else:
        await sleepAsync(50)

  waitFor all(
    server.serve(Port(port), handle_request(server_root_dir, source_root)),
    pollFileChanges(watcherConfig.channel, file_change_callback)
  )
