# Migration: the fleet onto acc 0.2.2

Moving the hosted sites off the pre-0.2 build image and onto the first
released 0.2. The decision is to **migrate the sites, not carry backward
compatibility** — the legacy spellings are converted at the source, acc's own
config is split out into `acc.yaml` while Heimr's fields stay in `config.yaml`,
and the compatibility shim in `file_router.nim` is left to die once nothing needs
it.

Site scope and build comparisons re-verified 2026-10-08, against the
released 0.2.2.

## On the version number

`0.2.2`, and it is worth knowing why it is not `0.2.0` or `0.2.1`.

Nothing in the 0.2 line had ever been released. The last release tag was
`v0.1.1`; `CHANGELOG.md` headed its top section `[0.2.0] - Unreleased`,
while `acc.nimble` had drifted to `0.2.1` — `b37382c` bumped it *"so local
installs need to distinguish patched from unpatched binaries"*, which is a
working-version bump, not a release.

The consequence is that binaries calling themselves `0.2.0` and `0.2.1`
already exist (`~/bin/acc-0.2.0`, `~/bin/acc-0.2.1`), and they are **not** what
was shipped — `page.path`, the router group-of-one fix and pitchfork 0.4.0
all landed after them. Reusing either number would have put two different
builds behind one version string. `0.2.2` is the first unburned number.

Done: `acc.nimble` reads `0.2.2`, the changelog section is
`[0.2.2] - 2026-10-08`, and `v0.2.2` is tagged on `main` — which was reset to
the 0.2 line first, so the release comes off `main` as it should.

## The flow, and the window it opens

1. **Fix all sites locally.** Every change below, verified against the
   pre-0.2 baseline. Do not deploy.
2. **Deploy the new build image.** Build a `build-accelerate` image carrying acc
   0.2.2 and bump `ACCELERATE_VERSION` in
   `static-sites-infrastructure/build-server/kubernetes/deployment.yaml:62` —
   currently pinned at `v1.4.0`, which is what the cluster runs today. No other
   platform change is needed; `build.sh` keeps reading `config.yaml` untouched
   (see breaking change 5).
3. **Rebuild the affected sites.**

The ordering matters, because choosing migration over backward compatibility
means the two spellings are mutually exclusive. A site respelled in step 1
renders **zero** product pages on the current image — verified, not assumed:
building hagges with `{.[slug]}` on `~/bin/acc` produces no product pages, no
error, exit 0. The reverse is equally true.

So between step 1 and step 2 there is a window in which the fixed sites must
not be built by the old image. Keep step 1 on a branch, or merged but not
deployed — whatever your deploy triggers allow. The risk is a content editor
triggering a rebuild mid-window and silently publishing a site with its
product pages missing.

If that window is unacceptable, the alternative is the fallback shim (see
"The road not taken"), which removes it entirely.

## Which sites are in scope

Cross-checked against the GKE cluster `accodeing-hosting`
(`europe-north1-a/primary`) with `kubectl get deploy -A | grep accelerate`, minus
`accelerate-content-sync`. **Thirteen deployed sites, and every one has a local
repo** in `~/static-sites` (a symlink to `~/workspace/accodeing/static-sites`) —
nothing is missing from the machine.

| site | prod | staging | dynamic templates | action |
|---|---|---|---|---|
| begravningstjansthabo.se | ✓ | ✓ | — | acc.yaml only |
| bjorkbackskyrkan.se | ✓ | ✓ | 2 | 2 renames |
| ecovs.se | ✓ | — | — | acc.yaml only |
| hagges.se | ✓ | ✓ | 3 | 2 renames + `$meta` block |
| harochco.se | ✓ | — | — | acc.yaml only |
| jobbonarspoolen.se | ✓ | ✓ | 1 | 1 rename |
| kustartilleri.se | ✓ | ✓ | 1 | 1 rename |
| liveaboard.yachts | ✓ | — | — | acc.yaml only |
| masaencasa.se | **—** | ✓ | 1 | 1 rename |
| smileofhope.se | ✓ | — | — | see special case |
| switsbake.se | ✓ | ✓ | 4 | 3 renames |
| theplanner.se | ✓ | ✓ | 1 | 1 rename |
| torbjornshusvagnar.se | ✓ | — | — | acc.yaml only |

