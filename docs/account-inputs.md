# Account input rules

The `admin`, `bypass`, and `dualboot` account prompts use the following unleash
policies. These rules are not a complete specification of values accepted by
every macOS release or directory service.

| Field | Tool policy | Empty line at prompt |
| --- | --- | --- |
| Full name | At least one non-whitespace character; no ASCII control characters. Spaces, apostrophes, Unicode, quotes, backslashes, and literal shell punctuation are allowed. No tool-defined maximum length. | Uses `Apple`. |
| Short username | 1–31 ASCII letters, digits, underscores, or hyphens; first character must be a letter or underscore. | Uses `Apple`. |
| Password | At least four characters, measured by Bash in the current locale; no ASCII control characters. Spaces and literal punctuation are allowed. No tool-defined maximum length. | Uses `1234`. |

The username character set and 31-character limit are conservative tool policy,
not claimed universal macOS limits. The four-character password minimum and
existing default are tool behavior, not a password-strength recommendation or a
guarantee that the target's password policy will accept the value.

## Literal input and errors

Prompts read one line, preserve surrounding spaces and backslashes, and assign
answers without evaluating shell syntax. A full name such as `O'Connor & Co.`
stays intact; text such as `$(example)` remains text. Whitespace-only full names
are rejected rather than trimmed. ASCII control characters include tabs,
carriage returns, newlines, and DEL. Bash variables cannot represent NUL bytes;
these prompts are intended for interactive, single-line text input.

Invalid values produce a field-specific warning and prompt again. Validation
errors do not include the entered password. Validators return diagnostics on
stdout for the prompts to capture; prompts display them on stderr. This message
handling adapts [ejams1's validation fix](https://github.com/ejams1/unleash/commit/f2a6642).

An empty line selects the documented default; EOF does not. EOF, including an
unterminated partial line, returns failure without assigning a default or
continuing account creation. Ctrl-C interrupts the command. Existing accounts
are not deleted for replacement until all three fields have been accepted.
Password masking and changes to default-password behavior are separate work.

## macOS interface and evidence

[Apple's account-renaming guidance](https://support.apple.com/en-us/102547)
distinguishes the full name from the username, permits spaces in the full name,
and connects the username to the home-folder name. It does not establish the
complete character or length limits enforced by every account-creation API.

This tool uses `dscl` to set `RealName`, `NFSHomeDirectory`, and the password.
The installed Apple `dscl(1)` manual (`man dscl`) documents `-create` attribute
values and `-passwd` password arguments. Values are passed as separate, quoted
arguments. Tool validation does not replace errors or password policy enforced
by `dscl` and the target directory service.

Tests use inert `dscl` fixtures to verify argument boundaries and literal values;
they do not create real accounts or prove that every permitted value succeeds
on every supported macOS version. Existing account, existing home-directory,
symlink, and ownership checks remain in force.
