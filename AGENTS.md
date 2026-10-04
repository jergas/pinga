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

## Changelog & Roadmap Policy

* When a new feature is FULLY implemented, add a one-liner to `HISTORY.md`
  (feature name + date). Old entries are generally NOT touched — only the very
  odd correction if an entry was somehow mistaken. Do not rewrite history.
* `roadmap.md` lists the development priorities and their bounded slices.
  Complete a slice before starting the next; add new ideas there rather than
  starting them ad hoc.
* The project is licensed AGPLv3-or-later (see `LICENSE`). Keep third-party
  contributions compatible with that licensing.
* `blueprint.md` is the single source of truth for code; `src/` is derived via
  `make tangle`. Never edit `src/` directly.
