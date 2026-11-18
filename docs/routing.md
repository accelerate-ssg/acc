# Routing

acc has no routes to configure. A template's path under `src` is the path of
the page it produces, and a part of that path written in braces turns one
template into a page per entry of a collection.

```
src/about.liquid               ->  public/about.html
src/blog/{posts[slug]}.liquid  ->  public/blog/hello-world.html
                                   public/blog/second-post.html
```

Routing applies to the files a [template step](modules.md#liquid-and-mustache)
renders. Assets copied by `@copy` keep their path as it is.

## Static templates

A template with no braces in its path produces one page, at the same path
with `.html` in place of the template's extension:

| Template | Output | `page.path` |
|---|---|---|
| `src/index.liquid` | `index.html` | `/` |
| `src/about.liquid` | `about.html` | `/about` |
| `src/blog/index.liquid` | `blog/index.html` | `/blog` |
| `src/sv/om-oss.liquid` | `sv/om-oss.html` | `/sv/om-oss` |

`page.path` is the URL the page is served at, which [templates](templates.md)
can read.

The output always ends in `.html`. `src/sitemap.xml.liquid` produces
`sitemap.xml.html`, so a file that must keep another extension has to be a
static asset that `@copy` copies.

A static template reads its content by name, for example
`{{ about.title }}` for `content/about.yaml`. See
[templates](templates.md#what-a-page-can-read).

## Dynamic segments

A segment of the path in braces is a binding. It names a collection in the
build context, and the template produces one page for each entry:

```yaml
# content/posts.yaml
- slug: hello-world
  title: Hello world
- slug: second-post
  title: Second post
```

```
src/blog/{posts[slug]}.liquid
```

```
public/blog/hello-world.html
public/blog/second-post.html
```

`posts` is the collection and `[slug]` the attribute that names each page.
In the template, `item` is that page's entry:

```liquid
<h1>{{ item.title }}</h1>
```

The full form of a binding is:

```
{ [.] collection [(attribute = $reference)] [[attribute]] }
```

| Part | Meaning | Section |
|---|---|---|
| `.` | Look the collection up in the enclosing entry instead of at the root | [Nested collections](#nested-collections) |
| `collection` | A dotted path to a list or a mapping | [Collections](#collections) |
| `(attribute = $reference)` | Keep only the entries that match | [Filters](#filters) |
| `[attribute]` | Name each page by this attribute | [Naming pages](#naming-pages) |
| `[attribute[]]` | The attribute is a list; a page per value | [Grouping](#grouping) |

## Collections

The collection is a dotted path from the root of the build context, the same
path a template would use to read it. Content in a language directory is
addressed with the directory first:

```
content/sv/services.json      ->  src/sv/{sv.services[slug]}.liquid
content/en/services.json      ->  src/en/{en.services[slug]}.liquid
```

A collection can be a list or a mapping. A directory of content files is a
mapping, keyed by file name, so each file can be a page of its own:

```
content/services/consulting.yaml
content/services/training.yaml
```

```
src/services/{services}.liquid
```

```
public/services/consulting.html
public/services/training.html
```

[Content](content.md) describes how files become keys.

## Naming pages

With an attribute in brackets, each page is named by that attribute's value.
Without one, a page is named by its key in a mapping or its index in a list:

| Template | Collection | Pages |
|---|---|---|
| `{posts[slug]}.liquid` | a list with `slug` | `hello-world.html`, `second-post.html` |
| `{posts}.liquid` | the same list | `0.html`, `1.html` |
| `{services}.liquid` | a mapping | `consulting.html`, `training.html` |

The attribute can be a dotted path into the entry. `{posts[meta.slug]}` names
each page by `meta.slug`.

Values are trimmed of surrounding whitespace, and numbers and booleans are
written as text. An entry whose attribute is missing or empty produces no
page and no warning.

A segment can carry text before and after the binding, but only one binding:

```
src/categories/category-{products[categories[]]}.liquid
->  public/categories/category-tools.html
```

A value is only ever used as a name. A slug containing braces or parentheses
produces a page with those characters in its name; it is never read as
another binding.

## Directories

A binding can be a directory as well as a file name. Every template under it
is rendered once per entry:

```
src/{posts[slug]}/index.liquid  ->  public/hello-world/index.html
                                    public/second-post/index.html
```

Those pages are served at `/hello-world` and `/second-post`.

A directory without braces adds to the path and nothing else. In
`src/blog/{posts[slug]}.liquid`, `blog` does not change where `posts` is
looked up.

## Nested collections

When each entry carries a collection of its own, a leading `.` looks the
next collection up inside the current entry:

```yaml
# content/brands.yaml
- slug: alpha
  name: Alpha
  products:
    - id: hammer
    - id: saw
- slug: beta
  name: Beta
  products:
    - id: kite
```

```
src/brands/{brands[slug]}/{.products[id]}.liquid
```

```
public/brands/alpha/hammer.html
public/brands/alpha/saw.html
public/brands/beta/kite.html
```

Without the dot, a collection is always looked up at the root, even inside
a dynamic directory. If the root also has a `products` collection,
`src/brands/{brands[slug]}/{products[id]}.liquid` puts every root product
under every brand.

A static template inside a dynamic directory gets that directory's entry as
`item`:

```
src/brands/{brands[slug]}/index.liquid
```

```liquid
<h1>{{ item.name }}</h1>
{% for product in item.products %}
  <a href="{{ page.path }}/{{ product.id }}">{{ product.id }}</a>
{% endfor %}
```

## Filters

A filter keeps the entries whose attribute matches a reference, which joins
one collection against another. With brands and products in separate files:

```yaml
# content/brands.yaml
- slug: alpha
  name: Alpha
- slug: beta
  name: Beta
```

```yaml
# content/products.yaml
- id: hammer
  brand: alpha
- id: saw
  brand: alpha
- id: kite
  brand: beta
```

```
src/brands/{brands[slug]}/{products(brand = $key)[id]}.liquid
```

```
public/brands/alpha/hammer.html
public/brands/alpha/saw.html
public/brands/beta/kite.html
```

The reference is one of:

| Reference | Is |
|---|---|
| `$key` | The name the enclosing segment produced, here the brand's `slug` |
| `$parent.attribute` | An attribute of the enclosing entry, such as `$parent.name` |

`$parent.parent.attribute` reaches one level further up.

Both sides of the comparison are treated as sets: a single value is a set of
one, and the entry matches when the two share any value. `brand: alpha` and
`brand: [alpha]` match alike, and a product with `brand: [alpha, beta]`
appears under both brands. Values compare as trimmed text, so `1` matches
`"1"`.

The filter's attribute can be a dotted path, such as
`(meta.brand.slug = $key)`. A filter that matches nothing produces no pages.

`$parent` needs a single enclosing entry. After a segment that grouped
several entries onto one page, see below, there is none, and the build stops
with an error naming the template. Use `$key` there instead.

## Grouping

Entries whose names come out the same share one page. Naming products by
their brand gives a page per brand:

```
src/by-brand/{products[brand]}.liquid
```

```
public/by-brand/alpha.html    items: hammer, saw
public/by-brand/beta.html     items: kite
```

`items` holds every entry that produced the page. `item` is set only when
there is exactly one, so on `alpha.html` it is empty and on `beta.html` it is
the kite. Write grouped pages against `items`, so they do not change shape
when a second entry arrives:

```liquid
{% for product in items %}
  <li>{{ product.id }}</li>
{% endfor %}
```

When the attribute holds a list, end it with `[]` to produce a page per value
in the list:

```yaml
# content/products.yaml
- id: hammer
  categories: [tools, garden]
- id: saw
  categories: [tools]
- id: kite
  categories: [toys]
```

```
src/categories/{products[categories[]]}.liquid
```

```
public/categories/garden.html   items: hammer
public/categories/tools.html    items: hammer, saw
public/categories/toys.html     items: kite
```

acc names a page per value whether or not the `[]` is there. With it, acc
also warns when it finds a single value where a list was expected.

A grouped directory with `{.[attribute]}` inside it gives each entry in the
group a page of its own:

```
src/categories/{products[categories[]]}/{.[id]}.liquid
```

```
public/categories/garden/hammer.html
public/categories/tools/hammer.html
public/categories/tools/saw.html
public/categories/toys/kite.html
```

The same pages come from a filter on the root collection,
`{products(categories = $key)[id]}`.

A static template inside a grouped directory, such as
`src/categories/{products[categories[]]}/index.liquid`, gets the group in
`items`. Its `item` is the entry when the group has one and the whole group
when it has several, so read `items` there as well.

## When a template produces no pages

acc warns and moves on when a template's collection does not exist:

```
[WARN]: Skipping 'blog/{posts[slug]}.liquid': no collection 'posts' to expand.
```

The build still exits 0, so check the log. The usual causes:

- The content is loaded in the same workflow as the template step. Routing
  happens before the steps run; see
  [configuration](configuration.md#load-in-one-workflow-render-in-a-later-one).
- The path does not match the content. `content/sv/posts.yaml` is `sv.posts`,
  not `posts`.
- The `@yaml` glob does not match the file, so it was never loaded. Each
  loaded file is logged as `Parsing: <path>`.

A template whose collection exists but whose entries all lack the naming
attribute, or whose filter matches nothing, produces no pages and no warning.

`acc dev` serves the whole build context as JSON at `/about:context`, which
shows the paths routing can use.

## Older spelling

Before acc 0.2, `{posts.slug}` meant what `{posts[slug]}` means now. A config
in the old `build:` format still reads that spelling; see
[configuration](configuration.md#older-configs). Under a current config,
`{posts.slug}` looks for a collection at the path `posts.slug`, usually
finds none, and the template is skipped with the warning above.

An inner binding that named entries of the enclosing group, such as `{id}`
in `{products.category}/{id}.mustache`, is written `{.[id]}` now. Under
either kind of config, a bare `{id}` looks for a root collection called `id`.
