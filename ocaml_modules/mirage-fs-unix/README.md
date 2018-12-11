mirage-fs-unix -- passthrough filesystem for MirageOS on Unix
-------------------------------------------------------------

This is a pass-through Mirage filesystem to an underlying Unix directory.  The
interface is intended to support eventual privilege separation (e.g. via the
Casper daemon in FreeBSD 11).

The current version supports the `Mirage_fs.S` and `Mirage_fs_lwt.S` signatures
defined in the `mirage-fs` package.

* WWW: <https://mirage.io>
* E-mail: <mirageos-devel@lists.xenproject.org>
