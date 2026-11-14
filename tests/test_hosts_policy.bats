#!/usr/bin/env bats
setup() {
  export HOSTS_TEST_PTY="$BATS_TEST_DIRNAME/helpers/hosts-policy-pty.py"
  export HOSTS_TEST_ROOT="$BATS_TEST_TMPDIR/hosts policy"
  export HOSTS_TEST_DEFS="$BATS_TEST_TMPDIR/hosts-definitions.sh"
  mkdir -p "$HOSTS_TEST_ROOT"
}
check_case() {
  local artifact
  for artifact in modules standalone; do
    python3 - "$BATS_TEST_DIRNAME/.." "$artifact" "$HOSTS_TEST_DEFS" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
module_source = '\n'.join((root/p).read_text() for p in ['lib/hosts.sh', 'lib/hosts_ui.sh', 'lib/uninstall.sh'])
source = (root/'unleash-standalone.sh').read_text() if sys.argv[2] == 'standalone' else module_source
names = re.findall(r'^(\w+)\(\) \{', module_source, re.M)
functions = []
for name in names:
    matches = re.findall(r'^'+name+r'\(\) \{.*?^\}', source, re.M | re.S)
    assert len(matches) == 1, name
    functions.extend(matches)
pathlib.Path(sys.argv[3]).write_text('\n'.join(functions)+'\n')
PY
    run /bin/bash -euo pipefail "$BATS_TEST_DIRNAME/helpers/hosts-policy-case.bash" "$1"
    [ "$status" -eq 0 ]
    rm -rf "$HOSTS_TEST_ROOT"
    mkdir -p "$HOSTS_TEST_ROOT"
  done
}

@test "default owns exactly three dual-stack domains and preserves unrelated aliases" {
  check_case default
}

@test "core overrides and optional toggles normalize and reset correctly" {
  check_case overrides
}

@test "invalid and executable-looking policy never changes target files" {
  check_case invalid
}

@test "migration removes only identifiable legacy entries and keeps a snapshot" {
  check_case migration
}

@test "foreign content inside owned sections fails without modifying hosts" {
  check_case malformed
}

@test "preview and dry-run show changes without creating target state" {
  check_case preview
}

@test "explicit snapshot rollback restores previous files and metadata" {
  check_case rollback
}

@test "rollback refuses to overwrite later administrator edits" {
  check_case stale
}

@test "failed policy publication restores original hosts" {
  check_case failure
}

@test "saving choices does not apply hosts entries" {
  check_case save
}

@test "numbered selector previews and applies only after explicit confirmation" {
  check_case numbered
}

@test "selector EOF exits without saving or applying" {
  check_case eof
}

@test "uninstall clears policy, keeps a private backup, and fresh apply restores defaults" {
  check_case remove
}

@test "PTY arrows preserves terminal and policy state" {
  check_case pty-arrows
}

@test "PTY resize preserves terminal and policy state" {
  check_case pty-resize
}

@test "PTY failed-stty preserves terminal and policy state" {
  check_case pty-failed-stty
}

@test "PTY small preserves terminal and policy state" {
  check_case pty-small
}

@test "PTY interrupt preserves terminal and policy state" {
  check_case pty-interrupt
}

@test "PTY missing-stty preserves terminal and policy state" {
  check_case pty-missing-stty
}

@test "PTY color preserves terminal and policy state" {
  check_case pty-color
}

@test "unmarked raw restore preserves all current blocks and policy" {
  check_case legacy-restore
}

@test "rollback preserves metadata changes made after application" {
  check_case metadata-stale
}

@test "PTY slate-truecolor selects supported shortcut colors" {
  check_case pty-slate-truecolor
}

@test "PTY slate-fallback selects supported shortcut colors" {
  check_case pty-slate-fallback
}

@test "core disable requires confirmation" {
  check_case cancel-core
}

@test "optional host toggle and reset keep core enabled" {
  check_case optional-ui
}

@test "legacy global presets cannot silently disable or re-enable cores" {
  check_case legacy-preset
}

@test "partial raw restore preserves explicit core choices and other core defaults" {
  check_case raw-partial
}

@test "SAVE saves only choices from either confirmation entrypoint" {
  check_case confirmation-save
}

@test "APPLY updates hosts from either confirmation entrypoint" {
  check_case confirmation-apply
}

@test "Enter cancels both confirmation entrypoints without writes" {
  check_case confirmation-cancel
}

@test "termination before hosts rename leaves original state intact" {
  check_case interrupt-before-hosts
}

@test "termination immediately after hosts rename restores original state" {
  check_case interrupt-after-hosts
}

@test "termination immediately after policy rename restores both files" {
  check_case interrupt-after-policy
}

@test "termination immediately after policy deletion rolls back the rollback" {
  check_case interrupt-after-delete
}

@test "termination preserves concurrent edits and retains recovery journal" {
  check_case interrupt-concurrent-edit
}

@test "uninstall dry run previews removal without clearing policy" {
  check_case remove-dry-run
}

@test "failed policy deletion restores installed hosts and policy" {
  check_case remove-failure
}

@test "interrupted uninstall restores installed hosts and policy" {
  check_case remove-interrupt
}

@test "uninstall backs up and clears legacy policy without interpreting it" {
  check_case remove-invalid-policy
}

@test "full uninstall stops background writers before hosts cleanup and retains its snapshot" {
  check_case full-uninstall
}

@test "PTY Ctrl-C during idle key read restores terminal and returns 130" {
  check_case pty-interrupt-idle
}

@test "editor policy generation failure aborts before input without writes" {
  check_case editor-policy-failure
}

@test "exact comparison preserves NULs final newlines and arbitrary bytes" {
  check_case exact-comparison
}

@test "Recovery preview apply matching and rollback run without cmp or diff" {
  check_case recovery-utilities
}

@test "Recovery preview rejects an input disappearing after line counting" {
  check_case preview-disappeared-input
}

@test "Recovery partial read aborts editor before APPLY confirmation or writes" {
  check_case preview-partial-read
}

@test "comparison rejects empty and partial read failures on either input" {
  check_case comparison-read-failure
}
