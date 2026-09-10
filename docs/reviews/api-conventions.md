# API conventions review

Comparison of the `unmango.*` and `dev.unmango.*` proto surface against the
conventions used by Cloudflare's public API, googleapis (Google AIP), and
Kubernetes.
No proto files were changed in producing this review.

Scope: `proto/unmango`, `proto/dev/unmango`.
Baseline: `feat/life-domain-apis`, commit `cf63a03`.

## Six things the public surfaces agree on

Cloudflare, googleapis, and Kubernetes disagree on almost everything at the
wire level, REST envelopes versus gRPC versus declarative reconciliation, but
converge on the same six underlying habits.

| Habit | Cloudflare | googleapis (AIP) | Kubernetes | unmango/apis |
|---|---|---|---|---|
| Pagination | page + per_page (numbered) | page_size / page_token (AIP-158) | limit / continue token | page_size / page_token / next_page_token |
| Zero-value enums | n/a, JSON strings | FOO_UNSPECIFIED = 0 (AIP-126) | "" empty string default | \<ENUM>\_UNSPECIFIED = 0, no exceptions |
| Field semantics | readOnly / writeOnly (OpenAPI) | google.api.field_behavior | spec vs. status split | field-number bands only, undeclared |
| Optimistic concurrency | ETag header | etag field + AIP-154 | metadata.resourceVersion | absent on resources; present on references |
| Idempotent writes | Idempotency-Key header | request_id field (AIP-155) | n/a, PUT is inherently idempotent | n/a, no Create RPCs exist yet |
| Structured errors | { code, message } array | google.rpc.Status + ErrorInfo | Condition{type,status,reason,message} | Condition for state; plain gRPC status for RPC errors |

## Already holding the line

The life domains were deliberately redesigned around the Kubernetes resource
graph rather than AIP-style CRUD, commit `360704e` stripped every
Get/List/Create/Update/Delete/Watch quintet out of the domain packages.
What's left already tracks the surviving conventions closely.

**Cursor pagination, not page numbers.**
`ListCommitsRequest/Response`, `CompareCommitsRequest/Response` use opaque
`page_token` / `next_page_token` pairs.
This is the AIP-158 shape, and it's the one Cloudflare itself is migrating
toward on newer endpoints, numbered pages break under concurrent inserts,
cursors don't.

**Enum zero-values, with zero exceptions.**
Every enum checked, `AccountType`, `CommitKind`, `PlaybackPhase`,
`Visibility`, a dozen more, opens on `<NAME>_UNSPECIFIED = 0`.
That discipline is what AIP-126 asks for and what most hand-written protos
drift away from within a year.

**Well-known types over ad hoc scalars.**
`google.type.Money`, `Date`, `Interval`, `PostalAddress`, `LatLng` appear
throughout `finance` and `asset` in place of raw `string`/`double` pairs, the
same library AIP-213 standardizes on, already a transitive dependency via
`buf.build/googleapis/googleapis`.

**A fifth relationship Kubernetes never needed.**
Four of the five relationship archetypes map onto controller reconciliation.
The fifth doesn't, and the repo names it as its own thing rather than
forcing a fit:

```
Commit >> Commit          // parents, ordered
Artifact >> Artifact      // inputs, ordered
```

Both get a field-band variant (`1-9` content-addressed identity, `50+`
derived) and a read-only service, `CommitService`, `ArtifactService`,
because nothing about a content-addressed node is ever declared.
Naming this as a distinct archetype instead of stretching ownership
semantics to cover it is the kind of modeling call the public schemas above
don't have an answer for at all.

**References travel as data, not imports.**
Every cross-domain pointer is a `ref.v1alpha1.ObjectReference`
(`api_version`/`kind`/`name`/`namespace`/`resource_version`) rather than a
proto `import` of another domain, confirmed by grep, zero domain-to-domain
imports exist.
This is the flatter Kubernetes `OwnerReference` shape rather than AIP-122's
hierarchical `parents/{id}/children/{id}` path, chosen on purpose.

## Worth adding, ready now

