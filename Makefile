.PHONY: build check update format fmt clean

build:
	nix build

check:
	nix flake check

update:
	nix flake update

format fmt:
	nix fmt

clean:
	rm -f result *.binpb
