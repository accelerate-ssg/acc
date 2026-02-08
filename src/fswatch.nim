import asyncdispatch

import ./fswatch/[types, support]



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



proc startWatching*(config: WatcherConfig) = #{.async.} =
  var
    thread: Thread[ptr WatcherConfig]
    configPtr = config.addr
  
  createThread(thread, watch, configPtr)

  while true:
    let event = config.channel[].recv()
    config.callback(event)

  thread.joinThread()



# Usage example
when isMainModule:
  proc onFileChange(event: Event) {.gcsafe.} =
    echo "File changed: ", event.path, " (", event.kind, ")"

  var channel: Channel[Event]  # Create actual Channel first
  channel.open()              # Initialize it

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

  let config = newWatcherConfig(watches, onFileChange, channel)

  #waitFor startWatching(config)
  startWatching(config)
