## ocaml-crunch -- convert a filesystem into a static OCaml module

`ocaml-crunch` takes a directory of files and compiles them into a standalone
OCaml module which serves the contents directly from memory.  This can be
convenient for libraries that need a few embedded files (such as a web server)
and do not want to deal with all the trouble of file configuration.

Run `man ocaml-crunch` or `ocaml-crunch --help` for more information:

```
NAME
       ocaml-crunch - Convert a directory structure into a standalone OCaml
       module that can serve the file contents without requiring an external
       filesystem to be present.

SYNOPSIS
       ocaml-crunch [OPTION]... DIRECTORIES...

ARGUMENTS
       DIRECTORIES
           Directories to recursively walk and crunch.

OPTIONS
       -e VALID EXTENSION, --ext=VALID EXTENSION
           If specified, only these extensions will be included in the
           crunched output. If not specified, then all files will be crunched
           into the output module.

       --help[=FMT] (default=pager)
           Show this help in format FMT (pager, plain or groff).

       -m MODE, --mode=MODE (absent=lwt)
           Interface access mode: 'lwt' or 'plain'. 'lwt' is the default.

       -o OUTPUT, --output=OUTPUT
           Output file for the OCaml module.

       --version
           Show version information.

BUGS
       Email bug reports to <mirage-devel@lists.xenproject.org>.
```
