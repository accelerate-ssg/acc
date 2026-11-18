# Content

Content is the data a site is built from: YAML and JSON files in the
`content` directory, loaded by the [`@yaml`](modules.md#yaml) step into one
tree, the build context. Templates read from that tree and
[routing](routing.md) pages over it.

## From file to key

A file is loaded at a key made from its path inside `content`, without the
extension. Each directory is one level:

| File | Key | Read in a template as |
|---|---|---|
| `content/general.yaml` | `general` | `{{ general.title }}` |
| `content/sv/general.yaml` | `sv.general` | `{{ sv.general.title }}` |
| `content/sv/services.json` | `sv.services` | `{% for service in sv.services %}` |
| `content/blog/posts/first.yaml` | `blog.posts.first` | `{{ blog.posts.first.title }}` |

What the file holds becomes the value at that key. A mapping is a mapping:

```yaml
# content/about.yaml
title: About us
intro: We build things.
```

```liquid
<h1>{{ about.title }}</h1>
<p>{{ about.intro }}</p>
```

and a list is a list, which routing can page over:

```yaml
# content/posts.yaml
- slug: hello-world
  title: Hello world
- slug: second-post
  title: Second post
```

```liquid
{% for post in posts %}
  <a href="/blog/{{ post.slug }}">{{ post.title }}</a>
{% endfor %}
```

A YAML file with several documents, separated by `---`, loads as a list of
them. An empty file loads as an empty list.

## A directory as a collection

Because each directory is a level, a directory of files is a mapping keyed by
file name:

```
content/services/consulting.yaml
content/services/training.yaml
```

A template can produce a page for each file; see
[routing](routing.md#collections). Looping over a mapping in Liquid gives
name and value pairs rather than the values, in the order the directory
lists the files rather than by name:

```liquid
{% for service in services %}
  <a href="/services/{{ service[0] }}">{{ service[1].title }}</a>
{% endfor %}
```

The other way to hold a collection is one file with a list, like
`posts.yaml` above. A list keeps its order and loops over its entries
directly, so it suits content that is listed as well as paged over. Pick the
shape that matches where the content comes from.
Content written by a CMS sync usually arrives as one list per type, and a
template written against that shape keeps working when the sync takes over
from hand-written files.

## Files and directories merge

A file and a directory with the same name load into the same key:

```yaml
# content/blog.yaml
title: Our blog
```

```yaml
# content/blog/first.yaml
title: First post
```

`blog` now holds both: `blog.title` is "Our blog" and `blog.first.title` is
"First post". That is fine for reading, but a template that pages over
`{blog}` produces a page for `title` as well as for `first`. Keep a
collection's directory free of anything that is not one of its entries.

If `blog.yaml` also had a `first:` key, the directory would win and the
file's value would be dropped without a warning. Do not give a directory the
same name as a key in its sibling file.

## Names to avoid

**Dots in file names.** `content/a.b.yaml` is loaded at a single key named
`a.b`, which `a.b` in a template or a binding cannot reach: that path means
the key `b` inside `a`. Use `-` or `_` instead.

**`item`, `items` and `page`.** These are set on every page by the render
step (see [templates](templates.md)), so a top-level file with one of these
names is hidden behind them. acc warns when it loads one:

```
[WARN]: Content file page.yaml binds the reserved context key 'page'; ...
```

The same names one level down, like `content/sv/page.yaml`, are fine.

## Seeing what was loaded

Each file `@yaml` loads is logged:

```
[INFO]: Parsing: sv/services.json
```

and `acc dev` serves the whole build context as JSON at `/about:context`, for
example `http://localhost:1331/about:context`.
