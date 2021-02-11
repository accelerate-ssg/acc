import tables

type
  Plugin* = object
    name*: string
    script*: string
    after*: seq[ string ]
    before*: seq[ string ]
    config*: Table[ string, string ]

proc init_plugin*(): Plugin =
  result = Plugin()
  result.name = ""
  result.script = ""
  result.after = @[]
  result.before = @[]
  result.config = initTable[string, string]()
