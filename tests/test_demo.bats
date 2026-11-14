#!/usr/bin/env bats

setup() {
  load '../lib/colors.sh'
  load '../lib/demo.sh'
}

@test "run_demo exits cleanly" {
  run run_demo 2>/dev/null || true
  [ "$status" -eq 0 ]
}

@test "run_demo contains demo steps" {
  run run_demo 2>/dev/null || true
  echo "$output" | grep -qi "demo"
}

@test "demo renders ANSI status colors and aligned completion headers in Bash 3.2" {
  local artifact
  for artifact in lib/demo.sh unleash-standalone.sh; do
    local definitions="$BATS_TEST_TMPDIR/demo-functions.sh"
    sed -n '/^run_demo() {$/,/^}$/p' "$BATS_TEST_DIRNAME/../$artifact" > "$definitions"
    export DEMO_SLEEP_LOG="$BATS_TEST_TMPDIR/sleeps"
    : > "$DEMO_SLEEP_LOG"
    run /bin/bash -eu -c '
      source "$1/lib/colors.sh"
      source "$1/lib/suppress.sh"
      source "$1/lib/heal.sh"
      source "$2"
      sleep() { printf "%s\n" "$1" >> "$DEMO_SLEEP_LOG"; }
      run_demo
    ' bash "$BATS_TEST_DIRNAME/.." "$definitions"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" > "$BATS_TEST_TMPDIR/output"
    python3 - "$BATS_TEST_TMPDIR/output" "$DEMO_SLEEP_LOG" <<'PY'
import pathlib
import re
import sys
output = pathlib.Path(sys.argv[1]).read_text()
assert '\\033[' not in output
assert '\x1b[1;31mPRESENT\x1b[0m' in output
assert '\x1b[1;32mCLEARED\x1b[0m' in output
assert '\x1b[1;32mRESTORED\x1b[0m' in output
plain = re.sub(r'\x1b\[[0-9;]*m', '', output)
borders = [line for line in plain.splitlines() if line.startswith(('╔', '║', '╚'))]
assert len(borders) == 6
for start in (0, 3):
    assert len({len(line) for line in borders[start:start + 3]}) == 1
assert 'Demo Complete' in borders[4]
assert 'Commands used: suppress, heal' in plain
assert pathlib.Path(sys.argv[2]).read_text().splitlines() == ['1'] * 4
PY
  done
}
