#!/usr/bin/env bash
# Headless Defold build (compiles every .lua to bytecode and reports errors).
# Lets us self-verify Lua 5.1 / Defold compatibility without the editor.
# Usage: bash tools/defold-build.sh   (run from repo root)
set -euo pipefail

APP="/Applications/Defold.app/Contents/Resources/packages"
# Pick the newest bundled JDK (bob needs Java 21+, not the older jdk-17).
JAVA=$(ls -d "$APP"/jdk-*/bin/java 2>/dev/null | sort -V | tail -1)
JAR=$(ls "$APP"/defold-*.jar 2>/dev/null | head -1)

if [[ -z "${JAVA:-}" || -z "${JAR:-}" ]]; then
  echo "ERROR: Defold app jar/jdk not found under $APP" >&2
  exit 2
fi

echo "java: $JAVA"
echo "bob:  $JAR"
echo "=== bob build ==="
# Build content (compiles lua). No --archive/bundle: we only want compile errors.
"$JAVA" -cp "$JAR" com.dynamo.bob.Bob --root . build
