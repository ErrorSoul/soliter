#!/usr/bin/env bash
# Headless js-web BUNDLE (playable build for tools/browser-test.py).
# Usage: bash tools/defold-bundle.sh <output-dir> [--variant debug|release]
# The bundle lands in <output-dir>/ShenzenSolitare (that dir holds index.html).
set -euo pipefail

OUT="${1:?usage: defold-bundle.sh <output-dir> [--variant debug|release]}"
VARIANT="${3:-debug}"

APP="/Applications/Defold.app/Contents/Resources/packages"
JAVA=$(ls -d "$APP"/jdk-*/bin/java 2>/dev/null | sort -V | tail -1)
JAR=$(ls "$APP"/defold-*.jar 2>/dev/null | head -1)

if [[ -z "${JAVA:-}" || -z "${JAR:-}" ]]; then
  echo "ERROR: Defold app jar/jdk not found under $APP" >&2
  exit 2
fi

rm -rf "$OUT"
mkdir -p "$OUT"

echo "java:    $JAVA"
echo "bob:     $JAR"
echo "variant: $VARIANT"
echo "out:     $OUT/ShenzenSolitare"
"$JAVA" -cp "$JAR" com.dynamo.bob.Bob --root . \
  --platform js-web --archive --variant "$VARIANT" \
  --bundle-output "$OUT" build bundle
