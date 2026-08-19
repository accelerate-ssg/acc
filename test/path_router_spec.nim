## Executable specification for the path router.
##
## These tests describe the *target* grammar agreed in design, not what the
## router does today. They are expected to fail until the router is rewritten;
## a failing test here is a to-do item, and the suite is the definition of done.
##
##   nim c -r -p:src --threads:on --mm:orc --deepcopy:on test/path_router_spec.nim
##
## GRAMMAR
##
##   binding := "{" [ "." ] [ collection ] [ filter ] [ selector ] "}"
##
##   .            resolve inside the enclosing scope; omitted means the root
##   collection   dotted path to a collection
##   filter       "(" attribute.path = $reference ")"
##   selector     "[" attribute.path [ "[]" ] "]"; omitted names by key or index
##   []           trailing, inside a selector: flatten an array attribute
##
## RULES
##
##   1. Literal path segments never change scope. Only a binding does.
##   2. Elements whose name collides merge onto one page. `items` accumulates,
##      `key` holds the shared name, `item` is set only when exactly one
##      element produced the page.
##   3. Comparison treats both sides as sets, scalars being one-element sets,
##      and matches on non-empty intersection.
##   4. The normalisation that builds a name is the same one that compares in a
##      filter, so a name and its filter can never disagree.
##   5. $key is always available. $parent is available only when the enclosing
##      segment produced exactly one element.

import json, sequtils, sugar, unittest

import types/render_state
import types/render_state/file_router


proc paths(items: seq[RenderStateItem]): seq[string] =
  items.map((i) => i.output_path)

proc byPath(items: seq[RenderStateItem], wanted: string): RenderStateItem =
  ## Never returns nil. A missing page yields a placeholder so the assertions
  ## that follow fail with a useful message instead of aborting the whole run,
  ## which matters while most of this suite is still red.
  for item in items:
    if item.output_path == wanted:
      return item
  return init_render_state_item(
    source_path = "",
    output_path = "<no page at " & wanted & ">",
    item = newJNull(),
    items = newJArray()
  )

proc isUnset(node: JsonNode): bool =
  node.isNil or node.kind == JNull

proc count(node: JsonNode): int =
  ## len() dereferences nil, which would abort the run rather than fail a test.
  if node.isNil: -1
  else: node.len


suite "path router: collections and selectors":

  test "C1 root collection named by an attribute":
    let ctx = %* { "pages": [ { "name": "about" }, { "name": "contact" } ] }
    let results = ctx.calculate_render_state_items_for("{pages[name]}.mustache")

    check results.paths == @["about.html", "contact.html"]

    let about = results.byPath("about.html")
    check about.key == "about"
    check about.item{"name"}.getStr == "about"
    check about.items.count == 1

  test "C2 a literal directory does not change scope":
    let ctx = %* { "products": [ { "id": "a" }, { "id": "b" } ] }
    let results = ctx.calculate_render_state_items_for("products/{products[id]}.mustache")

    check results.paths == @["products/a.html", "products/b.html"]

  test "C3 an object collection with no selector is named by key":
    let ctx = %* { "products": { "widget": { "name": "Widget" } } }
    let results = ctx.calculate_render_state_items_for("products/{products}.mustache")

    check results.paths == @["products/widget.html"]

    let widget = results.byPath("products/widget.html")
    check widget.key == "widget"
    check widget.item{"name"}.getStr == "Widget"

  test "C4 an array collection with no selector is named by index":
    let ctx = %* { "products": [ { "name": "A" }, { "name": "B" } ] }
    let results = ctx.calculate_render_state_items_for("products/{products}.mustache")

    check results.paths == @["products/0.html", "products/1.html"]

  test "C5 a selector may be a deep attribute path":
    let ctx = %* { "products": [
      { "metadata": { "from_cms": { "Name": "Alpha" } } }
    ] }
    let results = ctx.calculate_render_state_items_for(
      "products/{products[metadata.from_cms.Name]}.mustache")

    check results.paths == @["products/Alpha.html"]

  test "C6 elements missing the selector attribute are skipped, not fatal":
    let ctx = %* { "products": [
      { "id": "a" },
      { "title": "this one has no id" }
    ] }
    let results = ctx.calculate_render_state_items_for("products/{products[id]}.mustache")

    check results.paths == @["products/a.html"]


