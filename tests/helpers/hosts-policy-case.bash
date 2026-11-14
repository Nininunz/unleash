#!/bin/bash
set -euo pipefail
source "$HOSTS_TEST_DEFS"
DRY_RUN=false
root="$HOSTS_TEST_ROOT/target"
mkdir -p "$root/private/etc"
hosts="$root/private/etc/hosts"
policy="$HOSTS_TEST_ROOT/policy"
printf '127.0.0.1 localhost\n0.0.0.0 iprofiles.apple.com manual.alias # administrator\n' > "$hosts"
chmod 640 "$hosts"
cp -p "$hosts" "$HOSTS_TEST_ROOT/original"
printf 'version 2\n' > "$policy"
# No platform mutation is permitted in this fixture, even if accidentally called.
pfctl() { echo unexpected > "$HOSTS_TEST_ROOT/unexpected"; return 99; }
chflags() { echo unexpected > "$HOSTS_TEST_ROOT/unexpected"; return 99; }
dscacheutil() { echo unexpected > "$HOSTS_TEST_ROOT/unexpected"; return 99; }
killall() { echo unexpected > "$HOSTS_TEST_ROOT/unexpected"; return 99; }
is_root() { return 1; }
fail() { if "$@"; then printf 'Unexpected success\n' >&2; exit 1; fi; }
case "$1" in
 preview-disappeared-input)
  command() { if [ "$*" = '-v diff' ]; then return 1; fi; builtin command "$@"; }
  printf 'old\n' > "$HOSTS_TEST_ROOT/old"
  printf 'new\n' > "$HOSTS_TEST_ROOT/new"
  awk() {
    builtin command awk "$@" || return $?
    if [ "$1" = 'END {print NR+0}' ] && [ "$2" = "$HOSTS_TEST_ROOT/old" ]; then rm "$2"; fi
  }
  rc=0
  hosts_preview_diff "$HOSTS_TEST_ROOT/old" "$HOSTS_TEST_ROOT/new" > "$HOSTS_TEST_ROOT/preview" 2>/dev/null || rc=$?
  [ "$rc" -eq 2 ]
  ;;
 preview-partial-read)
  command() { if [ "$*" = '-v diff' ]; then return 1; fi; builtin command "$@"; }
  cat() {
    case "$1" in
      */candidate) head -n 1 "$1"; return 74 ;;
      *) builtin command cat "$@" ;;
    esac
  }
  rc=0
  printf 'a\nAPPLY\n' | cmd_hosts edit --root "$root" --policy "$policy" --plain > "$HOSTS_TEST_ROOT/editor-output" || rc=$?
  [ "$rc" -ne 0 ]
  ! grep -q 'Type APPLY' "$HOSTS_TEST_ROOT/editor-output"
  cmp "$hosts" "$HOSTS_TEST_ROOT/original"
  [ ! -e "$root/private/etc/unleash-hosts.conf" ]
  ;;
 recovery-utilities)
  command() { if [ "$*" = '-v diff' ] || [ "$*" = '-v cmp' ]; then return 1; fi; builtin command "$@"; }
  cmp() { echo 'unexpected cmp dependency' >&2; return 99; }
  diff() { echo 'unexpected diff dependency' >&2; return 99; }
  hosts_preview "$hosts" "$policy" > "$HOSTS_TEST_ROOT/preview"
  grep -Fx '+0.0.0.0 iprofiles.apple.com' "$HOSTS_TEST_ROOT/preview"
  hosts_transaction "$root" "$policy"
  hosts_policy_matches "$root"
  hosts_same_file "$hosts" "$hosts"
  backup=$(find "$root/private/etc" -name '.unleash-hosts-backup.*' -type d | head -1)
  hosts_transaction "$root" "$backup" rollback
  hosts_files_equal "$hosts" "$HOSTS_TEST_ROOT/original"
  ;;
 comparison-read-failure)
  printf 'different\n' > "$HOSTS_TEST_ROOT/other"
  # Both empty and partial failed reads must be errors, even for equal files.
  od() {
    if [ "$failure_side" = both ] || [ "$4" = "$failure_side" ]; then
      if [ "$failure_output" = partial ]; then printf ' 61\n'; fi
      return 1
    fi
    builtin command od "$@"
  }
  for failure_side in both "$hosts" "$HOSTS_TEST_ROOT/other"; do
    for failure_output in empty partial; do
      actual=0
      hosts_files_equal "$hosts" "$HOSTS_TEST_ROOT/other" || actual=$?
      [ "$actual" -eq 2 ]
    done
  done
  failure_side=both
  actual=0; hosts_files_equal "$hosts" "$hosts" || actual=$?
  [ "$actual" -eq 2 ]
  cmp "$hosts" "$HOSTS_TEST_ROOT/original"
  ;;
 exact-comparison)
  python3 - "$HOSTS_TEST_ROOT" <<'BYTES'
