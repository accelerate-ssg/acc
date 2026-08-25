# Package

version = "0.2.0"
author = "Jonas Schubert Erlandsson, Hannes Elvemyr"
description = "The Acc static site tools"
license = "GPL-3.0"
srcDir = "src"
bin = @["acc"]
paths = @[".","src"]


# Dependencies
#
# The vendored dependencies under deps/ are resolved by the Atlas section of
# src/nim.cfg; the sibling projects below are declared here because they are
# ours and are tracked as git repositories rather than published packages.

requires "nim >= 2.0.6"
requires "glob >= 0.11.2"

# The build context store.
requires "git+ssh://git@github.com/accelerate-ssg/arena.git"

# The template engine: one bytecode VM with per-language frontends, of which
# the Liquid one backs the @liquid module.
requires "git+ssh://git@github.com/accelerate-ssg/pitchfork.git"
