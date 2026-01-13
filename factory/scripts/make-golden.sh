#!/usr/bin/env bash
set -euo pipefail

# -------------------------
# make-golden.sh
# Usage:
#   ./make-golden.sh kyverno-output.txt [golden.yaml]
# -------------------------

INPUT="${1:-}"
OUT="${2:-golden.yaml}"

RAW="raw-mutated.yaml"
RAW_NDJSON="raw-mutated.ndjson"
DEDUP_NDJSON="dedup.ndjson"

need() { command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing dependency: $1"; exit 1; }; }
info() { echo -e "\n🔹 $*"; }
ok()   { echo -e "✅ $*"; }
fail() { echo -e "❌ $*"; exit 1; }

# ---- deps ----
need awk
need yq
need jq
need sed

# ---- input checks ----
[[ -n "${INPUT}" ]] || fail "No input provided. Example: ./make-golden.sh kyverno-output.txt"
[[ -f "${INPUT}" ]] || fail "Input file not found: ${INPUT}"
[[ -s "${INPUT}" ]] || fail "Input file is empty: ${INPUT}"
ok "Input found: ${INPUT}"

# ---- step 1: extract YAML blocks from Kyverno log (API-aware, no duplication) ----
info "Step 1/6: Extract YAML documents from Kyverno output -> ${RAW}"

awk '
  /^apiVersion:/ { last_api=$0; next }

  /^kind:/ {
    if (last_api != "") print last_api
    print
    next
  }

  /^[[:space:]]|^metadata:|^spec:|^---/ { print }
' "${INPUT}" \
| sed '/^Applying /d' \
| sed '/^policy /d' \
| sed '/^Mutation:/d' \
> "${RAW}"

[[ -s "${RAW}" ]] || fail "No YAML extracted. Check input formatting."
ok "Extracted YAML to ${RAW}"

# ---- step 2: verify YAML parses ----
info "Step 2/6: Verify extracted YAML is parseable"
yq eval '.' "${RAW}" >/dev/null 2>&1 || fail "raw-mutated.yaml is invalid YAML"
ok "Extracted YAML is valid YAML"

# ---- step 3: ensure required fields exist in every doc ----
info "Step 3/6: Verify each YAML doc has required keys"
yq eval -j '.' "${RAW}" | jq -c 'select(. != null)' > "${RAW_NDJSON}"

DOCS_TOTAL="$(wc -l < "${RAW_NDJSON}" | tr -d ' ')"
[[ "${DOCS_TOTAL}" -gt 0 ]] || fail "No YAML documents found after parsing."
ok "Parsed ${DOCS_TOTAL} YAML document(s)"

MISSING_COUNT="$(jq -r '
  [
    inputs
    | select(
        (.apiVersion|not) or
        (.kind|not) or
        (.metadata|not) or
        (.metadata.name|not) or
        (.metadata.namespace|not)
      )
  ] | length
' "${RAW_NDJSON}")"

[[ "${MISSING_COUNT}" -eq 0 ]] || fail "Found ${MISSING_COUNT} docs missing apiVersion/kind/metadata.name/metadata.namespace"
ok "All docs contain apiVersion/kind/metadata.name/metadata.namespace"

# ---- step 4: show counts by kind (sanity check) ----
info "Step 4/6: Show doc counts by kind (pre-dedupe)"
jq -r '
  [inputs | .kind] | group_by(.) | map({kind: .[0], count: length})
  | sort_by(.kind) | .[]
  | "\(.count)\t\(.kind)"
' "${RAW_NDJSON}" | column -t

# ---- step 5: deduplicate by kind+namespace+name (keep last occurrence) ----
info "Step 5/6: Deduplicate into golden file -> ${OUT}"

jq -s '
  reduce .[] as $doc ({}; .[$doc.kind + ":" + $doc.metadata.namespace + ":" + $doc.metadata.name] = $doc)
  | . as $m
  | [$m[]]
' "${RAW_NDJSON}" > "${DEDUP_NDJSON}"

DOCS_DEDUP="$(jq 'length' "${DEDUP_NDJSON}")"
[[ "${DOCS_DEDUP}" -gt 0 ]] || fail "Dedupe produced 0 docs (unexpected)."

ok "Docs before dedupe: ${DOCS_TOTAL}"
ok "Docs after  dedupe: ${DOCS_DEDUP}"

# Emit proper multi-doc YAML
jq -c '.[]' "${DEDUP_NDJSON}" \
| while read -r line; do
    echo '---'
    echo "$line" | yq eval -P -
  done \
| sed '1d' > "${OUT}"

[[ -s "${OUT}" ]] || fail "Output file ${OUT} is empty."
ok "Wrote golden YAML: ${OUT}"



# ---- step 6: final verification of golden.yaml ----
info "Step 6/6: Final verification of golden.yaml"

yq eval '.' "${OUT}" >/dev/null 2>&1 || fail "golden.yaml is invalid YAML"
ok "golden.yaml is valid YAML"

DUP_KEYS="$(yq eval -j '.' "${OUT}" \
| jq -r '
  [inputs | (.kind + ":" + .metadata.namespace + ":" + .metadata.name)]
  | group_by(.) | map(select(length>1) | {key: .[0], count: length})
  | if length==0 then empty else .[] end
')"

if [[ -n "${DUP_KEYS}" ]]; then
  echo "❌ Duplicate resources still exist in ${OUT}:"
  echo "${DUP_KEYS}"
  exit 1
fi
ok "No duplicate (kind/namespace/name) resources in golden.yaml"

# ---- summary ----
info "✅ DONE"
echo "Golden file: ${OUT}"
echo "Unique resources: ${DOCS_DEDUP}"
echo
echo "Preview (kind ns name):"
yq eval -j '.' "${OUT}" \
| jq -r 'inputs | "\(.kind)\t\(.metadata.namespace)\t\(.metadata.name)"' \
| column -t
# ---- cleanup (only after full success) ----
info "Cleaning up intermediate files"

rm -f \
  "${RAW}" \
  "${RAW_NDJSON}" \
  "${DEDUP_NDJSON}"

ok "Removed intermediate artifacts (kept: ${OUT})"
