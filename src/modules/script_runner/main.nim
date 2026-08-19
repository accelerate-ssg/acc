import loader, runner, types
import os, json

const dynlibExts = @["dll", "so", "dylib", "acc"]

proc loadAllScriptRunners() =
  for kind, path in walkDir("script_runners"):
    if kind in @[pcFile, pcLinkToFile] and splitFile(path).ext[1..^1] in dynlibExts:
      let unlinked_path = if kind == pcLinkToFile: expandSymlink(path) else: path
      discard loadScriptRunner(unlinked_path)

proc main() =
  loadAllScriptRunners()
  
  # Use script runners
  let testScript = "test_script.js"
  let runner = getScriptRunnerForFile(testScript)
  if runner != nil:
    var context = %*{"name": "Test", "array": [1, 2, 3]}
    try:
      runner.create()
      let result = runner.eval(readFile(testScript), cast[pointer](context))
      echo "Result from ", $runner.name(), ": ", result
      echo "Updated context: ", context
    except JSException as e:
      echo "JavaScript error occurred:"
      echo "Message: ", e.msg
      echo "Stacktrace:"
      echo e.stacktrace
    finally:
      runner.destroy()
  else:
    echo "No suitable script runner found for ", testScript

  unloadAllScriptRunners()


when isMainModule and not defined(release):
  main()
