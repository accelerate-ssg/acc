import sequtils, tables, strutils, sets, sugar
import ../config

type StringSet = HashSet[string]

proc sort(data: var OrderedTable[string, StringSet]) =
  ## Topologically sort the data in place.

  var ranks: Table[string, Natural]   # Maps the keys to a rank.

  # Remove self dependencies.
  for key, values in data.mpairs:
    values.excl key

  # Add extra items (i.e items present in values but not in keys).
  for values in toSeq(data.values):
    for value in values:
      if value notin data:
        data[value] = initHashSet[string]()

  # Find ranks.
  var deps = data   # Working copy of the table.
  var rank = 0
  while deps.len > 0:

    # Find a key with an empty dependency set.
    var keyToRemove: string
    for key, values in deps.pairs:
      if values.card == 0:
        keyToRemove = key
        break
    if keyToRemove.len == 0:
      # Not found: there is a cycle.
      raise newException(ValueError, "Unorderable items found: " & toSeq(deps.keys).join(", "))

    # Assign a rank to the key and remove it from keys and values.
    ranks[keyToRemove] = rank
    inc rank
    deps.del keyToRemove
    for k, v in deps.mpairs:
      v.excl keyToRemove

  # Sort the original data according to the ranks.
  data.sort((x, y) => cmp(ranks[x[0]], ranks[y[0]]))

proc topological_sort*(scripts: seq[ScriptConfig]): seq[ScriptConfig] =
  var
    data = initOrderedTable[string, StringSet]()
    available = scripts.mapIt(it.name).toHashSet
    
  # First pass: Initialize data structure and collect available scripts
  for script in scripts:
    if script.name notin data:
      data[script.name] = script.after.toHashSet
    else:
      data[script.name] = data[script.name].union script.after.toHashSet

  # Second pass: Process 'before' dependencies and check for missing dependencies
  for script in scripts:
    for before_script in script.before:
      if before_script notin available:
        raise newException(ValueError, "Unfulfilled dependency: " & before_script)
      if before_script notin data:
        data[before_script] = initHashSet[string]()
      data[before_script].incl script.name
    
    for after_script in script.after:
      if after_script notin available:
        raise newException(ValueError, "Unfulfilled dependency: " & after_script)

  sort(data)

  # Create the result maintaining the order and avoiding duplicates
  var seen = initHashSet[string]()
  result = newSeqOfCap[ScriptConfig](scripts.len)
  for key in data.keys:
    if key notin seen:
      for script in scripts:
        if script.name == key:
          result.add script
          seen.incl key
          break

proc topological_sort*(config: var Config) =
  config.scripts = topological_sort(config.scripts)

when isMainModule:
  import unittest

  suite "Topological Sort Tests":
    test "Simple order":
      let test1 = @[
        ScriptConfig(name: "A", before: @[], after: @[]),
        ScriptConfig(name: "B", before: @[], after: @["D"]),
        ScriptConfig(name: "C", before: @["A"], after: @["D"]),
        ScriptConfig(name: "D", before: @[], after: @[])
      ]

      let actual1 = topological_sort(test1).mapIt(it.name)
      let expected1 = @["D", "B", "C", "A"]
      check(actual1 == expected1)

    test "Dependency loop":
      let test2 = @[
        ScriptConfig(name: "A", before: @["B"], after: @[]),
        ScriptConfig(name: "B", before: @["A"], after: @[])
      ]

      expect ValueError:
        let actual2 = topological_sort(test2).mapIt(it.name)
        let expected2 = @["B", "A", "C"]
        check(actual2 == expected2)

    test "Unfulfilled before dependency":
      let test3 = @[ScriptConfig(name: "A", before: @["C"], after: @[])]
      
      expect ValueError:
        let actual3 = topological_sort(test3).mapIt(it.name)
        let expected3 = @["B", "A", "C"]
        check(actual3 == expected3)

    test "Unfulfilled after dependency":
      let test4 = @[ScriptConfig(name: "A", before: @[], after: @["C"])]
      
      expect ValueError:
        let actual4 = topological_sort(test4).mapIt(it.name)
        let expected4 = @["B", "A", "C"]
        check(actual4 == expected4)

    test "Double incoming dependency":
      let test5 = @[
        ScriptConfig(name: "A", before: @["C"], after: @["B"]),
        ScriptConfig(name: "A", before: @["C"], after: @[]),
        ScriptConfig(name: "B", before: @[], after: @[]),
        ScriptConfig(name: "C", before: @[], after: @[])
      ]

      let actual5 = topological_sort(test5).mapIt(it.name)
      let expected5 = @["B", "A", "C"]
      check(actual5 == expected5)
