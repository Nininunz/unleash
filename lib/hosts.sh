# Hosts-file policy only. No PF, VPN, resolver-cache, or network operations.
# Compare checked hexadecimal byte streams. Bash read cannot distinguish EOF
# from an I/O error; od reports read failures and preserves NULs and final LF.
# Missing utilities and partial reads fail closed with status 2.
hosts_files_equal() {
  (
    LC_ALL=C; export LC_ALL
    [ -f "$1" ] && [ -r "$1" ] && [ -f "$2" ] && [ -r "$2" ] || exit 2
    left=$(od -An -v -tx1 "$1") || exit 2
    right=$(od -An -v -tx1 "$2") || exit 2
    [ "$left" = "$right" ]
  )
}

# Append a sentinel only after a successful read. Holding the final record
# distinguishes a missing final newline; pipefail also catches partial cat reads.
hosts_preview_lines() {
  (
    set -o pipefail
    { cat "$2" || exit 2; printf '\001'; } |
      LC_ALL=C awk -v prefix="$1" '
        NR>1 {print prefix previous}
        {previous=$0}
        END {
          if(substr(previous,length(previous),1)!=sprintf("%c",1)) exit 2
          last=substr(previous,1,length(previous)-1)
          if(length(last)) {
            print prefix last
            print "\\ No newline at end of file"
          }
        }
      '
  )
}

# Recovery may lack diff. Display a complete replacement hunk in that case.
hosts_preview_diff() {
  if command -v diff >/dev/null 2>&1; then
    diff -u -L current-hosts -L proposed-hosts "$1" "$2"
    return $?
  fi
  local result=0 old_count new_count old_start=1 new_start=1 prefix file
  hosts_files_equal "$1" "$2" || result=$?
  [ "$result" -ne 0 ] || return 0
  [ "$result" -eq 1 ] || return 2
  old_count=$(awk 'END {print NR+0}' "$1") || return 2
  new_count=$(awk 'END {print NR+0}' "$2") || return 2
  [ "$old_count" -ne 0 ] || old_start=0
  [ "$new_count" -ne 0 ] || new_start=0
  printf '%s\n' '--- current-hosts' '+++ proposed-hosts'
  printf '@@ -%s,%s +%s,%s @@\n' "$old_start" "$old_count" "$new_start" "$new_count"
  for prefix in - +; do
    if [ "$prefix" = - ]; then file="$1"; else file="$2"; fi
    hosts_preview_lines "$prefix" "$file" || return 2
  done
  return 1
}

hosts_same_file() {
  [ ! -L "$2" ] && hosts_files_equal "$1" "$2" && [ "$(stat -f '%u:%g:%Lp' "$1")" = "$(stat -f '%u:%g:%Lp' "$2")" ]
}

