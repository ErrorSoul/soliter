---
name: build
description: Headless HTML5 build of the ShenzenSolitare project (Defold, js-web) via bob.jar, plus a runnable browser bundle and the headless play-test harness. Use when you need to compile, bundle, or actually RUN the game from the command line without the Defold Editor.
---

# build — headless HTML5 build (Defold / js-web)

Two different things, do not confuse them:

- **compile** — catches Lua/Defold errors, produces no runnable page. Fast (~15s).
- **bundle** — produces an `index.html` + wasm you can actually load in a browser.

## Compile only (the usual gate)

```
bash tools/defold-build.sh          # from the project root; EXIT 0 == clean
```

The script resolves both tools itself, so nothing is hardcoded at the call site:

- java: newest `/Applications/Defold.app/Contents/Resources/packages/jdk-*/bin/java`
  (bob needs Java 21+; system `/usr/bin/java` is 1.8 and will NOT work)
- bob:  `/Applications/Defold.app/Contents/Resources/packages/defold-*.jar`
  (invoked as `-cp <jar> com.dynamo.bob.Bob`, not `-jar`)

## Runnable browser bundle

```
JAVA=$(ls -d /Applications/Defold.app/Contents/Resources/packages/jdk-*/bin/java | sort -V | tail -1)
JAR=$(ls /Applications/Defold.app/Contents/Resources/packages/defold-*.jar | head -1)
"$JAVA" -cp "$JAR" com.dynamo.bob.Bob --root . --platform js-web --archive \
        --variant debug --bundle-output <DIR> build bundle
```

⚠ `<DIR>` must be **outside** `build/` — bob refuses to bundle into it
("this folder is reserved for Defold build system"). Use the scratchpad.
The page lands in `<DIR>/ShenzenSolitare/index.html`.

`--variant debug` keeps `print()` going to the browser console, which is what
makes the game observable from outside. Release strips it.

## Actually running it — tools/browser-test.py

```
python3 tools/browser-test.py <DIR>/ShenzenSolitare --scenario hittest --viewport 1200x540
python3 tools/browser-test.py <DIR>/ShenzenSolitare --scenario win
```

Headless Chromium with SwiftShader WebGL (playwright is installed for
`/opt/homebrew/opt/python@3.13/bin/python3.13`). Scenarios: `boot`, `hittest`
(drag verdict by pixels, the only check of non-16:9 canvases), `win`
(the solver drives the real cards; `debug_replay` prints its own
`[REPLAY] WIN ✓` verdict). Screenshots + `report.json` land in `--out`.

Two traps this harness exists to handle — both cost real time to rediscover:

1. **Input is sampled once per frame.** `page.mouse.click()` sends down+up in
   the same millisecond and the engine never sees a press. Hold ~250ms. Same
   for keys, and drag moves must be spaced a frame apart.
2. **`--no-coi` changes the binary under test.** With COOP/COEP the loader
   takes `ShenzenSolitare_pthread.wasm`; without them, `ShenzenSolitare.wasm`.
   A host that omits those headers runs the *other* build than a default run
   tests, so check both before calling a browser result green.
