run_demo() {
  header "Unleash Demo — Simulated MDM Bypass"

  local demo_dir
  demo_dir=$(mktemp -d)
  mkdir -p "$demo_dir/private/etc"
  mkdir -p "$demo_dir/private/var/db/ConfigurationProfiles/Settings"
  mkdir -p "$demo_dir/private/var/db/com.apple.xpc.launchd"
  mkdir -p "$demo_dir/Users/demo/Library/Preferences"
  mkdir -p "$demo_dir/Users/demo/Library/Application Support"

  touch "$demo_dir/private/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound"
  touch "$demo_dir/Users/demo/Library/Preferences/com.apple.mdm.plist"

  echo ""
  step "1. Simulating pre-bypass MDM state"
  printf '%b\n' "     DEP record:      ${RED}PRESENT${NC}"
  printf '%b\n' "     Hosts block:     ${RED}ABSENT${NC}"
  printf '%b\n' "     Daemon override: ${RED}ABSENT${NC}"
  printf '%b\n' "     User artifacts:  ${RED}PRESENT${NC}"
  sleep 1

  echo ""
  step "2. Running suppress_enrollment..."
  DRY_RUN=false
  suppress_enrollment "$demo_dir" 2>/dev/null || true
  sleep 1

  echo ""
  step "3. Verifying post-bypass state"
  local clean=true
  if [ -f "$demo_dir/private/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound" ]; then
    printf '%b\n' "     DEP record:      ${RED}STILL PRESENT (bug)${NC}"
    clean=false
  else
    printf '%b\n' "     DEP record:      ${GRN}CLEARED${NC}"
  fi
  if grep -q "iprofiles.apple.com" "$demo_dir/private/etc/hosts" 2>/dev/null; then
    printf '%b\n' "     Hosts block:     ${GRN}ACTIVE${NC}"
  else
    printf '%b\n' "     Hosts block:     ${RED}ABSENT (bug)${NC}"
    clean=false
  fi
  if [ -f "$demo_dir/Users/demo/Library/Preferences/com.apple.mdm.plist" ]; then
    printf '%b\n' "     User artifacts:  ${RED}STILL PRESENT (bug)${NC}"
    clean=false
  else
    printf '%b\n' "     User artifacts:  ${GRN}CLEANED${NC}"
  fi

  echo ""
  step "4. Simulating macOS update (re-enabling daemons)"
  rm -f "$demo_dir/private/var/db/com.apple.xpc.launchd/disabled.plist"
  printf '%b\n' "     Daemon override: ${RED}RESET (simulating update)${NC}"
  sleep 1

  echo ""
  step "5. Running heal — detecting and fixing..."
  heal_suppress "$demo_dir" 2>/dev/null || true
  sleep 1

  if [ -f "$demo_dir/private/var/db/com.apple.xpc.launchd/disabled.plist" ]; then
    printf '%b\n' "     Daemon override: ${GRN}RESTORED${NC}"
  fi

  echo ""
  step "6. Summary"
  if [ "$clean" = true ]; then
    printf '%b\n' "   ${GRN}✓ Demo completed successfully${NC}"
  else
    printf '%b\n' "   ${YEL}⚠ Demo completed with warnings${NC}"
  fi
  echo "   Simulated environment: $demo_dir"
  echo ""
  info "This is a simulated run. No real system was modified."
  info "Run 'rm -rf $demo_dir' to clean up."

  header "Demo Complete"
  printf '  %s\n' 'Commands used: suppress, heal'
  printf '  Try: %b%s%b for real diagnostics\n' "$YEL" 'sudo ./unleash doctor' "$NC"
}
