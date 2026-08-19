# SSG Editor Architecture

## Overview

The editor is a visual editing layer for static sites built by our SSG. It operates as an
overlay on the actual rendered site, providing true WYSIWYG editing — the page being edited
is the real SSG output, not a parallel rendering. The editor consists of three parts: a
client-side JavaScript library loaded in edit mode, an API module that mediates between the
editor and the filesystem, and a component library that defines both the editable properties
and the rendering templates for each component type.

The architecture maintains a strict separation from the SSG build pipeline. The SSG knows
nothing about the editor — it consumes Liquid templates, CSS files, and YAML/JSON content,
and produces static HTML. The editor manipulates those source files through the API module,
and the SSG's live reload rebuilds the page.


## Core Principles

**Git as source of truth.** All content, templates, and assets live in the repository. The
editor modifies files on disk, which are then committed through normal git workflows. There
is no database, no CMS backend, no content API at runtime.

**One rendering path.** The page displayed during editing is rendered by the SSG through the
normal Liquid template pipeline. The editor never renders page content itself. This
eliminates visual drift between edit mode and the published site.

**Components are versioned, not upgraded.** Each component version is a discrete set of files
(template + CSS) in the repository. Adding a new version of a component does not affect
existing pages. Migration is explicit and per-page, avoiding cascading breakage across the
site.

**The editor is optional.** Removing the editor, the API module, and all React component
sources from the repository should have zero effect on the site build. The SSG only depends
on the extracted artifacts (Liquid partials and CSS files).


## Content Model

Pages are defined by a YAML or JSON content file that references a template and declares an
ordered list of components:

```yaml
title: About Us
template: default
components:
  - type: hero
    data:
      heading: "Welcome"
      subheading: "We make things"
      image: /images/hero.jpg
      cta_text: "Learn More"
      cta_url: /about
  - type: image-carousel
    data:
      images:
        - src: /images/photo1.jpg
          alt: "Workshop"
        - src: /images/photo2.jpg
          alt: "Product"
  - type: text-block
    data:
      body: "Our story begins..."
```

The page template renders structural elements (header, footer, navigation) directly, and
delegates the content area to a data-driven component loop:

```liquid
{% include "partials/header" %}

{% for component in page.components %}
  {% assign partial_name = "components/" | append: component.type %}
  {% include partial_name with component.data %}
{% endfor %}

{% include "partials/footer" %}
```

This uses `include` rather than `render` because the reference Liquid implementation supports
variable template names with `include` but not with `render`. The `render` tag's restrictions
(static template names, isolated variable scope) were introduced for Shopify's multi-tenant
platform concerns and provide no benefit in an SSG context.


## Component Structure

### Repository Layout

```
site/
  content/
    pages/
      about.yaml
      index.yaml
  templates/
    default.liquid
    blog-post.liquid
  components/
    hero/
      hero.liquid
      hero.css
    hero-v2/
      hero-v2.liquid
      hero-v2.css
    image-carousel/
      image-carousel.liquid
      image-carousel.css
    text-block/
      text-block.liquid
      text-block.css
  editor/
    components/
      Hero.jsx
      HeroV2.jsx
      ImageCarousel.jsx
      TextBlock.jsx
```

The `components/` directory contains the artifacts the SSG consumes. The `editor/components/`
directory contains the React component sources used by the editor. These directories are
peers — the editor sources are the authoring format, the component directory holds the
extracted build artifacts.

### Component Source Format

Each component is defined as a single React file that contains the Liquid template, CSS, a
schema definition, and the editor UI:

```jsx
// editor/components/Hero.jsx
import { css } from '@linaria/core';

export const schema = {
  type: 'hero',
  name: 'Hero Banner',
  fields: [
    { key: 'heading',    type: 'text',  label: 'Heading' },
    { key: 'subheading', type: 'text',  label: 'Subheading' },
    { key: 'image',      type: 'image', label: 'Background Image' },
    { key: 'cta_text',   type: 'text',  label: 'Button Text' },
    { key: 'cta_url',    type: 'url',   label: 'Button URL' },
  ],
};

export const template = `
<div class="hero">
  <img class="hero__image" src="{{ data.image }}" alt="">
  <div class="hero__content">
    <h1>{{ data.heading }}</h1>
    <p>{{ data.subheading }}</p>
    {% if data.cta_url %}
      <a href="{{ data.cta_url }}" class="btn">{{ data.cta_text }}</a>
    {% endif %}
  </div>
