template with_label(default_label: string, parts: varargs[string], body: untyped) =
  var
    message {.inject.} = parts.join( "" )
    label {.inject.} = default_label

  let
    contains_label = parts.len > 0 and parts[0].startsWith("[") and parts[0].endsWith("]")

  if contains_label:
    label = parts[0]
    message = parts[1..^1].join( "" )

  block:
    body

template notice*( parts: varargs[string, `$`] ) =
  if log_level <= lvlNotice:
    with_label(" [INFO]", parts):
      colored_printline( BLUE, label, message);

template info*( parts: varargs[string, `$`] ) =
  if log_level <= lvlInfo:
    with_label("    [i]", parts):
      colored_printline( BLUE, label, message);

template warn*( parts: varargs[string, `$`] ) =
  if log_level <= lvlWarn:
    with_label(" [WARN]", parts):
      colored_printline( ORANGE, label, message);

template error*( parts: varargs[string, `$`] ) =
  if log_level <= lvlError:
    with_label("[ERROR]", parts):
      colored_printline( RED, label, message);

template fatal*(parts: varargs[string, `$`]) =
  if log_level <= lvlFatal:
    with_label("[FATAL]", parts):
      colored_printline(DARK_RED, label, message)

template debug*( parts: varargs[string, `$`] ) =
  if log_level <= lvlDebug:
    let (filename, line, column) = instantiation_info(full_paths = true)
    let index = filename.rfind("/src/")
    let path = filename[index .. ^1]
    let context = get_parsing_context()
    let context_string = " in context \"$#\" from $#($#,$#)\n"

    colored_printline(
      GREEN,
      "[DEBUG]",
      parts.join( "" ),
      context_string % [context,path,$line,$column]
    )
