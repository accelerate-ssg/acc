import ./fswatch/[types, support]
export types



when FileWatcherStrategy == "WindowsFileNotifyAPI":
  include fswatch/file-change-notification
elif FileWatcherStrategy == "FSEvent":
  include fswatch/fsevent
elif FileWatcherStrategy == "Kqueue":
  include fswatch/kqueue
elif FileWatcherStrategy == "Inotify":
  include fswatch/inotify
else:
  {.error: "No valid file watcher found for this platform".}



proc newWatcherConfig*(watches: seq[Watch], callback: WatcherCallback, channel: var Channel[Event]): WatcherConfig =
  result = WatcherConfig(
    watches: watches,
    channel: channel.addr,
    callback: callback
  )



proc startWatching*(config: var WatcherConfig) =
  var thread: Thread[ptr WatcherConfig]

  createThread(thread, watch, addr config)

  while true:
    let event = config.channel[].recv()
    config.callback(event)



# Usage example
when isMainModule and not defined(release):
  proc onFileChange(event: Event) {.gcsafe.} =
    echo "File changed: ", event.path, " (", event.kind, ")"

  var channel: Channel[Event]
  channel.open()

  let watches = @[
    Watch(
      path: "/Users/jonas/projects/accodeing/accelerate/acc2/src",
      including: @["*.nim"],
    ),
    Watch(
      path: "/Users/jonas/projects/accodeing/accelerate/acc2/test",
      excluding: @["**/*.nim"]
    )
  ]

  var config = newWatcherConfig(watches, onFileChange, channel)
  startWatching(config)
