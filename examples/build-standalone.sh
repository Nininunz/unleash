#!/bin/bash
set -euo pipefail

OUT="unleash-standalone.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

VERSION="$(grep '^VERSION=' "$SCRIPT_DIR/unleash" | head -1 | cut -d'"' -f2)"
[ -z "$VERSION" ] && VERSION="1.0.0"

cat > "$OUT" << HEADER
#!/bin/bash
set -euo pipefail
VERSION="$VERSION"
STANDALONE_BUILD=true
SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
SCRIPT_PATH="\$SCRIPT_DIR/\$(basename "\$0")"
HEADER

# Follow the entrypoint's module list so a rebuild cannot omit dependencies.
LIBS="$(sed -n 's/^for _lib in \(.*\); do$/\1/p' "$SCRIPT_DIR/unleash")"
[ -n "$LIBS" ] || { echo "Cannot identify the module loader" >&2; exit 1; }
for lib in $LIBS; do
  tail -n +1 "$SCRIPT_DIR/lib/$lib.sh" >> "$OUT"
  echo "" >> "$OUT"
done

sed -e '1,/_lib in /d' -e '/^done$/,$!d' -e '/^done$/d' "$SCRIPT_DIR/unleash" >> "$OUT"

chmod +x "$OUT"
echo "Created: $OUT (v$VERSION, $(wc -c < "$OUT") bytes, $(wc -l < "$OUT") lines)"
