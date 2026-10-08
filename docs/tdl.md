# tdl model

`proto/unmango/**` is generated from the [tdl](https://github.com/UnstoppableMango/tdl) model in `tdl/`.
Edit the `.tdl` files and regenerate; a hand edit to a generated `.proto` fails the `tdl-gen` flake check.
`proto/dev/unmango/**` is deprecated, not modelled, and stays hand-written.

## Regenerating

```sh
make tdl
```

It runs `tdl gen` over `tdl/unmango` from the repository root, because tdl resolves `out("proto")` against the working directory.
`tdl` comes from the dev shell, pinned by the `tdl` flake input.

`tdl gen` drops a `.tdl-output` marker claiming its output directory.
`make tdl` deletes it and `.gitignore` lists it, because `proto/` also holds the hand-written `proto/dev`, and a marked directory makes `tdl gen --verify` report every file another `.tdl` file generated as stale ([tdl#918](https://github.com/UnstoppableMango/tdl/issues/918)).

`nix flake check` runs `tdl-check`, `tdl-fmt`, and `tdl-gen` over `tdl/`.
Format with `tdl fmt -w <file>`.

## Layout

One `.tdl` file models one proto package, at the same path under `tdl/` that the package has under `proto/`.
`unmango.cli.v1alpha1` and `unmango.discord.backup.*` span several `.proto` files and are one `.tdl` file each, placing each declaration with `file(...)`.

`tdl/shim/` declares what the model references and another proto file defines:

| Shim | Stands in for |
|---|---|
| `shim/k8s/meta.tdl` | `k8s.io.apimachinery.pkg.apis.meta.v1` `OwnerReference`, `Condition`, `LabelSelector` |
| `shim/google/type.tdl` | `google.type` `Money`, `Date`, `Interval`, `TimeOfDay`, `LatLng`, `PostalAddress`, `PhoneNumber` (as `GooglePhoneNumber`), `DayOfWeek`, `CalendarPeriod` |
| `shim/protobuf.tdl` | `google.protobuf.Any` and `Struct` |
| `shim/rpc.tdl` | `Fn` and `Stream`, the types of a service's methods |

A shim is imported `as _`, and each file using one of its types maps it in its own target block with `foreign(file, message)`, so the reference is written as the external message and its file imported.
The mapping is repeated per file because tdl does not carry a dependency's declaration-level directives to its importers ([tdl#916](https://github.com/UnstoppableMango/tdl/issues/916)).
`google.type.PhoneNumber` is `GooglePhoneNumber` in tdl because `unmango.people.contact.v1alpha1` declares its own `PhoneNumber`.
For the same reason `unmango.cmd.v1alpha1` maps `cli.Utility` with `foreign` rather than importing it plainly: plain import would name `unmango/cli/v1alpha1/v1alpha1.proto` rather than `cli.proto`.

## How protobuf maps to tdl

| protobuf | tdl |
|---|---|
| message with `google.api.resource` | `type X: Entity { ... }` plus `option("(google.api.resource)", "{ type: ... }")` on `X` in the target block |
| other message | `type X { ... }` |
| enum | `enum X { ... }`, variants without the prefix or the `_UNSPECIFIED` value, which tdl adds |
| `oneof foo` in `M` | a field `foo: MFoo`, `enum MFoo { A { a: T } ... }`, and `M { foo => oneof }` |
| service | `type XService { Method: Fn<Req, Resp> }` plus `XService => service`, `Fn => rpc` |
| server or client streaming | `Fn<Req, Stream<Resp>>`, `Fn<Stream<Req>, Resp>`, plus `Stream => stream` |
| `int32`, `uint32`, `int64`, `float`, `double` | `int32`, `uint32`, `int`, `float32`, `float64` |
| `string`, `bool`, `bytes` | `string`, `bool`, `bytes` |
| `Timestamp`, `Duration` | `instant`, `duration` |
| `repeated T`, `map<string, string>` | `[T]`, `{string -> string}` |
| field or enum value number | `number(n)` |
| field option, such as `(google.api.field_behavior) = REQUIRED` | `option("(google.api.field_behavior)", "REQUIRED")`, once per value |
| `import "google/api/...";` for an option | `import("google/api/...")` in the target block |
| `reserved 2, 3;` | `reserved(2, 3)`, once per statement |
| `edition = "2024";` | `edition("2024")` |
| file name | `file("x.proto")` in the target block, or on a declaration to place it |
| `option deprecated = true;` at file scope | `option("deprecated", "true")` in the target block |
| `deprecated` on a declaration | `deprecated("reason")`, which also writes `Deprecated: reason` |

A `///` doc comment becomes the element's leading comment in the generated proto.
An ordinary `//` comment stays in the model only: section banners such as `// Desired state.`, file narratives, and the comments on `reserved` statements are read in `tdl/`, not in `proto/`.

## Open tdl issues

| Issue | Effect here |
|---|---|
| [#916](https://github.com/UnstoppableMango/tdl/issues/916) | `foreign` mappings repeat in every importing file |
| [#918](https://github.com/UnstoppableMango/tdl/issues/918) | the `.tdl-output` marker is deleted after generating |
| [#921](https://github.com/UnstoppableMango/tdl/issues/921) | the indented list in `Commit`'s doc loses its indentation |
