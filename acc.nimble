# Package

version = "0.1.0"
author = "Jonas Schubert Erlandsson"
description = "The Acc static site tools"
license = "GPL-3.0"
srcDir = "src"
bin = @["acc"]


# Dependencies

requires "regex >= 0.20.2"
requires "nim >= 1.6.12"
requires "yaml >= 1.0.0"
requires "cligen >= 1.6.0"
requires "regex >= 0.19.0"
requires "docopt >= 0.7.0"
requires "glob >= 0.11.2"
requires "mustache >= 0.4.3"
requires "markdown >= 0.8.0"
requires "libfswatch >= 0.1.0"
requires "ws >= 0.5.0"
