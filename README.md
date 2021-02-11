# Acc

Clone then run using `nimble -d:debug -d:nimWorkaround14447 -p:src --threads:off
run acc run -d ./test_site ./test_site/plugins/test.nims`

The `acc run -d ./test_site ./test_site/plugins/test.nims` part of the command
is the binary to build/run and the arguments to it.

# Naming bug

> Edit: there is a branch for this instead: `naming_bug` :)

To replicate the naming problem I have you need to edit `src/global_state.nim`
and rename the exported var from `state` to `global_state`. Then edit
`src/script/routines.nim` to import and use that symbol instead, this is the
first call site that the compiler gets stuck on.

Re run the app and you should get (at least I reliably do) the following error:
`src/script/routines.nim(9, 34) Error: undeclared identifier: 'context'`

There are a few more places where the problem occurs, like in `src/acc.nim` for
the `config` property that time.
