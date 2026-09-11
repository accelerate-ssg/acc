## The per-page context keys the template engines inject, and the names
## that reserves.
##
## Content files are bound at a top-level key taken from their filename
## (see key_stack.add_file_path), so a file named after one of these keys
## would be shadowed by the injected value. The engines have always
## injected `item` and `items` this way without saying so; naming the set
## here lets the content loader warn instead of losing the file silently.

import std/[os, strutils]

const RESERVED_CONTEXT_KEYS* = ["item", "items", "page"]
  ## Top-level context keys the render pass binds per page.

proc url_path*(output_path: string): string =
  ## The URL a page is served at, derived from the path it is written to.
  ##
  ## Strips a `.html` extension, collapses a trailing `index` segment, and
  ## returns an absolute path with no trailing slash — matching the routing
  ## convention that `src/about.mustache` serves at `/about`. Outputs that
  ## are not HTML keep their extension, since that is how they are served:
  ## `sitemap.xml` is `/sitemap.xml`.
  var path = output_path
  if path.toLowerAscii.endsWith(".html"):
    path.setLen(path.len - ".html".len)

  var segments: seq[string] = @[]
  for segment in path.split({DirSep, AltSep}):
    if segment.len > 0 and segment != ".":
      segments.add(segment)

  if segments.len > 0 and segments[^1] == "index":
    segments.setLen(segments.len - 1)

  "/" & segments.join("/")

when isMainModule:
  import unittest

  suite "url_path":

    test "root index collapses to the site root":
      check url_path("index.html") == "/"

    test "root page drops its extension":
      check url_path("blommor.html") == "/blommor"

    test "nested page keeps its directory":
      check url_path("om-oss/film.html") == "/om-oss/film"

    test "deeply nested page keeps every directory":
      check url_path("produkter/kategori/widget.html") == "/produkter/kategori/widget"

    test "nested index collapses to its directory":
      check url_path("om-oss/index.html") == "/om-oss"

    test "index in a nested directory collapses to that directory":
      check url_path("a/b/index.html") == "/a/b"

    test "a page merely named index-something is not collapsed":
      check url_path("index-of-things.html") == "/index-of-things"

    test "a non-html output keeps its extension":
      check url_path("sitemap.xml") == "/sitemap.xml"

    test "an extensionless output is left alone":
      check url_path("robots") == "/robots"

    test "a leading separator does not double up":
      check url_path("/om-oss/film.html") == "/om-oss/film"

    test "an uppercase extension is still stripped":
      check url_path("Om-Oss.HTML") == "/Om-Oss"

    test "an empty output path is the root":
      check url_path("") == "/"
