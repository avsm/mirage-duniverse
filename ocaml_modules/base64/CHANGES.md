### v3.1.0 (2019-02-03)

* Add `Base64.encode_string` that doesn't raise or return an error.
  This makes it easier to port pre-3.0 code to the new interface (#26 @avsm)

### v3.0.0 (2018-01-21)

* Implementation of Base64 according to RFC 2045 (available on base64.rfc2045)
* New implementation of Base64 according to RFC 4648 from nocrypto's implementation
* Fix bad access with `String.iter` on the old implementation of Base64 (@dinosaure, #23)
* Check isomorphism between `encode` & `decode` function (@hannesm, @dinosaure, #20)
* Add tests from RFC 3548 and from PHP impl. (@hannesm, @dinosaure, #24)
* Add fuzzer on both implementations
 - check isomorphism
 - check bijection
 - check if `decode` does not raise any exception
* __break-api__, `B64` was renamed to `Base64` (@copy, @avsm, @dinosaure, #17)
* __break-api__, `Base64.decode` and `Base64.encode` returns a result type instead to raise an exception (@hannesm, @dinosaure, #21)
* __break-api__, Add `sub` type to avoid allocation to the end-user (@avsm, @dinosaure, #24)
* __break-api__, Add `pad` argument on `decode` function to check if input is well-padded or not (@hannesm, @dinosaure, #24)
* __break-api__, Add `off` and `len` optional arguments on `encode` & `decode` functions to compute a part of input (@cfcs, @dinosaure, #24)
* Better performance (see #24) (@dinosaure)
* Review of code by @cfcs (see #24)

### v2.3.0 (2018-11-23)

* Add a `decode_opt` function that is a non-raising variant of `decode`.
* Reformat the code with ocamlformat (@dinosaure)
* Port build to dune from jbuilder (@dinosaure

### v2.2.0 (2017-06-20)

* Switch to jbuilder (#13, @rgrinberg)

### v2.1.2 (2016-10-18)

* Fix version number (#11, @hannesm)

### v2.1.1 (2016-10-03)

* Switch build to `topkg` and obey the `odig` conventions
  for installing metadata files.
* Add a test suite based on RFC4648 test vectors.
* Improve Travis CI tests to be multidistro.

### v2.0.0 (2014-12-24)

* Switch the top-level `Base64` module to `B64` to avoid
  clashing with various other similarly named modules in
  `extlib` and some other libraries.  This is obviously
  backwards compatibility breaking with all current users
  of this library. (#3).

### 1.1.0 (2014-12-16)

* Allow specifying a different alphabet during encoding or
  decoding, and supply a URI-safe alphabet along with the
  default Base64 standard.
* Add OCaml 4.02 `safe-string` compatibility.
* Optionally support encoding without padding.

### 1.0.0 (2014-08-03)

* Initial public release.
