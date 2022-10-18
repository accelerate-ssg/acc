# Package

version = "0.1.0"
author = "Jonas Schubert Erlandsson"
description = "The Acc static site tools"
license = "GPL-3.0"
srcDir = "src"
bin = @["acc"]


# Dependencies

requires "nim >= 1.6.6"
requires "compiler >= 1.6.6"
requires "yaml >= 1.0.0"
requires "docopt >= 0.7.0"
requires "glob >= 0.11.1"
requires "mustache >= 0.4.3"