from pathlib import Path
import sys
r=Path(sys.argv[1])
cases=[b'',b'a',b'a\n',b'a\n\n',b'a\x00',b'a\x00\x00',b'a\x00b',b'a\x00b\n',bytes(range(256)),b'\\*?[] $()\r\n',b'x'*100000]
for i,data in enumerate(cases): (r/('bytes-'+str(i))).write_bytes(data)
BYTES
  for left in "$HOSTS_TEST_ROOT"/bytes-*; do
    for right in "$HOSTS_TEST_ROOT"/bytes-*; do
      expected=0; actual=0
      cmp -s "$left" "$right" || expected=$?
      hosts_files_equal "$left" "$right" || actual=$?
      [ "$actual" -eq "$expected" ]
    done
  done
  actual=0; hosts_files_equal "$HOSTS_TEST_ROOT/missing" "$hosts" || actual=$?
  [ "$actual" -eq 2 ]
  ;;
 editor-policy-failure)
  set +e
  /bin/bash -euo pipefail -c '
    source "$HOSTS_TEST_DEFS"
    hosts_editor_policy() { return 71; }
    hosts_editor "$HOSTS_TEST_ROOT/target" "$HOSTS_TEST_ROOT/policy" true
  ' <<< q > "$HOSTS_TEST_ROOT/editor-output"
  rc=$?
  set -e
  [ "$rc" -eq 71 ]
  ! grep -q 'Choose:' "$HOSTS_TEST_ROOT/editor-output"
  cmp "$hosts" "$HOSTS_TEST_ROOT/original"
  [ ! -e "$root/private/etc/unleash-hosts.conf" ]
  ;;
 legacy-restore)
  # Unmarked backups cannot be interpreted as permission to clear core blocks.
  cp "$hosts" "$HOSTS_TEST_ROOT/old-backup"
  for domain in iprofiles.apple.com deviceenrollment.apple.com mdmenrollment.apple.com; do
    printf '0.0.0.0 %s\n:: %s\n' "$domain" "$domain" >> "$HOSTS_TEST_ROOT/old-backup"
  done
  hosts_transaction "$root" "$policy"
  echo '192.0.2.3 new.admin.example' >> "$hosts"
  cp "$hosts" "$HOSTS_TEST_ROOT/active-hosts"
  cp "$root/private/etc/unleash-hosts.conf" "$HOSTS_TEST_ROOT/active-policy"
  fail hosts_restore_owned_backup "$root" "$HOSTS_TEST_ROOT/old-backup"
  cmp "$HOSTS_TEST_ROOT/active-hosts" "$hosts"
  cmp "$HOSTS_TEST_ROOT/active-policy" "$root/private/etc/unleash-hosts.conf"
  ;;
 raw-partial)
  printf 'version 2\noverride iprofiles.apple.com off\n' > "$policy"
  hosts_transaction "$root" "$policy"
  printf '# BEGIN Unleash hosts\n0.0.0.0 axm-adm-mdm.apple.com\n:: axm-adm-mdm.apple.com\n# END Unleash hosts\n' > "$HOSTS_TEST_ROOT/partial-backup"
  hosts_restore_owned_backup "$root" "$HOSTS_TEST_ROOT/partial-backup"
  ! grep -Fx ':: iprofiles.apple.com' "$hosts"
  grep -Fx ':: deviceenrollment.apple.com' "$hosts"
  grep -Fx ':: mdmenrollment.apple.com' "$hosts"
  grep -Fx ':: axm-adm-mdm.apple.com' "$hosts"
  grep -Fx 'override iprofiles.apple.com off' "$root/private/etc/unleash-hosts.conf"
  ;;
 metadata-stale)
  hosts_transaction "$root" "$policy"
  backup=$(find "$root/private/etc" -name '.unleash-hosts-backup.*' -type d | head -1)
  chmod 600 "$hosts"
  fail hosts_transaction "$root" "$backup" rollback
  [ "$(stat -f %Lp "$hosts")" = 600 ]
  ;;
 pty-*)
  python3 "$HOSTS_TEST_PTY" "${1#pty-}"
  ;;
 default)
  hosts_resolve "$policy" > "$HOSTS_TEST_ROOT/rows"
  [ "$(grep -c present "$HOSTS_TEST_ROOT/rows")" = 3 ]
  hosts_transaction "$root" "$policy"
  [ "$(hosts_owned_count "$hosts")" = 3 ]
  [ "$(grep -c '^0.0.0.0 ' "$hosts")" = 4 ]
  grep -Fx '0.0.0.0 iprofiles.apple.com manual.alias # administrator' "$hosts"
  ! grep -E 'albert|gdmf|acmdm|configuration' "$hosts"
  cp "$hosts" "$HOSTS_TEST_ROOT/first"
  hosts_transaction "$root" "$policy"
  cmp "$HOSTS_TEST_ROOT/first" "$hosts"
  [ "$(stat -f %Lp "$hosts")" = 640 ]
  ;;
 overrides)
  printf 'version 2\noverride IPROFILES.Apple.com. off\noverride MDM.Example. on\noptional custom.example\n' > "$policy"
  hosts_transaction "$root" "$policy"
  ! grep -Fx '0.0.0.0 iprofiles.apple.com' "$hosts"
  ! grep -Fx ':: iprofiles.apple.com' "$hosts"
  grep -Fx '0.0.0.0 mdm.example' "$hosts"
  grep -Fx ':: mdm.example' "$hosts"
  ! grep -F 'custom.example' "$hosts"
  grep -Fx 'override iprofiles.apple.com off' "$root/private/etc/unleash-hosts.conf"
  hosts_policy_matches "$root"
  # Reset restores core defaults and turns optional hosts off.
  printf 'version 2\noptional custom.example\noptional mdm.example\n' > "$policy"
  hosts_transaction "$root" "$policy"
  grep -Fx ':: iprofiles.apple.com' "$hosts"
  ! grep -Fx ':: mdm.example' "$hosts"
  ! grep -Fx ':: custom.example' "$hosts"
  ;;
 invalid)
  for value in 'preset extended' 'optional https://example.com' 'optional 127.0.0.1' 'optional a..example' 'optional -a.example' 'optional bad_name.example' 'override example.com allow' 'override $(touch /tmp/unexpected) block'; do
    printf '%s\n' "$value" > "$policy"
    fail hosts_transaction "$root" "$policy"
    cmp "$HOSTS_TEST_ROOT/original" "$hosts"
    [ ! -e "$root/private/etc/unleash-hosts.conf" ]
  done
  printf 'override EXAMPLE.com on\noverride example.com off\n' > "$policy"
  fail hosts_resolve "$policy"
  [ -z "$(find "$root/private/etc" -name '.unleash-hosts*' -print)" ]
  ;;
 migration)
  cat >> "$hosts" <<'OLD'
