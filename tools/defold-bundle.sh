#!/usr/bin/env bash
# Headless HTML5 BUNDLE (playable build for tools/browser-test.py).
# Usage: bash tools/defold-bundle.sh <output-dir> [--variant debug|release]
# The bundle lands in <output-dir>/ShenzenSolitare (that dir holds index.html).
#
# Платформа. До Defold 1.13 здесь стояло `js-web`; в 1.13.1 этот id удалён
# (`Platform js-web not supported`), остались `wasm-web` и `wasm_pthread-web`.
# Берём pthread-вариант: именно он даёт бинари ShenzenSolitare_pthread.wasm /
# _pthread_wasm.js, которые ждёт browser-test.py, и требует cross-origin
# isolation — её харнесс и раздаёт (флаг --no-coi там же грузит ДРУГОЙ wasm).
# Переопределить можно переменной DEFOLD_PLATFORM.
set -euo pipefail

OUT="${1:?usage: defold-bundle.sh <output-dir> [--variant debug|release]}"
VARIANT="${3:-debug}"
PLATFORM="${DEFOLD_PLATFORM:-wasm_pthread-web}"

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
echo "platform: $PLATFORM"
echo "out:     $OUT/ShenzenSolitare"
"$JAVA" -cp "$JAR" com.dynamo.bob.Bob --root . \
  --platform "$PLATFORM" --archive --variant "$VARIANT" \
  --bundle-output "$OUT" build bundle
