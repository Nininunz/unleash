#!/usr/bin/env bats

setup() {
  PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$PROJECT/examples" "$PROJECT/lib"
  cp "$BATS_TEST_DIRNAME/../examples/build-standalone.sh" "$PROJECT/examples/"
  cat > "$PROJECT/unleash" <<'SH'
#!/bin/bash
VERSION="test"
for _lib in first second; do
  source "lib/$_lib.sh"
done
main "$@"
SH
  printf 'FIRST_MODULE=true\n' > "$PROJECT/lib/first.sh"
  printf 'SECOND_MODULE=true\n' > "$PROJECT/lib/second.sh"
}

build_fixture() {
  run /bin/bash -c 'cd "$1" && /bin/bash examples/build-standalone.sh' bash "$PROJECT"
}

@test "builder follows a changed entrypoint module list" {
  build_fixture
  [ "$status" -eq 0 ]
  grep -qx 'FIRST_MODULE=true' "$PROJECT/unleash-standalone.sh"
  grep -qx 'SECOND_MODULE=true' "$PROJECT/unleash-standalone.sh"
}

@test "builder fails when a required module is missing" {
  mv "$PROJECT/lib/second.sh" "$PROJECT/lib/not-loaded.sh"
  build_fixture
  [ "$status" -ne 0 ]
  [[ "$output" == *"second.sh"* ]]
}

@test "builder fails when the module loader cannot be identified" {
  printf '#!/bin/bash\nVERSION="test"\n' > "$PROJECT/unleash"
  build_fixture
  [ "$status" -ne 0 ]
  [[ "$output" == *"Cannot identify the module loader"* ]]
}

@test "standalone embeds every module from the entrypoint in order" {
  python3 - "$BATS_TEST_DIRNAME/.." <<'PY'
import pathlib
import re
import sys
root = pathlib.Path(sys.argv[1])
entrypoint = (root / 'unleash').read_text()
standalone = (root / 'unleash-standalone.sh').read_text()
names = re.search(r'^for _lib in (.*); do$', entrypoint, re.M)[1].split()
offset = 0
for name in names:
    module = (root / 'lib' / (name + '.sh')).read_text()
    offset = standalone.index(module, offset) + len(module)
PY
}
