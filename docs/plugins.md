# Plugins

# Callbacks
You can define a range of functions in your script that will get called by the
main program. This is useful to get access to some often used functionality
without having to implement it yourself. For example processing of certain files
in the project.

Available callbacks:
* `for_each_file( path: string )``

## Configuring
Plugins can use the general config values from `config.yaml`, if they do it
should be stated in the documentation for the plugin. They can also take
configuration from the `shared context`.

Using `for_each_file` as an example. If you use it as is it will get called for
every file in the `build folder`, recursively. Sometimes that might be what you
need, but more likely you are trying to process some kind of file, not all kinds
of files. To avoid having each plugin author write logic to select only the
types of files they need `for_each_file` can be configured with a POSIX glob
pattern, and will only get called for files that match the glob pattern.

The `shared context` configuration for callbacks are always under
`context.proc.[callback_name].*`. For example: configuration values for
`for_each_file` can be set under `context.proc.for_each_file`, like
`context.proc.for_each_file.glob` for the `glob` setting.

## `for_each_file( path: string )`
#### Configuration
`glob`: POSIX glob pattern to filer which files are returned by `acc`. Defaults
to `*`, all files.