hosts_resolve() {
  local policy="${1:-/dev/null}" format="${2:-rows}"
  [ -e "$policy" ] || policy=/dev/null
  awk -v format="$format" '
    function add(h) { if (!(h in known)) { known[h]=1; order[++count]=h } }
    function host(s, n,a,i) {
      s=tolower(s); sub(/[.]$/, "", s)
      if (length(s)>253 || s !~ /^[a-z0-9.-]+$/ || s ~ /^[0-9.]+$/) return ""
      n=split(s,a,"."); if(n<2) return ""
      for(i=1;i<=n;i++) if(length(a[i])<1 || length(a[i])>63 || a[i] !~ /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/) return ""
      return s
    }
    function fail() { print "Invalid hosts policy at line " NR > "/dev/stderr"; bad=1 }
    BEGIN {
      add("iprofiles.apple.com"); add("deviceenrollment.apple.com"); add("mdmenrollment.apple.com")
      for(i=1;i<=count;i++) core[order[i]]=1
      split("acmdm.apple.com axm-adm-mdm.apple.com albert.apple.com ax.init-content.apple.com init-content.apple.com xp.apple.com tb.apple.com vpp.itunes.apple.com", extras, " ")
      for(i=1;i<=8;i++) add(extras[i])
    }
    /^[[:space:]]*(#|$)/ { next }
    $1=="version" && NF==2 && $2=="2" { if(seenversion++) fail(); next }
    $1=="optional" && NF==2 {
      h=host($2); if(h=="" || core[h]) {fail(); next}; add(h); optional[h]=1; next
    }
    $1=="override" && NF==3 && $3 ~ /^(on|off)$/ {
      h=host($2); if(h=="" || (h in override)) {fail(); next}; add(h); override[h]=$3; next
    }
    { fail() }
    END {
      if(bad) { print "Use version 2 with optional HOST and override HOST on/off; legacy presets require explicit conversion." > "/dev/stderr"; exit 1 }
      if(format=="config") print "version 2"
      for(i=1;i<=count;i++) {
        h=order[i]; state=(h in override)?override[h]:"default"
        if((core[h] && state=="on") || (!core[h] && state=="off")) state="default"
        present=(state=="on" || (state=="default" && core[h]))
        if(format=="config") {
          if(!core[h] && (optional[h] || i>11)) print "optional " h
          if(state!="default") print "override " h " " state
        } else print h "\t" state "\t" (present?"present":"absent") "\t" (core[h]?"core":"optional")
      }
    }
  ' "$policy"
}

hosts_strip_owned() {
  local file="$1" mode="${2:-base}"
  awk -v mode="$mode" '
    function mapping() { return NF==2 && ($1=="0.0.0.0" || $1=="::") && $2 ~ /^[a-zA-Z0-9.-]+$/ }
    function owned() { if(mode=="owned") print tolower($2) "\t" $1 }
    BEGIN {
      split("iprofiles.apple.com deviceenrollment.apple.com mdmenrollment.apple.com acmdm.apple.com axm-adm-mdm.apple.com albert.apple.com gdmf.apple.com ax.init-content.apple.com init-content.apple.com xp.apple.com gs.apple.com tb.apple.com vpp.itunes.apple.com configuration.apple.com",list," ")
      for(i in list) legacyhost[list[i]]=1
    }
    $0=="# BEGIN Unleash hosts" { if(inside || seen++) bad=1; inside=1; legacy=0; next }
    $0=="# END Unleash hosts" { if(!inside) bad=1; inside=0; next }
    inside { if(!mapping()) bad=1; else owned(); next }
    $0=="# Added by unleash — DEP enrollment block" { legacy=1; next }
    legacy && mapping() && (tolower($2) in legacyhost) { owned(); next }
    { legacy=0; if(mode=="base") print }
    END { if(inside || bad) { print "Malformed owned hosts section or non-mapping content; preserving file" > "/dev/stderr"; exit 1 } }
  ' "$file"
}

hosts_candidate() {
  local original="$1" policy="$2" output="$3" rows="$4"
  hosts_resolve "$policy" > "$rows" || return 1
  hosts_strip_owned "$original" > "$output" || return 1
  if awk -F '\t' '$3=="present" { found=1 } END { exit !found }' "$rows"; then
    {
      printf '# BEGIN Unleash hosts\n'
      awk -F '\t' '$3=="present" { printf "0.0.0.0 %s\n:: %s\n",$1,$1 }' "$rows"
      printf '# END Unleash hosts\n'
    } >> "$output" || return 1
  fi
}

hosts_preview() {
  (
    hosts_preview_tmp=$(mktemp -d) || exit 1
    trap 'rm -rf "$hosts_preview_tmp"' EXIT
    : > "$hosts_preview_tmp/empty"
    hosts_preview_original="$1"
    [ -f "$hosts_preview_original" ] || hosts_preview_original="$hosts_preview_tmp/empty"
    if [ "${3:-apply}" = remove ]; then
      hosts_strip_owned "$hosts_preview_original" > "$hosts_preview_tmp/candidate" || exit 1
      printf 'Would remove owned entries and clear active policy; retain a private recovery snapshot.\n'
    else
      hosts_resolve "$2" config > "$hosts_preview_tmp/policy" || exit 1
      hosts_candidate "$hosts_preview_original" "$hosts_preview_tmp/policy" "$hosts_preview_tmp/candidate" "$hosts_preview_tmp/rows" || exit 1
    fi
    printf 'Hosts entries only; PF/VPN unchanged. Off removes owned mappings only; it is not a network allow rule.\n'
    hosts_preview_rc=0
    hosts_preview_diff "$hosts_preview_original" "$hosts_preview_tmp/candidate" || hosts_preview_rc=$?
    [ "$hosts_preview_rc" -le 1 ]
  )
}

hosts_transaction_finish() {
  local result="$1" i failed=false
  trap - EXIT HUP INT TERM
  if [ "$result" -ne 0 ]; then
    for ((i=1;i>=0;i--)); do
      [ "${hosts_tx_started[$i]}" = true ] || continue
      # Intent is recorded before mutation. If interrupted before the rename or
      # deletion took effect, the original already matches and needs no restore.
      if { [ "${hosts_tx_existed[$i]}" = true ] && [ -f "$hosts_tx_dir/before.$i" ] && hosts_same_file "$hosts_tx_dir/before.$i" "${hosts_tx_paths[$i]}"; } \
        || { [ "${hosts_tx_existed[$i]}" = false ] && [ ! -e "${hosts_tx_paths[$i]}" ] && [ ! -L "${hosts_tx_paths[$i]}" ]; }; then
        continue
      fi
      if { [ -f "$hosts_tx_dir/after.$i" ] && [ ! -L "${hosts_tx_paths[$i]}" ] && hosts_same_file "$hosts_tx_dir/after.$i" "${hosts_tx_paths[$i]}"; } \
        || { [ ! -e "$hosts_tx_dir/after.$i" ] && [ ! -e "${hosts_tx_paths[$i]}" ] && [ ! -L "${hosts_tx_paths[$i]}" ]; }; then
        if [ "${hosts_tx_existed[$i]}" = true ]; then
          if [ ! -f "$hosts_tx_dir/before.$i" ] || ! cp -p "$hosts_tx_dir/before.$i" "$hosts_tx_dir/restore.$i" || ! mv -f "$hosts_tx_dir/restore.$i" "${hosts_tx_paths[$i]}"; then failed=true; fi
        elif ! rm -f "${hosts_tx_paths[$i]}"; then failed=true
        fi
      else
        printf 'Concurrent edit preserved: %s\n' "${hosts_tx_paths[$i]}" >&2
        failed=true
      fi
    done
    if [ "$failed" = false ]; then rm -rf "$hosts_tx_dir"; else printf 'Incomplete hosts rollback; inspect journal: %s\n' "$hosts_tx_dir" >&2; fi
  else
    if [ "$hosts_tx_action" = remove ]; then
      printf 'Owned hosts entries and active policy removed. Rollback snapshot: %s\n' "$hosts_tx_dir"
    else
      printf 'Hosts policy saved/applied. Rollback snapshot: %s\n' "$hosts_tx_dir"
    fi
  fi
  rmdir "$hosts_tx_lock" 2>/dev/null || true
  exit "$result"
}

hosts_transaction() {
  (
    # Subshell variables survive until the Bash 3.2 EXIT trap (function locals do not).
    hosts_tx_root="${1%/}" hosts_tx_source="$2" hosts_tx_action="${3:-apply}"
    hosts_tx_parent="$hosts_tx_root/private/etc"
    hosts_tx_paths=("$hosts_tx_parent/hosts" "$hosts_tx_parent/unleash-hosts.conf")
    if [ "${DRY_RUN:-false}" = true ]; then hosts_preview "${hosts_tx_paths[0]}" "$hosts_tx_source" "$hosts_tx_action"; exit $?; fi
    case "$hosts_tx_action" in apply|save|rollback|remove) ;; *) exit 1 ;; esac
    # Validate before creating directories, locks or backups.
    if [ "$hosts_tx_action" = rollback ]; then
      [ -f "$hosts_tx_source/complete" ] && [ -f "$hosts_tx_source/manifest" ] || exit 1
      [ "$(sed -n '1p' "$hosts_tx_source/manifest")" = 'Unleash hosts snapshot v1' ] && [ "$(sed -n '2p' "$hosts_tx_source/manifest")" = "$hosts_tx_parent" ] || { printf 'Snapshot does not belong to this target\n' >&2; exit 1; }
    fi
    if [ "$hosts_tx_action" != rollback ] && [ "$hosts_tx_action" != remove ]; then hosts_resolve "$hosts_tx_source" config > /dev/null || exit 1; fi
    for hosts_tx_path in "$hosts_tx_parent" "${hosts_tx_paths[@]}"; do
      hosts_tx_check="$hosts_tx_path"
      while [ "$hosts_tx_check" != / ] && [ "$hosts_tx_check" != . ]; do
        case "$hosts_tx_check" in /var|/tmp) if [ "$(readlink "$hosts_tx_check" 2>/dev/null)" = "private$hosts_tx_check" ]; then break; fi ;; esac
        [ ! -L "$hosts_tx_check" ] || { printf 'Refusing symlink target: %s\n' "$hosts_tx_check" >&2; exit 1; }
        hosts_tx_check=$(dirname "$hosts_tx_check")
      done
      [ ! -e "$hosts_tx_path" ] || [ -f "$hosts_tx_path" ] || [ "$hosts_tx_path" = "$hosts_tx_parent" ] || exit 1
    done
    mkdir -p "$hosts_tx_parent" || exit 1
    hosts_tx_lock="$hosts_tx_parent/.unleash-hosts-lock"
    (umask 077; mkdir "$hosts_tx_lock") 2>/dev/null || { printf 'Hosts policy transaction busy\n' >&2; exit 1; }
    hosts_tx_dir=$(mktemp -d "$hosts_tx_parent/.unleash-hosts-backup.XXXXXX") || { rmdir "$hosts_tx_lock"; exit 1; }
    hosts_tx_started=(false false) hosts_tx_existed=(false false)
    trap 'hosts_transaction_finish $?' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    for hosts_tx_i in 0 1; do
      if [ -f "${hosts_tx_paths[$hosts_tx_i]}" ]; then
        hosts_tx_existed[hosts_tx_i]=true
        cp -p "${hosts_tx_paths[$hosts_tx_i]}" "$hosts_tx_dir/before.$hosts_tx_i" || exit 1
        : > "$hosts_tx_dir/present.$hosts_tx_i"
      else
        : > "$hosts_tx_dir/absent.$hosts_tx_i"
      fi
    done
    if [ "$hosts_tx_action" = rollback ]; then
      # Explicit snapshot, never a guessed latest backup or a sourced shell file.
      for hosts_tx_i in 0 1; do
        if [ -f "$hosts_tx_source/present.$hosts_tx_i" ]; then
          [ ! -e "$hosts_tx_source/absent.$hosts_tx_i" ] && [ -f "$hosts_tx_source/before.$hosts_tx_i" ] || exit 1
        else
          [ -f "$hosts_tx_source/absent.$hosts_tx_i" ] && [ ! -e "$hosts_tx_source/before.$hosts_tx_i" ] || exit 1
        fi
        if [ -f "$hosts_tx_source/after.$hosts_tx_i" ]; then
          hosts_same_file "$hosts_tx_source/after.$hosts_tx_i" "${hosts_tx_paths[$hosts_tx_i]}" || { printf 'Changed since snapshot; refusing stale rollback\n' >&2; exit 1; }
        else
          [ ! -e "${hosts_tx_paths[$hosts_tx_i]}" ] || exit 1
        fi
        if [ -f "$hosts_tx_source/present.$hosts_tx_i" ]; then
          cp -p "$hosts_tx_source/before.$hosts_tx_i" "$hosts_tx_dir/after.$hosts_tx_i" || exit 1
        fi
      done
    elif [ "$hosts_tx_action" = remove ]; then
      # Cleanup is not a policy preference. Retain both originals in the private
      # snapshot, publish only unrelated hosts content, and delete active policy.
      if [ -f "$hosts_tx_dir/before.0" ]; then
        cp -p "$hosts_tx_dir/before.0" "$hosts_tx_dir/after.0" || exit 1
        hosts_strip_owned "$hosts_tx_dir/before.0" > "$hosts_tx_dir/after.0" || exit 1
      fi
      # No after.1: transactionally remove policy instead of persisting Off overrides.
    else
      if [ -f "$hosts_tx_dir/before.1" ]; then cp -p "$hosts_tx_dir/before.1" "$hosts_tx_dir/after.1" || exit 1; fi
      hosts_resolve "$hosts_tx_source" config > "$hosts_tx_dir/after.1" || exit 1
      chmod 644 "$hosts_tx_dir/after.1" || exit 1
      : > "$hosts_tx_dir/empty"
      hosts_tx_original="$hosts_tx_dir/empty"
      [ ! -f "$hosts_tx_dir/before.0" ] || hosts_tx_original="$hosts_tx_dir/before.0"
      if [ "$hosts_tx_action" = save ]; then
        if [ -f "$hosts_tx_dir/before.0" ]; then cp -p "$hosts_tx_dir/before.0" "$hosts_tx_dir/after.0" || exit 1; fi
      else
        if [ -f "$hosts_tx_dir/before.0" ]; then cp -p "$hosts_tx_dir/before.0" "$hosts_tx_dir/after.0" || exit 1; fi
        hosts_candidate "$hosts_tx_original" "$hosts_tx_dir/after.1" "$hosts_tx_dir/after.0" "$hosts_tx_dir/rows" || exit 1
        if [ ! -f "$hosts_tx_dir/before.0" ]; then chmod 644 "$hosts_tx_dir/after.0" || exit 1; fi
      fi
    fi
    printf 'Unleash hosts snapshot v1\n%s\n' "$hosts_tx_parent" > "$hosts_tx_dir/manifest" || exit 1
    for hosts_tx_i in 0 1; do
      if [ "${hosts_tx_existed[$hosts_tx_i]}" = true ]; then
        hosts_same_file "$hosts_tx_dir/before.$hosts_tx_i" "${hosts_tx_paths[$hosts_tx_i]}" || exit 1
      else
        [ ! -e "${hosts_tx_paths[$hosts_tx_i]}" ] && [ ! -L "${hosts_tx_paths[$hosts_tx_i]}" ] || exit 1
      fi
      if [ -f "$hosts_tx_dir/after.$hosts_tx_i" ] && [ -f "$hosts_tx_dir/before.$hosts_tx_i" ] && hosts_same_file "$hosts_tx_dir/after.$hosts_tx_i" "$hosts_tx_dir/before.$hosts_tx_i"; then continue; fi
      if [ -f "$hosts_tx_dir/after.$hosts_tx_i" ]; then
        cp -p "$hosts_tx_dir/after.$hosts_tx_i" "$hosts_tx_dir/publish.$hosts_tx_i" || exit 1
        # Register intent first: traps can run after mv succeeds but before the
        # next shell statement. Recovery checks the actual file state above.
        hosts_tx_started[hosts_tx_i]=true
        mv -f "$hosts_tx_dir/publish.$hosts_tx_i" "${hosts_tx_paths[$hosts_tx_i]}" || exit 1
      else
        hosts_tx_started[hosts_tx_i]=true
        rm -f "${hosts_tx_paths[$hosts_tx_i]}" || exit 1
      fi
    done
    : > "$hosts_tx_dir/complete" || exit 1
    exit 0
  )
}

