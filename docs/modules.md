# Modules

A step runs a built-in module with `module:`. Every key on the step other
than those [every step takes](configuration.md#steps), such as `comment` and
`on_failure`, is an option for that module.

```yaml
- module: "@liquid"
  glob: "**/*.liquid"
  partial_directories:
    - "src/partials"
```

| Module | Does |
|---|---|
| [`@copy`](#copy) | Copies files from `src` to `destination` unchanged |
| [`@yaml`](#yaml) | Loads content files into the build context |
| [`@markdown`](#markdown) | Converts Markdown strings in the context to HTML |
| [`@liquid`](#liquid-and-mustache) | Renders `.liquid` templates |
| [`@mustache`](#liquid-and-mustache) | Renders `.mustache` templates |

An unknown module name fails the step, and with it the build:

```
Error: unhandled exception: Unknown module: @yml [ValueError]
```

Globs follow the usual rules: `*` matches within one directory, `**` across
directories, and `{a,b}` either alternative. They match case sensitively and
with `/` on every platform.

## @copy

Copies every file under `src` that matches `glob` to the same path under
`destination`.

```yaml
- module: "@copy"
  glob: "**/*.{css,js,svg,webp,woff2,ico,txt,xml}"
```

`src/assets/css/site.css` is copied to `public/assets/css/site.css`.

| Option | Default | |
|---|---|---|
| `glob` | `**/*` | Relative to `src` |

Always set `glob`. Without it the step copies everything, templates included.

A file whose copy already exists with the same size and an equal or newer
time is skipped, so a rebuild copies only what changed. A file that the
previous build copied and that no longer exists in `src` is deleted from
`destination`. That needs the previous build's record, so it does not happen
under `--no-cache`; see [builds](builds.md).

## @yaml

Loads content files from the `content` directory into the build context,
where templates and [routing](routing.md) read them.

```yaml
- module: "@yaml"
  glob: "**/*.{yml,yaml,json}"
```

| Option | Default | |
|---|---|---|
| `glob` | none | Relative to `content`. Without it nothing is loaded, silently. |
| `context_path_prefix` | none | A dotted path to load every file under |

Each file is loaded at a key taken from its path, so `content/sv/about.yaml`
becomes `sv.about`. [Content](content.md) covers how paths become keys and
how files merge.

With a prefix, the same file lands one level further down:

```yaml
- module: "@yaml"
  glob: "**/*.yaml"
  context_path_prefix: "data"
```

`content/sv/about.yaml` is then `data.sv.about`.

Files ending in `.json` are parsed as JSON and everything else as YAML. A
file that does not parse stops the build.

## @markdown

Walks everything in the context so far and replaces each matching string with
the HTML its Markdown produces. It changes values in place, so a template
reads the HTML at the same key the Markdown was loaded at.

```yaml
- module: "@yaml"
  glob: "**/*.yaml"
- module: "@markdown"
  path_contains: "-markdown"
```

A string is converted when either test matches:

| Option | Default | Matches a string when |
|---|---|---|
| `path_contains` | `-markdown.` | its path contains this text |
| `content_starts_with` | `[//]:` | its value starts with this text |

`*` makes a test match every string, and an empty value turns it off.

The path is the string's place in the context, written with dots and a
leading dot, and `[n]` for a list entry. With this content:

```yaml
# content/post.yaml
body-markdown: "Some *emphasis*"
intro-markdown:
  text: "Some *emphasis*"
flagged: "[//]: # (markdown)\nSome *emphasis*"
plain: "Some *emphasis*"
```

the paths are `.post.body-markdown`, `.post.intro-markdown.text`,
`.post.flagged` and `.post.plain`, and the default settings convert:

- `intro-markdown.text`, because its path contains `-markdown.`,
- `flagged`, because it starts with `[//]:`, a Markdown comment that renders
  as nothing.

`body-markdown` is not converted, because its path ends at `-markdown`
without a dot after it. `path_contains: "-markdown"` converts it as well. A
whole file named `about-markdown.yaml` matches the default too, since every
string in it has `.about-markdown.` in its path.

Run `@markdown` after the `@yaml` step that loads the content.

## @liquid and @mustache

Render templates from `src` into `destination`, one HTML file per page.
[Routing](routing.md) describes which pages a template produces, and
[templates](templates.md) what a template can read.

```yaml
- module: "@liquid"
  glob: "**/*.liquid"
  partial_directories:
    - "src/partials"
```

| Option | Engine | Default | |
|---|---|---|---|
| `glob` | both | `*.liquid`, `*.mustache` | Relative to `src` |
| `partial_directories` | both | none | Directories partials are loaded from, relative to the site root |
| `search_dirs` | Mustache | none | More partial directories, as one comma-separated string |

The default glob only matches templates directly in `src`, so set it to
`**/*.liquid` or `**/*.mustache` to render a whole tree.

A template step must be in a later workflow than the `@yaml` step whose
content it pages over; [configuration](configuration.md#load-in-one-workflow-render-in-a-later-one)
explains why.

### Partials

A file inside a directory listed in `partial_directories` is a partial, not a
page: it can be included from a template but produces no output of its own.
Any other template under `src` that matches the glob is rendered as a page,
even if it is also included as a partial somewhere.

The two engines name partials differently.

**Liquid** names a partial by its path, with the extension, relative to `src`
or to a partial directory. `.liquid` and `.html` files can be partials. With
`partial_directories: ["src/partials"]`, `src/partials/head.liquid` can be
included as either of these:

```liquid
{% render 'partials/head.liquid', title: about.title %}
{% render 'head.liquid', title: about.title %}
```

**Mustache** names a partial by its path without the extension, relative to
`src`, to the site root, to each `search_dirs` entry or to a partial
directory. When two files would take the same name, the first directory in
that order wins:

```mustache
{{> partials/head}}
{{> head}}
```

### Failed pages

A page that fails to render is logged and skipped, and the rest of the
template's pages still render. At the end the step fails and lists the pages
that did not render, so the build fails too.

### Options acc does not read

`blur_hash` appears in some older sites' configs. acc does not read it, so it
has no effect and can be removed.
