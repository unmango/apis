# AIP conformance review

A fourth pass over the proto surface, measuring it against
[Google's API Improvement Proposals](https://google.aip.dev) rather than against
another public API's habits.
[docs/aip.md](../aip.md) is the policy this review measures against; this file is
the gap between that policy and the tree.

Scope: the 44 life-domain files under `proto/unmango`, the ones carrying
`google.api.resource` annotations plus the shared `ref` and `uom` vocabularies.
The infrastructure APIs (`cli`, `cmd`, `protofs`, `discord/backup`) are out of
scope for the reason [docs/aip.md](../aip.md) gives: none of them models a
resource.
Baseline: `main`, commit `61cc0c3`.

Method: `api-linter` 2.3.1 over a `FileDescriptorSet` built by `buf`, all rules
enabled, no config.
4,007 findings across 35 rules.

## Verdict

3,112 of the 4,007 findings, 78%, come from five rules, and all five are
decisions the repository has already made and defended in writing.
They collapse into five rule disables.

664 findings across 13 rules are worth acting on, and twelve of the thirteen
are mechanical: an annotation to add or a name to change.

The one that is not mechanical is the resource pattern: all 91 resources declare
`pattern: "{account}"` where AIP-123 wants `pattern: "accounts/{account}"`.

## The gap, by rule

| Rule | Findings | Files | Disposition |
|---|---|---|---|
| `0192::has-comments` | 2228 | 44 | decline |
| `0215::foreign-type-reference` | 408 | 42 | decline |
| `0122::resource-reference-type` | 166 | 38 | decline |
| `0123::resource-reference-type` | 166 | 38 | decline |
| `0192::only-leading-comments` | 144 | 44 | decline |
| `0123::resource-pattern-plural` | 91 | 42 | fix |
| `0123::resource-name-components-alternate` | 91 | 42 | fix |
| `0122::resource-collection-identifiers` | 91 | 42 | fix |
| `0148::uid-format` | 91 | 42 | fix |
| `0203::resource-name-identifier` | 87 | 40 | fix |
| `0203::field-behavior-required` | 65 | 4 | fix |
| `0140::prepositions` | 46 | 24 | decline |
| `0191::file-layout` | 45 | 41 | decline |
| `0191::java-multiple-files` | 44 | 44 | fix, in `buf.gen.yaml` |
| `0191::java-outer-classname` | 44 | 44 | fix, in `buf.gen.yaml` |
| `0191::java-package` | 44 | 44 | fix, in `buf.gen.yaml` |
| `0191::proto-version` | 44 | 44 | decline |
| `0132::request-unknown-fields` | 18 | 3 | decline |
| `0127::http-annotation` | 17 | 4 | decline |
| `0122::name-suffix` | 16 | 7 | decline |
| `0216::synonyms` | 7 | 7 | fix |
| `0123::resource-annotation` | 7 | 6 | decline |
| `0131::request-unknown-fields` | 7 | 3 | decline |
| `0142::time-field-type` | 6 | 6 | decline |
| `0143::standardized-codes` | 4 | 3 | fix |
| `0121::no-mutable-cycles` | 4 | 4 | decline |
| `0131::response-message-name` | 4 | 3 | decline |
| `0131::method-signature` | 4 | 3 | decline |
| `0123::resource-name-field` | 4 | 4 | decline |
| `0131::request-name-required` | 4 | 3 | decline |
| `0142::time-field-names` | 3 | 2 | fix |
| `0121::resource-must-support-get` | 3 | 3 | decline |
| `0140::reserved-words` | 2 | 2 | fix |
| `0158::response-repeated-first-field` | 1 | 1 | decline |
| `0158::response-plural-first-field` | 1 | 1 | decline |

## What to fix

### Resource patterns are missing their collection segment

91 resources, every one of them.
`Account` declares:

```proto
option (google.api.resource) = {
  type: "unmango.finance.account/Account"
  pattern: "{account}"
  singular: "account"
  plural: "accounts"
};
```

AIP-123 asks for `accounts/{account}`: a pattern alternates collection segment
and identifier, and the collection segment is the plural.
`{account}` alone reads to a linter as a collection named `{account}`, which is
why one annotation produces three findings.

This is the only finding in the list that is a design question rather than an
edit.
The pattern describes the shape of the `name` field, and `name` here holds a
bare identifier, which is the Kubernetes shape the rest of the model is built
on.
Declaring `accounts/{account}` and continuing to store `my-checking` in `name`
would make the annotation a lie.

Two things make the change the right one anyway.
The `plural` is already declared on all 91, so the collection segment is not new
information, only newly positioned where AIP-122 puts it.
And a resource name that carries its own collection is what makes a reference
self-describing, which is the same argument `ObjectReference.kind` already makes
one field over.

### `uid` does not declare its format

91 resources carry `string uid = 2`, and AIP-148 says a `uid` is a UUID4 and
should say so with `(google.api.field_info).format = UUID4`.
`google/api/field_info.proto` is not currently vendored, so this needs a line in
`nix/googleapis.nix` before it needs 91 lines in the protos.

### `name` is annotated `IMMUTABLE` rather than `IDENTIFIER`

87 of them.
AIP-203 gave resource names their own field behavior, and `IDENTIFIER` says
strictly more than `IMMUTABLE` does: not merely unchangeable, but the field that
addresses this resource.
The four resources without a `name` field are the content-addressed ones, and
they are the reason the count is 87 rather than 91.

### Request fields carry no field behavior

65 findings in 4 files, all of them the read-only graph services.
`GetCommitRequest.repository`, `ListCertificatesRequest.page_size`,
`WalkInputsRequest.start_digest`, and 62 others state nothing about whether a
caller must set them.
These are the only request messages in the repository, so this is the whole of
the surface AIP-203 applies to on the request side.

### Enums are `Status`, not `State`

`CaptureStatus`, `TaskStatus`, `EventStatus`, `VehicleStatus`,
`TransactionStatus`, `FocusSessionStatus`, `DriftStatus`.
AIP-216 picked `State` and the reason is worth restating: "status" reads as a
summary of health, "state" as a position in a lifecycle, and every one of these
seven is a position in a lifecycle.
The enum values themselves need no change.

### Two fields hold a standardized code under a non-standard name

`record.note` `Note.content_type` and `journal.entry` `Entry.content_type` are
`mime_type` under AIP-143.
`media.library` `LibraryItem.language` and `Subtitle.language` are
`language_code`, which is the name the repository already uses for
`currency_code` two domains over.

### Three timestamps do not end in `_time`

`pki.certificate` `Certificate.not_before` and `not_after`, and `vcs.commit`
`Signature.time`.
The X.509 spelling is `notBefore`; `not_before_time` keeps the term and satisfies
the rule.

### Two booleans are named `default`

`vcs.branch` `Branch.default` and `vcs.repository` `Remote.default`.
`default` is a reserved word in C#, Java, and JavaScript, so a generated
accessor has to be escaped or mangled in three of the languages this schema is
meant to be consumed from.

### The Java file options belong in managed mode

`java_package`, `java_outer_classname`, and `java_multiple_files` are required by
AIP-191 and absent from all 44 files.
Writing them into the protos would be 132 lines of generator configuration in
files that otherwise contain none.
`buf.gen.yaml` managed mode sets them from outside, which satisfies the intent
without the lines.
The linter reads the proto rather than the generator config, so this one is
fixed and still reported; it is a rule disable with a fix behind it rather than
a rule disable alone.

## What not to fix

Each of these is argued in [docs/aip.md](../aip.md); this section adds only what
the measurement contributes.

**`0192::has-comments`, 2228 findings.**
The bulk is the identity band: ten fields repeated across 91 resources, most of
which are already explained once in `README.md` and would gain nothing from being
explained 91 more times.

**`0215::foreign-type-reference`, 408 findings.**
Every use of `ObjectReference`, `Quantity`, `OwnerReference`, `LabelSelector`,
and `Condition`, which is to say the entire shared vocabulary the design is built
around.

**`0122::resource-reference-type` and `0123::resource-reference-type`, 166 each.**
The same 166 fields counted twice, once by each AIP.
Both say a `resource_reference` belongs on a `string`; here it sits on an
`ObjectReference`.
Note that the annotation is present and correct on all 166: what the linter
objects to is the field type, not a missing declaration.

**`0140::prepositions`, 46 findings.**
`covered_by`, `resolved_into`, `blocked_by_subtasks`, `played_on`, `not_before`.
The preposition is the direction of the edge.

**`0122::name-suffix`, 16 findings.**
All 16 hold a name in a system other than this one: `ref_name` and
`base_ref_name` are git refs, `common_name` is the X.509 field, `person_name`
is a credit on a film, `type_name` is a symbol in a parsed schema.

**`0142::time-field-type`, 6 findings.**
False positives on names ending in a time-like word: `start_seconds`,
`meal_seconds`, `scan_interval_seconds`, `require_up_to_date`, `up_to_date`,
`reminder_lead_time` (already a `Duration`).
None of the six is a timestamp.

**`0123::resource-annotation`, 7 findings.**
Value objects with a `name` field, `ref` `ObjectReference`, `ci.job` `Step`,
`asset.maintenance` `PartUsed`, `vcs.commit` `Signature`,
`health.measurement` `Component`, `codegen.schema` `Field` and `Method`,
mistaken for resources because they have one.
Annotating them would claim an identity none of them has.

**`0121::no-mutable-cycles`, 4 findings.**
`Task -> Task`, `Repository -> Repository`, `Schema -> Schema`,
`JobRun -> JobRun`.

**The service rules: `0121::resource-must-support-get`, `0131::*`, `0132::*`,
`0133::*`, `0158::*`, `0127::http-annotation`. 58 findings.**
All of them land on the three read-only graph services and on the resources
those services read.
A `Commit` is addressed by revision within a repository, an `Artifact` by digest,
a `Certificate` by fingerprint, so none of them has a `name` for a Get request to
take, and `WalkCommits` filters by path and first-parent collapsing rather than
by the fields AIP-132 allows.
These are content-addressed nodes, the `>>` archetype `README.md` names as the
one relationship Kubernetes has no answer for, and the standard-method AIPs have
no answer for it either.

**`0191::file-layout`, 45 findings.**
Messages should precede top-level enums, and services should precede messages.
41 files are affected: most lead with their enums under a `Shared types`
banner, and the three files with services put them last.
Reordering is mechanical and `buf breaking` does not consider declaration
order, so this was listed as a fix on the first pass.
Attempting it is what changed the answer: the banner comments name sections
that mix enums and messages, `AccountType` and `InstitutionKind` and
`SyncConfig` under one `Shared types` heading, so hoisting the messages leaves
the heading on whatever happens to follow it.
The rule exists for readability and paying it here costs more of it than it
buys.

**`0191::proto-version`, 44 findings.**
The rule asks for proto3.
These files are edition 2024.

## A note on running the linter

`api-linter` 2.3.1 cannot parse edition 2024, either from source or from a
descriptor set: its bundled compiler accepts editions up to 2023, and given a
2024 descriptor set it reports zero files found rather than an error.

The measurement above was taken by copying the tree, rewriting
`edition = "2024"` to `edition = "2023"`, and building the descriptor set from
the copy.
Nothing in these files uses a feature whose default differs between the two
editions, so the descriptors are otherwise identical.
The rewrite belongs to the linter integration rather than to the tree; see
[docs/aip.md](../aip.md).

## Sources

`api-linter` 2.3.1 run with every rule enabled over a `buf`-built
`FileDescriptorSet` of the whole workspace, output in JSON, partitioned into
life-domain and infrastructure files and grouped by rule; plus direct reads of
every file named above, `README.md`, `AGENTS.md`, and the three prior reviews in
this directory.
