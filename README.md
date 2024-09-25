# Accelerate - static site generator

## Why?

What makes Accelerate different from other static site generators? Well,
it actually _is_ a static site generator!

If you think about the other static site generators that you have heard of
or used, like Jekyll, Gatsby, Next.js etc, are they really static site
generators? Or are they more like static site frameworks?

We tried several of them to manage our customers many sites but always got
into the same problems: maintainability and flexibility.

### Maintainability

If your site is built _in_ a static site framework and you have to keep it
updated that means updating the framework as well. Anyone that has spent
any time in the Node ecosystem will know that semver is more a loose
suggestion to many package maintainers and that your stack might break during
what should be a safe update.

There is also the bigger question of what you do with your 200 sites when a new
version comes out ... Update them all right then -
possibly weeks of unpaid work - or wait until you touch the site next time -
possibly years from now and likely days of work to get it up to date.

We figured there must be a better way.

### Flexibility

To minimize overhead when switching between customer projects you ideally want
the boilerplate between sites to be identical. But what do you do when a
customer needs something that is outside of the normal boilerplate?

We have normally solved it in one of two ways - depending on how likely it is
that the change will be relevant for other customers - add the new dependency to
the boilerplate and increase complexity and maintenance work forever, or add it
as a special dependency to that specific site and diverge that site from the
norm, increasing FTWs per hour and contextual load forever ...

(Sometimes we have also hacked "clever" solutions using the limited logic in the
template language, but let us not talk about that here ...)

## How

With Acc we are trying to take another approach to our sites entirely. Instead
of relying on complex dependancies and logic _in_ the site repo itself, we want
to keep the site repo as clean as possible while allowing for all the
flexibility when building each site.

So Acc is a build pipeline. It reads a raw HTML, CSS and JS repo + a build
pipeline config. Each step in the pipeline has access to the result of the
processing so far and can add/change whatever part of the state it wants to.

### Scripts

The pipeline consists of a number of Nimscript scripts that are called in
sequence. Each of these have access to the shared state and can pull from it or
push to it as well as execute external commands.

### Sources

The script based plugin system means that you can pull from basically anything.
All you need is a small Nimscript plugin that interfaces Acc with whatever you
want to use as a source.

You can pull from an external API with curl, a database locally or through an
SSH tunnel from a server, local files or anything else that you can get access
to.

The nice thing with the shared state and small script wrappers is that it makes
it really easy to integrate whatever tools you like the best into the build. No
fixed dependencies or complicated configurations where it is unclear what
actually happens and in what order.

The wrappers are small and easy to understand and the rest is up to you!

### Processing

Like with sources the processing is up to you. If you like React and JSX you can
build your site in that, leave templated sections in the code, pull in the info
from external sources at build time and finish by calling `yarn build` on the
original React project.

### Maintenance

One of the biggest problems we wanted to solve was maintenance. If you only run
one or a couple of sites in something like Gatsby this is not much of a problem.
But if you manage hundreds of sites for clients and like to get paid for your
time it is.

With the external build pipeline approach we only have to keep the core API
stable, or backwards compatible using a config version string, to be able to run
a new build - with a new version of the core - on every site no matter how old.

Plugins can easily be added or changed over time. Think about things like
rendering social media tags from the site config for example. Today you might
have plugins to render for Facebook and Twitter, but in a year there might be a
new site that everyone needs to support... Simply add a new section to your
global config for the new sites plugin and rebuild all the sites and presto!
New social media links on all sites for the price of updating in one place...

### Flexibility

With a global and per site config you regain the flexibility to do global
changes, like above, while keeping it easy for one site to override the globals
in its config for some purpose.

You can also keep all the tools in only two places: the build image for all the
global plugins and in the repo for any specialized ones.

The nature of the setup even allows your sites to pull external resources during
build if they need some specialized executable for example. At your own risk of
cause, but at least there is an easy escape hatch for the places where you need
one.

## Installation

### MacOS

1. Place the binary in your path, for instance in `~/bin`.
2. Install fswatch. If you are using brew: `brew install fswatch`
3. Install pcre. With brew: `brew install pcre`

If Accelerate can't find fswatch (`could not load: libfswatch.dylib`),
start by verifying that fswatch is actually installed, then find the path
to the library, for instance by using `brew info fswatch`. Then set that path as following to your `.zshrc`
or similar (where `/usr/local/lib` is the actual path to the library):
```sh
export DYLD_LIBRARY_PATH="/usr/local/lib"
```

## Development

Clone then run using `nimble -d:debug -d:nimDebugDlOpen -p:src --threads:on
 --mm:orc --deepcopy:on run acc dev ../test_site`

The `acc run -d ../test_site ../test_site/plugins/test.nims` part of the command
is the binary to build/run and the arguments to it.

## Production build

`nimble build -d:release -p:src --threads:on --mm:orc --deepcopy:on`

# Attribution

[Original logo vector created by 3ab2ou at freepik.com](https://www.freepik.com/vectors/logo)
