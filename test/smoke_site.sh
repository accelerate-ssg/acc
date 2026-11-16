#!/usr/bin/env bash
# Build test/smoke_site with the given acc binary and check what it wrote.
#   test/smoke_site.sh ./acc
set -euo pipefail

acc="$1"
site="$(dirname "$0")/smoke_site"
public="$site/public"

rm -rf "$public" "$site/.acc"
"$acc" build "$site"

failed=0
expect() {
  local file="$public/$1" text="$2"
  if [ ! -f "$file" ]; then
    echo "missing: $1"
    failed=1
  elif ! grep -qF -- "$text" "$file"; then
    echo "$1 does not contain: $text"
    failed=1
  fi
}

expect assets/css/main.css "margin: 0"
expect index.html "<title>Smoke</title>"
expect index.html "<p>Hej</p>"
expect index.html '<a href="/posts/second.html">Second post</a>'
expect posts/first.html "<h1>First post</h1>"
expect posts/first.html "<p>/posts/first</p>"
expect posts/second.html "<h1>Second post</h1>"

if [ "$failed" -ne 0 ]; then
  exit 1
fi
echo "smoke site built as expected"
