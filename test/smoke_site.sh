#!/usr/bin/env bash
# Build test/smoke_site with the given acc binary and check what it wrote.
# The site is built from a copy whose path has a space and an å in it, and
# kept in git, so that after one content change and one deleted template a
# --using=git build can be checked for rendering only what they affect.
#   test/smoke_site.sh ./acc
set -euo pipefail

acc="$1"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
site="$work/smoke sajt å"
public="$site/public"

cp -R "$(dirname "$0")/smoke_site" "$site"
rm -rf "$public" "$site/.acc"
git -C "$site" init -q
git -C "$site" add .
git -C "$site" -c user.email=smoke@example.com -c user.name=smoke commit -qm site

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

"$acc" build "$site"

expect assets/css/main.css "margin: 0"
expect index.html "<title>Smoke</title>"
expect index.html "<p>Hej</p>"
expect index.html '<a href="/posts/second.html">Second post</a>'
expect posts/first.html "<h1>First post</h1>"
expect posts/first.html "<p>/posts/first</p>"
expect posts/second.html "<h1>Second post</h1>"
expect about.html "<title>SMOKE</title>"
expect about.html '<nav><a href="/posts/first.html">First post</a><a href="/posts/second.html">Second post</a></nav>'
expect about.html "<p>/about</p>"
expect hej.html "<p>Hej</p>"

# Liquid pages are rendered for what they read, so about.html, which does
# not read the greeting, keeps the marker written over it. Mustache pages
# are all rendered again on any change. The posts template takes both its
# pages with it.
printf 'greeting: Hallå\n' > "$site/content/sv/general.yaml"
rm "$site/src/posts/{posts[slug]}.mustache"
printf 'not rendered again' > "$public/about.html"

"$acc" build --using=git "$site"

expect hej.html "<p>Hallå</p>"
expect index.html "<p>Hallå</p>"
expect about.html "not rendered again"
for page in posts/first.html posts/second.html; do
  if [ -e "$public/$page" ]; then
    echo "$page was not removed with its template"
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  exit 1
fi
echo "smoke site built as expected"
