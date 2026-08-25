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
# Everything acc imports, declared here and resolved by nimble. Versions are
# the ones acc is known to build and produce identical output with.

requires "nim >= 2.0.6"

requires "glob >= 0.11.3"        # step and blacklist globbing
requires "yaml >= 2.1.1"         # content loading
requires "docopt >= 0.7.1"       # CLI parsing
requires "markdown >= 0.8.8"     # the @markdown module
requires "ws >= 0.5.0"           # dev server live reload

# Ours, tracked as git repositories rather than published packages. Checkouts
# that keep them as siblings compile against those working copies instead —
# see the paths in src/nim.cfg.

# The build context store.
requires "git+ssh://git@github.com/accelerate-ssg/arena.git"

# The template engine: one bytecode VM with per-language frontends, backing
# both the @liquid and @mustache modules.
requires "git+ssh://git@github.com/accelerate-ssg/pitchfork.git"
