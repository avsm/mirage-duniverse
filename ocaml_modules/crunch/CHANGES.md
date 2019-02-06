## v2.2.0 (2019-02-05)
* Port to dune from jbuilder (#46 @hannesm)
* use `SOURCE_DATE_EPOCH` instead of gettimeofday if set to
  support reproducible builds (#45 @xclerc)

## v2.1.0 2017-06-24

* Port to Jbuilder and simplify test dependencies (#38 by @rgrinberg)

## v2.0.0 2016-02-24

* Fix reading of files consisting of multiple pages (#30 by @hannesm)
* Port to MirageOS3 API: removed unused `id` type (#17), add Failure
  error type (#20), `connect` does not return a result anymore.
* Generate a `mem` function for the filesystem (#18)
* Port to topkg and respect the odig packaging convention (#24 via @fgimenez)
* Add `LICENSE` file to repository (#19 via @djs55)

## v1.4.1 2016-02-08

* Use a poor-man `realpath` instead of relying on C bindings which are not
  available under Cygwin

## v1.4.0 2015-03-09

* Add an explicit `connect` function to the signature of generated code. (#13)
* Use centralised Travis CI scripts.

## v1.3.0 2014-03-08

* Deduplicate file chunks so that only one copy of each
  sector is allocated in the static module.

## v1.2.3 2013-12-24

* Fix compilation of 0-length files.

## v1.2.2 2013-12-08

* Use the `V1.KV_RO` signature from mirage-types>=0.5.0
* Add Travis CI scripts.

## v1.2.1 2013-12-08

* Generate the correct signature for `V1.KV_RO`.

## v1.2.0 2013-12-08

* Use the `V1.KV_RO` signature from mirage-types>=0.3.0

## v1.1.2 2013-12-07

* Do not skip files without an extension.

## v1.1.1 2013-12-06

* Bugfix release.

## v1.1.0 2013-12-05

* New release to adapt to the new mirage-types API

## v0.7.0 2013-07-21

* Add a `-nolwt` output mode which simply uses strings and has
  no dependence on Lwt.  For the modern user who demands ultra-convenience.

## v0.6.0 2013-07-09

* Adapt output to mirage-platform-0.9.2 Io_page API.

## v0.5.0 2013-03-28

* Added a -o option (needed for mirari)

## 0.4.0 2012-12-20

* Initial public release
