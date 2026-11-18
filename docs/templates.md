# Templates

acc renders Liquid (`.liquid`) and Mustache (`.mustache`) templates with
[pitchfork](https://github.com/accelerate-ssg/pitchfork), which documents
the languages themselves. This page covers what acc gives a template to read.
[Modules](modules.md#liquid-and-mustache) covers the step options and how
partials are named, and [routing](routing.md) which pages a template
produces.

## What a page can read

Every page can read the whole build context by name, as described in
[content](content.md):

```liquid
<title>{{ about.title }} – {{ general.site_name }}</title>
```

On top of that, acc sets three keys for each page:

| Key | Holds |
|---|---|
| `item` | The entry this page was produced from, see below |
| `items` | Every entry that produced this page, as a list |
| `page.path` | The URL the page is served at |

### item and items

What `item` and `items` hold depends on the template:

| Template | `item` | `items` |
|---|---|---|
| Static, like `about.liquid` | the whole build context | empty |
| One page per entry, like `{posts[slug]}.liquid` | the entry | the entry, alone |
| A page several entries share, like `{products[brand]}.liquid` | empty | the entries |
| Static inside a dynamic directory, like `{brands[slug]}/index.liquid` | the directory's entry, or the list of them if it has several | the entries |

So a static page reads its content by name, `{{ about.title }}`. On a static
page `{{ item.title }}` renders empty, because `item` is the whole context
there: the same value is `{{ item.about.title }}`.

On pages that several entries can share, read `items`. `item` there is set
only when one entry produced the page, so a template written against it
breaks the first time a second entry shares the page.

The enclosing entry of a nested route is not available to the template.
Routing uses it for `$parent` in [filters](routing.md#filters), but a page
under `{brands[slug]}/{.products[id]}` only sees the product. Put what the
page needs from the brand in the product's content, or look the brand up in
the context.

### Breadcrumbs

A breadcrumb needs the enclosing entry, so a nested page looks it up. When
the entry carries the parent's key, as with a
[filter](routing.md#filters), look the parent up by that key:

```
src/shop/{brands[slug]}/{products(brand = $key)[id]}.liquid
```

```liquid
{% assign brand = brands | where: "slug", item.brand | first %}
<nav>
  <a href="/shop">Shop</a> ›
  <a href="/shop/{{ brand.slug }}">{{ brand.name }}</a> ›
  {{ item.name }}
</nav>
```

When it does not, as with a [nested collection](routing.md#nested-collections),
take the key from `page.path`. On `/brands/alpha/saw` the parts are `""`,
`brands`, `alpha` and `saw`:

```
src/brands/{brands[slug]}/{.products[id]}.liquid
```

```liquid
{% assign parts = page.path | split: "/" %}
{% assign brand = brands | where: "slug", parts[2] | first %}
<a href="/brands/{{ brand.slug }}">{{ brand.name }}</a> › {{ item.name }}
```

Mustache has no filters to look anything up with, so a Mustache page needs
the parent's name in its own entry.

### page.path

`page.path` comes from the page's output path: `.html` is dropped, a
trailing `index` is dropped, and the path starts with `/` and has no
trailing `/`.

| Output | `page.path` |
|---|---|
| `index.html` | `/` |
| `about.html` | `/about` |
| `blog/index.html` | `/blog` |
| `blog/hello-world.html` | `/blog/hello-world` |

A dynamic template gets the path its entry was routed to, so a shared head
partial can build the canonical URL without a field on every page:

```liquid
<link rel="canonical" href="{{ general.url }}{{ page.path }}">
```

## Missing values

A value that does not exist renders as nothing, without a warning, in both
languages. A misspelt key gives an empty spot on the page rather than a
failed build, so check the output.

## Liquid

**`render` only sees what it is passed.** A partial included with `render`
gets its own scope, without the page's variables or the build context:

```liquid
{% render 'partials/head.liquid' %}
{% render 'partials/head.liquid', about: about, page: page %}
```

In the first line, `{{ about.title }}` and `{{ page.path }}` inside the
partial are empty. Pass what it needs, as in the second line, or use
`include`, which shares the including template's scope:

```liquid
{% include 'partials/head.liquid' %}
```

**An empty string is true.** Liquid treats only `nil` and `false` as false,
so an empty string and an empty list both pass an `if`. Test an optional
value for content explicitly:

```liquid
{% if about.image and about.image != "" %}
  <img src="{{ about.image }}" alt="">
{% endif %}
```

For a list, test its size: `{% if posts.size > 0 %}`.

## Mustache

**Empty values are false.** A section is skipped for a missing value,
`false`, an empty string, `0`, an empty list and an empty mapping:

```mustache
{{#about.image}}<img src="{{about.image}}" alt="">{{/about.image}}
{{^about.image}}<div class="placeholder"></div>{{/about.image}}
```

**A section over a list is the loop.** `{{#posts}}...{{/posts}}` renders once
per post with the post as the current context. To show something once, only
when the list has entries, test for its first entry:

```mustache
{{#posts.0}}<h2>Latest posts</h2>{{/posts.0}}
{{#posts}}<a href="/blog/{{slug}}">{{title}}</a>{{/posts}}
```

Partials see the context at the point they are included, so
`{{> partials/head}}` inside `{{#posts}}` can read the current post's
fields.

## Output files

Every page is written as an `.html` file, whatever the template is called.
`sitemap.xml.liquid` produces `sitemap.xml.html`, so a sitemap, a
`robots.txt` or a feed has to be a static file that `@copy` copies.
