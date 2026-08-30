# unmango/apis

[![CI](https://github.com/unmango/apis/actions/workflows/ci.yml/badge.svg)](https://github.com/unmango/apis/actions/workflows/ci.yml)
[![Buf CI](https://github.com/unmango/apis/actions/workflows/buf.yml/badge.svg)](https://github.com/unmango/apis/actions/workflows/buf.yml)
[![protobuf](https://img.shields.io/badge/protobuf-edition%202024-4285F4)](https://protobuf.dev)
[![buf.build](https://img.shields.io/badge/buf.build-unmango%2Fapis-0C3CF5)](https://buf.build/unmango/apis)

Public API definitions.
Published at [`buf.build/unmango/apis`](https://buf.build/unmango/apis), though publishing is paused: the `k8s.io/apimachinery` imports have no BSR module behind them, and `buf push` rejects a module whose dependencies are not themselves named BSR modules.

## APIs

The `unmango.*` life-domain APIs below take their design from the relationships between resources in the Kubernetes resource graph, not its `ObjectMeta`/`spec`/`status` layout.

Every field describes a class of thing, never a specific instance of one.
`RunnerPlatform`, `HostProvider`, `Forge`, and `VersionControlSystem` used to be closed enums naming individual products, GitHub, GitLab, AWS EC2, baked into the schema; they became `compute.platform` `Platform`, data pointed at by `ObjectReference`, because a schema change should never be required just to add a vendor.
An enum stays fine for a genuinely closed set of categories, `PlatformKind`, `AccountType`, since a category is the class, not an instance of one.
The test: would adding a new product, vendor, or other specific real-world entity require a proto change?
If yes, it belongs in data behind an `ObjectReference`, not in the schema.

Five archetypes recur across the domains.

| Notation | Archetype | Analogue |
|---|---|---|
| `->` | Ownership and expansion. A parent materializes children that carry `owner_refs` back and cascade on delete | Deployment -> ReplicaSet -> Pod |
| `~>` | Attachment. A child names a parent it was authored independently of, and the parent admits or rejects it | Gateway -> HTTPRoute |
| `=>` | Selector membership. A resource claims a set by label rather than naming members | Service -> Pods |
| `@` | Binding. A pending resource is assigned to a capacity provider | Pod -> Node |
| `>>` | Immutable DAG edge. The target predates the source, the edge is fixed at creation, and nothing cascades | a git commit's parent |

The fifth is used by `vcs.commit` and `codegen.artifact`, and is worth calling out because it is the one relationship Kubernetes has no answer for.
The other four all describe a controller reconciling declared state against observed state.
A commit declares nothing: it is content-addressed, immutable, and its parent edge is part of what the identity hashes over.
A generated artifact is the same shape, with its inputs in place of parents.
That is why both carry a reduced identity band and a read-only service, documented in the files themselves.

Each API group is versioned independently and imports no other domain.
Relationships cross domain boundaries as `ObjectReference` string coordinates, never as proto imports.
The shared vocabulary is [`unmango/ref`](./proto/unmango/ref) for relationships and [`unmango/uom`](./proto/unmango/uom) for units of measure, plus three types vendored from Kubernetes `apimachinery` (see [`nix/apimachinery.nix`](./nix/apimachinery.nix)).

Every kind uses the same field number bands: `1-10` identity, `11-39` templated desired state, `40-49` assigned desired state, `50+` observed state.
The identity band is positional, so a number means the same thing on all 91 kinds:

| | | | |
|---|---|---|---|
| 1 `name` | 2 `uid` | 3 `display_name` | 4 `labels` |
| 5 `annotations` | 6 `owner_refs` | 7 `generation` | 8 `create_time` |
| 9 `update_time` | 10 `delete_time` | | |

`hack/check-field-bands.py` enforces all of this as the `field-bands` flake check, since the band is a convention rather than a shared type and nothing else would catch a kind that drifts off it.

Immutable nodes fill 1, 2, 4, 5, and 8 and `reserved` the rest rather than compacting around the gaps, so `4` is still `labels` on a `Commit`.
Field `1` holds the content address, `revision` or `digest` or `fingerprint`, in place of a name, and `11-39` holds content fixed at creation rather than declared state.
`vcs.commit` `Commit` reserves `2` as well, since a content hash already is a stable unique identifier, and puts `commit_time` in the `create_time` slot because for a commit they are the same fact.
Their `50+` band is derived by whoever indexes the graph rather than observed by a controller, and they carry no `update_time`: a content-addressed node is never written twice.

The bands are declared, not just documented.
`google.api.field_behavior` marks `OUTPUT_ONLY` on observed state, `IMMUTABLE` on identity, and `OPTIONAL` on a field a caller may leave unset.
That last one replaces `features.field_presence = EXPLICIT`, which said nothing: explicit presence is already the default for singular fields in edition 2024, so the annotation generated no difference and its uneven application implied a distinction that did not exist.

Every kind carries a `google.api.resource` option naming its type, and every reference field a `google.api.resource_reference` naming what it may point at.
The type string is the `ObjectReference` coordinates it stands in for, `unmango.people.contact/Contact`, so a linter can check what previously lived only in the comment above the field.
The handful of fields that genuinely accept anything, `record.note` `Link.target`, `productivity.capture` `CaptureItem.resolved_into`, `asset.maintenance` `WorkOrder.subject`, use the `"*"` wildcard rather than a false narrowing.
The life domains deliberately define no CRUD services; the service layer is a design pass of its own, deferred until the resource graph settles.
The exceptions are the read-only graph services on the content-addressed nodes, `vcs.commit` `CommitService` and `codegen.artifact` `ArtifactService`, whose Get/List/Watch and traversal RPCs are part of how those graphs are meant to be read, plus `ConverterService.TestConverter`, a bare conformance check.
Their Watch RPCs take a `resource_version` to resume from and return one on every event, including a `BOOKMARK` event that advances an idle stream's resume point, so a client that drops its stream never replays from nothing.

Two or more fields standing in for one conceptual slot use `oneof` (`ci.job` `Trigger.actor`, `media.playback` `PlaybackSession.played_on`), never independent optional fields a caller has to know are mutually exclusive by convention alone.
A single field meaningful only for one enum value skips `oneof`: `UNIT_CUSTOM` paired with `custom_unit` is that pattern, since a `oneof` of one member buys nothing.
`oneof` members carry no optionality annotation of their own, and `repeated` fields can never join one.

### ref

[`proto/unmango/ref`](./proto/unmango/ref)

Relationship vocabulary shared by every life-domain API.

- `ObjectReference`: addresses any resource by api_version/kind/name, optionally pinned to a `uid` so a reused name cannot silently re-point it
- `ParentReference`: names an attachment parent
- `DeletePropagation`: cascade behavior along owner references, defined ahead of the Delete RPC that will carry it

Ownership, selection, and status reporting come from vendored `k8s.io.apimachinery.pkg.apis.meta.v1`: `OwnerReference`, `LabelSelector`, `Condition`.

### uom

[`proto/unmango/uom`](./proto/unmango/uom)

Measurement vocabulary shared by every life-domain API.
Kept separate from `ref`: `ref` addresses relationships between resources, `uom` carries the values attached to them.

- `Unit`: mass, volume, distance, and other measurement units
- `Quantity`: a value paired with its `Unit`, with a `custom_unit` fallback for a portion size no fixed unit covers
- `ResourceQuantity`: compute capacity shared by `compute.host` and `ci.runner`, with its units fixed in the field names since nobody asks for memory in pounds

Together, `ref` and `uom` are the only packages a life-domain API imports.

### calendar

[`proto/unmango/calendar`](./proto/unmango/calendar)

```
RecurringEvent -> Event @ asset Space
                    ^~ Attendance ~> people Contact
```

- `event`: `RecurringEvent`, `Event`, `Attendance`

### finance

[`proto/unmango/finance`](./proto/unmango/finance)

```
Institution -> Account
Budget -> BudgetPeriod -> Allocation => Transaction
Budget -> BudgetRevision >> BudgetRevision
RecurringTransaction -> Transaction ~> Account
```

- `account`: `Institution`, `Account`
- `budget`: `Budget`, `BudgetPeriod`, `Allocation`, `BudgetRevision` (read-only)
- `transaction`: `RecurringTransaction`, `Transaction`

### asset

[`proto/unmango/asset`](./proto/unmango/asset)

```
Property -> Space
Vehicle @ Space,  Vehicle -> OdometerReading
MaintenancePlan ~> {Vehicle | Property | Space | Host} -> WorkOrder -> ServiceRecord
```

- `property`: `Property`, `Space`
- `vehicle`: `Vehicle`, `OdometerReading`
- `maintenance`: `MaintenancePlan`, `WorkOrder`, `ServiceRecord`

### media

[`proto/unmango/media`](./proto/unmango/media)

```
Title -> Title -> Edition
Library => LibraryItem @ Edition,  Collection => Title
PlayState ~> Title -> PlaySession
```

- `title`: `Title`, `Edition`
- `library`: `Library`, `Collection`, `LibraryItem`
- `playback`: `PlayState`, `PlaySession`

### music

[`proto/unmango/music`](./proto/unmango/music)

```
Artist -> Artist                    (aliases)
Artist ^~ Membership ~> Artist
ArtistCredit ~> media.title Title
Playlist -> Playlist -> PlaylistEntry
```

- `artist`: `Artist`, `Membership`, `ArtistCredit`
- `playlist`: `Playlist`, `PlaylistEntry`

`media.title` already covers albums and tracks through `MediaKind`, holdings through `media.library`, and listening history through `media.playback` `PlaySession`.
This domain adds two things on top.

The first is the artist as a resource.
`media.title` `Credit` carries a bare `person_name` string, which is enough for a film's director and not enough for music, where the performer is the primary axis the catalog is browsed along.
`Artist` is the node that holds a band: a `people.contact` `Contact` is someone known personally, and a `Title` is a work.
`Artist` nests through owner references with `ArtistKind` naming the level, the same move `Title -> Title` makes: a pseudonym has no existence apart from the person behind it and cascades with them, while a side project that outlives the group that spawned it is a top-level Artist instead.

A `Membership` attaches to the group rather than being owned by it, which is the `calendar.event` `Attendance` shape.
People join several groups and leave them, and deleting a band should leave the record of having played in it standing.
An `ArtistCredit` attaches to a `media.title` `Title` for the same reason `media.playback` `PlayState` does: crediting an artist then needs no change to the catalog, and a Title that is deleted does not take the credit's history with it.

The second is order.
`media.library` `Collection` claims Titles by label selector, and that is the whole of what a collection is; a selector cannot express sequence.
So a `Playlist` owns a `PlaylistEntry` per track rather than selecting them.
A Playlist may still carry a `PlaylistSource`, but the source generates entries rather than being the membership, which keeps a rule-driven playlist and a hand-built one the same kind, differing only in who wrote the entries.

`PlaylistEntry.rank` is a string, not an integer position.
Under `ORDERING_STRATEGY_MANUAL` a caller inserting a track picks any value ordering between its new neighbors, so an insert rewrites one entry rather than every entry after it.
The derived `position` is reported as observed state, since under every strategy but MANUAL nothing declares it.

An entry names a `Title` rather than a `media.library` `LibraryItem`, so a playlist survives re-ripping and stays meaningful for tracks not held.
`prefer_edition` is how an entry asks for a particular remaster without naming the file that happens to hold it.

### health

[`proto/unmango/health`](./proto/unmango/health)

```
TrainingPlan -> Workout -> Activity
MealPlan -> Meal -> FoodEntry ~> Food
Goal => Measurement
```

- `training`: `TrainingPlan`, `Workout`, `Activity`
- `nutrition`: `MealPlan`, `Meal`, `FoodEntry`, `Food`
- `measurement`: `Measurement`, `Goal`

### compute

[`proto/unmango/compute`](./proto/unmango/compute)

```
Cluster => Host
```

- `host`: `Host`, `Cluster`
- `platform`: `Platform`

Capacity.
A `Host` is what work binds to, the Node of this design, and a `Cluster` claims Hosts by label rather than naming them.
Hosts also carry `asset.maintenance` plans, since a rack server needs servicing on the same terms as a car.

`Platform` is the kind the rest of the repository points at whenever a resource names an external system rather than declaring facts about one inline: a `vcs.repository` `Repository`'s forge and version control system, a `ci.runner` `Runner`'s CI system, a `Host`'s hosting provider, a `codegen.converter` `Converter`'s underlying tool.
It lives here rather than in a domain of its own because it plays the same role `Host` already does for `ci` and `vcs`: infrastructure other domains bind to or point at without owning.

One `Platform` per distinct product, not per vendor, since a `Repository`'s forge and a `Runner`'s CI system are different attachment points even when the same company operates both.
`Platform` replaces what used to be a closed enum on each of those domains (`RunnerPlatform`, `HostProvider`, `Forge`, `VersionControlSystem`), each of which baked a fixed vendor list into the schema itself and repeated every entry in every domain that named it.
`Platform` is data instead, created once and pointed at by `ObjectReference` from anywhere in the graph, the same pattern `people.contact` `Contact` uses for identity.

### ci

[`proto/unmango/ci`](./proto/unmango/ci)

```
RunnerPool -> RunnerSet -> Runner @ compute.host Host
Pipeline -> JobRun @ ci.runner Runner
```

- `runner`: `RunnerPool`, `RunnerSet`, `Runner`
- `job`: `Pipeline`, `JobRun`

The binding chain runs `JobRun -> Runner -> Host` and crosses into `compute` at its last hop, which is deliberate: capacity is modelled independently of what consumes it, so a Host can back CI today and something else later without `compute` knowing about CI at all.

### codegen

[`proto/unmango/codegen`](./proto/unmango/codegen)

```
ConverterRegistry => Converter
Schema -> TypeDef
Conversion -> ConversionRun @ ci.job JobRun -> Artifact
Artifact >> Artifact                          (inputs, ordered)
```

- `schema`: `Schema`, `TypeDef` (`TypeDef` read-only)
- `converter`: `Converter`, `ConverterRegistry`
- `conversion`: `Conversion`, `ConversionRun`
- `artifact`: `Artifact` (read-only)

Turning one representation into another.
A `Converter` declares what it accepts and produces and which tool it wraps; a `Conversion` declares what to run it on; a `ConversionRun` is one execution; an `Artifact` is what came out.

A `Schema` is the one kind here with genuine desired state: format, `source_uri`, and which repository the bytes are checked into are choices a caller makes.
Its `TypeDef`s are not.
They are facts about the bytes at `source_uri`, populated when something parses the `Schema`: there is nothing for a caller to declare and nothing to reconcile toward, the same reason an `Artifact` carries no desired state.

`ConversionRun` binds to a `ci.job` `JobRun` rather than to a `ci.runner` `Runner`.
`ci` already models a unit of work, its execution, and its placement on capacity, so the binding chain runs `ConversionRun -> JobRun -> Runner -> Host` and this domain owns only the first hop.
It is the same delegation `vcs.change` `Change` makes for its checks, and the same reason `ci` stops at `Host`.

Unlike `ci.job` `Pipeline`, a `Conversion` has no run template.
A Pipeline exists only to stamp JobRuns, so a template is all it carries; a Conversion carries the real specification and a `ConversionRun` snapshots it at creation.
That snapshot is what keeps a finished run reproducible after its Conversion is edited.

`Artifact` is the second immutable node in the repository, and the second use of `>>`.
It is content-addressed: its digest hashes over the bytes, the converter and version that produced them, and the digests of everything consumed, so its input edges are fixed at creation because they are part of what the identity covers.
A Nix derivation and a git commit are the same shape, which is why the field bands and the read-only service match `vcs.commit` rather than the mutable kinds.
Rebuilding from identical inputs yields the same node, and that is the point: it is what lets a `ConversionRun` resolve its `input_digest` against the graph and skip execution.

`ArtifactService` is where the graph is traversed.
`WalkInputs` streams the input closure, the derivation-graph equivalent of `WalkCommits`.
`WalkConsumers` walks the other way, from an artifact or an upstream source to everything built from it, which is the question the domain exists to answer: the schema moved, what regenerates.
`ResolveInputDigest` is the cache lookup performed before running anything.

Bytes are absent for the reason trees and blobs are absent from `vcs.commit`.
A generated SDK is a filesystem, so an `Artifact` exposes `tree_uri`, a `protofs` root, and reading generated output is an ordinary filesystem walk.

`Converter.entrypoint` says where a converter lives, not how it is called, so `invocation_kind` names the calling convention as a category: a plain CLI binary, a subprocess driven over stdin instead of argv, or an RPC method.
It stays a small closed enum, unlike `Schema.format` or `Port.format`, because it names a mechanism a caller must branch on in code, not a product a caller merely points at; the actual wire protocol behind `INVOCATION_KIND_RPC` is itself an open string on `RpcInvocation`, since which RPC framework a tool speaks is exactly the kind of fact that belongs behind a field, not a proto change.
A tool that discovers converters and executes them this way is the thing that resolves a `Conversion` to one of these entries and runs it, the same relationship a controller has to what it reconciles, so it sits outside the set of `Converter`s it resolves against.

`ConverterRegistry.selector` only claims Converters that already exist as declared resources.
`discovery` is what gets one declared in the first place: it names where to look, a filesystem directory or a repository's published releases, not a specific vendor's release mechanism, since a repository is the same forge-agnostic `vcs.repository` reference `Converter.repository` already uses.
Anything discovery finds is created and labelled per `converter_labels`, so it then joins through `selector` exactly like a hand-declared Converter would.

`TestConverter` asks a narrower question than running a real `Conversion` does: whether the converter still behaves the way its declaration claims, rather than whether converting some actual inputs succeeded.
That is why it is a bare RPC on `ConverterService` rather than another `Conversion` kind: a conformance run has no inputs worth keeping and produces no `Artifact`, so it leaves no trace beyond `Converter.last_conformance_time`.
`TestConverterResponse` carries a flat list of failure strings rather than a structured taxonomy because every real conformance suite this domain has a line on is one undifferentiated check deep so far; structure can follow once there is something to structure.

### iac

[`proto/unmango/iac`](./proto/unmango/iac)

```
ModuleRegistry => Module
Stack -> Run @ ci.job JobRun
Stack -> Resource
```

- `module`: `Module`, `ModuleRegistry`
- `stack`: `Stack`, `Run`
- `resource`: `Resource`

Infrastructure-as-code: Terraform, Pulumi, Ansible, Helm, plain Kubernetes manifests, or anything else that turns a declaration into provisioned infrastructure.
It follows the same declare/run/produce shape `codegen` already uses, since "declare a runnable thing, declare what to run it on, execute it, track output" is the same problem whether the output is generated code or a live resource.

A `Module` is one runnable unit: it declares where its source lives and which tool reads it, not what to run it against.
A `Stack` is that: this module, with these inputs, targeting this environment.
A `Run` is one execution of a `Stack` (a plan, an apply, or a destroy), and snapshots the `Stack`'s specification at creation, the same reproducibility guarantee `codegen.conversion` `ConversionRun` gives a `Conversion`.

`Run` binds `@` to a `ci.job` `JobRun` rather than modelling its own execution, the same delegation `codegen.conversion` `ConversionRun` makes: `ci` already models a unit of work, its execution, and its placement on capacity.
The binding chain runs `Run -> JobRun -> Runner -> Host`, and this domain owns only the first hop.

`Module.tool` points at a `compute.platform` `Platform` for the tool that reads it, the same pattern `ci.runner` `Runner` uses for its CI system and `vcs.repository` `Repository` uses for its forge: a closed enum of tools would bake a fixed vendor list into the schema and need extending every time a new one appeared.

`Resource` is owned by the `Stack` that provisions it, not by any single `Run`: a resource outlives any one plan or apply, and a `Stack` applies many times against the same resources.
It stays independent of `compute.host` `Host`.
An `iac`-managed resource that happens to be a VM is not folded into the capacity graph, since this domain models what was provisioned, not what work binds to it.

### pki

[`proto/unmango/pki`](./proto/unmango/pki)

```
CertificateRequest -> CertificateIssuance @ ci.job JobRun -> Certificate
Certificate >> Certificate                          (issuer chain)
```

- `issuer`: `Issuer`
- `certificate`: `CertificateRequest`, `CertificateIssuance`, `Certificate` (read-only)

Public-key infrastructure: certificate authorities, issuers, and the certificates they mint.
It follows the same declare/run/produce shape `iac` and `codegen` already use, since "declare a signing mechanism, declare what to issue, execute it, track output" is the same problem whether the output is provisioned infrastructure, generated code, or a signed certificate.

An `Issuer` names a signing mechanism, not a certificate: a self-signed root, an existing `Issuer`'s chain acting as an intermediate CA, an ACME account, or a Vault PKI secrets engine mount.
It does not declare what to issue, which is `CertificateRequest`'s job, the same split `codegen.converter` `Converter` draws from `codegen.conversion` `Conversion` and `iac.module` `Module` draws from `iac.stack` `Stack`.
`Issuer.config` is a `oneof` rather than a closed kind enum plus per-kind optional fields, the same shape `codegen.converter` `DiscoverySource` uses: each mechanism needs different fields, so a field meaningful only for one mechanism does not belong outside its `oneof` member.
`AcmeConfig.platform` points at a `compute.platform` `Platform` for the ACME server's specific provider, the same argument `Converter.platform` already makes: a closed enum of providers would bake a fixed vendor list into the schema.

`CertificateRequest` is the durable definition: these names, from this `Issuer`, with this policy.
`CertificateIssuance` is one signing attempt, owned by the request that materialized it, snapshotted at creation the same way `codegen.conversion` `ConversionRun` snapshots its `Conversion`, so a finished issuance stays reproducible after its request is edited.
It binds `@` to a `ci.job` `JobRun` rather than modelling its own execution, the same delegation `ConversionRun` and `iac.stack` `Run` make: the binding chain runs `CertificateIssuance -> JobRun -> Runner -> Host`, and this domain owns only the first hop.

`Certificate` is the third use of the `>>` archetype, alongside `vcs.commit` `Commit` and `codegen.artifact` `Artifact`: a signed certificate is immutable once minted, reissuing produces a different one, and `issuer_fingerprint` is fixed at creation because the issuing certificate's identity is part of what a conforming chain-of-trust covers.
Private key material is deliberately absent, the same reason commit bytes are absent from `vcs.commit` and generated bytes are absent from `codegen.artifact`: `material_uri` is a `dev.unmango.protofs` root, and reading or provisioning the actual PEM bytes is an ordinary filesystem operation this API does not restate.

### productivity

[`proto/unmango/productivity`](./proto/unmango/productivity)

```
RecurringTask -> Task -> Task
CaptureItem
FocusSession -> Interruption
Project => Task,  Project -> Project
Habit -> HabitLog
Review
```

- `task`: `RecurringTask`, `Task`
- `capture`: `CaptureItem`
- `focus`: `FocusSession`, `Interruption`
- `project`: `Project`
- `habit`: `Habit`, `HabitLog`
- `review`: `Review`

Getting things done, not merely declaring what should get done.
`task` used to live under `calendar`, but a deadline and a set of subtasks are an executive-function concern, not a scheduling one; `calendar` keeps only booked time, `RecurringEvent -> Event`, and everything about deciding and tracking work moved here.

`capture` exists because a `Task` asks too much of a thought the moment it arrives: a priority, a due date, whether it has subtasks.
`CaptureItem` asks nothing but the thought itself, so it is safe to let go of before any of those decisions are made.
Triage happens later, on the caller's own time, and turns a `CaptureItem` into a `Task`, a `calendar.event` `Event`, or a `record.note` `Note`, recorded on `resolved_into`, a plain pointer rather than a `->` edge, since nothing is owned or cascades.

`focus` is not another way to book time; `calendar.event` already does that.
A `FocusSession` is the after-the-fact record of what actually happened inside a block of work, planned duration against actual, energy before and after, and its owned `Interruption`s log each point attention slipped and why.
That is what makes a pattern visible, this time of day, this distraction source, this kind of task, instead of leaving it as a feeling nobody ever named.
`FocusSession.task` points at a `Task` the same way `Task.scheduled_event` points at an `Event`: a plain reference, not ownership, so a session can work untargeted, or a Task can be worked by several sessions over time.

`project` groups Tasks toward one outcome, the layer `task` has no answer for on its own: a `Task` can depend on other Tasks and nest into subtasks, but nothing organizes many of them toward a shared goal.
`Project` claims Tasks by selector rather than owning them, the same `Notebook => Note` relationship `record.note` uses, since a Task predates any Project it joins and leaving one deletes nothing.
Sub-projects nest through `owner_refs` like every other ownership edge in the repository.
A `Project` carries no priority or due time of day, those stay Task-level concerns; what it adds is the rollup, how many claimed Tasks exist and how many are done.

`habit` is not another `RecurringTask`.
`RecurringTask` materializes a full `Task`, due date, subtasks, dependencies, every period, and its `skip_missed` field even names the gap directly: "What a daily habit wants." That is too much for "did I meditate today," where there is no due date and nothing to triage, only whether it happened.
A `Habit` never materializes a `Task`; a `HabitLog` is created the moment the behavior happens, and `current_streak` is computed from the log history against a target frequency, not from completed occurrences of a generated child.
`Habit` and `HabitLog` follow `FocusSession` and `Interruption`'s shape, an owned child with a full identity band, rather than `CaptureItem`'s reserved-band shape, since a `HabitLog` genuinely is owned.

`review` is a periodic personal retrospective, deliberately as small as `journal.entry` `Entry`: no template, no container, one freeform record per period.
It is unrelated to `vcs.change` `Review`, a forge reviewer's verdict on a `Change`, the same English word reused across two packages the way `task`, `note`, and `goal` already are, disambiguated by full package path rather than an invented synonym.
Nothing owns or reconciles a `Review`, the same identity-band variant `CaptureItem` uses.
`highlights` points at whatever from the period is worth remembering, a Task completed, a FocusSession had, a Habit logged; `related_entry` points at the same-day `journal.entry` `Entry` rather than duplicating mood tracking here.

### vcs

[`proto/unmango/vcs`](./proto/unmango/vcs)

```
Repository -> Remote,  RepositoryGroup => Repository
Repository -> Branch -> Commit,  Repository -> Tag -> Commit
Repository -> Grant ~> people.contact Contact
Repository -> Composition                 (nests another vcs.repository Repository, pinned)
Commit >> Commit                          (parents, ordered)
ChangeSet -> Change ~> vcs.branch Branch
               ^~ Review ~> people.contact Contact
Change @ ci.job JobRun
Branch -> MergeQueue -> QueueEntry ~> Change
```

- `repository`: `Repository`, `Remote`, `RepositoryGroup`, `Grant`, `Composition`
- `branch`: `Branch`, `Tag`
- `commit`: `Commit` (read-only)
- `change`: `ChangeSet`, `Change`, `Review`
- `queue`: `MergeQueue`, `QueueEntry`

`Change` is forge-neutral: a pull request, a merge request, and a Gerrit change are one shape.
It attaches to its target `Branch` rather than being owned by it, and the branch admits or rejects it on its `Protection` rules.
Required approvals and required checks are the branch's terms, evaluated against a change the branch did not author.
This is the most literal Gateway -> HTTPRoute relationship in the repository.

A `ChangeSet` materializes one `Change` per target repository from a template, which is what a stacked or fleet-wide edit is: one intent, many proposals, tracked together with rollout progress.

`Branch` splits desired from observed unusually cleanly.
Protection rules are declared; the head commit is observed, because nobody declares where a branch points: they push, and the pointer moves.
`Tag` inverts this: its target is declared once, since a tag that moves is a bug.

`commit` models history as a graph.
A `Commit` is a node; `parent_revisions` are its outgoing edges, ordered so the first is the mainline.
`CommitService` is where the graph is traversed: `WalkCommits` streams from a set of tips with exclusions, path filters, and first-parent collapsing; `GetMergeBase` finds lowest common ancestors; `CompareCommits` returns ahead/behind divergence.
The service is read-only, because creating, editing, and deleting are not operations that exist for a content-addressed object.

Trees and blobs are deliberately absent.
A git tree is a filesystem, and this repository already models one, so a `Commit` exposes `tree_uri`, a `protofs` root, and browsing a commit is an ordinary filesystem walk rather than a second object model.

`Grant` is `owner_refs`-attached to either a `Repository` or a `RepositoryGroup`, reusing the kind-polymorphism `owner_refs` already carries everywhere else rather than adding two separate binding fields the way `ChangeSet` does for `repositories`/`repository_group`.
Its `role` is an open string rather than a closed enum, the same choice `codegen.schema` `Schema.format` made: GitHub, GitLab, and Gerrit each name their own permission tiers, and this repository does not execute logic against the value, only records and syncs it.

`Composition` nests one `Repository` inside another at a path, pinned to a fixed revision: a submodule, subrepository, or external, depending which VCS is asked.
It differs from `Repository.upstream`, which tracks a live head: a `Composition`'s `pinned_revision` moves only when the `Composition` itself is explicitly updated, never by activity in the nested repository, the same declared-versus-observed split `Tag.target_revision` already draws against `Branch.head_revision`.

`queue` sequences many `Change`s within one repository against one branch, where `change.ChangeSet` sequences one `Change` per repository across many repositories.
The two are complementary, not overlapping.
A `MergeQueue` owns the `Branch` it serializes, and a `QueueEntry` attaches to the queue the same way a `Change` attaches to its target `Branch`: authored independently, admitted or rejected on the queue's terms, batched with its neighbors and speculatively tested before merging.

### people

[`proto/unmango/people`](./proto/unmango/people)

```
Contact ~> Relationship ~> Contact,  Group => Contact
```

- `contact`: `Contact`, `Relationship`, `Group`

`Contact` is the identity anchor the rest of the repository points at whenever a person is involved: a calendar `Attendance` attendee, a compute `Trigger` actor, an asset `WorkOrder` assignee, a media `PlayState` viewer, a media `LibraryItem` borrower.

### record

[`proto/unmango/record`](./proto/unmango/record)

```
Notebook => Note -> Note
```

- `note`: `Notebook`, `Note`

`Note.links` is the generic edge into every other domain: a note can point at a `Transaction`, a `ServiceRecord`, or a `Title` without any of those packages knowing that notes exist.

### journal

[`proto/unmango/journal`](./proto/unmango/journal)

```
Entry
```

- `entry`: `Entry`

A personal, dated log, deliberately smaller than `record.note`: no `Notebook`-style `=>` container, since there is one continuous stream of entries rather than any need to group them, and no generic `Link` graph, since an entry's only cross-domain reach is two optional pointers, `author` at a `people.contact` `Contact`, for households where more than one person keeps entries, and `mood_measurement` at a `health.measurement` `Measurement`, for anyone who wants a quantified reading behind the coarse five-point `mood` recorded inline.
A `RecurringPrompt -> Entry` archetype, scheduled prompts that stamp out entries to answer, was considered and deferred: entries are freeform only for now.

`entry_date` is the day an entry is for, and the field callers order and range-query by; `create_time` is when it was actually typed, which may be later, a backfilled entry writes today with an `entry_date` from last week.
Nothing enforces one entry per day, the same way `record.note` allows more than one note in a day: this is a data model, not a business-rule engine.

### protofs

[`proto/dev/unmango/protofs`](./proto/dev/unmango/protofs)

Models the Go `io/fs` filesystem interface over gRPC.

- `FileService`: file-level operations (Read, Write, Stat, Truncate, Readdir)
- `FsService`: filesystem-level operations (Chmod, Create, Open, Remove, Rename, etc.)

### discord/backup

[`proto/dev/unmango/discord/backup`](./proto/dev/unmango/discord/backup)

Schema for a complete backup/snapshot of a Discord server (guild).
Captures everything needed to restore a server: structure, content, and configuration.

- `ServerBackup`: top-level backup message containing all guild data
- `Guild`, `Channel`, `Role`, `Member`, `User`: server structure
- `Emoji`, `Sticker`, `Webhook`, `Invite`: guild assets and access
- `ScheduledEvent`, `AutoModRule`: configuration
- `Message`, `Attachment`, `Embed`: message content

## Development

Requires [Nix](https://nixos.org/).
Enter the dev shell:

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
