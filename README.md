# unmango/apis

[![CI](https://github.com/unmango/apis/actions/workflows/ci.yml/badge.svg)](https://github.com/unmango/apis/actions/workflows/ci.yml)
[![Buf CI](https://github.com/unmango/apis/actions/workflows/buf.yml/badge.svg)](https://github.com/unmango/apis/actions/workflows/buf.yml)
[![protobuf](https://img.shields.io/badge/protobuf-edition%202024-4285F4)](https://protobuf.dev)
[![buf.build](https://img.shields.io/badge/buf.build-unmango%2Fapis-0C3CF5)](https://buf.build/unmango/apis)

Public API definitions. Published at [`buf.build/unmango/apis`](https://buf.build/unmango/apis).

## APIs

### protofs

[`proto/dev/unmango/protofs`](./proto/dev/unmango/protofs)

Models the Go `io/fs` filesystem interface over gRPC.

- `FileService` — file-level operations (Read, Write, Stat, Truncate, Readdir)
- `FsService` — filesystem-level operations (Chmod, Create, Open, Remove, Rename, etc.)

### discord/backup

[`proto/dev/unmango/discord/backup`](./proto/dev/unmango/discord/backup)

Schema for a complete backup/snapshot of a Discord server (guild). Captures everything needed to restore a server: structure, content, and configuration.

- `ServerBackup` — top-level backup message containing all guild data
- `Guild`, `Channel`, `Role`, `Member`, `User` — server structure
- `Emoji`, `Sticker`, `Webhook`, `Invite` — guild assets and access
- `ScheduledEvent`, `AutoModRule` — configuration
- `Message`, `Attachment`, `Embed` — message content

## Development

Requires [Nix](https://nixos.org/). Enter the dev shell:

```sh
nix develop   # or: direnv allow
```

| Task | Command |
|------|---------|
| Build | `make` or `nix build` |
| Format | `make fmt` or `nix fmt` |
| Check | `make check` or `nix flake check` |
| Lint protos | `buf lint` |
| Generate code | `buf generate` |
