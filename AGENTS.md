# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## Overview

This is a Protocol Buffer API definition repository (`buf.build/unmango/apis`).
It is language-agnostic: the proto definitions are the source of truth, and client/server code is generated from them.

Two proto namespaces coexist under `proto/`:

- `unmango.*`: life-domain APIs (calendar, finance, asset, media, health, compute, ci, codegen, vcs, people, record) modeled on the Kubernetes resource graph.
  See [README.md](./README.md) for the domain architecture, relationship notation, and field-numbering convention; it is the primary reference for this namespace, not this file.
- `dev.unmango.*`: infrastructure APIs, `protofs` (Go `io/fs` over gRPC) and `discord/backup` (Discord guild backup schema).

## Development Environment

This project uses Nix for the development environment.
Enter it via:

```sh
nix develop   # or: direnv allow (if using direnv)
```

Available tools in the dev shell: `buf`, `gnumake`.

## Commands

| Task | Command |
|------|---------|
| Format | `make fmt` or `nix fmt` |
| Check (Nix flake) | `make check` or `nix flake check` |
| Update flake inputs | `make update` or `nix flake update` |
| Vendor third-party protos | `make vendor` (required before bare `buf` in the repo root) |
| Lint protos | `make lint` (see gotcha below) |
| Check breaking changes | `make breaking` (override the base ref with `make breaking AGAINST=<ref>`) |
| Generate code | `buf generate` (only `proto/unmango/*`, see gotcha below) |

**Gotcha:** `buf generate` needs `protoc-gen-go` on `$PATH`, which `nix develop` does not currently provide in this environment.
`make lint` is the practical check for schema changes instead.

**Gotcha:** there is no BSR module for apimachinery, so the `k8s.io/apimachinery/...` imports resolve only against a vendored copy.
`buf.yaml` declares that copy as the gitignored `third_party/k8s` module; `make vendor` materializes it out of the Nix build, and every bare `buf` command in the repo root fails until it does.
`make lint` and `make breaking` sidestep it by pointing `buf` at the Nix-built workspace instead, which vendors the same tree.
`.github/workflows/buf.yml` runs `make vendor` before `buf-action`, leaving that job with `buf build` alone.
Its `lint`, `breaking`, and `format` steps are off: `nix flake check` covers lint and the treefmt `buf` formatter, `make breaking` covers breaking changes, and `buf format` would flag the vendored protos, which are copied in verbatim.
`push` is off too: `buf push` rejects a module whose dependencies are not themselves named BSR modules, so `buf.build/unmango/apis` cannot be published until `k8s.io/apimachinery` has a BSR module to depend on.

**Gotcha:** `buf format -d` takes exactly one positional path.
To diff-check several files, repeat `--path`: `buf format -d --path a.proto --path b.proto`.

## Architecture

### Proto layout

- `proto/unmango/<domain>/<package>/<version>/`: life-domain APIs (`calendar`, `finance`, `asset`, `media`, `health`, `compute`, `ci`, `codegen`, `vcs`, `people`, `record`, plus the shared `ref` and `uom` vocabularies).
  Domain-by-domain design and the `->`/`~>`/`=>`/`@`/`>>` relationship notation are documented in [README.md](./README.md), not here.
- `proto/dev/unmango/protofs/{file,fs}/v1alpha1/`: `FileService` (Go `io/fs.File` over gRPC: Read, Write, Stat, Truncate, Readdir) and `FsService` (filesystem-level RPCs: Chmod, Create, Open, Remove, Rename).
  Mode/perm fields are `uint32` bitmasks; `FileModeConst` documents the named bit constants.
- `proto/dev/unmango/discord/backup/v1alpha1/`: Discord guild backup/restore schema (`ServerBackup`, `Guild`, `Channel`, `Message`, etc.).
- `proto/dev/unmango/{cli,cmd}/` and `proto/unmango/{cli,cmd}/`: CLI/command-execution APIs; both namespaces currently have live versions, check git history before assuming which is canonical for new work.