# Added by unleash — DEP enrollment block
0.0.0.0 albert.apple.com
:: albert.apple.com
0.0.0.0 configuration.apple.com
:: configuration.apple.com
0.0.0.0 unknown.example
:: unknown.example alias.example
# administrator
0.0.0.0 gdmf.apple.com
OLD
  cp "$hosts" "$HOSTS_TEST_ROOT/legacy"
  hosts_transaction "$root" "$policy"
  ! grep -F 'albert.apple.com' "$hosts"
  ! grep -F 'configuration.apple.com' "$hosts"
  grep -Fx '0.0.0.0 unknown.example' "$hosts"
  grep -Fx ':: unknown.example alias.example' "$hosts"
  grep -Fx '0.0.0.0 gdmf.apple.com' "$hosts"
  backup=$(find "$root/private/etc" -name '.unleash-hosts-backup.*' -type d | head -1)
  cmp "$HOSTS_TEST_ROOT/legacy" "$backup/before.0"
  ;;
 malformed)
  printf '# BEGIN Unleash hosts\n127.0.0.1 administrator.example\n# END Unleash hosts\n' >> "$hosts"
  cp "$hosts" "$HOSTS_TEST_ROOT/before"
  fail hosts_transaction "$root" "$policy"
  cmp "$HOSTS_TEST_ROOT/before" "$hosts"
  ;;
 preview)
  hosts_preview "$hosts" "$policy" > "$HOSTS_TEST_ROOT/preview"
  grep -Fx '+0.0.0.0 iprofiles.apple.com' "$HOSTS_TEST_ROOT/preview"
  DRY_RUN=true hosts_transaction "$root" "$policy"
  cmp "$HOSTS_TEST_ROOT/original" "$hosts"
  [ -z "$(find "$root/private/etc" -name '.unleash-hosts*' -print)" ]
  [ ! -e "$root/private/etc/unleash-hosts.conf" ]
  ;;
 rollback)
  hosts_transaction "$root" "$policy"
  backup=$(find "$root/private/etc" -name '.unleash-hosts-backup.*' -type d | head -1)
  hosts_transaction "$root" "$backup" rollback
  cmp "$HOSTS_TEST_ROOT/original" "$hosts"
  [ "$(stat -f %Lp "$hosts")" = 640 ]
  [ ! -e "$root/private/etc/unleash-hosts.conf" ]
  ;;
 stale)
  hosts_transaction "$root" "$policy"
  backup=$(find "$root/private/etc" -name '.unleash-hosts-backup.*' -type d | head -1)
  echo '# administrator later edit' >> "$hosts"
  cp "$hosts" "$HOSTS_TEST_ROOT/later"
  fail hosts_transaction "$root" "$backup" rollback
  cmp "$HOSTS_TEST_ROOT/later" "$hosts"
  ;;
 interrupt-before-hosts|interrupt-after-hosts|interrupt-after-policy|interrupt-after-delete|interrupt-concurrent-edit)
  hosts_fault_case="$1"
  hosts_fault_action=apply
  hosts_fault_source="$policy"
  if [ "$hosts_fault_case" = interrupt-after-policy ]; then
    printf 'version 2\noptional before.example\n' > "$root/private/etc/unleash-hosts.conf"
    chmod 644 "$root/private/etc/unleash-hosts.conf"
  elif [ "$hosts_fault_case" = interrupt-after-delete ]; then
    hosts_transaction "$root" "$policy"
    hosts_fault_source=$(find "$root/private/etc" -name '.unleash-hosts-backup.*' -type d | head -1)
    hosts_fault_action=rollback
  fi
  cp -p "$hosts" "$HOSTS_TEST_ROOT/pre-interrupt-hosts"
  if [ -f "$root/private/etc/unleash-hosts.conf" ]; then
    cp -p "$root/private/etc/unleash-hosts.conf" "$HOSTS_TEST_ROOT/pre-interrupt-policy"
  fi
  mv() {
    if [ "$hosts_fault_case" = interrupt-before-hosts ]; then
      case "${2:-}" in */publish.0) /bin/sh -c 'kill -TERM "$PPID"' ;; esac
    fi
    command mv "$@" || return 1
    case "$hosts_fault_case:${2:-}" in
      interrupt-after-hosts:*/publish.0|interrupt-after-policy:*/publish.1)
        /bin/sh -c 'kill -TERM "$PPID"' ;;
      interrupt-concurrent-edit:*/publish.0)
        printf '# concurrent administrator edit\n' >> "$hosts"
        /bin/sh -c 'kill -TERM "$PPID"' ;;
    esac
    return 0
  }
  rm() {
    command rm "$@" || return 1
    if [ "$hosts_fault_case" = interrupt-after-delete ]; then
      case "${2:-}" in */unleash-hosts.conf) /bin/sh -c 'kill -TERM "$PPID"' ;; esac
    fi
    return 0
  }
  hosts_fault_rc=0
  hosts_transaction "$root" "$hosts_fault_source" "$hosts_fault_action" || hosts_fault_rc=$?
  [ "$hosts_fault_rc" -eq 143 ]
  if [ "$hosts_fault_case" = interrupt-concurrent-edit ]; then
    grep -Fx '# concurrent administrator edit' "$hosts"
    hosts_fault_journal=$(find "$root/private/etc" -name '.unleash-hosts-backup.*' -type d | head -1)
    [ -n "$hosts_fault_journal" ]
    cmp "$HOSTS_TEST_ROOT/pre-interrupt-hosts" "$hosts_fault_journal/before.0"
    [ ! -f "$hosts_fault_journal/complete" ]
  else
    hosts_same_file "$HOSTS_TEST_ROOT/pre-interrupt-hosts" "$hosts"
    if [ "$hosts_fault_case" = interrupt-after-delete ]; then
      [ "$(find "$root/private/etc" -name '.unleash-hosts-backup.*' -type d | wc -l | tr -d ' ')" = 1 ]
    else
      [ -z "$(find "$root/private/etc" -name '.unleash-hosts-backup.*' -type d -print)" ]
    fi
  fi
  if [ -f "$HOSTS_TEST_ROOT/pre-interrupt-policy" ]; then
    hosts_same_file "$HOSTS_TEST_ROOT/pre-interrupt-policy" "$root/private/etc/unleash-hosts.conf"
  else
    [ ! -e "$root/private/etc/unleash-hosts.conf" ]
  fi
  [ ! -d "$root/private/etc/.unleash-hosts-lock" ]
  ;;
 failure)
  mv() {
    case "${2:-}" in */publish.1) return 1 ;; esac
    command mv "$@"
  }
  fail hosts_transaction "$root" "$policy"
  cmp "$HOSTS_TEST_ROOT/original" "$hosts"
  [ ! -e "$root/private/etc/unleash-hosts.conf" ]
  [ ! -d "$root/private/etc/.unleash-hosts-lock" ]
  ;;
 save)
  cmd_hosts save --root "$root" --policy "$policy"
  cmp "$HOSTS_TEST_ROOT/original" "$hosts"
  grep -Fx 'version 2' "$root/private/etc/unleash-hosts.conf"
  # Read-only CLI commands must also work for users other than the privileged writer.
  [ "$(stat -f %Lp "$root/private/etc/unleash-hosts.conf")" = 644 ]
  cmd_hosts preview --root "$root"
  cmd_hosts status --root "$root"
  cmd_hosts edit --root "$root" --plain </dev/null
  ;;
 confirmation-save|confirmation-apply|confirmation-cancel)
  for entry in a s; do
    cp "$HOSTS_TEST_ROOT/original" "$hosts"
    rm -f "$root/private/etc/unleash-hosts.conf"
    case "$1" in
      confirmation-save) choice=SAVE ;;
      confirmation-apply) choice=APPLY ;;
      confirmation-cancel) choice="" ;;
    esac
    printf '4\n%s\n%s\n\nq\n' "$entry" "$choice" | cmd_hosts edit --root "$root" --policy "$policy" --plain
    case "$choice" in
      SAVE)
        grep -Fx 'override acmdm.apple.com on' "$root/private/etc/unleash-hosts.conf"
        cmp "$HOSTS_TEST_ROOT/original" "$hosts" ;;
      APPLY)
        grep -Fx 'override acmdm.apple.com on' "$root/private/etc/unleash-hosts.conf"
        grep -Fx ':: acmdm.apple.com' "$hosts"
        grep -Fx ':: iprofiles.apple.com' "$hosts" ;;
      "")
        [ ! -e "$root/private/etc/unleash-hosts.conf" ]
        cmp "$HOSTS_TEST_ROOT/original" "$hosts" ;;
    esac
  done
  ;;
 numbered)
  printf '1\nOFF\na\nAPPLY\n\nq\n' | cmd_hosts edit --root "$root" --policy "$policy" --plain
  grep -Fx 'override iprofiles.apple.com off' "$root/private/etc/unleash-hosts.conf"
  ! grep -Fx ':: iprofiles.apple.com' "$hosts"
  grep -Fx ':: deviceenrollment.apple.com' "$hosts"
  ;;
 cancel-core)
  printf '1\nno\na\nAPPLY\n\nq\n' | cmd_hosts edit --root "$root" --policy "$policy" --plain
  grep -Fx ':: iprofiles.apple.com' "$hosts"
  ! grep -q '^override' "$root/private/etc/unleash-hosts.conf"
  ;;
 optional-ui)
  printf '4\na\nAPPLY\n\nr\na\nAPPLY\n\nq\n' | cmd_hosts edit --root "$root" --policy "$policy" --plain
  ! grep -Fx ':: acmdm.apple.com' "$hosts"
  grep -Fx ':: iprofiles.apple.com' "$hosts"
  ! grep -q '^override' "$root/private/etc/unleash-hosts.conf"
  ;;
 legacy-preset)
  for preset in enrollment custom off; do
    printf 'preset %s\n' "$preset" > "$policy"
    fail hosts_transaction "$root" "$policy"
    cmp "$HOSTS_TEST_ROOT/original" "$hosts"
  done
  ;;
 eof)
  cmd_hosts edit --root "$root" --policy "$policy" --plain </dev/null
  cmp "$HOSTS_TEST_ROOT/original" "$hosts"
  [ ! -e "$root/private/etc/unleash-hosts.conf" ]
  ;;
 full-uninstall)
  export HOSTS_UNINSTALL_ROOT="$HOSTS_TEST_ROOT/uninstall-system"
  mkdir -p "$HOSTS_UNINSTALL_ROOT/private/etc" "$HOSTS_UNINSTALL_ROOT/tmp" "$HOSTS_UNINSTALL_ROOT/Library/LaunchDaemons" "$HOSTS_UNINSTALL_ROOT/home"
  printf '127.0.0.1 localhost\n' > "$HOSTS_UNINSTALL_ROOT/private/etc/hosts"
  hosts_transaction "$HOSTS_UNINSTALL_ROOT" "$policy"
  cp -p "$HOSTS_UNINSTALL_ROOT/private/etc/hosts" "$HOSTS_TEST_ROOT/uninstall-before-hosts"
  cp -p "$HOSTS_UNINSTALL_ROOT/private/etc/unleash-hosts.conf" "$HOSTS_TEST_ROOT/uninstall-before-policy"
  touch "$HOSTS_UNINSTALL_ROOT/Library/LaunchDaemons/com.unleash.heal.plist" "$HOSTS_UNINSTALL_ROOT/Library/LaunchDaemons/com.unleash.monitor.plist"
  printf '424242\n' > "$HOSTS_UNINSTALL_ROOT/tmp/unleash-monitor.pid"
  python3 - "$HOSTS_TEST_DEFS" "$HOSTS_TEST_ROOT/uninstall-fixture.sh" <<'PYTHON'
