# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## Overview

This is a Protocol Buffer API definition repository (`buf.build/unmango/apis`) for a file system API (`protofs`). It is language-agnostic — the proto definitions are the source of truth, and client/server code is generated from them.

## Development Environment

This project uses Nix for the development environment. Enter it via:

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
| Lint protos | `buf lint` |
| Check breaking changes | `buf breaking --against <baseline>` |
| Generate code | `buf generate` |

## Architecture

### Proto layout

All proto definitions live under `proto/` and follow the `dev.unmango.*` package namespace:

- `proto/dev/unmango/protofs/file/v1alpha1/file.proto` — `FileService` and supporting types (`File`, `FileInfo`, `FileMode` enum). Models the Go `io/fs.File` interface over gRPC.
- `proto/dev/unmango/protofs/fs/v1alpha1/fs.proto` — `FsService` with filesystem-level RPCs (Chmod, Create, Open, Remove, Rename, etc.). Read/Write use server-streaming for large data transfers.

### Buf configuration

`buf.yaml` defines the module at `buf.build/unmango/apis` with:

- Linting: `STANDARD` ruleset
- Breaking change detection: `FILE` ruleset
- Module root: `proto/`

When adding new proto files, place them under `proto/dev/unmango/<package>/<version>/` following the existing pattern.