Plus one cloned but not yet deployed:

| site | dynamic templates | action |
|---|---|---|
| bokbageriet.se | 1 | 1 rename — already on the new convention, see Verification |

`masaencasa.se` has **no production deployment**, only staging. Confirm that is
intended before treating it as live.

Not in scope: `accodeing.com` is `pipeline: jekyll`; `platform24.com` has no
config and is not an acc site. `switsbake.se.src` is gone.

## What changed, and what each site must do

### 1. Dynamic path segments use the new grammar — SILENT

`133ff3e` (Jonas, 2026-08-19) rewrote the router as parse-once-then-expand.
The old router re-scanned generated paths, so a resolved *value* containing
braces was re-read as template text — the source of *"the infinite recursion
and the silent drops"*. The rewrite also collapsed the `()`, `{}` and `[]`
matchers into one naming rule, and made scope explicit: *"literal directories
no longer traverse the context, a leading `.` resolves inside the enclosing
scope, and everything else resolves from the root."*

The grammar, from `src/types/render_state/path_template.nim`:

```
binding := "{" [ "." ] [ collection ] [ filter ] [ selector ] "}"

  .            resolve inside the enclosing scope; omitted means the root
  collection   dotted path to a collection
  filter       "(" attribute.path = $reference ")"
  selector     "[" attribute.path [ "[]" ] "]"; omitted names by key or index
```

Two conversions follow. **“Legacy-spelled”** throughout this document means a
filename still written the pre-0.2 way, in either of these forms:

| legacy | native | meaning |
|---|---|---|
| `{a.b}` | `{a[b]}` | group collection `a`, name each element by attribute `b` |
| `{b}` (not the first binding) | `{.[b]}` | iterate the enclosing group, name by attribute `b` |

The second is Jonas's own spec case **C19**, *"a dot with only a selector
iterates the enclosing group"*:

```
produkter/{products[types[]]}/{.[id]}.mustache
```

The first currently still works, but only through the legacy fallback in
`file_router.nim:353-357` (`d84ef45`). **Every dynamic template in the fleet
is running on that shim** — this is not limited to the two that break outright.
Migrating means respelling all of them.

Symptom when it is wrong: `Skipping '<template>': no collection '<x>' to
expand.` in the log, the pages absent from `public/`, and exit code 0.

#### Exact renames — 15 files across 8 sites

`git mv` each of these. Two are **directories**.

**bjorkbackskyrkan.se**
```
src/{pages.slug}.mustache            ->  src/{pages[slug]}.mustache
src/{uthyrning.slug}.mustache        ->  src/{uthyrning[slug]}.mustache
```

**bokbageriet.se**
```
src/{pages.slug}.mustache            ->  src/{pages[slug]}.mustache
```

**hagges.se**
```
src/{pages.slug}.mustache                        ->  src/{pages[slug]}.mustache
src/{products.categorySlug}/                     ->  src/{products[categorySlug]}/      (directory)
src/{products.categorySlug}/{slug}.mustache      ->  src/{products[categorySlug]}/{.[slug]}.mustache
```

**jobbonarspoolen.se**
```
src/{pages.slug}.mustache            ->  src/{pages[slug]}.mustache
```

**kustartilleri.se**
```
src/en/signs/{en.signs.number}.mustache  ->  src/en/signs/{en.signs[number]}.mustache
```

**masaencasa.se**
```
src/{pages.slug}.mustache            ->  src/{pages[slug]}.mustache
```

**switsbake.se**
```
src/{kontakt.slug}.mustache                                         ->  src/{kontakt[slug]}.mustache
src/sortiment/foodservice/{trademarks.id}.mustache                  ->  .../{trademarks[id]}.mustache
src/sortiment/foodservice/{products.trademark_id}/                  ->  .../{products[trademark_id]}/   (directory)
src/sortiment/foodservice/{products.trademark_id}/{article_id}.mustache
    ->  src/sortiment/foodservice/{products[trademark_id]}/{.[article_id]}.mustache
```

