import std/[json, strutils]
import glob

import config

proc search_dirs*(step: Step): seq[string] =
  result = @["./"]
  if step.extraConfig != nil and step.extraConfig.hasKey("search_dirs"):
    for path in step.extraConfig["search_dirs"].getStr.split(','):
      result.add(path.strip)

proc glob*(step: Step, default: string = "**/*"): Glob =
  result = glob(default)
  if step.extraConfig != nil and step.extraConfig.hasKey("glob"):
    result = glob(step.extraConfig["glob"].getStr)

proc context_path_prefix*(step: Step, default: string = ""): string =
  result = default
  if step.extraConfig != nil and step.extraConfig.hasKey("context_path_prefix"):
    result = step.extraConfig["context_path_prefix"].getStr
