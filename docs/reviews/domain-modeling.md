# Domain modeling review

A second pass over the `unmango.*` proto surface, this time through a
Domain-Driven Design lens: aggregate boundaries, entity vs. value-object
treatment, ubiquitous language, and where borrowing Kubernetes' shape helps
or strains the thing being modeled.
No proto files were changed in producing this review.

Scope: `proto/unmango`, 13 life domains.
Baseline: `feat/life-domain-apis`.
References: Evans & Vernon DDD tactical patterns, the Kubernetes resource
model.

## The ownership chains, audited

Every domain that materializes work follows the same three-tier shape
borrowed from Deployment -> ReplicaSet -> Pod: a standing intent, a
materialized window or set, and the leaf that does the work.
The question worth asking of each one is whether the leaf still needed to
be a full, independently-addressable resource, or could have been a value
sitting inside its parent.

| Domain | Chain | Leaf is | Value objects underneath |
|---|---|---|---|
| finance.budget | Budget -> BudgetPeriod -> Allocation | full resource | AllocationTemplate |
| asset.maintenance | MaintenancePlan -> WorkOrder -> ServiceRecord | full resource | Task, PartUsed |
| vcs.change | ChangeSet -> Change -> Review | full resource | ReviewComment |
| ci.runner | RunnerPool -> RunnerSet -> Runner | full resource | RunnerScope, RolloutStrategy |
| health.nutrition | MealPlan -> Meal -> FoodEntry | full resource | Nutrients, Serving, Ingredient |
| health.training | TrainingPlan -> Workout -> Activity | full resource | StrengthSet, Targets |

Six chains, six full-resource leaves, zero exceptions, three is the ceiling
everywhere sampled, and it's never collapsed into a repeated value list on
the root.
The line the repo actually draws isn't chain depth; it's addressability.
`ReviewComment` stays a value object specifically because, per its own
comment, "it has no lifetime apart from its Review and is never addressed
alone."
Every leaf above, Allocation, ServiceRecord, Review, Runner, FoodEntry,
Activity, *is* addressed alone: from `covered_by`, from `current_job`, from
a calendar event, from a note's link.
That's a real, consistently-applied test, just one that resolves to "full
resource" more often than a DDD reading tuned toward small aggregates might
expect.

## Where the borrowed shape fits, and where it strains

The identity band, `owner_refs`, `generation`, `observed_generation`,
`conditions`, is Kubernetes' vocabulary for one specific situation:
something is declared, a controller reconciles it toward that declaration,
and the gap between the two is worth reporting.
That situation is real in some of these domains and absent in others, and
the schema currently doesn't distinguish.

**Fits, ci.runner.RunnerPool.**
A fleet with a rollout strategy, a revision history, and replicas that lag
behind desired state during a rollout *is* a reconciliation problem, the
same shape Kubernetes solves for the same reason.

```
updated_replicas = 52;
outdated_replicas = 55;  // draining
current_revision  = 56;
update_revision   = 57;
```

**Strains, productivity.capture.CaptureItem.**
The type's own doc comment: "one field and no decisions."
Nothing here is ever declared-then-reconciled, yet it carries the identical
apparatus, including an `owner_refs` that the doc says is always empty.

```
generation          = 7;
observed_generation = 50;
conditions           = 51;  // admits what, exactly?
```

`record.note.Note` carries the same apparatus for the same reason worth
questioning: a note isn't admitted by a controller, it's just written.
Uniform banding buys real things, one List/Watch shape works everywhere,
tooling never special-cases a kind, but for a scratch note or a captured
thought, `conditions` is a field with no process behind it to report on.

## Holding up well

**Value objects are a real, reused vocabulary.**
`Nutrients` is computed at four different altitudes, a food's per-serving
facts, one entry's scaled portion, a meal's total, a plan's rolling
average, and it's the same message every time, not four ad hoc field
groups.
`ResourceQuantity` does the same job for `compute.host` and `ci.runner`.
This is what a DDD value-object library is supposed to look like: defined
once, meaning-preserving everywhere it's reused.

**The entity/value line gets reasoned about, not assumed.**
`asset.vehicle.OdometerReading` could easily have been a repeated scalar on
`Vehicle`; instead it's a full resource, with an explicit comment
explaining why, it's an append-only series, not a fact about the vehicle.
That's a case-by-case call being made deliberately, in the open, which is
the difference between a convention and a habit.