**theplanner.se**
```
src/fragor-och-svar/{qa.slug}.mustache  ->  src/fragor-och-svar/{qa[slug]}.mustache
```

`begravningstjansthabo.se`, `ecovs.se`, `harochco.se`, `liveaboard.yachts`,
`smileofhope.se` and `torbjornshusvagnar.se` have no dynamic templates and need
nothing here.

`jobbonarspoolen.se` and `switsbake.se` each *gained* a dynamic template between
2026-09-16 and 2026-10-07, and `bokbageriet.se` is new in that window — re-scan
with `find <site>/src -name '*{*'` before trusting this list.

### 2. `item` no longer binds a static page's content file — SILENT

Per `CHANGELOG.md` (0.2.2, "Reconciled with the legacy development line"):
dynamic segments choose what a page binds to, static segments only shape the
output path. So an all-literal template binds **the enclosing scope**, not the
matching content key.

| form | pre-0.2 | 0.2.x |
|---|---|---|
| `{{<page>.title}}` | works | works |
| `{{item.title}}` | works | **empty** |
| `{{item.<page>.title}}` | **empty** | works |

`{{<page>.title}}` is the only form that works on both. Dynamic templates are
unaffected — `item` is still the element there, which is the documented
contract.

Measured across the fleet, this bites in exactly one place: **hagges.se**,
where `src/partials/head.mustache` reads `{{#item.meta}}` and `index.mustache`
is static, so `index.html` lost all nine `og:`/`twitter:` tags.

`theplanner.se` has six `item.` hits but all of them are inside its dynamic
`{qa[slug]}.mustache`, where the contract is unchanged — verified clean.
`smileofhope.se` has seven in static templates, but see the special case below.

The partial is shared with the dynamic `{pages[slug]}.mustache`, where `item`
is correct, so it cannot simply name the content file. Fix already applied and
verified on both binaries — give `head` a `{{$meta}}` block defaulting to
`{{#item.meta}}`, and override it from `index.mustache` with
`{{#index.meta}}`. The site already used that pattern for
`{{< partials/header}}`.

### 3. An empty value is falsy to a Mustache section — no site action

pitchfork 0.3.0. Pre-0.2 acc rendered with nim-mustache, where `""`, `0` and
an empty list or object are falsy. The tine had inherited Liquid's rule (only
nil and false falsy), so every `{{#field}}` guarding an optional field
rendered its body empty.

This only ever *removed* empty markup: an empty alert banner on
kustartilleri.se, empty `markdown-from-cms` wrappers on hagges.se, and on
bjorkbackskyrkan.se an `<a href="tel:+46"></a>` with no number — a broken link
no build error mentions. Nothing to do per site; it is why
`kustartilleri.se`'s literal `alert: ''` needs no edit.

### 4. Apostrophes are HTML-escaped — no site action

`'` renders as `&#39;`. pitchfork's escape set came from the Liquid VM;
nim-mustache escaped exactly `& " < >`, which is also all the spec's escaping
test covers, so neither is wrong. Renders identically.

Four kustartilleri.se pages differ by nothing else — un-escaping `&#39;` on
the new side gives a zero-line diff. The only cost is that a diff-based deploy
re-uploads those four once.

### 5. acc's config moves to `acc.yaml`; Heimr's stays in `config.yaml`

0.2 defaults to `acc.yaml`; every site has `config.yaml`. With no `-c`, the
build "succeeds" having rendered nothing:

```
[WARN]: No workflows defined in config
```

It is not the legacy converter failing — `convertLegacyConfig` handles the old
`build:` list fine once the file is read. The file is simply never found.

**Decided: split the file rather than rename it.** The two consumers already have
disjoint fields, and `accelerate-conventions.md` / `heimr-conventions.md` already
describe them as separate concerns. Give each consumer its own file:

| file | keys | read by |
|---|---|---|
| `acc.yaml` | `build:`, `content_root` (and `manifest_version`, `directories`, `workflows` once a site adopts the modern format) | acc |
| `config.yaml` | `name`, `pipeline`, `domains`, `base_image`, `type`, `dummy_counter`, `forceRebuild` | Heimr (the build server) |

