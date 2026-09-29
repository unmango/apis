#!/usr/bin/env bash
# Compares the unmango.* descriptors built from proto/ with those built from
# gen/tdl, the protobuf tdl emits from tdl/. Prints a markdown fidelity report.
#
# A message or enum counts as exact when every field or value matches by name,
# number, label, and type. Message-typed fields compare by the last segment of
# the type name, since tdl emits one file per package with its own names.
#
# Needs buf and jq. `buf build` on proto/ needs third_party/k8s (`make vendor`).
set -euo pipefail

cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

buf build --path proto/unmango --exclude-imports -o "$tmp/proto.json"
buf build gen/tdl --exclude-imports -o "$tmp/tdl.json"

# One line per declaration: kind, package, name, and a signature of its
# members. Messages and enums only; services are counted separately.
decls='
  def short: (. // "") | split(".") | last;
  .file[] | select(.package | startswith("unmango.")) | .package as $p |
  ( (.messageType // [])[] |
      ["message", $p, .name,
       ([(.field // [])[] | "\(.name)=\(.number):\(.label):\(.type):\(.typeName | short)"] | sort | join(","))] ),
  ( (.enumType // [])[] |
      ["enum", $p, .name,
       ([(.value // [])[] | "\(.name)=\(.number)"] | sort | join(","))] )
  | @tsv'
jq -r "$decls" "$tmp/proto.json" | sort >"$tmp/proto.tsv"
jq -r "$decls" "$tmp/tdl.json" | sort >"$tmp/tdl.tsv"

services='.file[] | select(.package | startswith("unmango.")) | .package as $p | (.service // [])[] | [$p, .name, (.method | length)] | @tsv'
jq -r "$services" "$tmp/proto.json" | sort >"$tmp/proto-svc.tsv"
jq -r "$services" "$tmp/tdl.json" | sort >"$tmp/tdl-svc.tsv"

# Per package: declarations in proto/, how many tdl emitted under the same
# name, and how many of those match exactly.
awk -F'\t' '
  FNR == NR { tdl[$1 FS $2 FS $3] = $4; next }
  {
    key = $1 FS $2 FS $3
    pkgs[$2] = 1
    total[$2, $1]++
    if (key in tdl) {
      emitted[$2, $1]++
      if (tdl[key] == $4) exact[$2, $1]++
    }
  }
  END {
    print "| Package | Messages (exact / emitted / proto) | Enums (exact / emitted / proto) |"
    print "|---|---|---|"
    n = asorti(pkgs, sorted)
    for (i = 1; i <= n; i++) {
      p = sorted[i]
      printf "| `%s` | %d / %d / %d | %d / %d / %d |\n", p,
        exact[p, "message"], emitted[p, "message"], total[p, "message"],
        exact[p, "enum"], emitted[p, "enum"], total[p, "enum"]
      for (k in total) if (index(k, p SUBSEP) == 1) {
        split(k, parts, SUBSEP)
        T[parts[2]] += total[k]; E[parts[2]] += emitted[k]; X[parts[2]] += exact[k]
      }
    }
    printf "| **Total** | **%d / %d / %d** | **%d / %d / %d** |\n",
      X["message"], E["message"], T["message"], X["enum"], E["enum"], T["enum"]
  }
' "$tmp/tdl.tsv" "$tmp/proto.tsv"

echo
printf 'Services: %d in proto/ (%d rpcs), %d emitted from tdl.\n' \
  "$(wc -l <"$tmp/proto-svc.tsv")" \
  "$(awk -F'\t' '{ n += $3 } END { print n + 0 }' "$tmp/proto-svc.tsv")" \
  "$(wc -l <"$tmp/tdl-svc.tsv")"

# Declarations tdl emitted that proto/ does not have, such as a oneof lifted
# into its own message.
extra=$(awk -F'\t' 'FNR == NR { p[$1 FS $2 FS $3] = 1; next } !(($1 FS $2 FS $3) in p) { print "- " $1 " `" $2 "." $3 "`" }' "$tmp/proto.tsv" "$tmp/tdl.tsv")
if [[ -n $extra ]]; then
  echo
  echo "Emitted by tdl with no counterpart in proto/:"
  echo
  echo "$extra"
fi

# Emitted under a matching name but different members.
mismatch=$(awk -F'\t' 'FNR == NR { p[$1 FS $2 FS $3] = $4; next } (($1 FS $2 FS $3) in p) && p[$1 FS $2 FS $3] != $4 { print "- " $1 " `" $2 "." $3 "`" }' "$tmp/proto.tsv" "$tmp/tdl.tsv")
if [[ -n $mismatch ]]; then
  echo
  echo "Emitted with members that differ from proto/:"
  echo
  echo "$mismatch"
fi