import pathlib,re,sys
source=pathlib.Path(sys.argv[1]).read_text()
source=re.search(r'^do_uninstall\(\) \{.*?^\}', source,re.M|re.S)[0]
for prefix in ['/Library/', '/etc/', '/private/', '/tmp/']:
    source=source.replace(prefix, '${HOSTS_UNINSTALL_ROOT}'+prefix)
source=source.replace('hosts_remove ""', 'hosts_remove "$HOSTS_UNINSTALL_ROOT"')
source=source.replace('pfctl -f ${HOSTS_UNINSTALL_ROOT}/etc/pf.conf', 'pfctl -f "${HOSTS_UNINSTALL_ROOT}/etc/pf.conf"')
pathlib.Path(sys.argv[2]).write_text(source+'\n')
PYTHON
  source "$HOSTS_TEST_ROOT/uninstall-fixture.sh"
  is_root() { true; }
  header() { :; }
  begin() { :; }
  end_ok() { :; }
  end_fail() { :; }
  success() { :; }
  info() { :; }
  launchctl() { :; }
  pfctl() { :; } # Always a shell mock, never the workstation executable.
  kill() { [ "$1" = 424242 ]; touch "$HOSTS_TEST_ROOT/monitor-stopped"; }
  hosts_remove() {
    [ -f "$HOSTS_TEST_ROOT/monitor-stopped" ]
    [ ! -e "$HOSTS_UNINSTALL_ROOT/Library/LaunchDaemons/com.unleash.heal.plist" ]
    [ ! -e "$HOSTS_UNINSTALL_ROOT/Library/LaunchDaemons/com.unleash.monitor.plist" ]
    hosts_transaction "$1" /dev/null remove
  }
  HOME="$HOSTS_UNINSTALL_ROOT/home"
  cd "$HOSTS_UNINSTALL_ROOT"
  do_uninstall
  [ ! -e "$HOSTS_UNINSTALL_ROOT/private/etc/unleash-hosts.conf" ]
  [ "$(cat "$HOSTS_UNINSTALL_ROOT/private/etc/hosts")" = '127.0.0.1 localhost' ]
  found=false
  for candidate in "$HOSTS_UNINSTALL_ROOT/private/etc/".unleash-hosts-backup.*; do
    if [ -f "$candidate/before.1" ] && cmp -s "$HOSTS_TEST_ROOT/uninstall-before-policy" "$candidate/before.1"; then
      cmp "$HOSTS_TEST_ROOT/uninstall-before-hosts" "$candidate/before.0"
      [ -f "$candidate/complete" ]
      found=true
    fi
  done
  [ "$found" = true ]
  ;;
 remove)
  printf 'version 2\noverride iprofiles.apple.com off\noverride axm-adm-mdm.apple.com on\n' > "$policy"
  hosts_transaction "$root" "$policy"
  cp -p "$hosts" "$HOSTS_TEST_ROOT/installed-hosts"
  cp -p "$root/private/etc/unleash-hosts.conf" "$HOSTS_TEST_ROOT/installed-policy"
  hosts_remove "$root"
  cmp "$HOSTS_TEST_ROOT/original" "$hosts"
  [ ! -e "$root/private/etc/unleash-hosts.conf" ]
  cleanup_backup=""
  for candidate in "$root/private/etc/".unleash-hosts-backup.*; do
    if [ -f "$candidate/before.1" ] && cmp -s "$HOSTS_TEST_ROOT/installed-policy" "$candidate/before.1"; then cleanup_backup="$candidate"; fi
  done
  [ -n "$cleanup_backup" ] && [ -f "$cleanup_backup/complete" ]
  [ "$(stat -f %Lp "$cleanup_backup")" = 700 ]
  hosts_same_file "$HOSTS_TEST_ROOT/installed-hosts" "$cleanup_backup/before.0"
  hosts_same_file "$HOSTS_TEST_ROOT/installed-policy" "$cleanup_backup/before.1"
  # Cleanup itself is reversible, including the exact saved choices.
  hosts_transaction "$root" "$cleanup_backup" rollback
  hosts_same_file "$HOSTS_TEST_ROOT/installed-hosts" "$hosts"
  hosts_same_file "$HOSTS_TEST_ROOT/installed-policy" "$root/private/etc/unleash-hosts.conf"
  hosts_remove "$root"
  # A fresh apply/heal uses defaults, without inherited uninstall overrides.
  hosts_transaction "$root" "$root/private/etc/unleash-hosts.conf"
  [ "$(hosts_owned_count "$hosts")" = 3 ]
  for d in iprofiles.apple.com deviceenrollment.apple.com mdmenrollment.apple.com; do grep -Fx ":: $d" "$hosts"; done
  ! grep -Fx ':: axm-adm-mdm.apple.com' "$hosts"
  ! grep -q '^override' "$root/private/etc/unleash-hosts.conf"
  ;;
 remove-dry-run)
  hosts_transaction "$root" "$policy"
  cp -p "$hosts" "$HOSTS_TEST_ROOT/installed-hosts"
  cp -p "$root/private/etc/unleash-hosts.conf" "$HOSTS_TEST_ROOT/installed-policy"
  DRY_RUN=true hosts_remove "$root" > "$HOSTS_TEST_ROOT/cleanup-preview"
  grep -Fx -- '-0.0.0.0 iprofiles.apple.com' "$HOSTS_TEST_ROOT/cleanup-preview"
  hosts_same_file "$HOSTS_TEST_ROOT/installed-hosts" "$hosts"
  hosts_same_file "$HOSTS_TEST_ROOT/installed-policy" "$root/private/etc/unleash-hosts.conf"
  [ "$(find "$root/private/etc" -name '.unleash-hosts-backup.*' -type d | wc -l | tr -d ' ')" = 1 ]
  ;;
 remove-failure|remove-interrupt)
  hosts_transaction "$root" "$policy"
  cp -p "$hosts" "$HOSTS_TEST_ROOT/installed-hosts"
  cp -p "$root/private/etc/unleash-hosts.conf" "$HOSTS_TEST_ROOT/installed-policy"
  hosts_remove_fault="$1"
  rm() {
    if [ "$hosts_remove_fault" = remove-failure ]; then
      case "${2:-}" in */unleash-hosts.conf) return 1 ;; esac
    fi
    command rm "$@" || return 1
    if [ "$hosts_remove_fault" = remove-interrupt ]; then
      case "${2:-}" in */unleash-hosts.conf) /bin/sh -c 'kill -TERM "$PPID"' ;; esac
    fi
    return 0
  }
  cleanup_rc=0
  hosts_remove "$root" || cleanup_rc=$?
  if [ "$hosts_remove_fault" = remove-interrupt ]; then [ "$cleanup_rc" = 143 ]; else [ "$cleanup_rc" != 0 ]; fi
  hosts_same_file "$HOSTS_TEST_ROOT/installed-hosts" "$hosts"
  hosts_same_file "$HOSTS_TEST_ROOT/installed-policy" "$root/private/etc/unleash-hosts.conf"
  [ ! -d "$root/private/etc/.unleash-hosts-lock" ]
  ;;
 remove-invalid-policy)
  hosts_transaction "$root" "$policy"
  printf 'preset off\n' > "$root/private/etc/unleash-hosts.conf"
  cp "$root/private/etc/unleash-hosts.conf" "$HOSTS_TEST_ROOT/legacy-policy"
  hosts_remove "$root"
  cmp "$HOSTS_TEST_ROOT/original" "$hosts"
  [ ! -e "$root/private/etc/unleash-hosts.conf" ]
  found=false
  for candidate in "$root/private/etc/".unleash-hosts-backup.*; do
    if [ -f "$candidate/before.1" ] && cmp -s "$HOSTS_TEST_ROOT/legacy-policy" "$candidate/before.1"; then found=true; fi
  done
  [ "$found" = true ]
  ;;

esac
[ ! -e "$HOSTS_TEST_ROOT/unexpected" ]
