# Continuous integration

GitHub Actions runs the checks in `.github/workflows/ci.yml` for pushes to
`main`, pull requests targeting any branch, and manual workflow dispatches.
Pull requests between stacked branches receive the same checks.

The macOS 15 job uses system Bash 3.2, installs ShellCheck and Bats with
Homebrew, and runs `make ci`. Tool versions are printed in each run; Homebrew
provides the installed ShellCheck and Bats versions.

## Local checks

On macOS, install the development tools and run the shared CI command:

```sh
brew install shellcheck bats-core
make ci
```

Python 3 and Git are also required. Keep Bash 3.2 first on `PATH` when checking
compatibility with the system shell.

`make ci` runs:

- `make lint`: Bash syntax checks and ShellCheck through the shared lint script.
- `make test`: the Bats suite with isolated macOS command fixtures.
- `make check-build`: rebuild the standalone script and fail if it differs from
  the tracked artifact.

After changing an embedded module or the entrypoint, run `make build` and include
the updated `unleash-standalone.sh` in the commit before running `make ci`.
The build consistency check intentionally reports a diff until the generated
artifact matches the committed version.

Markdown lint is not part of the required checks. The previous Markdown jobs
ignored failures and did not enforce a documentation standard.

## Troubleshooting

Check the repository's Actions tab and run annotations for disabled workflows,
runner failures, or account restrictions. There is no CircleCI fallback config;
run `make ci` locally when hosted checks are unavailable.
