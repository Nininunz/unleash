#!/usr/bin/env bats

prepare_account_script() {
  SCRIPT="$BATS_TEST_DIRNAME/../$1"
  DEFINITIONS="$BATS_TEST_TMPDIR/account-functions.sh"
  sed '/^main "\$@"$/d' "$SCRIPT" > "$DEFINITIONS"
}

@test "account flows stop on EOF at every field without creating or deleting accounts" {
  local artifact mode stage
  for artifact in unleash unleash-standalone.sh; do
    prepare_account_script "$artifact"
    for mode in admin_only_mode full_bypass_mode cmd_dualboot; do
      for stage in 0 1 2 3 4; do
        # Stage 3 confirms an existing-account replacement, then ends at password.
        # Stage 4 ends at the replacement confirmation itself.
        local input="$BATS_TEST_TMPDIR/input" target="$BATS_TEST_TMPDIR/volume"
        : > "$input"
        if [ "$stage" -ge 1 ]; then printf '%s\n' 'Fixture User' >> "$input"; fi
        if [ "$stage" -ge 2 ]; then printf '%s\n' fixture >> "$input"; fi
        if [ "$stage" -eq 3 ]; then printf '%s\n' y >> "$input"; fi
        run /bin/bash -u -c '
          source "$1"
          target="$2" mode="$3" stage="$4" marker="$5"
          dscl_node() { printf "%s\n" /fixture-node; }
          is_root() { return 0; }
          resolve_target_volumes() { printf "%s|%s\n" "$target-system" "$target"; }
          check_user_exists() { [ "$stage" -ge 3 ]; }
          delete_user() { touch "$marker"; }
          create_admin_user() { touch "$marker"; }
          find_available_uid() { touch "$marker"; printf "501\n"; }
          if "$mode" "$target"; then exit 90; fi
          [ ! -e "$marker" ]
          [ ! -e "$target/private/var/db/.AppleSetupDone" ]
        ' "$SCRIPT" "$DEFINITIONS" "$target" "$mode" "$stage" "$BATS_TEST_TMPDIR/mutated" < "$input"
        [ "$status" -eq 0 ]
        [[ "$output" == *"Account input cancelled"* ]]
      done
    done
  done
}

@test "literal account inputs reach dscl as separate unchanged arguments" {
  export ACCOUNT_TEST_NAME='  José O'\''Connor $(touch "$ACCOUNT_TEST_MARKER") `literal` "quotes" \backslash  '
  export ACCOUNT_TEST_PASSWORD='- $(touch "$ACCOUNT_TEST_MARKER") `literal` "quotes" \backslash & spaces '
  export ACCOUNT_TEST_MARKER="$BATS_TEST_TMPDIR/executed"
  local artifact
  for artifact in unleash unleash-standalone.sh; do
    prepare_account_script "$artifact"
    local target="$BATS_TEST_TMPDIR/$artifact-volume" calls="$BATS_TEST_TMPDIR/$artifact-calls"
    mkdir -p "$target/Users"
    run /bin/bash -eu -c '
      source "$1"
      target="$2" calls="$3"
      check_user_exists() { return 1; }
      dscl() { printf "%s\0" "$#" "$@" >> "$calls"; }
      chown() { [ "$1" = 501:20 ] && [ "$2" = "$target/Users/fixture_user" ]; }
      local_inputs="$4"
      printf "%s\n" "$ACCOUNT_TEST_NAME" fixture_user "$ACCOUNT_TEST_PASSWORD" > "$local_inputs"
      {
        prompt_fullname real_name
        prompt_username username
        prompt_password password
      } < "$local_inputs"
      create_admin_user /fixture-node "$target" "$username" "$real_name" "$password" 501
    ' "$SCRIPT" "$DEFINITIONS" "$target" "$calls" "$BATS_TEST_TMPDIR/inputs"
    [ "$status" -eq 0 ]
    [ ! -e "$ACCOUNT_TEST_MARKER" ]
    [[ "$output" != *"$ACCOUNT_TEST_PASSWORD"* ]]
    python3 - "$calls" <<'PY'
import os
import pathlib
import sys
parts = pathlib.Path(sys.argv[1]).read_bytes().split(b'\0')[:-1]
calls = []
while parts:
    count = int(parts.pop(0))
    calls.append([value.decode() for value in parts[:count]])
    del parts[:count]
record = '/Local/Default/Users/fixture_user'
assert ['-f', '/fixture-node', 'localhost', '-create', record, 'RealName', os.environ['ACCOUNT_TEST_NAME']] in calls
assert ['-f', '/fixture-node', 'localhost', '-passwd', record, os.environ['ACCOUNT_TEST_PASSWORD']] in calls
assert ['-f', '/fixture-node', 'localhost', '-append', '/Local/Default/Groups/admin', 'GroupMembership', 'fixture_user'] in calls
PY
  done
}

@test "account creation rejects invalid fields before any directory service mutation" {
  local artifact field
  for artifact in unleash unleash-standalone.sh; do
    prepare_account_script "$artifact"
    for field in username fullname password; do
      run /bin/bash -u -c '
        source "$1"
        marker="$2" field="$3"
        username=fixture real_name="Fixture User" password=fixture-password
        case "$field" in
          username) username="../bad" ;;
          fullname) real_name="   " ;;
          password) password=xyz ;;
        esac
        dscl() { touch "$marker"; }
        create_admin_user /fixture-node /fixture-volume "$username" "$real_name" "$password" 501
      ' "$SCRIPT" "$DEFINITIONS" "$BATS_TEST_TMPDIR/mutated" "$field"
      [ "$status" -ne 0 ]
      [ ! -e "$BATS_TEST_TMPDIR/mutated" ]
      [[ "$output" != *"xyz"* ]]
    done
  done
}
