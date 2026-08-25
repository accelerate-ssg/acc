from os import absolutePath, normalizedPath, fileExists, dirExists, isAbsolute, `/`, getCurrentDir
import docopt

from version import application_version

const help = """
accelerate - static site generator

Usage:
  acc init [options] [ROOT_DIR]
  acc build [options] [ROOT_DIR]
  acc dev [options] [ROOT_DIR]
  acc run <workflow> [options] [ROOT_DIR]
  acc clean [options]
  acc -h | --help
  acc -v | --version

Arguments:
  ROOT_DIR               Project root directory [default: .]
  workflow               Name of a workflow defined in the config

Build/Dev options:
  -c, --config FILE      Config file path [default: acc.yaml]
  -s, --src DIR          Source directory override
  -d, --destination DIR  Destination directory override
  -w, --work DIR         Work directory override
  -b, --build DIR        Build directory override
  -u, --using STRATEGY   How to find what changed: full, git, mtime
                         [default: full]
  --since REF            Baseline ref for --using=git [default: HEAD]
  --no-cache             Do not load or save the persisted build context
                         (it lives in the work directory and is what
                         selective rebuilds and --using=mtime build on)

Options:
  -l, --log LEVEL        Log level: all, debug, info, warning, error,
                         fatal, silent [default: info]
  -m, --show-me ASPECT   Dump internal state as JSON and exit
                         (config, files)
  -h, --help             Print this help message
  -v, --version          Print version information
"""

proc resolveDir*(root: string, value: string): string =
  if value == "":
    return ""
  absolutePath(normalizedPath(root / value))

proc parseCliArgs*(): Config =
  let
    version_string = "Accelerate " & application_version & ", built at " & CompileDate & " " & CompileTime & " using Nim " & NimVersion
    args = docopt(help, version = version_string)

  result = Config()

  # Determine root directory
  let root_dir = if args["ROOT_DIR"]: absolutePath(normalizedPath($args["ROOT_DIR"]))
                 else: getCurrentDir()

  result.directories.root = root_dir

  # Determine action
  if args["init"]:
    result.action = ActionInit
  elif args["build"]:
    result.action = ActionBuild
  elif args["dev"]:
    result.action = ActionDev
  elif args["run"]:
    result.action = ActionRun
    result.runWorkflow = $args["<workflow>"]
  elif args["clean"]:
    result.action = ActionClean

  # Determine config file path and load config if it exists
  # docopt returns the default value "acc.yaml" even when --config is not explicitly provided,
  # so we resolve relative to root_dir in that case.
  let
    configArg = $args["--config"]
    config_path = if configArg.isAbsolute: configArg
                  else: root_dir / configArg

  if fileExists(config_path) and result.action != ActionInit:
    let file_content = readFile(config_path)
    # A malformed config is a user error, not a crash: report the file
    # and the problem, then exit.
    try:
      result = loadConfig(file_content)
    except CatchableError as e:
      stderr.writeLine "Invalid config " & config_path & ": " & e.msg
      quit(1)
    result.directories.root = root_dir
    # Re-apply the action (loadConfig doesn't set it)
    if args["init"]: result.action = ActionInit
    elif args["build"]: result.action = ActionBuild
    elif args["dev"]: result.action = ActionDev
    elif args["run"]:
      result.action = ActionRun
      result.runWorkflow = $args["<workflow>"]
    elif args["clean"]: result.action = ActionClean

  # Change detection strategy
  result.changeStrategy = if args["--using"]: $args["--using"] else: "full"
  result.changeSince = if args["--since"]: $args["--since"] else: "HEAD"
  result.useCache = not bool(args["--no-cache"])

  # Apply CLI directory overrides
  if args["--src"]:
    result.directories.src = resolveDir(root_dir, $args["--src"])
  elif result.directories.src != "" and not result.directories.src.isAbsolute:
    result.directories.src = resolveDir(root_dir, result.directories.src)

  if args["--destination"]:
    result.directories.destination = resolveDir(root_dir, $args["--destination"])
  elif result.directories.destination != "" and not result.directories.destination.isAbsolute:
    result.directories.destination = resolveDir(root_dir, result.directories.destination)

  if args["--work"]:
    result.directories.work = resolveDir(root_dir, $args["--work"])
  elif result.directories.work != "" and not result.directories.work.isAbsolute:
    result.directories.work = resolveDir(root_dir, result.directories.work)

  if args["--build"]:
    result.directories.build = resolveDir(root_dir, $args["--build"])
  elif result.directories.build != "" and not result.directories.build.isAbsolute:
    result.directories.build = resolveDir(root_dir, result.directories.build)

  # Resolve remaining config-file directories
  if result.directories.content != "" and not result.directories.content.isAbsolute:
    result.directories.content = resolveDir(root_dir, result.directories.content)
  if result.directories.config != "" and not result.directories.config.isAbsolute:
    result.directories.config = resolveDir(root_dir, result.directories.config)
  if result.directories.scripts != "" and not result.directories.scripts.isAbsolute:
    result.directories.scripts = resolveDir(root_dir, result.directories.scripts)

  # Parse log level
  case toLowerAscii($args["--log"]):
  of "all": result.logLevel = lvlAll
  of "debug": result.logLevel = lvlDebug
  of "info": result.logLevel = lvlInfo
  of "warning": result.logLevel = lvlWarn
  of "error": result.logLevel = lvlError
  of "fatal": result.logLevel = lvlFatal
  of "silent": result.logLevel = lvlNone
  else: discard

  # Parse --show-me
  if args["--show-me"]:
    result.showMe = $args["--show-me"]
