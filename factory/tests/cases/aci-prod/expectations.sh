# tests/cases/aci-prod/expectations.sh
# This file contains the assertions for the aci-prod test case.

GOLDEN_MANIFEST="${TEMP_DIR}/01-golden.yaml"
POLICY_REPORT="${TEMP_DIR}/02-policy-report.yaml"

assert_golden_manifest_contains() {
  echo "    -> ASSERT: Golden manifest contains '$1'"
  grep -q "$1" "${GOLDEN_MANIFEST}" || (echo "Assertion failed!" && exit 1)
}

assert_policy_report_has() {
  echo "    -> ASSERT: Policy report has '$1' count of '$2'"
  grep -q "$1: $2" "${POLICY_REPORT}" || (echo "Assertion failed! Report contents:" && cat ${POLICY_REPORT} && exit 1)
}
