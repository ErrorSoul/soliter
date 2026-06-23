---
name: build
description: Headless HTML5 build of the ShenzenSolitare project (Defold, js-web) via bob.jar. Use when you need to produce a build from the command line without the Defold Editor.
---

# build — headless HTML5 build (Defold / js-web)

Build HTML5 either via the Defold Editor or headless via `bob.jar`:

```
java -jar bob.jar --platform js-web --archive build
```

Run from the project root (where `game.project` lives).

## Environment

- System `java` is 1.8 (`/usr/bin/java`). If bob.jar requires a newer JRE,
  point to a suitable Java explicitly.
- **The path to `bob.jar` is not pinned in the repo** — it is not in the project root.
  Confirm its location before building (usually next to the Defold install or in a
  separate tools folder). Once confirmed, commit the path here.

## Artifact

`--archive build` writes the built output to the `build/` directory.
