# Package

version = "0.2.0"
author = "Jonas Schubert Erlandsson, Hannes Elvemyr"
description = "The Acc static site tools"
license = "GPL-3.0"
srcDir = "src"
bin = @["acc"]
paths = @[".","src"]


# Dependencies

requires "nim >= 2.0.6"
requires "glob >= 0.11.2"