suite "path router: scope and parent":

  test "C7 a dot prefix resolves inside the enclosing scope":
    let ctx = %* { "manufacturers": [
      { "path": "kubota",   "products": [ { "id": "m5-092" } ] },
      { "path": "junkkari", "products": [ { "id": "hj172g" } ] }
    ] }
    let results = ctx.calculate_render_state_items_for(
      "produkter/{manufacturers[path]}/{.products[id]}.mustache")

    check results.paths == @[
      "produkter/kubota/m5-092.html",
      "produkter/junkkari/hj172g.html"
    ]

    let m5 = results.byPath("produkter/kubota/m5-092.html")
    check m5.key == "m5-092"
    check m5.item{"id"}.getStr == "m5-092"
    check m5.parent{"path"}.getStr == "kubota"

  test "C8 without a dot prefix the root collection is used, never the scope":
    # The manufacturer carries its own `products`, but the binding asks for the
    # root one. Resolution must not silently prefer the nearer collection.
    let ctx = %* {
      "manufacturers": [ { "path": "kubota", "products": [ { "id": "nested" } ] } ],
      "products": [ { "id": "root" } ]
    }
    let results = ctx.calculate_render_state_items_for(
      "produkter/{manufacturers[path]}/{products[id]}.mustache")

    check results.paths == @["produkter/kubota/root.html"]

  test "C9 parent is recursive so templates can walk up":
    let ctx = %* { "regions": [
      { "slug": "nordic", "manufacturers": [
        { "path": "kubota", "products": [ { "id": "m5-092" } ] }
      ] }
    ] }
    let results = ctx.calculate_render_state_items_for(
      "{regions[slug]}/{.manufacturers[path]}/{.products[id]}.mustache")

    check results.paths == @["nordic/kubota/m5-092.html"]

    let m5 = results.byPath("nordic/kubota/m5-092.html")
    check m5.parent{"path"}.getStr == "kubota"
    check m5.parent{"parent"}{"slug"}.getStr == "nordic"

  test "C10 a literal template takes the enclosing scope as its item":
    let ctx = %* { "manufacturers": [
      { "path": "kubota", "name": "Kubota", "products": [ { "id": "m5-092" } ] }
    ] }
    let results = ctx.calculate_render_state_items_for(
      "produkter/{manufacturers[path]}/index.mustache")

    check results.paths == @["produkter/kubota/index.html"]

    let index = results.byPath("produkter/kubota/index.html")
    check index.item{"name"}.getStr == "Kubota"
    check index.item{"products"}.count == 1