**Gotcha:** `buf.gen.yaml` only lists `proto/unmango` under `inputs.paths`, so `buf generate` silently produces no Go code for anything under `proto/dev/unmango/*`.
If you add a `dev.unmango.*` package that needs generated code, update `buf.gen.yaml` too.

**Gotcha:** no domain package may be named `ref` or `uom`.
A package `unmango.<domain>.ref` (or `.uom`) would capture the relative name before it reached `unmango.ref.v1alpha1` (or `unmango.uom.v1alpha1`), silently breaking every reference in that domain.
See the comment in `proto/unmango/vcs/branch/v1alpha1/branch.proto` for the full explanation.

### Version coexistence

Several `dev.unmango.*` packages (`protofs/file`, `protofs/fs`, `cmd`, `discord/backup`) currently ship two `vN.alphaM` directories side by side.
When a new version supersedes a prior one, mark the superseded package `option deprecated = true` (at file scope when the whole package is superseded wholesale, at service scope when only part of it is) plus a `// Deprecated: use vN.alphaM+1.` comment naming the replacement, rather than leaving the choice to git-history archaeology.
Both versions stay checked in until a separate decision is made to delete the old one.

### Buf configuration

`buf.yaml` defines the module at `buf.build/unmango/apis` with:

- Linting: `STANDARD` ruleset
- Breaking change detection: `FILE` ruleset
- Module roots: `proto/` and the gitignored `third_party/k8s`, which is ignored by both rulesets
- Remote dependency: `buf.build/googleapis/googleapis`
- `buf.gen.yaml` sets `go_package_prefix` to `github.com/unmango/apis/go`, so generated Go lands under `go/` mirroring the proto path

Third-party protos are not checked in.
The Nix build vendors them into its own workspace (see below), and `make vendor` materializes the apimachinery half into `third_party/k8s` for the CLI.

`buf.yaml`, `buf.lock`, and `buf.gen.yaml` drive the CLI workflow: `buf generate`, BSR pushes, and the format check in the `buf-action` CI job.
The Nix build does not read them.

### Nix build

`nix build` assembles its own v2 buf workspace instead of resolving the BSR dependency, so the build never touches the network.
The builders come from [a2b](https://github.com/UnstoppableMango/a2b), reached through `inputs'.a2b.legacyPackages.lib.buf`:

- `nix/googleapis.nix`: `buf.vendor` copies `google/type`, `google/api/field_behavior.proto`, and `google/api/resource.proto` out of the pinned `googleapis` flake input into a tree matching its import paths
- `nix/apimachinery.nix`: the same for the three `k8s.io/apimachinery` protos, out of the tag-pinned `apimachinery` flake input.
  `prefix` restores the `k8s.io/apimachinery` segments the repo root omits
- `nix/workspace.nix`: `buf.mkWorkspace` stitches those two trees and `proto/` into one workspace whose modules resolve each other's imports.
  `vendor = true` keeps the third-party modules out of lint and breaking checks
- `nix/generate.nix`: `buf.generate` over the workspace root, with plugins and managed mode declared through `buf.mkTemplate`.
  Mirrors `buf.gen.yaml`, which a template cannot reuse directly because its `inputs:` key conflicts with a command-line input
- `nix/proto.nix`: `buf.build` over the workspace, producing `apis.binpb`

Generating from the workspace root covers the vendored modules too, so the `github.com/unmango/apis/go/google/type` and `.../k8s.io/...` imports that managed mode writes into the generated code resolve to generated packages.

Bump the vendored googleapis with `make update` (`nix flake update`).
The `apimachinery` input is pinned to a tag in its URL, so `make update` leaves it alone; bumping it means editing the URL in `flake.nix` and running `nix flake lock --update-input apimachinery`.

When adding new proto files, place them under `proto/unmango/<domain>/<package>/<version>/` (life-domain APIs) or `proto/dev/unmango/<package>/<version>/` (infrastructure APIs), following the existing pattern.
