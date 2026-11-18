# Configuration

A site is configured by `acc.yaml` in its root directory. It names the
directories acc works with and the workflows a build runs.

```yaml
manifest_version: v1
name: "Example"

directories:
  src: "src"
  destination: "public"
  content: "content"
  config: ".acc"
  work: ".acc/work"
  scripts: ".acc/scripts"
  build: ".acc/build"

workflows:
  - name: "build"
    workflows:
      - "load"
      - "render"

  - name: "load"
    steps:
      - module: "@copy"
        glob: "**/*.{css,js,svg,webp,woff2}"
      - module: "@yaml"
        glob: "**/*.{yml,yaml,json}"

  - name: "render"
    steps:
      - module: "@liquid"
        glob: "**/*.liquid"
        partial_directories:
          - "src/partials"
```

`acc init` writes a starting point. Pass `--config FILE` to use another file,
and a `ROOT_DIR` argument to build a site other than the one in the current
directory:

```sh
acc build ../another-site
acc build --config staging.yaml
```

## Directories

Every directory is relative to the site root. acc has no defaults for them,
so name all of them.

| Key | What it holds |
|---|---|
| `src` | Templates, partials and static assets. A template's path here is its page's path, see [routing](routing.md). |
| `destination` | The built site. `acc dev` serves it and `acc clean` deletes it. |
| `content` | The content files `@yaml` loads, see [content](content.md). |
| `config` | acc's own directory, `.acc` by convention. |
| `work` | The build cache (`context.cache`) and the build manifest (`manifest.json`). `acc clean` deletes it. |
| `scripts` | Where a `script:` step's path is resolved. |
| `build` | Created before every build and deleted by `acc clean`. |

`--src`, `--destination`, `--work` and `--build` override the matching entry
for one run.

If `destination` or `config` sits inside `src`, it is left out of the source
tree, so a build never reads its own output.

## Workflows

`workflows` is a list. Each entry has a `name` and either `steps`, which it
runs in order, or `workflows`, a list of other workflows' names that it runs
in order:

```yaml
workflows:
  - name: "build"
    workflows:
      - "load"
      - "render"

  - name: "load"
    steps:
      - module: "@yaml"
        glob: "**/*.yaml"

  - name: "render"
    steps:
      - module: "@liquid"
        glob: "**/*.liquid"
```

A composition lists names, not workflow definitions. Each name must be
defined at the top level of `workflows`.

`acc build` and `acc dev` run the workflow named `build`. If there is none,
they run every workflow in the order the file lists them. `acc run NAME` runs
one workflow by name:

```sh
acc run load
```

### Load in one workflow, render in a later one

When a workflow with steps starts, acc first works out every page that
workflow's template steps will produce, and only then runs the steps. Content
that a step in the same workflow loads does not exist yet at that point, so a
template that pages over it finds nothing:

```yaml
# Wrong: the pages are worked out before @yaml has run
workflows:
  - name: "build"
    steps:
      - module: "@yaml"
        glob: "**/*.yaml"
      - module: "@liquid"
        glob: "**/*.liquid"
```

The log says so with a warning, and the build still exits 0:

```
[WARN]: Skipping '{posts[slug]}.liquid': no collection 'posts' to expand.
```

Templates that read content directly, like `{{ about.title }}`, still render,
because rendering happens after loading. Only templates with a
[dynamic segment](routing.md) are affected. With the build cache on, the
second build may even work, because it routes against the content the first
build loaded. A cold build in CI does not have that cache.

Put the template steps in a later workflow, as in the example at the top of
this page.

### Conditions

A workflow with an `if` runs only when the condition holds. Otherwise it is
skipped with a note in the log:

```yaml
- name: "deploy"
  if: "$BRANCH == main"
  steps:
    - command: "./deploy.sh"
```

acc evaluates the condition itself rather than through a shell, so it works
the same on every platform. `$NAME` and `${NAME}` expand from the
environment, except inside single quotes, and an unset variable expands to
nothing. These are the forms it accepts:

