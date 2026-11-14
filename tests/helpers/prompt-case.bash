#!/bin/bash
# Called explicitly with macOS Bash 3.2 by test_prompts.bats.
# Sources and variable assignments below are exercised indirectly by the harness;
# substitution syntax is intentionally literal test data.
# shellcheck disable=SC1090,SC1091,SC2016,SC2034,SC2329
if [ "$1" = modules ]; then
  source "$PROMPT_TEST_ROOT/lib/colors.sh"
  source "$PROMPT_TEST_ROOT/lib/validate.sh"
else
  CYAN='' NC=''
  source "$PROMPT_TEST_STANDALONE"
fi
warn() { :; }

check_literal() {
  local result=unchanged input
  # All execution markers are harmless and confined to Bats' temporary folder.
  input='  $(touch "$PROMPT_TEST_MARKER") `touch "$PROMPT_TEST_MARKER"` "quotes" '\''apostrophe'\'' \backslash %s * ;  '
  prompt_default result 'Full name' Apple <<< "$input"
  [ "$result" = "$input" ]
  prompt_password result <<< "$input"
  [ "$result" = "$input" ]
  # Username policy rejects these characters; check the assignment path with
  # a permissive validator without changing production field policy.
  validate_username() { return 0; }
  prompt_username result <<< "$input"
  [ "$result" = "$input" ]
}

check_defaults() {
  local result=unchanged fallback='$(touch "$PROMPT_TEST_MARKER") `literal` \ " spaces '
  prompt_default result Name "$fallback" <<< ''
  [ "$result" = "$fallback" ]
  prompt_default result Name '' <<< ''
  [ "$result" = '' ]
  prompt_username result <<< ''
  [ "$result" = Apple ]
  prompt_password result <<< ''
  [ "$result" = 1234 ]
}

check_collisions() {
  local value=old var_name=old prompt_text=old default=old msg=old destination
  for destination in value var_name prompt_text default msg; do
    prompt_default "$destination" Name Apple <<< 'Fixture User'
    [ "${!destination}" = 'Fixture User' ]
    prompt_username "$destination" <<< Fixture_User
    [ "${!destination}" = Fixture_User ]
    prompt_password "$destination" <<< 'fixture password'
    [ "${!destination}" = 'fixture password' ]
  done
  [ "$destination" = msg ]
}

check_destinations() {
  local destination prompt result=unchanged __unleash_prompt_value=unchanged
  for destination in '' 'a[0]' 'a[$(touch "$PROMPT_TEST_MARKER")]' 'a-b' '1abc' '__unleash_prompt_value' '__unleash_prompt_msg'; do
    for prompt in prompt_default prompt_username prompt_password; do
      if "$prompt" "$destination" Name Apple <<< 'fixture'; then
        return 1
      fi
    done
  done
  [ "$__unleash_prompt_value" = unchanged ]
  [ "$result" = unchanged ]
}

check_eof() {
  local result=unchanged prompt
  for prompt in prompt_default prompt_username prompt_password; do
    if "$prompt" result Name Apple < /dev/null; then
      return 1
    fi
    [ "$result" = unchanged ]
  done
}

check_reprompt() {
  local result=unchanged msg=sentinel
  local invalid='$(touch "$PROMPT_TEST_MARKER") `touch "$PROMPT_TEST_MARKER"`'
  prompt_username result <<< "$invalid"$'\nFixture_User'
  [ "$result" = Fixture_User ]
  prompt_password result <<< $'abc\nfixture password'
  [ "$result" = 'fixture password' ]
  [ "$msg" = sentinel ]
}

"check_$2"
