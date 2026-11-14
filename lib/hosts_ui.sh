# CLI and dependency-free terminal editor for hosts policy.
cmd_hosts() {
  local action="${1:-preview}" root="" policy="" backup="" plain=false
  [ "$#" -eq 0 ] || shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root|--policy|--backup)
        [ "$#" -ge 2 ] && [ -n "$2" ] || { printf 'Missing value for %s\n' "$1" >&2; return 1; }
        case "$1" in --root) root="$2" ;; --policy) policy="$2" ;; --backup) backup="$2" ;; esac
        shift 2 ;;
      --plain) plain=true; shift ;;
      *) printf 'Unknown hosts option: %s\n' "$1" >&2; return 1 ;;
    esac
  done
  if [ -n "$root" ]; then
    case "$root" in /*) ;; *) printf 'Target root must be absolute\n' >&2; return 1 ;; esac
    root=$(cd "$root" && pwd -P) || return 1
    [ "$root" != / ] || root=""
  fi
  local hosts="$root/private/etc/hosts" saved="$root/private/etc/unleash-hosts.conf"
  if [ -n "$policy" ]; then
    [ -f "$policy" ] || { printf 'Policy file not found\n' >&2; return 1; }
  else policy="$saved"
  fi
  case "$action" in
    preview) hosts_preview "$hosts" "$policy" ;;
    status) hosts_status "$hosts" "$policy" ;;
    edit) hosts_editor "$root" "$policy" "$plain" ;;
    apply|save)
      if [ -z "$root" ] && [ "${DRY_RUN:-false}" != true ] && ! is_root; then printf 'Applying/saving live hosts policy requires sudo\n' >&2; return 1; fi
      hosts_transaction "$root" "$policy" "$action" ;;
    rollback)
      [ -n "$backup" ] || { printf 'Rollback requires --backup SNAPSHOT_DIRECTORY\n' >&2; return 1; }
      if [ "${DRY_RUN:-false}" = true ]; then printf '[dry-run] Rollback requires matching current files; no changes\n'; return 0; fi
      if [ -z "$root" ] && ! is_root; then printf 'Live rollback requires sudo\n' >&2; return 1; fi
      hosts_transaction "$root" "$backup" rollback ;;
    *) printf 'Usage: unleash hosts {edit|preview|status|apply|save|rollback} [--root DIR] [--policy FILE] [--plain] [--backup DIR]\n' >&2; return 1 ;;
  esac
}

hosts_editor_restore() {
  if [ -n "$hosts_ui_stty" ]; then stty "$hosts_ui_stty" 2>/dev/null || true; fi
  hosts_ui_stty=""
  if [ "$hosts_ui_arrows" = true ]; then printf '\033[0m\033[?25h\033[?1049l'; fi
  hosts_ui_arrows=false
}

hosts_editor_policy() {
  local i
  printf 'version 2\n'
  awk '$1=="optional" {print}' "$hosts_ui_tmp/original"
  for ((i=0;i<${#hosts_ui_domains[@]};i++)); do
    [ "${hosts_ui_overrides[$i]}" = default ] || printf 'override %s %s\n' "${hosts_ui_domains[$i]}" "${hosts_ui_overrides[$i]}"
  done
}

hosts_editor() {
  (
    hosts_ui_root="$1" hosts_ui_policy="$2" hosts_ui_plain="$3"
    hosts_ui_tmp=$(mktemp -d) || exit 1
    hosts_ui_stty="" hosts_ui_arrows=false
    # Subshell state survives Bash 3.2 EXIT handling; restore before every line prompt.
    trap 'hosts_editor_restore; rm -rf "$hosts_ui_tmp"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
    hosts_resolve "$hosts_ui_policy" config > "$hosts_ui_tmp/original" || exit 1
    hosts_resolve "$hosts_ui_policy" > "$hosts_ui_tmp/rows" || exit 1
    hosts_ui_domains=() hosts_ui_overrides=() hosts_ui_selected=0
    while IFS=$'\t' read -r hosts_ui_domain hosts_ui_override hosts_ui_result hosts_ui_category; do
      hosts_ui_domains+=("$hosts_ui_domain"); hosts_ui_overrides+=("$hosts_ui_override")
    done < "$hosts_ui_tmp/rows"
    hosts_ui_color="" hosts_ui_reset="" hosts_ui_present="" hosts_ui_absent="" hosts_ui_amber="" hosts_ui_shortcut="" hosts_ui_help="" hosts_ui_header=""
    hosts_ui_capable=false
    case "${TERM:-dumb}" in xterm*|screen*|tmux*|vt100|vt220|ansi|rxvt*|linux) hosts_ui_capable=true ;; esac
    if [ -t 1 ] && [ "$hosts_ui_capable" = true ] && [ "${NO_COLOR+x}" != x ]; then
      hosts_ui_color=$'\033[36m'; hosts_ui_reset=$'\033[0m'; hosts_ui_present=$'\033[32m'; hosts_ui_absent=$'\033[2m'; hosts_ui_amber=$'\033[33m'; hosts_ui_shortcut=$'\033[37m'
      # Recovery/unadvertised terminals use readable standard light gray.
      # Apple Terminal commonly advertises 256 colors rather than true color.
      hosts_ui_help=$'\033[37m'
      hosts_ui_header=$'\033[1;37m'
      case "${COLORTERM:-}:${TERM:-}" in
        truecolor:*|24bit:*|*:*-direct) hosts_ui_shortcut=$'\033[38;2;143;175;199m'; hosts_ui_help=$'\033[38;2;208;208;208m'; hosts_ui_header=$'\033[1;37m' ;;
        *:*256color*) hosts_ui_shortcut=$'\033[38;5;110m'; hosts_ui_help=$'\033[38;5;252m'; hosts_ui_header=$'\033[1;37m' ;;
      esac
    fi
    while :; do
      if [ "$hosts_ui_plain" = false ] && [ "$hosts_ui_capable" = true ] && [ -t 0 ] && [ -t 1 ] && command -v stty >/dev/null 2>&1; then
        hosts_ui_stty=$(stty -g 2>/dev/null) || hosts_ui_stty=""
        hosts_ui_size=$(stty size 2>/dev/null) || hosts_ui_size='0 0'
        read -r hosts_ui_rows hosts_ui_columns <<< "$hosts_ui_size"
        case "$hosts_ui_rows:$hosts_ui_columns" in *[!0-9:]*|:*|*:) hosts_ui_rows=0; hosts_ui_columns=0 ;; esac
        if [ -n "$hosts_ui_stty" ] && [ "$hosts_ui_rows" -ge "$((${#hosts_ui_domains[@]}+13))" ] && [ "$hosts_ui_columns" -ge 70 ] && stty -echo -icanon min 1 time 0 2>/dev/null; then
          hosts_ui_arrows=true
          printf '\033[?1049h\033[?25l\033[H\033[2J'
        else hosts_editor_restore; hosts_ui_plain=true
        fi
      fi
      hosts_editor_policy > "$hosts_ui_tmp/current"
      hosts_resolve "$hosts_ui_tmp/current" > "$hosts_ui_tmp/rows" || exit 1
      printf '%sHOSTS POLICY%s\n' "$hosts_ui_color" "$hosts_ui_reset"
      printf 'Owned hosts entries only. PF/VPN unchanged.\n\n'
      hosts_ui_section=""
      hosts_ui_i=0
      while IFS=$'\t' read -r hosts_ui_domain hosts_ui_override hosts_ui_result hosts_ui_category; do
        if [ "$hosts_ui_category" != "$hosts_ui_section" ]; then
          [ -z "$hosts_ui_section" ] || printf '\n'
          case "$hosts_ui_category" in
            core) printf '%sCORE — On by default%s\n' "$hosts_ui_header" "$hosts_ui_reset" ;;
            optional) printf '%sOPTIONAL — Off by default%s\n' "$hosts_ui_header" "$hosts_ui_reset" ;;
          esac
          printf '%s   # %-36s %-5s %s%s\n' "$hosts_ui_header" DOMAIN STATE OVERRIDE "$hosts_ui_reset"
          hosts_ui_section="$hosts_ui_category"
        fi
        hosts_ui_mark=' '
        hosts_ui_row_color=""
        if [ "$hosts_ui_i" -eq "$hosts_ui_selected" ]; then hosts_ui_mark='>'; hosts_ui_row_color="$hosts_ui_color"; fi
        hosts_ui_override_color="$hosts_ui_amber"
        [ "$hosts_ui_override" != default ] || hosts_ui_override_color="$hosts_ui_absent"
        hosts_ui_state=Off
        [ "$hosts_ui_result" != present ] || hosts_ui_state=On
        hosts_ui_note=default
        [ "$hosts_ui_override" = default ] || hosts_ui_note="manual override"
        hosts_ui_entry_color="$hosts_ui_absent"
        [ "$hosts_ui_result" != present ] || hosts_ui_entry_color="$hosts_ui_present"
        printf '%s%s %2s %-36s%s %s%-5s%s %s%s%s\n' "$hosts_ui_row_color" "$hosts_ui_mark" "$((hosts_ui_i+1))" "$hosts_ui_domain" "$hosts_ui_reset" "$hosts_ui_entry_color" "$hosts_ui_state" "$hosts_ui_reset" "$hosts_ui_override_color" "$hosts_ui_note" "$hosts_ui_reset"
        hosts_ui_i=$((hosts_ui_i+1))
      done < "$hosts_ui_tmp/rows"
      printf '\n'
      if [ "$hosts_ui_arrows" = true ]; then
        printf '%sUp/Down%s: navigate | %sSpace%s: toggle On/Off%s\n' "$hosts_ui_shortcut" "$hosts_ui_help" "$hosts_ui_shortcut" "$hosts_ui_help" "$hosts_ui_reset"
      else
        printf '%snumber%s: toggle On/Off%s\n' "$hosts_ui_shortcut" "$hosts_ui_help" "$hosts_ui_reset"
      fi
      printf '%sc%s: add optional host | %sr%s: reset defaults | %sv%s: preview%s\n' "$hosts_ui_shortcut" "$hosts_ui_help" "$hosts_ui_shortcut" "$hosts_ui_help" "$hosts_ui_shortcut" "$hosts_ui_help" "$hosts_ui_reset"
      printf '%ss%s: save choices | %sa%s: preview and apply | %sn%s: numbered | %sq%s: quit%s\n' "$hosts_ui_shortcut" "$hosts_ui_help" "$hosts_ui_shortcut" "$hosts_ui_help" "$hosts_ui_shortcut" "$hosts_ui_help" "$hosts_ui_shortcut" "$hosts_ui_help" "$hosts_ui_reset"
      hosts_ui_key=""
      if [ "$hosts_ui_arrows" = true ]; then
        IFS= read -r -s -n 1 hosts_ui_key || break
        if [ "$hosts_ui_key" = $'\033' ]; then
          hosts_ui_part=""
          if IFS= read -r -s -n 1 -t 1 hosts_ui_part && { [ "$hosts_ui_part" = '[' ] || [ "$hosts_ui_part" = O ]; }; then
            IFS= read -r -s -n 1 -t 1 hosts_ui_part || hosts_ui_part=""
            case "$hosts_ui_part" in A) hosts_ui_key=up ;; B) hosts_ui_key=down ;; C) hosts_ui_key=right ;; D) hosts_ui_key=left ;; *) hosts_ui_key=escape ;; esac
          else hosts_ui_key=escape
          fi
        fi
      else
        printf 'Choose: '
        IFS= read -r hosts_ui_key || break
      fi
      hosts_ui_was_arrows="$hosts_ui_arrows"
      hosts_editor_restore
      case "$hosts_ui_key" in
        up) hosts_ui_selected=$(((hosts_ui_selected+${#hosts_ui_domains[@]}-1)%${#hosts_ui_domains[@]})) ;;
        down) hosts_ui_selected=$(((hosts_ui_selected+1)%${#hosts_ui_domains[@]})) ;;
        ' '|[0-9]*)
          if [ "$hosts_ui_key" != ' ' ]; then
            [ "$hosts_ui_was_arrows" != true ] || continue
            case "$hosts_ui_key" in *[!0-9]*|'') continue ;; esac
            # Avoid evaluating arbitrary input or octal/oversized arithmetic.
            [ "${#hosts_ui_key}" -le 5 ] || continue
            hosts_ui_selected=$((10#$hosts_ui_key-1))
            [ "$hosts_ui_selected" -ge 0 ] && [ "$hosts_ui_selected" -lt "${#hosts_ui_domains[@]}" ] || { hosts_ui_selected=0; continue; }
          fi
          hosts_ui_current=$(awk -F '\t' -v n="$((hosts_ui_selected+1))" 'NR==n {print $3}' "$hosts_ui_tmp/rows")
          if [ "$hosts_ui_current" = present ]; then
            if [ "$hosts_ui_selected" -lt 3 ]; then
              printf 'Turn OFF core host %s? Type OFF to confirm: ' "${hosts_ui_domains[$hosts_ui_selected]}"
              IFS= read -r hosts_ui_choice || break
              [ "$hosts_ui_choice" = OFF ] || continue
              hosts_ui_overrides[hosts_ui_selected]=off
            else hosts_ui_overrides[hosts_ui_selected]=default
            fi
          elif [ "$hosts_ui_selected" -lt 3 ]; then hosts_ui_overrides[hosts_ui_selected]=default
          else hosts_ui_overrides[hosts_ui_selected]=on
          fi ;;
        c)
          printf 'Exact optional hostname (starts Off): '
          IFS= read -r hosts_ui_choice || break
          hosts_editor_policy > "$hosts_ui_tmp/add"
          printf 'optional %s\n' "$hosts_ui_choice" >> "$hosts_ui_tmp/add"
          if hosts_resolve "$hosts_ui_tmp/add" config > "$hosts_ui_tmp/validated"; then
            cp "$hosts_ui_tmp/validated" "$hosts_ui_tmp/original"
            hosts_resolve "$hosts_ui_tmp/original" > "$hosts_ui_tmp/rows"
            hosts_ui_domains=() hosts_ui_overrides=()
            while IFS=$'\t' read -r hosts_ui_domain hosts_ui_override hosts_ui_result hosts_ui_category; do hosts_ui_domains+=("$hosts_ui_domain"); hosts_ui_overrides+=("$hosts_ui_override"); done < "$hosts_ui_tmp/rows"
          fi ;;
        r) for ((hosts_ui_i=0;hosts_ui_i<${#hosts_ui_domains[@]};hosts_ui_i++)); do hosts_ui_overrides[hosts_ui_i]=default; done ;;
        v|a|s)
          hosts_editor_policy > "$hosts_ui_tmp/current"
          hosts_preview "$hosts_ui_root/private/etc/hosts" "$hosts_ui_tmp/current" || exit 1
          if [ "$hosts_ui_key" != v ]; then
            printf 'Saving changes the policy used by suppression/healing.\n'
            printf 'Type APPLY to update hosts, SAVE to save choices only (Enter cancels): '
            IFS= read -r hosts_ui_choice || break
            hosts_ui_operation=""
            case "$hosts_ui_choice" in APPLY) hosts_ui_operation=apply ;; SAVE) hosts_ui_operation=save ;; esac
            if [ -n "$hosts_ui_operation" ]; then cmd_hosts "$hosts_ui_operation" --root "${hosts_ui_root:-/}" --policy "$hosts_ui_tmp/current" || exit 1; fi
          fi
          printf 'Enter to return: '; IFS= read -r hosts_ui_choice || break ;;
        n) hosts_ui_plain=true ;;
        q|Q|$'\004') break ;;
      esac
    done
    hosts_editor_restore
  )
}
