.PHONY: build breaking check update format fmt clean lint vendor

AGAINST ?= main

build:
	nix build

check:
	nix flake check

lint:
	buf lint $$(nix build --no-link --print-out-paths .#unmangoApis.workspace)

# The repo-root buf.yaml declares third_party/k8s as a module because
# k8s.io/apimachinery has no BSR module. The tree is gitignored; Nix builds it.
vendor:
	rm -rf third_party/k8s
	mkdir -p third_party
	cp -rL $$(nix build --no-link --print-out-paths .#unmangoApis.apimachinery) third_party/k8s
	chmod -R u+w third_party/k8s

update:
	nix flake update

format fmt:
	nix fmt

clean:
	rm -rf result *.binpb third_party

# k8s.io imports resolve only inside the nix workspace, so both sides of the
# comparison are images built from it rather than from proto/ alone.
breaking:
	buf breaking \
		$$(nix build --no-link --print-out-paths .#unmangoApis.proto) \
		--against $$(nix build --no-link --print-out-paths 'git+file://$(CURDIR)?ref=$(AGAINST)#unmangoApis.proto')
