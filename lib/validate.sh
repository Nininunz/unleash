# These are unleash input policies, not a complete macOS account specification.
# Diagnostics go to stdout for prompt capture; warn renders them on stderr.
# Adapted from https://github.com/ejams1/unleash/commit/f2a6642
account_has_control_chars() {
	local LC_ALL=C
	[[ "$1" == *[[:cntrl:]]* ]]
}

validate_fullname() {
	[[ "$1" == *[![:space:]]* ]] \
		|| { printf '%s\n' 'Full name must contain a non-whitespace character'; return 1; }
	account_has_control_chars "$1" \
		&& { printf '%s\n' 'Full name cannot contain control characters'; return 1; }
	return 0
}

validate_username() {
	local u="$1"
	local LC_ALL=C
	[ -z "$u" ] && { echo "Username cannot be empty"; return 1; }
	[ ${#u} -gt 31 ] && { echo "Username too long (max 31 chars)"; return 1; }
	[[ "$u" =~ ^[a-zA-Z0-9_-]+$ ]] \
		|| { echo "Use only ASCII letters, numbers, underscore, hyphen"; return 1; }
	[[ "$u" =~ ^[a-zA-Z_] ]] \
		|| { echo "Must start with a letter or underscore"; return 1; }
	return 0
}

validate_password() {
	[ -z "$1" ] && { echo "Password cannot be empty"; return 1; }
	[ ${#1} -lt 4 ] && { echo "Minimum 4 characters"; return 1; }
	account_has_control_chars "$1" \
		&& { printf '%s\n' 'Password cannot contain control characters'; return 1; }
	return 0
}

prompt_account_field() {
	prompt_destination_valid "$1" || return 1
	local __unleash_prompt_value __unleash_prompt_msg
	while true; do
		IFS= read -r -p "$2" __unleash_prompt_value || {
			warn 'Account input cancelled (end of input or interrupted read).'
			return 1
		}
		__unleash_prompt_value="${__unleash_prompt_value:-$3}"
		if __unleash_prompt_msg=$("$4" "$__unleash_prompt_value"); then
			printf -v "$1" '%s' "$__unleash_prompt_value" || return 1
			return 0
		else
			warn "$__unleash_prompt_msg"
		fi
	done
}

prompt_fullname() {
	prompt_account_field "$1" "Full name (default 'Apple'): " Apple validate_fullname
}

prompt_username() {
	prompt_account_field "$1" "Username (default 'Apple'): " Apple validate_username
}

prompt_password() {
	prompt_account_field "$1" "Password (default '1234'): " 1234 validate_password
}
