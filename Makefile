.PHONY: build check update format fmt clean lint

build:
	nix build

check lint:
	nix flake check

update:
	nix flake update

format fmt:
	nix fmt

clean:
	rm -f result *.binpb

breaking:
	buf breaking --against .git#branch=main
