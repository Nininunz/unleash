
validate_username() {
	local u="$1"
	[ -z "$u" ] && { echo "Username cannot be empty" >&2; return 1; }
	[ ${#u} -gt 31 ] && { echo "Username too long (max 31 chars)" >&2; return 1; }
	[[ "$u" =~ ^[a-zA-Z0-9_-]+$ ]] \
		|| { echo "Use only letters, numbers, underscore, hyphen" >&2; return 1; }
	[[ "$u" =~ ^[a-zA-Z_] ]] \
		|| { echo "Must start with a letter or underscore" >&2; return 1; }
	return 0
}

validate_password() {
	[ -z "$1" ] && { echo "Password cannot be empty" >&2; return 1; }
	[ ${#1} -lt 4 ] && { echo "Minimum 4 characters" >&2; return 1; }
	return 0
}

prompt_username() {
	prompt_destination_valid "$1" || return 1
	local __unleash_prompt_value __unleash_prompt_msg
	while true; do
		IFS= read -r -p "Username (default 'Apple'): " __unleash_prompt_value || return 1
		__unleash_prompt_value="${__unleash_prompt_value:-Apple}"
		if __unleash_prompt_msg=$(validate_username "$__unleash_prompt_value"); then
			printf -v "$1" '%s' "$__unleash_prompt_value" || return 1
			return 0
		else
			warn "$__unleash_prompt_msg"
		fi
	done
}

prompt_password() {
	prompt_destination_valid "$1" || return 1
	local __unleash_prompt_value __unleash_prompt_msg
	while true; do
		IFS= read -r -p "Password (default '1234'): " __unleash_prompt_value || return 1
		__unleash_prompt_value="${__unleash_prompt_value:-1234}"
		if __unleash_prompt_msg=$(validate_password "$__unleash_prompt_value"); then
			printf -v "$1" '%s' "$__unleash_prompt_value" || return 1
			return 0
		else
			warn "$__unleash_prompt_msg"
		fi
	done
}
