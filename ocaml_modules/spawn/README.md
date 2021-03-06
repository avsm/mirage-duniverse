# SPAWN - spawning system process

Spawn is a small library exposing only one function:
`Spawn.spawn`. Its purpose is to start command in the
background. Spawn aims to provide a few missing features of
`Unix.create_process` such as providing a working directory as well as
improving error reporting and performance.

Errors such as directory or program not found are properly reported as
`Unix.Unix_error` exceptions, on both Unix and Windows.

On Unix, Spawn uses `vfork` by default as it is often a lot faster
than fork. There is a benchmark comparing `Spawn.spawn` to
`Unix.create_process` in `spawn-lib/bench`. If you don't trust
`vfork`, you can set the environment variable `SPAWN_USE_FORK` to make
Spawn use `fork` instead.
