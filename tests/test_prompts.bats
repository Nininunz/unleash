#!/usr/bin/env bats

setup() {
  export PROMPT_TEST_ROOT="$BATS_TEST_DIRNAME/.."
  export PROMPT_TEST_MARKER="$BATS_TEST_TMPDIR/executed"
  # Extract only function definitions: never dispatch the real standalone app.
  export PROMPT_TEST_STANDALONE="$BATS_TEST_TMPDIR/standalone-prompts.sh"
  python3 - "$PROMPT_TEST_ROOT/unleash-standalone.sh" "$PROMPT_TEST_STANDALONE" <<'PY'
import pathlib
import re
import sys
source = pathlib.Path(sys.argv[1]).read_text()
names = ('prompt_destination_valid', 'prompt_default', 'account_has_control_chars',
         'validate_fullname', 'validate_username', 'validate_password',
         'prompt_account_field', 'prompt_fullname', 'prompt_username', 'prompt_password')
functions = []
for name in names:
    matches = re.findall(r'^' + name + r'\(\) \{.*?^\}', source, re.M | re.S)
    assert len(matches) == 1, name
    functions.extend(matches)
pathlib.Path(sys.argv[2]).write_text('\n'.join(functions) + '\n')
PY
}

check_prompt_case() {
  local artifact
  for artifact in modules standalone; do
    run /bin/bash -euo pipefail "$BATS_TEST_DIRNAME/helpers/prompt-case.bash" "$artifact" "$1"
    [ "$status" -eq 0 ]
    [ ! -e "$PROMPT_TEST_MARKER" ]
  done
}

@test "prompt text remains literal without executing substitutions" {
  check_prompt_case literal
}

@test "empty prompt input preserves literal defaults" {
  check_prompt_case defaults
}

@test "prompts assign caller locals despite former helper name collisions" {
  check_prompt_case collisions
}

@test "prompts reject reserved and non-scalar destinations before reading" {
  check_prompt_case destinations
}

@test "prompts return failure on EOF without changing the destination" {
  check_prompt_case eof
}

@test "validated prompts still reprompt before assigning" {
  check_prompt_case reprompt
}

@test "account fields enforce separate boundaries and preserve literal permitted text" {
  check_prompt_case fields
}

@test "invalid fields display specific warnings without password contents" {
  check_prompt_case messages
}