| Condition | Holds when |
|---|---|
| `VALUE` | `VALUE` is not empty |
| `A = B`, `A == B` | `A` and `B` are the same text |
| `A != B` | they differ |
| `-n VALUE` | `VALUE` is not empty |
| `-z VALUE` | `VALUE` is empty |
| `-e PATH` | `PATH` exists |
| `-f PATH` | `PATH` is a file |
| `-d PATH` | `PATH` is a directory |

Quote a value that contains spaces: `"$TITLE" = "two words"`. Anything else is
an error rather than a false condition, and that includes what a shell would
expand: `$(...)`, backticks, `${NAME:-default}` and `~`.

### Environment variables

`env` sets environment variables when its workflow starts, as a list of
`NAME=value` strings:

```yaml
- name: "load"
  env:
    - "SITE_ENV=production"
  steps:
    - command: "echo $SITE_ENV"
```

The variables are set after the workflow's `if` has been evaluated, and they
stay set for the rest of the run. A workflow that runs later sees them too,
in its condition as well as its steps.

## Steps

Each step does one of three things: runs a built-in `module`, a `script` or a
shell `command`.

```yaml
steps:
  - comment: "Copy static assets"
    module: "@copy"
    glob: "**/*.{css,js}"

  - command: "npx tailwindcss -o public/assets/site.css"

  - script: "generate_feed.js"
```

`comment` is logged when the step starts. Any other key is an option for the
module, such as `glob` above; [modules](modules.md) lists them.

### Failures

A failing step stops its workflow and the build. `on_failure: continue` turns
the failure into a warning instead:

```yaml
- command: "./optional-step.sh"
  on_failure: continue
```

A template step does not stop at the first page that fails. It renders every
page it can, logs each failure, and then fails as a whole, naming the pages.

### Commands

A `command` runs through the shell: `sh` on macOS and Linux, `cmd.exe` on
Windows. A non-zero exit code fails the step.

The command runs in the directory acc was started from, not in the site root.
`acc build ../another-site` therefore runs `./deploy.sh` from the current
directory. Start acc from the site root, or write paths the command can
resolve from anywhere.

### Scripts

A `script` path is resolved against `directories.scripts` unless it is
absolute. The script receives the build context, and the changes it makes to
it are merged back after it has run.

Scripts run through a script runner, a library acc loads at startup from a
`script_runners/` directory in the directory acc is started from.

A script step fails, like any other step, when the script file does not
exist, when there is no runner for its extension, or when the script raises
an error:

```
Error: unhandled exception: Script not found: /path/to/site/.acc/scripts/generate_feed.js [IOError]
```

`.nims` scripts are not supported yet, so a step naming one fails too.

### Settings that are accepted but not used yet

acc reads `depends_on` and `timeout` on a step, and `parallel` and
`max_concurrent` on a workflow, so a config that sets them still loads.
They have no effect yet: steps and workflows run one at a time, in the order
they are listed, and are never timed out.

## Values from the config

`${key}` in a directory or workflow value is replaced by a value from the top
level of `acc.yaml`. Dots walk into a mapping and `[n]` picks a list entry:

```yaml
name: "example"
domains:
  - "example.com"

workflows:
  - name: "publish"
    steps:
      - command: "echo Publishing ${name} to ${domains[0]}"
```

Only text values are substituted. A key that does not exist, or that holds a
number, a list or a mapping, is left as written, `${...}` included. In a
`command` the shell then reads it as an environment variable, which is
usually unset, so `echo ${count}` with `count: 3` prints an empty line.

## Older configs

A config with no `workflows` but a top-level `build:` list is the format from
before acc 0.2. acc converts it when it loads: each entry becomes a workflow
of its own, chained by a `build` workflow. Template file names in such a site
are read with the old spelling, where `{pages.slug}` meant what
`{pages[slug]}` means now. Write new sites in the format above.
