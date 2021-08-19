# Plugins

## Debug
If your script contains an error Accelerate will try to print a useful error
message, with line info. The line info from the compiler gives you the first
location where the compiler could not continue. In some cases, such as writing
`proc something()` without giving an implementation, and depending on what comes
after, the compiler will not give the "correct" line info.

The actual error might be above the given line, since the compiler managed to
parse a bit further before it ran into something unexpected. This also means
that the error might seem to be something that it is not.

So the line info is a rough guide, sometimes it will be correct and sometimes it
will be a few lines after the actual line. Use it and the message about the
error to find the actual problem with your code.

### Output

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

## Callbacks
You can define a range of functions in your script that will get called by the
main program. This is useful to get access to some often used functionality
without having to implement it yourself. For example processing of certain files
in the project.

Available callbacks:
* `for_each_file( path: string )``

### `for_each_file( path: string )`

Runs once for each file that matches the `glob` pattern. The walk starts at the
root of the `build folder`, as given when you ran Accelerate. Each path is
relative to the `build folder` when checked against the pattern. So a match test
could look like this: `"src/foo.html" matches "**/*"`, with the default pattern.

#### Configuration
`glob`: string - POSIX glob pattern to filer which files are returned by `acc`.
Defaults to `**/*`, all files recursively.
`yield_absolute`: boolean - Determines if paths are yielded as relative or
absolute. Defaults to `true`.
`match_relative`: boolean - Determines if paths are matched as relative or
absolute. Defaults to `true`.
