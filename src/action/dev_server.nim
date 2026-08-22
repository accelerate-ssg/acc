## Development server: serve the rendered site, watch for changes,
## rebuild, and tell every connected browser tab to reload.
##
## Threading model — deliberately minimal:
##
##   One async dispatcher thread runs everything: the HTTP server, the
##   websocket connections, the change handler and the builds. Builds
##   block the dispatcher for their duration, which is fine for a dev
##   server and means none of this state needs locks or atomics.
##
##   The only second thread is the platform file watcher, which cannot
##   share the dispatcher. It communicates exclusively by sending Events
##   through a Channel; the dispatcher polls the channel. Nothing else
##   crosses threads.

import asynchttpserver, asyncdispatch, os, strutils, ws, random, sequtils, json, terminal
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
  port = 1331

var clients: seq[tuple[id: string, socket: WebSocket]]
  ## Every connected tab. Only touched from the dispatcher thread.

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

proc broadcast_reload() {.gcsafe.} =
  ## Tell every connected tab to reload, and forget the ones that are
  ## gone. Reloading pages close their sockets themselves; the next
  ## broadcast prunes them.
  {.cast(gcsafe).}:
    var open: seq[tuple[id: string, socket: WebSocket]] = @[]
    for client in clients:
      if client.socket.ready_state == Open:
        debug "Sending reload to tab ", client.id
        async_check client.socket.send("reload")
        open.add(client)
      else:
        debug "Dropping closed tab ", client.id
    clients = open

proc process_websocket(request: Request) {.async.} =
  ## One connection per open tab. The socket only exists so the server
  ## can push "reload"; whatever the client sends is drained and
  ## ignored.
  let
    id = generate_id()
    old_parsing_context = get_parsing_context()

  set_parsing_context("websocket " & id)

  try:
    var socket = await new_web_socket(request)
    debug "Tab connected: ", id
    {.cast(gcsafe).}:
      clients.add((id, socket))
    await socket.send("connect")
    while socket.ready_state == Open:
      discard await socket.receive_str_packet()
  except WebSocketError:
    discard  # tabs close sockets when they navigate or reload
  finally:
    {.cast(gcsafe).}:
      for i in 0 ..< clients.len:
        if clients[i].id == id:
          clients.delete(i)
          break
    debug "Tab disconnected: ", id
    set_parsing_context(old_parsing_context)

proc context_as_json(): string {.gcsafe.} =
  {.cast(gcsafe).}:
    result = $state.context

proc process_request( request: Request, root_dir: string, source_root: string ) {.async, gcsafe.} =
  var
    path: string
    status = Http200
    content = ""
    headers = {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store"
    }.newHttpHeaders()
    existing_file = false

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
      debug "Serving: ", path
      break

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
    debug "Not found: ", request.url.path
    let
      file_tree = html_tree_from_dir(root_dir)

    content = file_not_found.replace("{reload_script}", reload_script).replace("{file_tree}", file_tree).replace("{file_tree_root}", root_dir.absolute_path )
    status = Http404

  await request.respond(status, content, headers)

proc handle_request( root_dir: string, source_root: string ): (proc( request: Request) {.async, gcsafe.}) =
  return proc(request: Request) {.async, gcsafe.} =
    if request.url.path == "/ws":
      await process_websocket(request)
    else:
      await process_request(request, root_dir, source_root)

proc report_shadow_invalidation(changed_path: string) {.gcsafe.} =
  ## Shadow mode: when the changed file is one the loader tracked, report
  ## what the access log says a selective rebuild would cover — without
  ## acting on it yet. Once the sets have proven themselves against real
  ## editing sessions, this query replaces the blanket rebuilds.
  {.cast(gcsafe).}:
    let load_label = "@load " & changed_path
    if state.context.known_consumer( load_label ):
      let stale = state.context.arena.invalidatedBy( state.context.consumer( load_label ))
      var labels: seq[string] = @[]
      for id in stale:
        labels.add( state.context.consumer_label( id ))
      labels.sort()
      notice "[shadow] ", changed_path.extract_filename,
        " would invalidate ", $labels.len, " consumer(s): ", labels.join( ", " )

