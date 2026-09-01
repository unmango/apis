# AIP conformance

[Google's API Improvement Proposals](https://google.aip.dev) are the design rules googleapis is written against.
This repository adopts them as its default, and this file records where it does not and why.

An AIP that is neither adopted nor listed under [Declined](#declined) below is adopted by omission: nothing here overrides it, and a new file that violates it is a bug rather than a precedent.

## Scope

The rules apply to the life domains under `proto/unmango/<domain>/<package>/<version>/`, the 42 files carrying `google.api.resource` annotations.

They do not apply to the infrastructure APIs, `unmango.cli`, `unmango.cmd`, `unmango.protofs`, and `unmango.discord.backup`.
Those define services over a filesystem, a process, a command line, and a Discord export.
None of them models a resource with an identity, a lifecycle, or a name, so the resource-oriented AIPs have nothing to say about them.
[README.md](../README.md) already states that they follow none of the life-domain conventions; this is the same boundary drawn against AIP.

The deprecated `dev.unmango.*` namespace is out of scope in full.

## Adopted

**AIP-126, enum values.**
Every enum opens on `<NAME>_UNSPECIFIED = 0`, across 97 enums in the life domains, no exceptions.

**AIP-142, time fields.**
Timestamps are `google.protobuf.Timestamp` and their field names end in `_time`.

**AIP-143, standardized codes.**
A field carrying a value from a standard registry uses the standard name for it: `mime_type`, `language_code`, `currency_code`.

**AIP-148, standard fields.**
`name`, `uid`, `display_name`, `labels`, `annotations`, `create_time`, `update_time`, and `delete_time` mean what AIP-148 says they mean, and occupy fixed slots in the identity band described in [README.md](../README.md).
`uid` is a UUID4 and declares that with `google.api.field_info`.

**AIP-158, pagination.**
List and walk RPCs take `page_size` and `page_token` and return `next_page_token`.
Numbered pages are not used anywhere.

**AIP-191, file structure.**
One package per file path segment, one API version per directory, messages before top-level enums, services before messages.

**AIP-203, field behavior.**
`google.api.field_behavior` is set on every field whose behavior is not the default: `IDENTIFIER` on a resource name, `OUTPUT_ONLY` on observed state, `IMMUTABLE` on identity, `OPTIONAL` and `REQUIRED` on request fields.
The annotation is what makes the field bands machine-readable rather than a comment convention.

**AIP-213, well-known types.**
`google.type.Money`, `Date`, `Interval`, `PostalAddress`, and `LatLng` are used in place of hand-rolled scalar pairs.

**AIP-216, states.**
A lifecycle enum is named `<Resource>State`, not `<Resource>Status`.

**AIP-122 and AIP-123, resource names and types.**
Every resource carries a `google.api.resource` option whose `type` is `<package>/<Kind>` and whose `pattern` is the plural collection segment followed by the identifier, `accounts/{account}`.
`singular` and `plural` are declared explicitly rather than left to be guessed from the type.

**AIP-154, AIP-155, and AIP-134 are reserved rather than adopted.**
`etag`, `request_id`, and `update_mask` all belong on write RPCs, and the life domains deliberately define none.
[docs/reviews/api-conventions.md](./reviews/api-conventions.md) records the slots each one will take when the service layer lands.

## Declined

Each of these is an AIP the repository declines, for a reason it already committed to elsewhere.

**AIP-122, references as typed messages rather than strings.**
AIP carries a reference as a plain `string` annotated with `google.api.resource_reference`.
This repository carries it as a `unmango.ref.v1alpha1.ObjectReference`, a message of `api_version`, `kind`, `name`, and an optional `uid` pin.
The `resource_reference` annotation is still applied, so the target type is still declared and still checkable; only the wire shape differs.
The reason is the graph: a reference here addresses a resource in another independently versioned package with no shared name space to resolve a bare string against, and pinning a `uid` is what keeps a deleted-and-recreated name from silently re-pointing.
This is the Kubernetes `OwnerReference` shape, and [docs/reviews/ref-pattern-and-cohesion.md](./reviews/ref-pattern-and-cohesion.md) argues both sides of it at length.

**AIP-127, HTTP annotations.**
`google.api.http` exists to let a gRPC service also answer REST calls.
There are no REST consumers of this surface and no plan for any.

**AIP-131 through AIP-135, standard methods.**
The life domains define no CRUD services at all; the service layer is a design pass of its own, deferred until the resource graph settles.
Three read-only graph services exist, `vcs.commit` `CommitService`, `codegen.artifact` `ArtifactService`, and `pki.certificate` `CertificateService`, and they address content-addressed nodes by digest rather than by name.
A `Commit` has no `name` field because a revision already is a stable unique identifier, so `GetCommitRequest` cannot take one.

**AIP-140, prepositions in field names.**
`covered_by`, `resolved_into`, `played_on`, and `blocked_by_subtasks` are the domain's own vocabulary, and the direction of the relationship is the whole content of the name.
Dropping the preposition loses it.

**AIP-122, the `_name` suffix.**
The flagged fields, `branch_name`, `person_name`, `common_name`, hold a literal name in an external system rather than a resource name in this one.
`common_name` in particular is the X.509 field's own name.

**AIP-146, `google.protobuf.Any`.**
Used only by the Discord backup schema, which is out of scope.

**AIP-191, `java_package`, `java_outer_classname`, `java_multiple_files`, and proto3 syntax.**
File options are set by buf managed mode in [buf.gen.yaml](../buf.gen.yaml) rather than written into the protos, which is what keeps 60 files from carrying three generator options each.
The syntax rule asks for proto3; these files are edition 2024, which postdates the rule.

**AIP-192, a comment on every field.**
Documentation here is written at the message and section level, with the domain narrative in [README.md](../README.md).
A comment on each of the several thousand fields and enum values would mean a line of prose above every repetition of the identity band.

**AIP-215, foreign type references.**
`unmango.ref` and `unmango.uom` are shared vocabularies every life domain imports on purpose, and `k8s.io.apimachinery` `OwnerReference`, `LabelSelector`, and `Condition` are vendored deliberately.
That every domain reaches outside its own package for them is the design.

**AIP-121, reference cycles.**
`Task -> Task`, `Repository -> Repository`, `Schema -> Schema`, and `JobRun -> JobRun` are self-nesting resources: a subtask, a fork, an imported schema, a retried run.
The cycle is the model.