**The platform needs no change at all.** `config.yaml` keeps the three fields
`heimr-conventions.md` documents — `name`, `pipeline`, `domains` — exactly where
Heimr already looks. That removes the cross-repo coupling a straight rename would
have forced, and with it the risk of the platform losing track of every site at
once.

This is safe because of what acc actually reads. `loadConfig`
(`src/config/io.nim:100-134`) consumes only `manifest_version`, `directories`,
`workflows`, and for legacy configs `build:` and `content_root`. Everything else
lands in `genericConfig`, which is used solely for `${...}` interpolation inside
the config itself and for `--show-me config`; it never reaches the template
context. **No site config in the fleet uses `${...}` at all**, so nothing
interpolates a Heimr field into a build step. Verified by grep across all
thirteen.

Verified by build: all thirteen sites produce the same output split as they do
with a wholesale rename — zero `Skipping`, zero `No workflows defined in config`.

Note the cliff this creates in the other direction: the pre-0.2 binary reads
`build:` from `config.yaml`, so once it has moved to `acc.yaml` the old image has
no pipeline to run. Same window as the grammar renames, no worse.

Still to do, so new sites scaffold right: split
`heimr/accelerate-template/config.yaml` the same way, and update the references in
`accelerate-conventions.md` (lines 21, 59, 61, 197, 656) and `README.md` (line 14)
to point the pipeline at `acc.yaml`, while leaving `heimr-conventions.md`
describing `config.yaml`. `rewrites.conf` is documented as a "sibling of
`config.yaml`" — still true. `heimr/jackelyn` already emits `acc.yaml`
(`src/jackelyn/core/output.nim:503-508`).

**Confirmed against the build server**
(`accodeing/static-sites-infrastructure/build-server/build.sh`). It is the only
thing reading `config.yaml`, and it never looks at `build:`:

- `113-115` — requires `config.yaml` **or** `config.json` in the repo root, and
  fails the build if neither exists. Presence only; contents unchecked.
- `119-121` — `yq eval` on `.pipeline` and `.name`.
- `126-128` — fails if `name` is missing or `null` (`yq` prints `"null"` and
  exits 0 for a missing key, so an incomplete config would otherwise deploy
  something like `static-null` and report success).
- `131-134` — on production only, fails if `.domains` is missing or `null`.
- `151` — `yq eval` on `.base_image`, used at `212` to pick the h2o Dockerfile
  over the nginx one. No site in the fleet sets it.
- `176-195` — `.pipeline` selects the build container; `accelerate` resolves to
  `build-accelerate:$ACCELERATE_VERSION`.
- `199-203` — runs that container with the repo mounted at `/repo`. **The
  pipeline itself is read inside the container, by `acc`** — the build server
  never parses it.

So the split needs **zero build-server changes**: `config.yaml` keeps `name`,
`pipeline`, `domains` and `base_image`, every check still passes, and `build:`
moves to a file only `acc` reads.

Two small follow-ups it does imply:

- `templates/dockerignore.tmpl` excludes `**/config.yaml`, `**/config.json` and
  `**/config.yml` from the serving image. Add `**/acc.yaml` for symmetry. It is
  belt-and-braces — the context is `/temp`, where `repo/` is already excluded
  wholesale — so this is tidiness, not a leak.
- `build-server/CLAUDE.md:73` documents step 2 as reading `pipeline`, `name`,
  `domains`, `base_image` from `config.yaml`. Still accurate after the split;
  worth a sentence noting the pipeline now lives in `acc.yaml`.

Two oddities found while splitting, neither blocking:

- `bjorkbackskyrkan.se/config.yaml` has `dummy_conuter` — a typo for
  `dummy_counter`. If Heimr reads that key to trigger rebuilds, it has never
  worked on that site.
- `kustartilleri.se` carries `forceRebuild`, which no other site has. Heimr-side;
  stays in `config.yaml`.

## Verification