hosts_owned_count() {
  if [ ! -f "$1" ]; then printf '0\n'; return 0; fi
  local entries
  entries=$(hosts_strip_owned "$1" owned) || return 1
  printf '%s\n' "$entries" | awk -F '\t' 'NF==2 && !seen[$1]++ {n++} END { print n+0 }'
}

hosts_status() {
  local file="$1" policy="$2" desired observed rows
  rows=$(hosts_resolve "$policy") || return 1
  desired=$(printf '%s\n' "$rows" | awk -F '\t' '$3=="present" {n++} END { print n+0 }') || return 1
  observed=$(hosts_owned_count "$file") || return 1
  printf 'Hosts policy: %s desired domains; %s observed owned domains (not a reachability test).\n' "$desired" "$observed"
}

hosts_policy_matches() {
  (
    hosts_match_tmp=$(mktemp -d) || exit 1
    trap 'rm -rf "$hosts_match_tmp"' EXIT
    [ -f "$1/private/etc/hosts" ] || exit 1
    hosts_candidate "$1/private/etc/hosts" "$1/private/etc/unleash-hosts.conf" "$hosts_match_tmp/candidate" "$hosts_match_tmp/rows" || exit 1
    hosts_files_equal "$1/private/etc/hosts" "$hosts_match_tmp/candidate"
  )
}