Three gaps that cost little because the machinery is already present:
`buf.build/googleapis/googleapis` is already a dependency, and each of
these slots into a convention the repo already half-follows.

1. **Annotate the field bands, don't just document them.**
   The 1-9 / 10-39 / 40-49 / 50+ identity/desired/assigned/observed
   convention is real and consistently applied, but it lives only in
   comments and README prose.
   `google.api.field_behavior` would make it machine-readable:
   `OUTPUT_ONLY` on every field 50+, `IMMUTABLE` on identity fields like
   `Account.name`, `Commit.revision`, `Artifact.digest`.
   Generated docs, linters, and SDKs all read this annotation today; none
   of them can read a comment.

1. **Give Watch a resume point.**
   `WatchCommitsRequest` takes a `selector`, a `repository`, and
   `watch_refs`, but no starting `resource_version` or bookmark.
   A client that drops its stream has to replay from nothing.
   Kubernetes Watch, which this repo mirrors everywhere else, solves
   exactly this with a resume token; it's a one-field addition here.

1. **Write down the version-coexistence policy.**
   `protofs/fs`, `dev.unmango.cmd`, and `discord/backup` all currently ship
   `v1alpha1` and `v1alpha2` side by side.
   AGENTS.md's guidance for picking the canonical one is "check git
   history", workable for one maintainer, not for anyone else.
   A short written policy plus `option deprecated = true` on the superseded
   package replaces archaeology with a file you can read.

## Worth reserving, once CRUD lands

The life domains deliberately defer their service layer, "a design pass of
its own," per the README.
These four don't need action now, but each has a known slot to fill when
that pass starts, so it's cheaper to name them now than to retrofit later.

1. **A resource's own version, alongside its reference's.**
   `ObjectReference.resource_version` already exists, but it pins what a
   pointer refers to, not what an `Account` or `Repository` carries about
   its own write history.
   Update RPCs will need the latter for compare-and-swap, the same job
   `metadata.resourceVersion` does on every Kubernetes object.

1. **Reserve `update_mask` for partial updates.**
   AIP-134's standard shape, an `UpdateFooRequest` carrying the resource
   plus a `google.protobuf.FieldMask`, has no analogue here yet, because
   there's no Update RPC to carry it.
   Worth designing in from the first draft rather than bolting on.

1. **Reserve `request_id` for idempotent creates.**
   The proto-native version of Cloudflare's `Idempotency-Key` header and
   Stripe's idempotency keys: a client-generated `request_id` on
   `CreateFooRequest` so a retried call after a dropped response doesn't
   double-create.
   AIP-155.

1. **Grow `TestConverter`'s failures into a taxonomy.**
   `TestConverterResponse` already returns flat failure strings on purpose,
   the repo's own comment calls it "one undifferentiated check deep so
   far."
   When that changes, `google.rpc.ErrorInfo`'s reason/domain/metadata shape
   is the standard place to put the structure, rather than inventing one.

## Considered, and left alone

Three patterns the public surfaces lean on that don't belong here, named
explicitly so the gap above reads as a choice, not an oversight.

- **AIP-122 hierarchical resource names.**
  `parents/{id}/children/{id}` paths would fight the flat `ObjectReference`
  model the repo already committed to, and buys nothing a `kind` + `name`
  pair doesn't already give it.
- **Cloudflare-style numbered pagination.**
  Already covered above, the repo's cursor tokens are the more durable
  pattern; adopting page numbers would be a regression, not an improvement.
- **REST/OpenAPI transcoding.**
  `google.api.http` annotations exist to let a gRPC service also answer
  REST calls.
  Nothing about this surface suggests public REST consumers are a goal;
  add it if that changes, not before.

## Sources

Findings are grounded in direct reads of `README.md`, `buf.yaml`,
`commit.proto`, `account.proto`, `ref.proto`, `fs.proto`, plus a full-repo
grep for `field_behavior`, `google.api.resource`, `google.api.http`,
`longrunning`, `etag`, `resource_version`, `FieldMask`, `google.rpc`, and
`deprecated` across every domain.
