# tdl model

`proto/unmango/**` is generated from the [tdl](https://github.com/UnstoppableMango/tdl) model in `tdl/`.
Edit the `.tdl` files and regenerate; a hand edit to a generated `.proto` fails the `tdl-gen` flake check.
`proto/dev/unmango/**` is deprecated, not modelled, and stays hand-written.

## Regenerating

```sh
make tdl
```

It runs `tdl gen` over every file in `tdl/unmango`.
`tdl` comes from the dev shell, pinned by the `tdl` flake input.

Each target block's `out(...)` is relative to the `.tdl` file declaring it, so a file four directories below `tdl/` writes `out("../../../../../proto")`.

`proto/.tdl-output` lists every file tdl wrote, and is committed.
`tdl gen` overwrites and `tdl gen --clean` removes only the files it lists, so the hand-written `proto/dev` is left alone, and `tdl gen --verify` reports a listed file that no model generates any more.
A new generated file is added to the list by the run that first writes it.

`nix flake check` runs `tdl-check`, `tdl-fmt`, and `tdl-gen` over `tdl/`.
`tdl/tdl.toml` silences the loss warnings `tdl gen` prints for the `protobuf` target.
Each names something importing the protos back into tdl would not recover, and nothing here imports.
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

A shim is imported `as _`, and its own target block maps each type with `foreign(file, message)`, so an importer writes the reference as the external message and imports its file.
The fields a shim declares never reach the output; they go once tdl can import a `.proto` file directly ([tdl#1164](https://github.com/UnstoppableMango/tdl/issues/1164)).
`google.type.PhoneNumber` is `GooglePhoneNumber` in tdl because `unmango.people.contact.v1alpha1` declares its own `PhoneNumber`.

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
| [#1163](https://github.com/UnstoppableMango/tdl/issues/1163) | `tdl gen` prints a loss warning per fact import would not recover; `tdl/tdl.toml` allows the codes |
| [#1164](https://github.com/UnstoppableMango/tdl/issues/1164) | `tdl/shim/` re-declares the external messages the model references |
