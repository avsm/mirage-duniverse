.PHONY: build clean test

build:
	dune build

test:
	dune runtest

clean:
	dune clean

doc:
	dune build @doc

# until we have https://github.com/ocaml/opam-publish/issues/38

REPO=../opam-repository
PACKAGES=$(REPO)/packages

pkg-%:
	topkg opam pkg -n $*
	mkdir -p $(PACKAGES)/$*
	cp -r _build/$*.* $(PACKAGES)/$*/
	rm -f $(PACKAGES)/$*/$*.opam
	cd $(PACKAGES) && git add $*

PKGS=$(basename $(wildcard *.opam))
opam-pkg:
	$(MAKE) $(PKGS:%=pkg-%)
