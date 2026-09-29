# tdl model

[tdl](https://github.com/UnstoppableMango/tdl) is a type description language with a protobuf backend.
`tdl/` models every `unmango.*` package in it, and `gen/tdl/` is the protobuf tdl emits from that model.
`proto/` stays the source of truth; nothing builds from `gen/tdl/`.

The model is written against tdl 0.2.9.
It says everything `proto/` says, including field numbers, annotations, reserved numbers, and services.
The protobuf backend does not yet emit most of it, and this file records what is missing and which tdl issue tracks each gap.

## Regenerating

```sh
make tdl       # tdl gen over tdl/unmango into gen/tdl
make tdl-diff  # fidelity report: gen/tdl against proto/unmango
```

`tdl` is not in the Nix dev shell; `nix run github:UnstoppableMango/tdl` or the flake's overlay provides it.
`make tdl-diff` builds `proto/` with `buf`, so it needs `third_party/k8s` from `make vendor`.

tdl resolves `out("gen/tdl")` against the working directory rather than the file, so `tdl gen` runs from the repository root.

## Layout

One `.tdl` file models one proto package, at the same path under `tdl/` that the package has under `proto/`.
`unmango.cli.v1alpha1` and `unmango.discord.backup.*` span several `.proto` files and are one `.tdl` file each, with a section per original file.
tdl reaches another file only through an import, and the backend treats an imported declaration as foreign, so a package split across files would not generate even the parts it could.

`tdl/shim/` holds stand-ins for what the model references and tdl cannot:

| Shim | Stands in for |
|---|---|
| `shim/k8s/meta.tdl` | `k8s.io.apimachinery.pkg.apis.meta.v1` `OwnerReference`, `Condition`, `LabelSelector` |
| `shim/google/type.tdl` | `google.type` `Money`, `Date`, `Interval`, `TimeOfDay`, `LatLng`, `PostalAddress`, `PhoneNumber`, `DayOfWeek`, `CalendarPeriod` |
| `shim/protobuf.tdl` | `google.protobuf.Any` and `Struct` |
| `shim/scalar.tdl` | `int32`, `uint32`, `float`, `double` |
| `shim/rpc.tdl` | `Fn` and `Stream`, the types of a service's methods |

Every shim is imported as a foreign package, so a declaration reaching one is skipped today and generates once tdl can map it.

## How the model maps to protobuf

| protobuf | tdl |
|---|---|
| message with `google.api.resource` | `type X: Entity { ... }` plus `resource(type, pattern, singular, plural)` in the target block |
| other message | `type X { ... }` |
| enum | `enum X { ... }`, variants without the prefix or the `_UNSPECIFIED` value, which the backend adds |
| `oneof foo` in `M` | a field `foo: MFoo` and `enum MFoo { A { a: T } ... }` |
| service | `type XService { Method: rpc.Fn<Req, Resp> }` plus `XService => service` |
| server or client streaming | `rpc.Fn<Req, rpc.Stream<Resp>>`, `rpc.Fn<rpc.Stream<Req>, Resp>` |
| `int64`, `string`, `bool`, `bytes` | `int`, `string`, `bool`, `bytes` |
| `Timestamp`, `Duration` | `instant`, `duration` |
| `string` with `field_info.format = UUID4` | `uuid` |
| `repeated T`, `map<string, string>` | `[T]`, `{string -> string}` |
| field number | `number(n)` on every field |
| `(google.api.field_behavior) = X` | `field_behavior(X)` |
| `(google.api.field_info).format = UUID4` | `field_info(UUID4)` |
| `(google.api.resource_reference).type` | `resource_reference("type")` |
| `reserved 2, 3;` | `reserved(2, 3)` |
| `edition = "2024";` | `edition("2024")` |
| `deprecated` | `deprecated("reason")` on the declaration, or a bare `deprecated` in the target block for a file |

Leading comments are `///` doc comments, which tdl carries into the model.
File narratives, section banners, and trailing comments are `//` comments, which tdl drops, so the generated protobuf has none of them.

Every field is pinned with `number(n)`.
tdl numbers an unpinned field by its position and does not skip numbers already pinned, so pinning some fields and not others collides.
Pinning all of them also keeps the field bands in [README.md](../README.md) readable from the target block.

## Fidelity

`make tdl-diff` at the time of writing:

| | Exact | Emitted | In `proto/` |
|---|---|---|---|
| Messages | 127 | 131 | 390 |
| Enums | 143 | 143 | 143 |
| Services | 0 | 0 | 14 (71 rpcs) |

Every emitted enum and every emitted message outside a oneof matches `proto/` by name, number, label, and type.
The four emitted messages that differ each hold a oneof, which tdl emits as a field of a separate message.
Those separate messages are the five tdl emits that `proto/` does not have.

The 259 messages not emitted are skipped for one reason: each reaches a foreign declaration, directly (238 warnings) or through a message that does (43 warnings).
Nothing generated is annotated, reserved, or in an edition: the backend passes over the 2,320 directive uses it does not declare.

## Gaps

Each row is a construct the model expresses and the protobuf backend does not emit.

| Gap | In `proto/` | tdl issue |
|---|---|---|
| Editions: the backend always writes `syntax = "proto3"` | 55 packages | ISSUE-EDITION |
| `reserved`: no directive, and a second directive of one name in a scope is an error | 16 statements | ISSUE-RESERVED |
| Options: `field_behavior`, `field_info`, `resource`, `resource_reference` | 1,939 / 94 / 94 / 169 uses | ISSUE-OPTIONS |
| A declaration reaching another tdl package is skipped, not imported | 39 packages import `unmango.ref` | ISSUE-IMPORT |
| No mapping from a tdl declaration to an external proto message | `k8s.io` 226 fields, `google.type` 143, `Any`/`Struct` 7 | ISSUE-EXTERNAL, [#812](https://github.com/UnstoppableMango/tdl/issues/812) |
| No fixed-width numerics | `int32` 330, `uint32` 20, `double` 54, `float` 2 | ISSUE-NUMERICS |
| Unpinned numbers collide with pinned ones | every message | ISSUE-NUMBERS |
| A oneof is a separate message with a `oneof variant` | 13 oneofs | ISSUE-ONEOF |
| Output file is always `<last package segment>.proto` | every package | ISSUE-LAYOUT |
| No services | 14 services, 71 rpcs | ISSUE-SERVICE |
| `import ... as _` does not bind a lower-case primitive | `shim/scalar.tdl` | ISSUE-UNDERSCORE |
| A keyword cannot be a package segment | `google.type` | ISSUE-KEYWORD |
| `tdl fmt` removes blank lines between comment groups | every file banner | ISSUE-FMT |

Related, already tracked: `tdl check` does not lower a file ([#821](https://github.com/UnstoppableMango/tdl/issues/821)), so the duplicate `reserved` error surfaces only in `tdl gen`.

`google.type` is modelled as the package `google.gtype` because of the keyword gap.
Its `DayOfWeek` and `CalendarPeriod` values are unprefixed in `google.type`, which tdl's enum naming cannot express without a `name` directive per value.
Where two `reserved` statements share a message, the model merges them into one directive and keeps both reasons as comments.