proc rebuild(changed: seq[string]) {.gcsafe.} =
  ## Rebuild for a batch of changed files, then tell the tabs. A file
  ## outside the source tree, or one that other templates include, can
  ## affect any page: those rebuild everything, anything else rebuilds
  ## only itself.
  {.cast(gcsafe).}:
    let old_parsing_context = get_parsing_context()
    set_parsing_context("rebuild")

    try:
      let source_root = absolutePath( state.config.directories.src )
      var
        rebuild_all = false
        relative_paths: seq[string] = @[]

      for changed_path in changed:
        report_shadow_invalidation(changed_path)
        let relative_path = relativePath( changed_path, source_root )
        if relative_path.starts_with( ".." ) or state.config.is_partial( relative_path ):
          rebuild_all = true
        else:
          relative_paths.add( relative_path )

      if rebuild_all:
        debug "Rebuilding everything"
        build( state )
      else:
        debug "Rebuilding only: ", relative_paths.join( ", " )
        build( state, relative_paths )

      broadcast_reload()

    except CatchableError as e:
      error "Rebuild failed: ", e.msg
      error "Serving the previous build; fix the error and save to rebuild."
    finally:
      set_parsing_context(old_parsing_context)

proc watch_for_changes(channel: ptr Channel[Event]) {.async.} =
  ## Poll the watcher's channel. When something arrives, wait a moment
  ## and drain whatever else has queued, so an editor save that fires
  ## several events — or several files saved at once — becomes one
  ## rebuild of the whole batch instead of a build per event.
  while true:
    let (has_data, first) = channel[].tryRecv()
    if not has_data:
      await sleepAsync(50)
      continue

    var changed = initOrderedSet[string]()
    changed.incl(absolutePath(first.path))

    await sleepAsync(30)
    while true:
      let (more, event) = channel[].tryRecv()
      if not more:
        break
      changed.incl(absolutePath(event.path))

    debug "Change detected: ", changed.toSeq.join(", ")
    rebuild(changed.toSeq)

proc dev_server*( state: State ) =
  var server = new_async_http_server()

  let
    current_dir = get_current_dir()
    dest_dir = state.config.directories.destination
    src_dir = state.config.directories.src
    server_root_dir = if dest_dir != "": relative_path(dest_dir, current_dir) else: current_dir
    source_root = if src_dir != "": relative_path(src_dir, current_dir) else: current_dir

  randomize()

  info "╔══════════════════════════════════════════════════════╗"
  info "║  Starting development server at http://0.0.0.0:" & $port & "  ║"
  info "╚══════════════════════════════════════════════════════╝"

  # A broken template must not keep the dev server from starting: serve
  # whatever rendered, report the failure, and let the next file change
  # trigger a rebuild.
  try:
    build( state )
  except CatchableError as e:
    error "Initial build failed: ", e.msg
    error "Serving what rendered; fix the error and save to rebuild."

  var channel: Channel[Event]
  channel.open()

  # Watch content alongside the sources: a content edit lands in the
  # rebuild-everything branch, while the shadow query reports what a
  # selective rebuild would cover.
  var watches = @[
    Watch(path: src_dir)
  ]
  if state.config.directories.content != "" and
     state.config.directories.content.dirExists:
    watches.add(Watch(path: state.config.directories.content))

  var watcherConfig = newWatcherConfig(watches, nil, channel)

  # The watcher is the only other thread; it just feeds the channel.
  var watcherThread: Thread[ptr WatcherConfig]
  createThread(watcherThread, watch, addr watcherConfig)

  waitFor all(
    server.serve(Port(port), handle_request(server_root_dir, source_root)),
    watch_for_changes(watcherConfig.channel)
  )
