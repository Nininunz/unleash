#!/usr/bin/env bats
# Tests for heal.sh - run with: bats tests/test_heal.bats

setup() {
  load '../lib/colors.sh'
  load '../lib/hosts.sh'
  load '../lib/suppress.sh'
  load '../lib/heal.sh'
  TEST_DIR="$BATS_TEST_TMPDIR/volume"
  mkdir -p "$TEST_DIR/private/etc"
  mkdir -p "$TEST_DIR/private/var/db/ConfigurationProfiles/Settings"
  mkdir -p "$TEST_DIR/private/var/db/com.apple.xpc.launchd"
  DRY_RUN=false
  suppress_enrollment "$TEST_DIR" 2>/dev/null || true
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "heal detects clean system" {
  run heal_suppress "$TEST_DIR" 2>/dev/null || true
  [ "$status" -eq 0 ]
}

@test "heal re-applies when DEP record reappears" {
  touch "$TEST_DIR/private/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound"
  heal_suppress "$TEST_DIR" 2>/dev/null || true
  [ ! -f "$TEST_DIR/private/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound" ]
}

@test "heal re-applies when hosts block missing" {
  > "$TEST_DIR/private/etc/hosts"
  heal_suppress "$TEST_DIR" 2>/dev/null || true
  run grep -c "iprofiles.apple.com" "$TEST_DIR/private/etc/hosts"
  [ "$output" -gt 0 ]
}

@test "heal respects individual core Off and optional On choices" {
  printf 'version 2\noverride iprofiles.apple.com off\noverride axm-adm-mdm.apple.com on\n' > "$TEST_DIR/private/etc/unleash-hosts.conf"
  touch "$TEST_DIR/private/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound"
  heal_suppress "$TEST_DIR"
  ! grep -Fxq ':: iprofiles.apple.com' "$TEST_DIR/private/etc/hosts"
  grep -Fxq ':: deviceenrollment.apple.com' "$TEST_DIR/private/etc/hosts"
  grep -Fxq ':: axm-adm-mdm.apple.com' "$TEST_DIR/private/etc/hosts"
  grep -Fxq 'override iprofiles.apple.com off' "$TEST_DIR/private/etc/unleash-hosts.conf"
  hosts_policy_matches "$TEST_DIR"
}