</div>
`;

export const styles = css`
  .hero {
    position: relative;
    min-height: 60vh;
    display: flex;
    align-items: center;
  }
  .hero__image {
    object-fit: cover;
    width: 100%;
    height: 100%;
    position: absolute;
  }
  .hero__content {
    position: relative;
    z-index: 1;
    padding: 2rem;
  }
`;

export default function HeroEditor({ data, onChange }) {
  return (
    <>
      <TextField
        label="Heading"
        value={data.heading}
        onChange={(v) => onChange({ ...data, heading: v })}
      />
      <TextField
        label="Subheading"
        value={data.subheading}
        onChange={(v) => onChange({ ...data, subheading: v })}
      />
      <ImageField
        label="Background Image"
        value={data.image}
        onChange={(v) => onChange({ ...data, image: v })}
      />
      <TextField
        label="Button Text"
        value={data.cta_text}
        onChange={(v) => onChange({ ...data, cta_text: v })}
      />
      <UrlField
        label="Button URL"
        value={data.cta_url}
        onChange={(v) => onChange({ ...data, cta_url: v })}
      />
    </>
  );
}
```

The schema serves multiple purposes: it drives the editor UI field generation, provides
content validation for the SSG at build time, and documents the data contract between the
content file and the template.

The editor component (default export) is a pure property editor rendered in a side panel. It
does not render page content or attempt to mirror the template's markup. Its only job is to
present form controls for modifying the component's data fields and to call `onChange` with
updated values.

### Component Versioning

Components are versioned by convention through naming. A page references `type: hero` or
`type: hero-v2`, and the template loop resolves this to `components/hero/hero.liquid` or
`components/hero-v2/hero-v2.liquid`. There is no automatic migration — updating a page to
use a new component version is an explicit change to that page's content file, including any
necessary data restructuring.

This means a site can have pages using different versions of the same component
simultaneously, and a five-year-old page will still build and render correctly without
modification.


## API Module

The API module is an HTTP service that runs alongside the SSG dev server during editing
sessions. It provides the bridge between the editor's client-side JavaScript and the
filesystem. It is not part of the SSG, is not involved in the build pipeline, and is not
deployed to production.

### Responsibilities

**Content operations.** Reading and writing page content files (YAML/JSON). When the editor
modifies a component's data, the API module updates the corresponding content file on disk.
The SSG's file watcher detects the change and triggers a rebuild.

**Structural operations.** Adding, removing, and reordering components in a page's content
file. When a new component is added, the API module inserts a new entry in the page's
`components` array with default values derived from the component schema.

**Component extraction.** When a component type is added to a page for the first time, the
API module checks whether the corresponding Liquid partial and CSS file exist in the
`components/` directory. If not, it extracts them from the React component source and writes
them to disk. This is the only point at which the editor touches the SSG's input files in a
generative capacity.

**Context awareness.** The SSG dev server knows which template and content source correspond
to the currently viewed page. The API module receives this context and uses it to determine
which content file to modify and which component slots are available for editing.

**Asset handling.** When images or other assets are added through the editor (for example,
through an image picker field), the API module writes them to the appropriate assets
directory in the repository.

### Endpoints

