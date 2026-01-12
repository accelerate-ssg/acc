# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Static templates now correctly populate `item` from matching context key. For example, `about.mustache` will have `item` set to the value of `about` in the context, allowing `{{item.name}}` to work as expected. This restores behavior that was broken in 0.1.0.
