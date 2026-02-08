import os, json
import glob

import logger
import global_state
import config

proc getStepExtraStr(key: string, default: string): string =
  let step = state.current_step
  if step.extraConfig != nil and step.extraConfig.hasKey(key):
    return step.extraConfig[key].getStr
  return default

iterator each*(paths: openArray[string]): tuple[absolute: string, relative: string] =
  let
    root = state.config.directories.root
    match_relative = getStepExtraStr("match_relative", "true") == "true"
    pattern = glob(getStepExtraStr("glob", "**/*"))

  for path in paths:
    let
      absolute_path = path
      relative_path = relativePath(absolute_path, root)
      matches = if match_relative: relative_path.matches(pattern) else: absolute_path.matches(pattern)

    if match_relative:
      warn relative_path, " matches ", getStepExtraStr("glob", "**/*"), " = ", matches
    else:
      warn absolute_path, " matches ", getStepExtraStr("glob", "**/*"), " = ", matches

    if matches:
      yield (absolute: absolute_path, relative: relative_path)
