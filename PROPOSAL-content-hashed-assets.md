# Proposal: content-hashed asset filenames (`@digest`)

A new Accelerate pipeline step that renames build outputs to include a hash of
their contents, and rewrites references to match. It would make cache
invalidation exact and automatic, replacing the manual schemes sites use today.

Written up from the Accodeing side, where sites hit the problem daily. Moved
here from the site-template repo's TODO because the work is in `acc`, not in any
one site.

## The problem it replaces

Accelerate emits assets under stable names, so a deployed file keeps its URL
when its bytes change. Every site therefore has to invent its own cache-busting
scheme. Accodeing's sites currently use three different ones depending on the
asset: CSS and first-party JS share one `version:` integer bumped by hand;
images and fonts each carry their own `?v=` at every reference; vendored JS
carries its version in the filename and takes no query string at all.

The three rules are each defensible in isolation, and together they are still
three things a human has to get right on every commit, with no feedback when
they get it wrong:

- **Nothing catches a missed bump.** Accodeing's nginx image serves everything
  under `/assets/` as `immutable` with a long max-age. `immutable` means
  conforming browsers skip revalidation *even on an explicit reload* — the
  `ETag` is never consulted, because the browser never asks. Only a hard reload
  clears it. So a missed bump is invisible to the developer who has devtools
  open, and sticks for everyone else.
- **Per-file versions are easy to under-apply.** A single image is often
  referenced from several templates, and `srcset` names each variant
  separately, so one replacement can mean four or five edits. Miss one and that
  reference serves the old bytes indefinitely.
- **The rules encode a payload tradeoff that hashing makes moot.** Images are
  versioned separately from CSS only because tying them to a shared version
  would re-download megabytes of unchanged images to fix a CSS typo. With
  content hashing there is no tradeoff: everything is invalidated exactly when
  its bytes change.

## What we want

Build-time content hashing, the way Gatsby and every JS bundler do it:
`main.css` becomes `main.9f8a3c1.css`, where the hash derives from the file's
bytes. Same content → same hash → same URL → the cached copy stays valid.
Changed content → new URL → guaranteed fetch. Invalidation becomes exact and
automatic:

- no version field, and nothing to remember at commit time
- every asset class covered — CSS, JS, images, fonts — not just the ones
  someone remembered to annotate
- precise: changing one image invalidates that one URL, not the whole site
- `immutable` becomes correct by construction rather than a loaded gun. Today
  the year-long cache is the thing that punishes a missed bump; with hashing it
  is simply true, because a given URL's bytes can never change

## Why this is cheap

It is worth separating this from the CSS bundling that Accodeing's template TODO
also wants. Bundling is blocked on both sides of the stack — the build
environment is deliberately minimal (no Node, no Rust, no CSS toolchain) and
`acc` has no CSS pipeline step. **None of that applies to hashing.**

Hashing never parses the file: read bytes, hash, write under a new name, rewrite
references. It is format-agnostic, so one implementation covers `.css`, `.js`,
`.webp` and `.woff2` identically. Nim's standard library already ships
`std/sha1`, so this adds no dependency on either side of the stack.

It also fits the architecture rather than fighting it. `acc --help` describes
Accelerate as a thin core that "doesn't come with a lot built in" and delegates
to plugins written against its DSL and Nimscript, and a site's `config.yaml` is
already a declarative list of steps (`@copy`, `@yaml`, `@markdown`,
`@mustache`). This is one more step, not a fork.

## Sketch

A new `@digest` step, placed after `@copy` (which puts assets in the output) and
before `@mustache` (which needs the final names):

```yaml
- name: '@digest'
  config:
    glob: 'assets/**/*.{css,js,webp,png,jpg,svg,woff2}'
    length: 8
    manifest: 'asset-manifest.json'
```

For each matching file it hashes the contents, renames the output to
`<stem>.<hash><ext>`, and records `original path → hashed path` in a manifest.
Templates then resolve names through a lookup instead of hardcoding them:

```html
<link rel="stylesheet" href="{{#asset}}/assets/css/main.css{{/asset}}" />
```

Mustache is logic-less, so a section lambda is the natural shape for the helper:
it receives the source path and returns the hashed one.

Implementation would sit alongside the existing steps in
`src/action/internal_functions/` — `copy.nim`, `markdown_renderer.nim`,
`mustache_renderer.nim` — as `digest.nim`.

## The hard part: rewriting references

Hashing is trivial; finding every reference is the actual design work. Four
categories, and the helper above only solves the first:

1. **Template markup** — `<link>`, `<script>`, `<img src>`, `srcset`.
2. **`url()` inside CSS** — stylesheets referencing fonts and images. Needs a
   rewrite pass over CSS text before those stylesheets are themselves hashed.
3. **Non-template static files** — `site.webmanifest` names every icon. These
   are `@copy`'d verbatim today and would need to pass through substitution.
4. **Content YAML** — any `content/*.yaml` field naming an image path.

**Ordering matters, and it is not obvious.** Hashing a font changes the CSS that
references it, which changes that stylesheet's own hash. So `@digest` has to
work in dependency order: hash the leaves (fonts, images) first, rewrite `url()`
in CSS, then hash the CSS, then render templates. A naive single pass yields
either stale references or hashes that churn on every build.

**Dev mode should opt out.** Under `acc dev`, hashed names are noise and churn
the rebuild. `@digest` should no-op in dev, with the helper falling through to
the original path, so templates behave identically in both modes.

## Adoption by existing sites

Backwards-compatible if the helper falls back to the original path whenever
there is no manifest entry, so sites can adopt it incrementally. Per site the
work is: add the `@digest` step to `config.yaml`, swap literal asset paths for
the helper, then delete whatever manual cache-busting the site was using.

## Open questions

- Hash length. Eight hex characters is the usual compromise; collisions are a
  non-issue at these file counts.
- Should the manifest ship in the build artifact, or stay a build-time
  intermediate?
- What should the web server do when an old hashed name is requested after a
  deploy — plain 404, or fall back to the current file?
- Does `@digest` own the `url()` rewrite in CSS, or should that be a separate
  step so a future bundler can reuse it?
