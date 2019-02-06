## v0.5 2017-12-20

- prometheus-app: update to cohttp.1.0.0 API (#15, @djs55)
- add support for histograms (#14, @stijn-devriendt and @talex5)
- add `Sample_set module` to clean up the API a bit (#13, @talex5)
- fix gettimeofday parameter not used in favor of Unix.gettimeofdaya (#12, @stijn-devriendt)

## v0.4 2017-08-02

- unix: update to cohttp >= 0.99.0. Note this means the unix package
  requires OCaml 4.03+. The main library still only requires OCaml 4.01+

## v0.3 2017-07-03

- Build tweaks to support topkg versioning (@avsm)

## v0.2 2017-05-18

- add example program and update README
- switch to jbuilder
- throw a clearer error on registering a duplicate metric
- use `Re` rather than `Str`

## v0.1

- Initial release.
