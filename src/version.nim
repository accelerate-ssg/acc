import strutils

proc get_version(): string =
  result = ""
  var nimble_config = staticRead "../acc.nimble"
  var lines = nimble_config.split_lines

  for line in lines:
    if line.strip.starts_with("version"):
      var parts = line.rsplit("=", 1)
      result = $parts[^1].strip[1..^2]

const
  application_version* = get_version()
