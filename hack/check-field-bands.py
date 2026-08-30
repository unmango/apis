#!/usr/bin/env python3
"""Enforce the field-number bands the life-domain resources all share.

The identity band is a convention repeated across every resource rather than a
shared message type, which is a deliberate choice: a resource stays flat, so
`name` sits where google.api.resource and AIP-122 expect it, and an update mask
addresses `display_name` rather than `metadata.display_name`.

The cost of that choice is drift. Nothing in the compiler stops a new resource
from putting `labels` at 3. This does.

Usage: check-field-bands.py <proto-root>
"""

import re
import sys
from pathlib import Path

# Field number -> the only field that may occupy it on any resource.
IDENTITY = {
    2: "uid",
    3: "display_name",
    4: "labels",
    5: "annotations",
    6: "owner_refs",
    7: "generation",
    8: "create_time",
    9: "update_time",
    10: "delete_time",
}

# Slot 8 holds the moment the node came into being. On a commit that is the
# committer timestamp, which is the same fact under a different name.
SLOT_8_ALIASES = {"create_time", "commit_time"}

MESSAGE = re.compile(r"^message (\w+) \{\n(.*?)^\}", re.M | re.S)
FIELD = re.compile(
    r"^\s+(?:repeated |optional )?[\w.<>, ]*?\b(\w+) = (\d+)\b", re.M)
RESERVED = re.compile(r"^\s*reserved ([^;]+);", re.M)
REF_FIELD = re.compile(
    r"^\s+(?:repeated )?ref\.v1alpha1\.(?:Object|Parent)Reference (\w+) = \d+([^;]*);",
    re.M)


def contiguous(nums, start):
    return nums == list(range(start, start + len(nums)))


def check_message(kind, body):
    """Yield a complaint string for every band violation in one resource."""
    fields = {n: int(v) for n, v in FIELD.findall(body)}
    by_num = {}
    for name, num in fields.items():
        by_num.setdefault(num, []).append(name)
    reserved = {
        int(n)
        for stmt in RESERVED.findall(body)
        for n in re.findall(r"\d+", stmt.replace(" to ", " "))
    }
    for stmt in RESERVED.findall(body):
        if " to " in stmt:
            lo, hi = (int(x) for x in re.findall(r"\d+", stmt))
            reserved |= set(range(lo, hi + 1))

    mutable = "name" in fields and fields["name"] == 1

    if 1 not in by_num:
        yield "field 1 is neither a name nor a content address"

    for num, want in IDENTITY.items():
        got = by_num.get(num)
        if got is None:
            if num not in reserved:
                yield f"{num} is neither {want} nor reserved"
        elif num == 8:
            if got[0] not in SLOT_8_ALIASES:
                yield f"{num} is {got[0]}, expected create_time or commit_time"
        elif got[0] != want:
            yield f"{num} is {got[0]}, expected {want}"

    if mutable and "update_time" not in fields:
        yield "a mutable kind with no update_time"
    if not mutable and "update_time" in fields:
        yield "a content-addressed kind with an update_time; it is never written twice"

    for num, names in sorted(by_num.items()):
        if len(names) > 1:
            yield f"field number {num} is used by {' and '.join(names)}"

    declared = sorted({v for v in fields.values() if 11 <= v <= 39})
    if declared and not contiguous(declared, 11):
        yield f"declared band is not contiguous from 11: {declared}"

    assigned = sorted({v for v in fields.values() if 40 <= v <= 49})
    if assigned and not contiguous(assigned, 40):
        yield f"assigned band is not contiguous from 40: {assigned}"

    observed = sorted({v for v in fields.values() if v >= 50})
    if observed and not contiguous(observed, min(observed)):
        yield f"observed band has a gap: {observed}"
    if observed:
        skipped = [n for n in range(50, observed[0]) if n not in reserved]
        if skipped:
            nums = ", ".join(str(n) for n in skipped)
            yield f"observed band starts at {observed[0]} without reserving {nums}"

    if "option (google.api.resource)" not in body:
        yield "no google.api.resource option"


def is_resource(body):
    """A resource declares an identity at field 1 and a uid, or is content-addressed."""
    if "string name = 1 [(google.api.field_behavior) = IMMUTABLE];" in body:
        return True
    return bool(
        re.search(r"^  string \w+ = 1 \[\(google\.api\.field_behavior\) = OUTPUT_ONLY\];", body, re.M)
        and "// Content-addressed identity." in body
    ) or "The identity." in body


def main(root):
    problems = []
    resources = 0
    refs = 0
    for path in sorted(Path(root).rglob("*.proto")):
        if "unmango/ref/" in str(path) or "/dev/" in str(path):
            continue
        text = path.read_text()
        rel = path.relative_to(root)
        for kind, body in MESSAGE.findall(text):
            for name, opts in REF_FIELD.findall(body):
                refs += 1
                if "resource_reference" not in opts:
                    problems.append(f"{rel}: {kind}.{name} has no resource_reference")
            if not is_resource(body):
                continue
            resources += 1
            for complaint in check_message(kind, body):
                problems.append(f"{rel}: {kind}: {complaint}")

    for p in problems:
        print(p, file=sys.stderr)
    n = len(problems)
    print(f"checked {resources} resources and {refs} reference fields, "
          f"{n} problem{'' if n == 1 else 's'}")
    return 1 if problems else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
