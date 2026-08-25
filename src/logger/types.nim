type
  LogLevel* = enum
    lvlAll,                   ## All levels active
    lvlDebug,                 ## Debug level and above are active
    lvlInfo,                  ## Info level and above are active
    lvlNotice,                ## Notice level and above are active
    lvlWarn,                  ## Warn level and above are active
    lvlError,                 ## Error level and above are active
    lvlFatal,                 ## Fatal level and above are active
    lvlNone                   ## No levels active; nothing is logged

  OutputFormat* = enum
    ofCli,                    ## Colored terminal output (real-time)
    ofJson,                   ## Structured JSON tree (on flush)
    ofHtml                    ## HTML build report (on flush)

  OutputTarget* = object
    format*: OutputFormat
    stream*: Stream
    path*: string             ## For file-backed targets: opened lazily on
                              ## first flush, so a run that never writes
                              ## structured output leaves no file behind.
    enabled*: bool

  LogEntry* = object
    level*: LogLevel
    message*: string
    timestamp*: Time
    metadata*: JsonNode

  LogSection* = ref object
    name*: string
    entries*: seq[LogEntry]
    subsections*: seq[LogSection]
    parent*: LogSection
    isOpen*: bool

  StructuredLogger* = ref object
    root*: LogSection
    current*: LogSection
    lock*: Lock
    outputs*: seq[OutputTarget]
    flushCount*: int
