# Repository Instructions & Memory Protocol

## Context & Build Commands

* The architectural blueprint and literate source: `blueprint.md`.
* Regenerate source from the blueprint: `make tangle` (python3 tools/tangle.py blueprint.md)
* Optional readable export: `make weave` (needs pandoc)
* Check / test / lint the tangled output: `make check` / `make test` / `make lint`

## Memory Management Protocol

1. BEFORE REFACTORING OR WRITING CODE:
   * Read `.memory/wiki/index.md` and check `.memory/wiki/gotchas.md`.
   * Search for prior failures in `.memory/wiki/failed_approaches.md` before re-attempting complex fixes.
2. DURING AND AFTER WORK:
   * If you encounter a library bug, environment quirk, or make an architectural decision, immediately record it under `.memory/wiki/`.
   * Log significant changes in `.memory/wiki/log.md` using the format: `## [YYYY-MM-DD] ACTION | Summary`.
   * Never store architectural decisions or quirks solely in session-private memory.