Re-verified **2026-10-08** against the released 0.2.2. Every site built
twice — the pre-0.2 binary (now `~/bin/acc-0.1.1`) with its
current `config.yaml` (what production serves today) against the 0.2.2 candidate
with all renames and the config split, no `-c` — each into its own tree, with no
site working copy written to. Compared whitespace-normalised, since 0.2 indents
differently around block sections.

| site | pre-0.2 | 0.2.2 migrated | same | real diffs |
|---|---|---|---|---|
| begravningstjansthabo.se | 27 | 27 | 27 | 0 |
| bjorkbackskyrkan.se | 41 | 41 | 41 | 0 |
| bokbageriet.se | 8 | 8 | 4 | 4 — expected, see below |
| ecovs.se | 11 | 11 | 11 | 0 |
| hagges.se | 24 | 24 | 24 | 0 |
| harochco.se | 4 | 4 | 4 | 0 |
| jobbonarspoolen.se | 19 | 19 | 19 | 0 |
| kustartilleri.se | 270 | 270 | 266 | 4 — apostrophes only |
| liveaboard.yachts | 2 | 2 | 2 | 0 |
| masaencasa.se | 13 | 13 | 13 | 0 |
| switsbake.se | 125 | 125 | 125 | 0 |
| theplanner.se | 26 | 26 | 26 | 0 |
| torbjornshusvagnar.se | 6 | 6 | 6 | 0 |

**Zero `Skipping` warnings on any site.** No stray `accelerate.json` in any
build, including `--version` — breaking change 4 of the fleet-verification
handover looks fixed by `49c3fde`; confirm and drop that note.

Page counts drift as content syncs: kustartilleri went 253 → 270 and masaencasa
8 → 13 between runs three weeks apart, and jobbonarspoolen and switsbake each
*gained* a dynamic template in that time. **Re-run this comparison immediately
before committing the renames** — do not trust the table once it is more than a
few days old.

Re-run per site with:

```
rsync -a --exclude .git --exclude public --exclude .acc <site>/ /tmp/m/<site>/
cd /tmp/m/<site> && mv config.yaml acc.yaml && acc build .

# the pre-0.2 baseline, for comparison, still reads config.yaml:
~/bin/acc-0.1.1 build .
```

### bokbageriet.se is already on the new convention

Its four differences are `page.path` working, not a regression. Its
`src/partials/head.mustache` already carries the `b4be3ac` template default:

```mustache
<link rel="canonical" href="{{$url}}{{general.url}}{{page.path}}{{/url}}" />
<meta property="og:url" content="{{$url}}{{general.url}}{{page.path}}{{/url}}" />
```

On the old image `{{page.path}}` renders empty, so every page claims the site
root as canonical — precisely the bug `page.path` exists to remove. On 0.2.2
`om-oss.html` correctly says `https://bokbageriet.se/om-oss`.

It is the only site on the new convention so far, which makes it the working
reference for the per-site rollout. Two notes: the root canonical becomes
`https://bokbageriet.se/` with a trailing slash (`page.path` is `/` for
`index.html`), and `partials/head.html` is being rendered as a page — a missing
`partial_directories` exclusion, pre-existing on both binaries.

### Special case: smileofhope.se

Its `config.yaml` has **no `build:` section** — only `name`, `pipeline`,
`type`, `domains`. Neither binary builds it: pre-0.2 finishes in 0.00s having
done nothing, 0.2 warns `No workflows defined in config`. Its `public/` is
committed to the repo (30 files) and served as-is, and the last commit is from
2023-12-14.

**So it is unaffected by this migration** — acc does nothing for it today and
will do nothing after. Under the split it needs **nothing** — it has no `build:`
to move, and its Heimr fields stay where they are. Separately it needs a
decision: either give it a pipeline or stop declaring `pipeline: accelerate`. It also still carries
`set-css-version.sh`, an old-template marker.

Probed with a standard `build:` section grafted on, it builds 9 pages on both
binaries with one real difference — `index.html` loses its `<h1>` and ingress,
which is breaking change 2 again (`{{item.name}}`,
`{{item.sections.ingress.*}}` in a static `index.mustache`, plus
`{{#item.meta.names}}` in `partials/head.mustache`). Whoever revives the site
should convert those first.