```
GET  /api/page/:path
     Returns the parsed content file for the given page, including
     the component list and all data.

PUT  /api/page/:path
     Writes an updated content file. Used for bulk updates and
     reordering.

PUT  /api/page/:path/components/:index
     Updates the data for a specific component by its position in
     the component list.

POST /api/page/:path/components
     Adds a new component to the page. Accepts a component type
     and optional initial data. Returns the updated component list.

DELETE /api/page/:path/components/:index
       Removes a component from the page by its position.

POST /api/page/:path/components/reorder
     Accepts a new ordering of component indices and rewrites the
     component list accordingly.

GET  /api/components
     Returns the list of available component types with their
     schemas, read from the editor component sources. This drives
     the component palette in the editor.

POST /api/components/:type/extract
     Forces re-extraction of the Liquid template and CSS from the
     React component source into the components directory. Used
     when the component source has been updated.

POST /api/assets/upload
     Handles file uploads for images and other media. Writes the
     file to the assets directory and returns its path for use in
     content data.
```

### Extraction Process

When the API module needs to extract artifacts from a React component source:

1. Parse the JSX file and evaluate the `template` and `styles` exports.
2. Write the template string to `components/{type}/{type}.liquid`, stripping any
   surrounding whitespace.
3. Process the Linaria CSS through its extraction pipeline and write the result to
   `components/{type}/{type}.css`.
4. The SSG's file watcher picks up the new files. The CSS is included in the global
   stylesheet if the component is used on the current page. The Liquid partial is now
   available for the template loop.

Extraction is triggered lazily on first use and can be forced through the API for updates.
There is no automatic re-extraction when the source changes — updating extracted artifacts
is a deliberate manual action to preserve the principle that existing pages are never
affected by component source changes.


## Editor Client

The editor client is a JavaScript application loaded on the page in edit mode only. It is
not part of the SSG output and adds no weight to the production site.

### Loading

The SSG dev server injects a script tag when running in edit mode:

```html
<script src="/editor/editor.js" type="module"></script>
```

This script bootstraps the editor application, which renders a toolbar and side panel
outside the page's DOM (using a shadow DOM or a separate root element to avoid style
conflicts).

### Interaction Model

The editor operates in two layers:

**Page overlay.** The rendered page is displayed normally. The editor adds hover outlines and
click targets over component boundaries on the page. Clicking a component selects it and
opens its property editor in the side panel. Components are identified on the page through
data attributes added by the SSG during dev builds:

```html
<div data-component-type="hero" data-component-index="0">
  <!-- rendered component output -->
</div>
```

**Side panel.** When a component is selected, the editor loads the corresponding React editor
component and renders it in the side panel with the component's current data. Changes to
fields trigger API calls that update the content file, which triggers an SSG rebuild and
page reload.

### Component Palette

The side panel also provides a component palette for adding new components to the page. The
palette is populated from the `/api/components` endpoint, which reads the available component
schemas. Dragging or clicking a component from the palette inserts it at the selected
position in the page.


## Data Flow

A complete editing interaction follows this path:

```
User changes a field in the side panel
  → Editor calls PUT /api/page/:path/components/:index
    → API module reads the page content file
    → API module updates the component data
    → API module writes the content file to disk
      → SSG file watcher detects the change
      → SSG rebuilds the page
      → Browser receives the updated page via live reload
        → Editor re-selects the component and restores panel state
```

Adding a new component:

```
User drags a component from the palette
  → Editor calls POST /api/page/:path/components
    → API module reads the component schema for default values
    → API module checks if template/CSS artifacts exist
      → If not, extracts them from the React component source
    → API module appends the component to the content file
    → API module writes the content file to disk
      → SSG rebuilds, browser reloads
```


## Future: Customer-Facing Editor

The architecture is designed to transition from a development tool to a customer-facing
content editor with minimal changes:

**What stays the same.** The component format, the rendering pipeline, the side panel editor
UI, the data flow model, and the WYSIWYG principle of editing the real rendered page.

**What changes.** The API module's write target moves from the local filesystem to a git
backend (committing to a branch, creating pull requests, or writing to a headless git
service). Asset uploads move to cloud storage. Authentication and permissions are added
around the API endpoints. The component palette may be curated per-customer rather than
exposing all available components.

The editor client itself requires no changes — it communicates through the same API
endpoints regardless of what backs them. This is the primary architectural benefit of
keeping the API module as the sole interface between the editor and the content storage.
