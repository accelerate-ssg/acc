# Package

version       = "0.1.0"
author        = "Jonas Schubert Erlandsson"
description   = "The Acc static site tools"
license       = "GPL-3.0"
srcDir        = "src"
bin           = @["acc"]


# Dependencies

requires "nim >= 1.4.2"
requires "compiler >= 1.4.2"
requires "yaml >= 0.14.0"
requires "docopt >= 0.6.8"
requires "glob >= 0.11.0"