**Contact and Platform are textbook generic subdomains.**
`people.contact.Contact` is referenced from 13 points across 9 unrelated
domains, journal, calendar, maintenance, ci, three separate vcs packages,
productivity, three media packages, and none of them own it.
`compute.platform.Platform` plays the same role for "which external
system" across 5 domains.
Neither domain had to bend to accommodate the other; both explicitly
justify staying separate in their own file comments.

**Bounded contexts hold: zero cross-domain imports.**
`grep -rn "^import" proto/unmango/` across all 13 life domains turns up
only `unmango/ref`, `unmango/uom`, and third-party well-known types.
No domain proto-imports another domain's messages directly, every
cross-domain fact travels as an `ObjectReference`, which is the DDD
anti-corruption boundary done at the schema level rather than left to
convention.

**Deliberate escape hatches, not accidental ones.**
`record.note.Note.links` and `productivity.capture.CaptureItem.resolved_into`
both reach into arbitrary, unnamed domains, a note can point at a
transaction, a service record, or a title without any of those packages
knowing notes exist.
Both are called out in-file as the intentional exception to the "no domain
knows about another" rule, which is what keeps it from becoming the rule's
quiet erosion.

## Worth examining now

Small, scoped adjustments, none require moving a message between domains or
renaming a mechanism, just narrowing where the mechanism applies.

1. **A lighter identity-band variant for momentary resources.**
   The repo already has precedent for a second band variant, content-addressed
   nodes drop `display_name`/`owner_refs`/`generation`/`delete_time` because
   nothing about them is declared.
   A third variant, keep `name`/`uid`/`labels`/`annotations`/`create_time`,
   drop `generation`/`observed_generation`/`conditions`, would fit
   `CaptureItem`, `journal.Entry`, and arguably `Note`: things that are
   written once and read, never reconciled.

1. **Lead with the domain concept before the mechanism.**
   `Allocation.selector` and `Meal.selector` sit in the domain-facing 10-39
   band, but the field type is a raw Kubernetes `LabelSelector` and most of
   the surrounding comments describe the mechanism ("claims by label")
   before the concept ("which transactions this envelope covers").
   The mechanism can stay exactly as it is; leading each comment with the
   domain-native description and treating the label-matching as an
   implementation note would keep the ubiquitous language pointed at what a
   budgeter or meal-planner would actually call the relationship.

1. **Write down the Allocation\<->Transaction label contract.**
   `Allocation.selector` matches labels that `finance.transaction.Transaction`
   is expected to carry, a real protocol between two independently-versioned
   packages, currently documented only as prose comments on each side
   rather than as a named, cross-referenced contract.
   Neither file imports the other (correctly), but the agreement between
   them is exactly the kind of thing that silently drifts when one side
   changes its labeling convention and the other has no way to notice.

## Worth deciding, not fixing

One real fork in the road, presented as a choice rather than a defect, the
current answer is coherent and has genuine upside.

**Should every materialized leaf carry its own labels and annotations?**
An `Allocation`, a `ServiceRecord`, a `Review`, each gets independent
`labels`/`annotations` maps, even though in practice most are stamped once
from a template and never hand-edited afterward.
Keeping them buys uniform tooling: one `LabelSelector` shape works on every
kind, no caller has to learn which resources support labels and which
don't.
The cost is real too: every leaf resource carries the full apparatus for a
capability, independent relabeling, that some of them may never exercise.
Neither answer is obviously right; it's worth a deliberate call rather than
defaulting to uniformity because that's what the rest of the repo does.

## Already right

**Don't collapse the three-tier chains into embedded lists.**
A stricter small-aggregate reading might push `Allocation` or `Runner` down
into a repeated field on their parent.
That would break references that already exist elsewhere in the schema,
`ci.job.JobRun.current_job` points at a `Runner` directly, `calendar.event`
points at a `WorkOrder` directly.
These leaves are addressed from outside their chain, which is precisely the
repo's own stated test for needing full identity.

**Don't replace LabelSelector as the join mechanism.**
The mechanism itself is sound and consistent with the repository's whole
strategy of borrowing Kubernetes' relationship vocabulary wholesale rather
than reinventing a parallel one.
The recommendation above is about how the concept reads in comments and
docs, not about swapping the underlying join.

## Sources

Findings are grounded in direct reads of `budget.proto`,
`maintenance.proto`, `change.proto`, `runner.proto`, `nutrition.proto`,
`task.proto`, `capture.proto`, `note.proto`, `ref.proto`, plus a full-repo
grep of every `^import` line across `proto/unmango/` and every cross-domain
reference to `people.contact.Contact` and `compute.platform.Platform`.
