import std/[tables, strutils]
import glob

import types/plugin

proc search_dirs*(plugin: Plugin): seq[string] =
  result = @["./"]
  if plugin.config.has_key("search_dirs"):
    for path in plugin.config["search_dirs"].split(','):
      result.add(path.strip)

proc glob*(plugin: Plugin, default: string = "**/*"): Glob =
  result = glob(default)
  if plugin.config.has_key("glob"):
    result = glob(plugin.config["glob"])

proc context_path_prefix*( plugin: Plugin, default: string = ""): string =
  result = default
  if plugin.config.has_key("context_path_prefix"):
    result = plugin.config["context_path_prefix"]
