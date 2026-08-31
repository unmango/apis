# Ref pattern and cohesion review

A third pass over the proto surface, focused on the questions the first two
did not ask directly: whether `unmango.ref` is the right mechanism at the
scale it is now used, where the schema creates friction for a caller, and how
the result reads against Cloudflare's public API and googleapis.
No proto files were changed in producing this review.

Scope: all 63 protos under `proto/`, plus `README.md` and `AGENTS.md`.
Baseline: `feat/life-domain-apis`, commit `733cf7d`.

Several recommendations from
[api-conventions.md](./api-conventions.md) and
[domain-modeling.md](./domain-modeling.md) have since landed and are treated
here as settled: `google.api.field_behavior` now appears in all 42
life-domain files, `productivity.capture` `CaptureItem` carries the third
identity-band variant, and the watch RPCs accept a resume token.

## Verdict

The ref pattern is the right call for cross-domain edges and the wrong one for
the roughly 85% of fields where it is currently used.
Everything else is unusually disciplined; the friction is concentrated in four
concrete places.

## Does the ref pattern make sense?

Yes as a boundary mechanism, no as a default field type.

The good part is real: zero domain-to-domain proto imports across 13 domains,
verified by grep.
Cross-domain facts travel as data.
That is an anti-corruption boundary enforced by the schema rather than by
discipline, and it is why `record.note` `Note.links` and
`productivity.capture` `CaptureItem.resolved_into` can reach anywhere without
any package knowing notes exist.

The problem is that `ObjectReference` is fully polymorphic
(`api_version` + `kind` + `name`) and is used in 171 places, almost all of
which are monomorphic.
The comments prove it:

```proto
// The people.contact Contact attending.
ref.v1alpha1.ObjectReference attendee = 11;

// The calendar.event Event booked to do the work.
ref.v1alpha1.ObjectReference scheduled_event = 44;
```

The schema already knows the target kind.
It is stated in English above the field and then discarded at the type level.
Genuinely polymorphic slots number about six: `asset.maintenance`
`WorkOrder.subject`, `Note.links`, `CaptureItem.resolved_into`,
`productivity.review` `Review.highlights`, `health.measurement`
`Measurement.source_device`, and `vcs.repository` `Grant`'s owner.

Kubernetes reached the same conclusion the hard way.
`core/v1.ObjectReference` is deprecated in the API conventions document
precisely because untyped references cannot be validated, and single-kind
slots use `LocalObjectReference` or a bare name string (`Pod.spec.nodeName`,
`secretName`).
googleapis never carries the type on the wire at all: a plain `string` field
plus `google.api.resource_reference` naming the allowed type, which linters,
generated docs, and SDKs all read.

Two further gaps in `ObjectReference` itself:

- **No `uid`.**
  Every resource has one, but a reference cannot pin it.
  The Kubernetes `OwnerReference` carries `uid` specifically because
  name-based references silently re-point when a resource is deleted and
  recreated under the same name.
- **`resource_version` pins a target version that no resource publishes.**
  Only three `resource_version` fields exist outside `ref`, and all three are
  watch-resume tokens rather than resource fields.
  Nothing in the graph carries a write-history version to pin against, so the
  field is currently unfillable.

`DeletePropagation` has zero uses anywhere in the repository.
That is expected while the service layer is deferred, since it belongs on a
Delete RPC that does not exist yet, but it is worth a note in the file saying
so.

## Friction points, ranked

### 1. All 801 `features.field_presence = EXPLICIT` annotations are no-ops

In edition 2024, explicit presence is already the default for singular fields.
This was verified empirically rather than from memory: dropping the annotation
from a scratch edition-2024 field produces no `buf breaking` finding, while
changing it to `IMPLICIT` produces
`changed cardinality from "optional with explicit presence" to "optional with implicit presence"`.

The annotation is being used as a documentation convention meaning "optional,"
but it generates nothing, and it actively misleads.
`compute.host` `Host.provider` carries no annotation and `Host.location` does,
both `ObjectReference`, and a reader reasonably infers a difference that does
not exist.
45 `ObjectReference` fields carry it, 59 do not.

`google.api.field_behavior = OPTIONAL` / `REQUIRED` states the intended
meaning, is machine-readable, and the import is already present in every file.

### 2. The watch RPCs accept a resume token but never emit one

`WatchCommitsRequest`, `WatchArtifactsRequest`, and `WatchCertificatesRequest`
all take a `resource_version`.
None of the three responses returns one, and there is no bookmark event type.
A client has no way to learn the value it is meant to resume from.
Kubernetes solves this with `BOOKMARK` events plus a version on each object;
one field on the response plus one enum value closes it.

### 3. `unmango.cli` and `unmango.cmd` break the namespace's own rules

