.PHONY: aip bands build breaking check update format fmt clean lint tdl vendor

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

# Also runs as the api-linter flake check; this is the fast local path.
aip:
	nix build --no-link .#unmangoApis.apiLinter

# Also runs as the field-bands flake check; this is the fast local path.
bands:
	python3 hack/check-field-bands.py proto

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

# proto/unmango is generated from tdl/; see docs/tdl.md.
tdl:
	tdl gen $(TDL_FILES)

# The devShell sets TDL_GMK to tdl's GNU make loadable object, which defines
# $(tdl-files dir...): the .tdl files under each dir, relative to this
# Makefile. Outside the devShell, or with a make that cannot load the object,
# nothing is loaded, the call expands to nothing, and find takes over. make
# tries to remake an object it failed to load, so the empty rule stops a
# missing one from failing the build.
ifdef TDL_GMK
-load $(TDL_GMK)
$(TDL_GMK): ;
endif

TDL_FILES = $(or $(tdl-files tdl/unmango),$(shell find tdl/unmango -name '*.tdl' | sort))
