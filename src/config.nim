import yaml/[parser, dom, stream, data, tojson], tables, options, json, strutils, sequtils
import regex

include config/types
include config/helpers
include config/loaders
include config/io
include config/json_serialization
include config/cli

# Example usage
when not defined(release):
  include ../test/test_config
