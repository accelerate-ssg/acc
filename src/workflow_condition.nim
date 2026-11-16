## A workflow's `if:` is evaluated here rather than by the shell, so it
## means the same on Windows, where there is no `test`. The syntax is the
## part of `test` a condition needs: `$VAR` and `${VAR}` expand from the
## environment, except inside single quotes. Any other expansion is refused,
## since taken literally it would quietly change what the condition means.

import std/[os, strutils]

proc condition_tokens(condition: string): seq[string] =
  var
    token = ""
    in_token = false
    quote = '\0'
    i = 0

  template unsupported(syntax: string) =
    raise newException(ValueError,
      syntax & " is not supported in a condition: " & condition)

  while i < condition.len:
    let c = condition[i]
    if c == '`' and quote != '\'':
      unsupported("Command substitution")
    elif c == '~' and quote == '\0' and not in_token:
      unsupported("~")
    elif quote == '\0' and c in Whitespace:
      if in_token:
        result.add(token)
        token = ""
        in_token = false
    elif quote == '\0' and c in {'"', '\''}:
      quote = c
      in_token = true
    elif c == quote:
      quote = '\0'
    elif c == '$' and quote != '\'':
      var name = ""
      if i + 1 < condition.len and condition[i + 1] == '{':
        let close = condition.find('}', i + 2)
        if close < 0:
          raise newException(ValueError, "Unclosed ${ in condition: " & condition)
        name = condition[i + 2 ..< close]
        if name.len == 0 or name[0] notin IdentStartChars or
            not name.allCharsInSet(IdentChars):
          unsupported("${" & name & "}")
        i = close
      elif i + 1 < condition.len and condition[i + 1] == '(':
        unsupported("Command substitution")
      elif i + 1 < condition.len and condition[i + 1] in {'?', '#', '@', '*', '!', '$', '-'}:
        unsupported("$" & condition[i + 1])
      else:
        while i + 1 < condition.len and condition[i + 1] in IdentChars:
          name.add(condition[i + 1])
          inc i
      if name.len == 0: token.add('$') else: token.add(getEnv(name))
      in_token = true
    else:
      token.add(c)
      in_token = true
    inc i

  if quote != '\0':
    raise newException(ValueError, "Unclosed quote in condition: " & condition)
  if in_token:
    result.add(token)

proc evaluateCondition*(condition: string): bool =
  if condition.strip == "":
    return true

  let tokens = condition_tokens(condition)
  template unsupported() =
    raise newException(ValueError, "Unsupported condition: " & condition)

  case tokens.len
  of 1:
    tokens[0].len > 0
  of 2:
    let operand = tokens[1]
    case tokens[0]
    of "-n": operand.len > 0
    of "-z": operand.len == 0
    of "-e": operand.fileExists or operand.dirExists
    of "-f": operand.fileExists
    of "-d": operand.dirExists
    else: unsupported()
  of 3:
    case tokens[1]
    of "=", "==": tokens[0] == tokens[2]
    of "!=": tokens[0] != tokens[2]
    else: unsupported()
  else:
    unsupported()



when isMainModule:
  import std/unittest

  suite "workflow conditions":
    setup:
      putEnv("ACC_CONDITION_TEST", "production")
      delEnv("ACC_CONDITION_UNSET")

    test "an empty condition holds":
      check evaluateCondition("")

    test "comparisons expand variables":
      check evaluateCondition("$ACC_CONDITION_TEST == production")
      check evaluateCondition("${ACC_CONDITION_TEST} = production")
      check not evaluateCondition("$ACC_CONDITION_TEST == development")
      check evaluateCondition("$ACC_CONDITION_TEST != development")

    test "an unset variable compares as empty":
      check not evaluateCondition("$ACC_CONDITION_UNSET == production")
      check evaluateCondition("\"$ACC_CONDITION_UNSET\" = \"\"")
      check evaluateCondition("-z $ACC_CONDITION_UNSET")

    test "quotes group words and single quotes do not expand":
      putEnv("ACC_CONDITION_SPACED", "two words")
      check evaluateCondition("\"$ACC_CONDITION_SPACED\" = \"two words\"")
      check evaluateCondition("'$ACC_CONDITION_TEST' = '$ACC_CONDITION_TEST'")
      check not evaluateCondition("'$ACC_CONDITION_TEST' = production")

    test "a bare value holds when it is not empty":
      check evaluateCondition("$ACC_CONDITION_TEST")
      check not evaluateCondition("$ACC_CONDITION_UNSET")

    test "file tests":
      check evaluateCondition("-d " & get_temp_dir())
      check not evaluateCondition("-f " & get_temp_dir())
      check not evaluateCondition("-e " & (get_temp_dir() / "acc_condition_missing"))

    test "anything else is refused":
      expect ValueError: discard evaluateCondition("$ACC_CONDITION_TEST -eq 1")
      expect ValueError: discard evaluateCondition("\"unclosed")

    test "shell expansions it cannot perform are refused, not taken literally":
      expect ValueError: discard evaluateCondition("\"$(git branch --show-current)\" = main")
      expect ValueError: discard evaluateCondition("`hostname` = build")
      expect ValueError: discard evaluateCondition("\"${ACC_CONDITION_UNSET:-production}\" = production")
      expect ValueError: discard evaluateCondition("$? = 0")
      expect ValueError: discard evaluateCondition("-f ~/acc.yaml")
      check evaluateCondition("'$(x)' = '$(x)'")
      check evaluateCondition("\"~\" = '~'")