### Caveat: .html templates

`liveaboard.yachts` renders `src/*.html` through `@mustache` with
`glob: "**/*.html"`. That works — the step glob decides what is rendered. But
acc's partial loader in `src/plugins/mustache_engine.nim` collects only files
ending `.mustache`, so a `.html`-template site that *used* partials would not
find them. liveaboard.yachts has none, so it is clean; flagged in case another
site adopts the pattern.

## Engine changes this release depends on

All three have landed.

- **pitchfork v0.4.0** — `acc.nimble` requires it as of `b9a3752`; v0.3.1 as of
  `ce3c4b5`. Carries the Mustache section truthiness change, the
  `mustache#block` split that keeps an override rendering to nothing from
  falling back to its block default, and the nested same-named loop fix (an
  inner `{% for item in b %}` inside `{% for item in a %}` hung and grew the
  output without bound). acc never depended on v0.3.0 in a commit.
- **`file_router.nim` group-of-one fix** — `b54cfeb`. A scoped selector over a
  grouped collection only expanded when the group held two or more members, so a
  category with one product silently lost its page and routing depended on how
  many rows shared a grouping value. Restores
  `hagges-klassiker/mazarin.html` and `tartbotten/hagges-tartan.html`. Needed
  regardless of this migration.
- **`page.path`** — `a5f1856`. A page's own URL in the template context. Not
  required by this migration, but it is what `bokbageriet.se` already uses and
  what the per-site canonical rollout below depends on.
- **Build manifest completeness** — `@copy` recorded nothing in
  `rendered_outputs`, so `manifest.json` listed rendered pages and none of the
  copied assets. Fixed, and worth knowing about because of what it implies for
  the deploy: **nothing reads the manifest today**. `build.sh` builds the
  serving image with `COPY artifacts /public`
  (`build-server/templates/Dockerfile.nginx:2`), shipping the whole output
  directory every time. So this migration transfers complete sites regardless,
  and the manifest only matters if a delta deploy is built on it later — at
  which point it is now correct.

## After the image lands

Once every site is on the native grammar and `legacyPaths` has no users:

1. Delete the legacy fallback in `file_router.nim:348-357` and its cases in
   `test/legacy_config.nim`.
2. Then the `page.path` downstream work in the sites. **The canonical template
   side is already done** — `b4be3ac` defaults `$url` to `{{general.url}}{{page.path}}`
   in `heimr/accelerate-template`, and `8dea917` / `d681948` carry the
   convention docs. Do not redo it.

   What remains is per-site, because each site repo has its own copy of
   `head.mustache`: add `{{page.path}}` to both `$url` defaults, delete the
   `$url` override from every page, and drop the `slug:` fields that existed
   only to feed it. The procedure, with detector greps and the
   `general.url`-trailing-slash trap, is
   `claude-skills/upgrade-accelerate-site/references/upgrades/canonical-from-page-path.md`;
   it gates itself on the build image being newer than 0.2.1, so it is safe to
   reach for before this release only to read.

   `slug` keeps its routing job in `{pages[slug]}.mustache` — only the
   canonical-feeding use goes away.

## Rollback

Step 2 is reversible — pin the image back — but only for sites not yet
respelled. A site that has completed step 1 cannot build on the old image, so
rolling back means reverting that site's commit too — both the grammar renames
and the config split. Keep each site's changes as **one commit per site** so
`git revert` is a single operation. Nothing platform-side has to roll back, since
`config.yaml` never stopped carrying Heimr's fields.

## The road not taken

Widening the legacy fallback at `file_router.nim:353` to cover the bare
single-atom case would have made the current spellings work on both binaries —
about a dozen lines, gated on `legacyPaths`, firing only when the lookup
already failed. That removes the step 1 → step 2 window entirely, at the cost
of carrying two spellings until the sites are converted anyway.

Rejected in favour of converting the sites now. Recorded here because it is
the fallback if the window turns out to be a problem in practice.
