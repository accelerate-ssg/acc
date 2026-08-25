## Release automation for Accelerate.
##
## This file is included by acc.nimble, which exposes it as two tasks:
##
##   nimble prepare_release 1.2.3   Validate, bump, update the changelog, commit, tag
##   nimble publish_release         Push the commit and the tag, which starts the CI release
##
## It is included rather than run as a script so that its output reaches the
## terminal. Nimble swallows the output of anything it shells out to.
##
## The README "Releasing" section describes the process this implements.

import std/strutils

const
  nimble_path = "acc.nimble"
  changelog_path = "CHANGELOG.md"
  repo_url = "https://github.com/accelerate-ssg/acc"
  release_branch = "main"
  build_command = "nimble build -d:release -p:src --threads:on --mm:orc --deepcopy:on"
  unreleased_heading = "## [Unreleased]"
  unreleased_link = "[Unreleased]: "


proc abort( message: string ) {.noreturn.} =
  echo ""
  echo "Release aborted: ", message
  quit 1


proc capture( command: string ): string =
  ## Run a command for its output, aborting if it fails.
  let (output, exit_code) = gorgeEx( command )
  if exit_code != 0:
    abort "`" & command & "` failed:\n" & output
  result = output.strip


proc succeeds( command: string ): bool =
  gorgeEx( command )[1] == 0


proc run_command( command: string ) =
  ## Run a command for its effect, aborting if it fails.
  echo "  ", command
  try:
    exec command
  except OSError:
    abort "`" & command & "` failed."


proc today(): string =
  # NimScript can't call times.now(), so ask the shell. The second form is for
  # Windows, where there is no POSIX date.
  for command in [ "date +%Y-%m-%d",
                   "powershell -NoProfile -Command \"Get-Date -Format yyyy-MM-dd\"" ]:
    let
      (output, exit_code) = gorgeEx( command )
      stamp = output.strip
    if exit_code == 0 and stamp.len == 10 and stamp[4] == '-' and stamp[7] == '-':
      return stamp
  abort "could not determine today's date."


proc current_version(): string =
  for line in readFile( nimble_path ).splitLines:
    if line.strip.startsWith( "version" ):
      return line.rsplit( "=", 1 )[^1].strip.strip( chars = {'"'} )
  abort "no `version` line found in " & nimble_path


proc parse_version( version: string ): (int, int, int) =
  let parts = version.split( "." )
  if parts.len != 3:
    abort "version must look like X.Y.Z, got: " & version
  try:
    result = ( parts[0].parseInt, parts[1].parseInt, parts[2].parseInt )
  except ValueError:
    abort "version must look like X.Y.Z, got: " & version


proc unreleased_notes( changelog: string ): string =
  ## The body between the Unreleased heading and the next version heading.
  let start = changelog.find( unreleased_heading )
  if start < 0:
    abort changelog_path & " has no `" & unreleased_heading & "` heading."

  let
    body_start = start + unreleased_heading.len
    next_heading = changelog.find( "\n## [", body_start )
  result = if next_heading < 0: changelog[ body_start .. ^1 ]
           else: changelog[ body_start ..< next_heading ]


proc with_release_heading( changelog, version, date: string ): string =
  ## Leave Unreleased in place and open a dated section for this version below it.
  let cut = changelog.find( unreleased_heading ) + unreleased_heading.len
  result = changelog[ 0 ..< cut ] &
    "\n\n## [" & version & "] - " & date &
    changelog[ cut .. ^1 ]


proc with_updated_links( changelog, version, previous: string ): string =
  ## Point Unreleased at the new tag and add a compare link for the release.
  let start = changelog.find( unreleased_link )
  if start < 0:
    abort changelog_path & " has no `" & unreleased_link & "` link definition."

  var stop = changelog.find( "\n", start )
  if stop < 0:
    stop = changelog.len

  result = changelog[ 0 ..< start ] &
    unreleased_link & repo_url & "/compare/v" & version & "...HEAD\n" &
    "[" & version & "]: " & repo_url & "/compare/v" & previous & "...v" & version &
    changelog[ stop .. ^1 ]


proc bump_nimble_version( version: string ) =
  var
    lines: seq[string] = @[]
    bumped = false

  for line in readFile( nimble_path ).splitLines:
    if not bumped and line.strip.startsWith( "version" ):
      lines.add "version = \"" & version & "\""
      bumped = true
    else:
      lines.add line

  if not bumped:
    abort "no `version` line found in " & nimble_path
  writeFile( nimble_path, lines.join( "\n" ) )


proc assert_release_branch() =
  let branch = capture( "git rev-parse --abbrev-ref HEAD" )
  if branch != release_branch:
    abort "releases are cut from `" & release_branch & "`, but you are on `" &
      branch & "`."


proc assert_clean_tree() =
  let status = capture( "git status --porcelain --untracked-files=no" )
  if status.len > 0:
    abort "there are uncommitted changes:\n" & status


proc assert_tag_is_free( tag: string ) =
  if succeeds( "git rev-parse --quiet --verify refs/tags/" & tag ):
    abort "tag " & tag & " already exists locally."
  if capture( "git ls-remote --tags origin refs/tags/" & tag ).len > 0:
    abort "tag " & tag & " already exists on origin."


proc prepare_release( version: string ) =
  let
    tag = "v" & version
    previous = current_version()

  if parse_version( version ) <= parse_version( previous ):
    abort version & " is not newer than the current version " & previous & "."

  assert_release_branch()
  assert_clean_tree()
  assert_tag_is_free( tag )

  let changelog = readFile( changelog_path )
  if unreleased_notes( changelog ).strip.len == 0:
    abort "the `" & unreleased_heading & "` section of " & changelog_path &
      " is empty. Write the release notes before releasing."

  # Build before touching anything, so a broken tree fails without leaving a
  # half-prepared release behind. CI builds the binaries that ship.
  echo "Building a release binary as a smoke test..."
  run_command build_command

  echo "Bumping ", nimble_path, " to ", version, "..."
  bump_nimble_version( version )

  echo "Closing the changelog entry for ", version, "..."
  writeFile( changelog_path,
    changelog
      .with_release_heading( version, today() )
      .with_updated_links( version, previous ) )

  echo "Committing and tagging..."
  run_command "git add " & nimble_path & " " & changelog_path
  run_command "git commit -m \"Release " & version & "\""
  run_command "git tag -a " & tag & " -m \"Release " & tag & "\""

  echo ""
  echo "Prepared ", tag, ". Review the commit, then run `nimble publish_release`."


proc publish_release() =
  let
    version = current_version()
    tag = "v" & version

  assert_release_branch()
  assert_clean_tree()

  if not succeeds( "git rev-parse --quiet --verify refs/tags/" & tag ):
    abort "tag " & tag & " does not exist. Run `nimble prepare_release " &
      version & "` first."

  if capture( "git rev-parse " & tag & "^{}" ) != capture( "git rev-parse HEAD" ):
    echo "Warning: ", tag, " does not point at HEAD, so the release will not ",
      "include your latest commits."

  run_command "git push origin " & release_branch
  run_command "git push origin " & tag

  echo ""
  echo "Pushed ", tag, ". The release workflow builds the binaries and publishes"
  echo "them at ", repo_url, "/releases/tag/", tag
