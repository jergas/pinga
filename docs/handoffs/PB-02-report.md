# PB-02 / revision 2 — contrast regression fix: report

Status: **SUBMITTED for review** (not accepted). Assignment: `pinga-pb02-assignment-01`
(+ regression `pinga-pb02-regression-01`). Builder: DeepSeek High. No installs,
no global edits, no live provider sessions, no commits, no push.

## Outcome of the contrast follow-up

**Tools are now installed** (yazi 26.9.1, glow 3.0.0, bat 0.26.1, less 704).
The original PB-01 browser smoke passed. The FIRST PB-02 contrast patch
(`theme.toml` with `[status] overall` + `[mode]`) was verified in the user's
live test to make the lower-right **corner indicators disappear**.

**Root cause (verified, not assumed).** Rendered the installed Yazi 26.9.1 in
an isolated PTY and compared frames:
- Overriding **any** `[status]` table — even `overall = { fg = ... }` alone —
  makes the right-hand `1/` tab indicator disappear and inserts an extra left
  separator (regression).
- Overriding **`[mode]` alone** is safe: the rendered status row is byte-identical
  to baseline and every indicator stays.

**Fix (narrow).** `THEME_TOML` is now `[mode]`-only:
`normal_main = { fg = "#ffffff", bg = "#2d5aa0", bold = true }`. Re-verified in
the PTY: status bar layout byte-identical to baseline (indicators restored) and
the blue/white mode block recolored to white-on-medium-blue (fixed contrast,
independent of terminal palette).

**Remaining uncertainty (reported).** The lower-left status text/separator
colors are Yazi defaults and are NOT safely adjustable via `theme.toml`:
any `[status]` table hides the right tab indicator in 26.9.1. The fix therefore
covers the lower-right blue/white mode block only; a final user visual re-check
is recommended to confirm the lower-left is acceptable as-is.

## Provider loose ends (unchanged from PB-02/1)

No small release-blocking production defect found (adapter `unwrap`/`expect`
are test-only); limits already conservative and documented in
`docs/antigravity-integration.md` section 5b (plain-agy launches Ambiguous,
never inferred by cwd/title/time; Pinga names label the tmux window only;
rename unsupported). No new providers/title hacks/identity guessing.

## Actual checks

```
make tangle           15 files tangled
make check            cargo check: OK
make test             120 passed; 0 failed
make lint             cargo clippy -D warnings: clean
cargo clippy --all-targets -- -D warnings    clean
repeat-tangle fidelity                       byte-identical after second tangle
git diff --check                             clean
PTY verification (yazi 26.9.1 installed)     baseline vs patched frames compared
```

Changed paths: `blueprint.md` (`THEME_TOML` narrowed to `[mode]`-only + prose),
`docs/antigravity-integration.md` (5b limits, from PB-02/1). Generated `src/`
remains gitignored/tangled. No commit was made.

## Recommendation

Original PB-01 smoke passed; the contrast regression was diagnosed against the
installed Yazi and corrected to a verified indicator-preserving `[mode]`-only
override. Ready for a short user visual re-check; not accepted yet. Real-tool
smoke items beyond contrast (opener blocking, `%s1` quoting, glow config
precedence) remain as listed in `docs/handoffs/PB-01-smoke-ready.md`.
## User palette revision
User clarified the affected UI is the directory browser and requested green and
purple. Architect changed both normal_main and normal_alt to light text on dark
purple/green respectively, preserving the mode-only override. Earlier blue palette
observations above describe the superseded revision.

## Final acceptance
User approved the final green/purple browser palette. Text colors are #a5e5aa
and #d3a4ef on the existing dark purple/green backgrounds. Build and whitespace
checks passed after the final color-only adjustment. Provider limits remain
documented; ready for publication.