They sit in the life-domain namespace but are infrastructure APIs.
They are undocumented in `README.md`, which covers every other package.
They define RPC services in a namespace whose stated policy is that the life
domains define no services yet.
`proto/unmango/cmd/v1alpha1/cmd.proto` imports
`unmango/cli/v1alpha1/cli.proto`, the only cross-package import in
`unmango/*` outside `ref` and `uom`.
Meanwhile `dev.unmango.cli` and `dev.unmango.cmd` cover overlapping ground at
`v1alpha1` and `v1alpha2`.
These read as pre-redesign survivors the reorganization missed.

### 4. `CaptureItem`'s human-driven fields are marked `OUTPUT_ONLY`

The file argues correctly that nothing reconciles a capture, and reserves
6, 7, 50, and 51 on that basis.
But `status`, `resolved_into`, `triaged_time`, and `discard_reason` are all
`OUTPUT_ONLY`, and triage is explicitly described as a human choice made
through a client.
With no controller and no `Triage` RPC, nothing can legally write them.
Either they are ordinary input fields, or the domain owes itself a `Triage`
RPC that sets them.

### 5. `ResourceQuantity` sits in the wrong package

`ref` is documented as the relationship vocabulary and `uom` as the value
vocabulary, "and the two vocabularies grow independently."
`ResourceQuantity` is a value, used by exactly two domains (`compute.host`,
`ci.runner`), and lives in `ref`.
It is the one type in that file that is not a reference.

## Cohesion

Strong, with one structural cost worth naming.

The identity band is repeated across 89 resources, roughly nine fields plus
annotations each, so about 800 of the 12,119 proto lines are the same block
copied.
`README.md` frames this as deliberate, borrowing Kubernetes relationships
rather than its `ObjectMeta`/`spec`/`status` layout, and flat resources do
match googleapis.
But googleapis flattens three or four fields, not nine, and every future band
change is an 89-site edit.
That is a live cost rather than a hypothetical one: `field_behavior` had to be
applied 89 times, and the third band variant had to be hand-reasoned per file.

What holds up:

- The `>>` archetype for content-addressed nodes (`vcs.commit` `Commit`,
  `codegen.artifact` `Artifact`, `pki.certificate` `Certificate`) is a real
  modeling contribution.
  Neither Kubernetes nor AIP has an answer for a node that declares nothing,
  and the repository named it instead of stretching ownership to fit.
- `health.nutrition` `Nutrients` is computed identically at four altitudes,
  `people.contact` `Contact` is referenced from 13 points across 9 domains
  without any of them owning it, and `compute.platform` `Platform` replaced
  four separate vendor enums.
  That is a value-object library and two generic subdomains behaving the way
  the tactical patterns describe.
- Every enum opens on `_UNSPECIFIED = 0`, across roughly 60 enums, no
  exceptions.
- The vendor-enum test in `README.md` is applied consistently, including the
  subtle case: `codegen.converter` `InvocationKind` stays closed because it
  names a mechanism a caller branches on in code, while the RPC framework
  behind `INVOCATION_KIND_RPC` stays an open string.

## Against Cloudflare and googleapis

| | Cloudflare | googleapis | unmango/apis |
|---|---|---|---|
| Reference typing | ids in the URL path | `string` + `resource_reference` | untyped `ObjectReference` on the wire |
| Resource type registry | OpenAPI schema | `google.api.resource` | none, `kind` is convention only |
| Pagination | numbered pages | `page_token` | `page_token`, matches AIP-158 |
| Optimistic concurrency | ETag header | `etag` (AIP-154) | absent, zero occurrences |
| Timestamps | varies | `create_time` + `update_time` (AIP-148) | `create_time` + `delete_time`, no `update_time` |
| Field semantics | OpenAPI `readOnly` | `field_behavior` | `field_behavior`, adopted everywhere |

Two rows are worth acting on before the service layer lands.
There is no `update_time` anywhere, which AIP-148 treats as mandatory and
which any list sorted by recency needs.
And `google.api.resource` is the missing piece that would make the ref pattern
verifiable: annotate each resource with a type string, annotate each reference
field with `resource_reference`, and the 171 English comments naming target
kinds become something a linter can check.

The deliberate divergences hold up.
A flat `ObjectReference` rather than AIP-122 hierarchical paths is correct for
a graph rather than a tree.
Cursor pagination rather than Cloudflare's page numbers is the more durable
choice.
Omitting `google.api.http` is right until REST consumers exist.

## Sources

Findings are grounded in direct reads of every file under `proto/`, plus
`README.md`, `AGENTS.md`, `buf.yaml`, and both prior reviews; full-repo counts
of `ObjectReference`, `ParentReference`, `DeletePropagation`,
`ResourceQuantity`, `features.field_presence`, `field_behavior`,
`google.api.resource`, `etag`, `update_time`, `resource_version`, and every
`^import` line under `proto/unmango/`; and an empirical `buf breaking` check
of edition 2024 presence defaults against a scratch module.
