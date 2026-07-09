#!/usr/bin/env bash
#
# mayhem/test.sh — RUN hoextdown's own functional suite (already built by mayhem/build.sh).
# test/runner.py renders each Markdown fixture with ./hoedown and diffs the (tidy-normalized)
# output against the golden .html — a behavioral golden-output oracle, not an exit-status check.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# The runner drives the pre-built ./hoedown binary; do NOT build here.
if [ ! -x ./hoedown ]; then
  echo "FATAL: ./hoedown missing — mayhem/build.sh must build the test binary" >&2
  emit_ctrf "python-unittest" 0 1
  exit 1
fi
command -v tidy >/dev/null || { echo "FATAL: tidy not installed (Dockerfile must apt-get it)" >&2; emit_ctrf "python-unittest" 0 1; exit 1; }

out="$(python3 test/runner.py -v 2>&1)" ; rc=$?
echo "$out" | tail -n 20

ran=$(echo "$out" | grep -oE 'Ran [0-9]+ tests?' | grep -oE '[0-9]+' | head -1)
ran=${ran:-0}
failures=$(echo "$out" | grep -oE 'failures=[0-9]+' | grep -oE '[0-9]+' | head -1); failures=${failures:-0}
errors=$(echo "$out" | grep -oE 'errors=[0-9]+' | grep -oE '[0-9]+' | head -1); errors=${errors:-0}
skipped=$(echo "$out" | grep -oE 'skipped=[0-9]+' | grep -oE '[0-9]+' | head -1); skipped=${skipped:-0}
expfail=$(echo "$out" | grep -oE 'expected failures=[0-9]+' | grep -oE '[0-9]+$' | head -1); expfail=${expfail:-0}

failed=$(( failures + errors ))
# a crashed runner with no parsed counts must fail loudly
if [ "$ran" -eq 0 ]; then
  echo "FATAL: could not parse test results (runner rc=$rc)" >&2
  emit_ctrf "python-unittest" 0 1
  exit 1
fi
passed=$(( ran - failed - skipped - expfail ))

emit_ctrf "python-unittest" "$passed" "$failed" "$skipped" 0 "$expfail"