hosts_remove() {
  hosts_transaction "${1:-}" /dev/null remove
}

hosts_restore_owned_backup() {
  (
    hosts_restore_tmp=$(mktemp -d) || exit 1
    trap 'rm -rf "$hosts_restore_tmp"' EXIT
    hosts_strip_owned "$2" owned > "$hosts_restore_tmp/owned" || exit 1
    if [ ! -s "$hosts_restore_tmp/owned" ]; then
      printf 'No identifiable owned entries in raw backup; explicit migration or a complete hosts snapshot is required.\n' >&2
      exit 1
    fi
    hosts_restore_current=$(hosts_resolve "$1/private/etc/unleash-hosts.conf" config) || exit 1
    printf 'version 2\n' > "$hosts_restore_tmp/policy"
    # Raw mappings do not encode approval to disable a core host. Keep current
    # explicit core overrides; exact historical choices require snapshot rollback.
    printf '%s\n' "$hosts_restore_current" | awk '$1=="optional" || ($1=="override" && ($2=="iprofiles.apple.com" || $2=="deviceenrollment.apple.com" || $2=="mdmenrollment.apple.com"))' >> "$hosts_restore_tmp/policy" || exit 1
    hosts_resolve /dev/null > "$hosts_restore_tmp/defaults" || exit 1
    awk -F '\t' 'FILENAME==ARGV[1] {if(NF==2) owned[$1]=1; next}
      {seen[$1]=1; if($4!="core" && owned[$1]) print "override " $1 " on"}
      END {for(h in owned) if(!seen[h]) {print "optional " h; print "override " h " on"}}' "$hosts_restore_tmp/owned" "$hosts_restore_tmp/defaults" >> "$hosts_restore_tmp/policy" || exit 1
    # Restore recognized owned mappings only. Never copy unrelated stale mappings.
    hosts_transaction "$1" "$hosts_restore_tmp/policy" apply
  )
}