suite "path router: filters and joins":

  test "C11 a filter joins a root collection against the parent key":
    let ctx = %* {
      "manufacturers": [ { "path": "junkkari" }, { "path": "kubota" } ],
      "products": [
        { "id": "hj172g", "manufacturer": [ "junkkari" ] },
        { "id": "m5-092", "manufacturer": [ "kubota" ] }
      ]
    }
    let results = ctx.calculate_render_state_items_for(
      "produkter/{manufacturers[path]}/{products(manufacturer = $key)[id]}.mustache")

    check results.paths == @[
      "produkter/junkkari/hj172g.html",
      "produkter/kubota/m5-092.html"
    ]

    let hj = results.byPath("produkter/junkkari/hj172g.html")
    check hj.item{"id"}.getStr == "hj172g"
    check hj.parent{"path"}.getStr == "junkkari"

  test "C12 a scalar foreign key matches exactly like a single element array":
    let ctx = %* {
      "manufacturers": [ { "path": "junkkari" } ],
      "products": [ { "id": "hj172g", "manufacturer": "junkkari" } ]
    }
    let results = ctx.calculate_render_state_items_for(
      "produkter/{manufacturers[path]}/{products(manufacturer = $key)[id]}.mustache")

    check results.paths == @["produkter/junkkari/hj172g.html"]

  test "C13 a filter may reference a field of the parent":
    let ctx = %* {
      "manufacturers": [ { "path": "junkkari", "name": "Junkkari" } ],
      "products": [ { "id": "hj172g", "brand": "Junkkari" } ]
    }
    let results = ctx.calculate_render_state_items_for(
      "produkter/{manufacturers[path]}/{products(brand = $parent.name)[id]}.mustache")

    check results.paths == @["produkter/junkkari/hj172g.html"]

  test "C14 a filter attribute may be a deep path":
    let ctx = %* {
      "manufacturers": [ { "path": "junkkari" } ],
      "products": [ { "id": "hj172g", "meta": { "brand": { "slug": "junkkari" } } } ]
    }
    let results = ctx.calculate_render_state_items_for(
      "produkter/{manufacturers[path]}/{products(meta.brand.slug = $key)[id]}.mustache")

    check results.paths == @["produkter/junkkari/hj172g.html"]

  test "C15 a filter that matches nothing yields no pages":
    let ctx = %* {
      "manufacturers": [ { "path": "junkkari" } ],
      "products": [ { "id": "orphan", "manufacturer": [ "nobody" ] } ]
    }
    let results = ctx.calculate_render_state_items_for(
      "produkter/{manufacturers[path]}/{products(manufacturer = $key)[id]}.mustache")

    check results.len == 0


suite "path router: merging and grouping":

  test "C16 colliding names merge onto one page":
    let ctx = %* { "products": [
      { "id": "a", "manufacturer": [ "junkkari" ] },
      { "id": "b", "manufacturer": [ "junkkari" ] },
      { "id": "c", "manufacturer": [ "kubota" ] }
    ] }
    let results = ctx.calculate_render_state_items_for(
      "produkter/{products[manufacturer]}.mustache")

    check results.paths == @["produkter/junkkari.html", "produkter/kubota.html"]

    let junkkari = results.byPath("produkter/junkkari.html")
    check junkkari.key == "junkkari"
    check junkkari.items.count == 2
    # item is set only when exactly one element produced the page, so that its
    # type does not change as data grows.
    check junkkari.item.isUnset

    let kubota = results.byPath("produkter/kubota.html")
    check kubota.items.count == 1
    check kubota.item{"id"}.getStr == "c"

  test "C17 a trailing [] flattens an array attribute":
    let ctx = %* { "products": [
      { "id": "a", "types": [ "redskap", "traktor" ] },
      { "id": "b", "types": [ "redskap" ] }
    ] }
    let results = ctx.calculate_render_state_items_for(
      "produkter/{products[types[]]}.mustache")

    check results.paths.len == 2
    check "produkter/redskap.html" in results.paths
    check "produkter/traktor.html" in results.paths

    let redskap = results.byPath("produkter/redskap.html")
    check redskap.key == "redskap"
    check redskap.items.count == 2

    let traktor = results.byPath("produkter/traktor.html")
    check traktor.items.count == 1

  test "C18 a product appears under every type it belongs to":
    let ctx = %* { "products": [
      { "id": "a", "types": [ "redskap", "traktor" ] },
      { "id": "b", "types": [ "redskap" ] }
    ] }
    let results = ctx.calculate_render_state_items_for(
      "produkter/{products[types[]]}/{products(types = $key)[id]}.mustache")

    check results.paths.len == 3
    check "produkter/redskap/a.html" in results.paths
    check "produkter/traktor/a.html" in results.paths
    check "produkter/redskap/b.html" in results.paths
    check "produkter/traktor/b.html" notin results.paths

  test "C19 a dot with only a selector iterates the enclosing group":
    let ctx = %* { "products": [
      { "id": "a", "types": [ "redskap" ] },
      { "id": "b", "types": [ "redskap" ] }
    ] }
    let results = ctx.calculate_render_state_items_for(
      "produkter/{products[types[]]}/{.[id]}.mustache")

    check results.paths == @["produkter/redskap/a.html", "produkter/redskap/b.html"]

  test "C20 $parent after a merged segment is a template error":
    let ctx = %* { "products": [
      { "id": "a", "types": [ "redskap" ] },
      { "id": "b", "types": [ "redskap" ] }
    ] }

    # Two products merged onto the redskap page, so there is no single parent
    # to read a field from. Unioning their fields would silently widen the
    # filter, so this must fail loudly instead.
    expect ValueError:
      discard ctx.calculate_render_state_items_for(
        "produkter/{products[types[]]}/{products(id = $parent.id)[id]}.mustache")


