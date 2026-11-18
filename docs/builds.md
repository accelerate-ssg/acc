# Builds

```sh
acc build [ROOT_DIR]    # run the build workflow once
acc dev [ROOT_DIR]      # build, then watch and serve
acc run <workflow>      # run a single named workflow
acc clean               # remove generated output
acc init [ROOT_DIR]     # write a starting acc.yaml and its directories
```

`acc build` and `acc dev` run the workflow named `build`; see
[configuration](configuration.md#workflows).

## The development server

`acc dev` builds the site, serves it, and rebuilds when a file changes:

```sh
acc dev
acc dev --port 8080
```

Without `--port` it serves on the first free port from 1331 up to 1340, so
several sites can run at once, and logs which one it took. With `--port` it
uses that port or stops.

A request is answered from `destination`. `/about` serves `about.html`,
`/blog` serves `blog/index.html`, and a path with nothing in `destination`
falls back to the same path under `src`. HTML pages get a small script that
reloads the browser tab after each rebuild.

It watches `src` and `content`. Saving several files at once gives one
rebuild. A change to `acc.yaml` is not picked up; restart `acc dev` for that.

If a build fails, the server keeps serving what was last built and tries
again on the next change.

`/about:context` returns the whole build context as JSON, which shows what
the content files loaded as and the paths templates and routing can use:

```sh
curl http://localhost:1331/about:context
```

## Selective builds

By default `acc build` walks the whole source tree and renders everything.
On a site with a lot of pages that is wasteful when only a handful of files
have changed, so the build can instead be told what changed and render only
the pages affected by it.

`--using` picks how to find the changes:

```sh
acc build --using=git --since=origin/main
```

That asks git for everything that differs between `origin/main` and the
working tree, including untracked files, and builds only what those changes
affect. It is the mode a CI or deploy server wants: the baseline is whatever
the site looked like when it was last published, so a branch that touches one
content file rebuilds one page.

`--since` takes any ref git understands and defaults to `HEAD`, which means
"uncommitted work only". The strategy requires the site to be inside a git
repository.

The other strategies are `--using=mtime`, which rebuilds files in `src` and
`content` modified since the previous build's timestamp, and `--using=full`
(the default), which rebuilds everything. `mtime` looks at nothing else, so a
change to `acc.yaml` goes unnoticed under it.

`--using=mtime` needs the cache: the timestamp it compares against is the
previous build's, which is stored there, so `--using=mtime --no-cache`
reports that there is no baseline yet and exits without building.

It also cannot see deletions on its own, since a timestamp scan only finds
files that still exist, so removals come from the previous build's record.
Use `--using=git` where removals matter; it reports them directly.

### What a change renders

This applies to `--using=git`, `--using=mtime` and the rebuilds of
`acc dev`. A plain `acc build` renders everything.

| Change | Renders |
|---|---|
| A template | Every page it produces |
| A content file | The pages that read the data that changed in it |
| A new entry in a collection | The new page |
| A removed template, content file or entry | Nothing; the pages that no longer exist are deleted from `destination` |
| A partial, `acc.yaml`, or any other file in the site, where the strategy sees it | Everything |

A content change is narrowed to the values that actually changed, so
editing one post in a file of fifty re-renders that post's page and not the
other forty-nine:

```
[INFO]: Rendering 1 page(s) for this change
```

That works for Liquid, which records what each page reads. The Mustache step
reads the whole context for every page, so any content change renders all of
its pages:

```
[INFO]: Rendering every @mustache page: its step reads the whole context.
```

## Build cache

Selective builds and `--using=mtime` build on the persisted build context,
which acc saves to `context.cache` in the work directory after every build
and loads on the next one. It holds the previous build's content, the record
of which page read which data, the pages it produced, and its timestamp.

```
[INFO]: Continuing from the cached context of the previous build.
```

Pass `--no-cache` to neither load nor save it. A build without the cache
has no previous build to compare with, so it renders everything and deletes
no stale pages or assets.

Because the cache carries the previous build's content, a template that only
works when that content is already present can pass with the cache and fail
without it. Before trusting a change to routing or workflows, run one build
with `--no-cache`:

```sh
acc build --no-cache
```

## The build manifest

After each build, `manifest.json` in the work directory lists what the build
wrote and what it removed, which is what a deploy needs to upload and
delete:

```json
{
  "rendered": ["index.html", "blog/hello-world.html", "assets/site.css"],
  "removed": ["blog/old-post.html"]
}
```

Assets that `@copy` skipped because they had not changed are not listed.

## Cleaning up

`acc clean` deletes the `work`, `build` and `destination` directories,
including the cache. The next build is a full one.

## Inspecting the setup

`--show-me` prints internal state as JSON and exits without building:

```sh
acc build --show-me config   # the config as acc read it
acc build --show-me files    # source files each workflow's globs match
```

`files` lists every workflow with steps that `acc build` runs, in the order
it runs them, with the files under `src` that the workflow's globs match:

```json
{
  "load": ["assets/site.css"],
  "render": ["index.liquid", "blog/{posts[slug]}.liquid"]
}
```

The log is written to the same output, so add `--log silent` to get only
the JSON:

```sh
acc build --show-me files --log silent
```

`--log` sets how much is logged: `all`, `debug`, `info` (the default),
`warning`, `error`, `fatal` or `silent`.