suite "path router: normalisation":

  test "C21 names are stripped and filters compare the stripped form":
    let ctx = %* {
      "manufacturers": [ { "path": "  junkkari  " } ],
      "products": [ { "id": "hj172g", "manufacturer": [ "junkkari" ] } ]
    }
    let results = ctx.calculate_render_state_items_for(
      "produkter/{manufacturers[path]}/{products(manufacturer = $key)[id]}.mustache")

    # If naming stripped but comparison did not, this would produce an empty
    # produkter/junkkari/ directory and no warning.
    check results.paths == @["produkter/junkkari/hj172g.html"]

  test "C22 numbers and strings compare by their string form":
    let ctx = %* {
      "manufacturers": [ { "path": 1 } ],
      "products": [ { "id": "hj172g", "manufacturer": "1" } ]
    }
    let results = ctx.calculate_render_state_items_for(
      "produkter/{manufacturers[path]}/{products(manufacturer = $key)[id]}.mustache")

    check results.paths == @["produkter/1/hj172g.html"]

  test "C23 an empty or missing name skips the element":
    let ctx = %* { "products": [
      { "id": "a" },
      { "id": "" },
      { "id": nil }
    ] }
    let results = ctx.calculate_render_state_items_for("products/{products[id]}.mustache")

    check results.paths == @["products/a.html"]

  test "C24 a data value containing braces is inert":
    # Resolved values are data. The template is parsed once and then expanded,
    # so a value like this can never be re-parsed as a binding.
    let ctx = %* { "manufacturers": [ { "path": "{manufacturers[path]}" } ] }
    let results = ctx.calculate_render_state_items_for(
      "produkter/{manufacturers[path]}/index.mustache")

    check results.paths == @["produkter/{manufacturers[path]}/index.html"]

  test "C25 a data value containing parentheses is inert":
    let ctx = %* { "manufacturers": [
      { "path": "kubota (premium)", "products": [ { "id": "m5-092" } ] }
    ] }
    let results = ctx.calculate_render_state_items_for(
      "produkter/{manufacturers[path]}/{.products[id]}.mustache")

    check results.paths == @["produkter/kubota (premium)/m5-092.html"]


suite "path router: static templates":

  test "C26 a static template at the root takes the root context as item":
    let ctx = %* { "about": { "name": "About Us" } }
    let results = ctx.calculate_render_state_items_for("about.mustache")

    check results.paths == @["about.html"]

    let about = results.byPath("about.html")
    check about.item == ctx
    check about.parent.isUnset

  test "C27 a static template under literal directories keeps them in the path":
    let ctx = %* { "about": { "name": "About Us" } }
    let results = ctx.calculate_render_state_items_for("a/b/c/about.mustache")

    check results.paths == @["a/b/c/about.html"]

  test "C28 an unknown collection yields no pages and does not raise":
    let ctx = %* { "other": [ { "id": "a" } ] }
    let results = ctx.calculate_render_state_items_for("products/{products[id]}.mustache")

    check results.len == 0
