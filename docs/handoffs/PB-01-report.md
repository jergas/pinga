# PB-01 / revision 1 (corrections 2) — external project browser: implementation report

Status: **SUBMITTED** (second review CHANGES REQUESTED → corrected; awaiting
re-review). Assignment: `pinga-pb01-assignment-01` (PB-01/1; reviews
`pinga-pb01-review-01`, `pinga-pb01-review-02`). Builder: DeepSeek High.
Provider work remains paused and preserved; no commits, no global config edits,
no installation or deployment.

## Corrections implemented (per `docs/handoffs/PB-01-review-2.md`)

1. **Glow config isolation.** Glow's `main.go` (`tryLoadConfigFromDefaultPlaces`)
   PREPENDS `GLOW_CONFIG_HOME` to the searched config dirs — it does not replace
   them, so an empty private dir falls through to the user's personal
   `glow.yml`. Fix: a valid minimal `glow.yml` is now PUBLISHED in the private
   Glow home (viper finds it first), and ambient behavior-changing `GLOW_*` env
   is neutralized in the launch (`GLOW_TUI=false`; the `-p` flag wins over env
   for pager mode). Config precedence is source-verified; executable proof
   against a real Glow is marked PENDING (tools not installed).
2. **Single-file viewer policy.** Glow declares `cobra.MaximumNArgs(1)`, so
   `glow -p -- %s` would break on multi-select. Openers now use `%s1` (first
   selected file) with a documented single-file policy for both Glow and bat;
   multi-select never reaches a viewer. The recorder test no longer implies
   multi-file support: it now runs ONE hostile file at a time and asserts
   exactly three args (flag, `--`, path) and that path intact — and is labelled
   precisely as emulating Yazi's `%s1` quoting with a recorder substituting for
   the viewer (real Yazi/Glow runtime validation remains PENDING).
3. **Color-preserving pager.** `PAGER=less` would drop Glow's default raw-color
   flag and show ANSI escapes. Both viewers now pin `less -R` (`BAT_PAGER` and
   `PAGER`), `LESS=""` neutralizes ambient `LESS` flags that can cause
   immediate exit (e.g. `-F`), and `less` is added to the pre-launch tool check
   (the actual pager executable). Filenames and `--` handling are preserved.
4. **User-visible fallback failures.** Missing viewers are caught pre-launch;
   the refuse opener prints a clear in-pane message (never executes the file);
   viewer/pager failures appear in the Yazi pane. Noted as documented behavior
   pending real-tool smoke.

## Requirement → test mapping

| Requirement | Regression |
| --- | --- |
| Visible errors modal+inline, edits kept | `browse_errors_render_alongside_the_still_editable_form` (rendered buffer, both modes) |
| Full rules override (no defaults ahead) | `opener_templates_use_single_file_policy_and_full_rules_override` (no append/prepend, `*`→refuse) |
| Single-file policy (glow MaximumNArgs(1)) | `opener_templates_use_single_file_policy_and_full_rules_override` (`glow -p -- %s1`, `bat --paging=always -- %s1`) |
| Argument boundary (leading `-`, quotes, spaces, Unicode) | `opener_templates_survive_posix_quoting_for_single_hostile_file` (real `sh -c`, one file at a time, exactly `[flag, --, path]`) |
| Glow config isolation (published glow.yml) | `profile_is_written_atomically_and_hermetic` (glow.yml published with `pager: true`) |
| Full tool isolation + ambient neutralization | `browse_launch_roots_yazi_with_private_profile` (YAZI_CONFIG_HOME, GLOW_CONFIG_HOME, GLOW_TUI=false, BAT_CONFIG_PATH, BAT_PAGER=less -R, PAGER=less -R, LESS="") |
| Concurrent profile publication | `profile_publication_is_safe_under_concurrent_writers` |
| Absolute paths; reject non-UTF-8 | `profile_is_written_atomically_and_hermetic` (canonical abs), `browse_launch_rejects_non_utf8_paths` |
| PINGA_STATE_DIR scoped to browsing | `from_parts` uses platform state dir for tracking; browse uses `pinga_state_dir()` |
| Root semantics: existing dir prefill + fallback | `browse_falls_back_to_cwd_when_session_dir_missing_or_file` |
| Literal paths incl. leading/trailing spaces | `resolve_directory_preserves_leading_trailing_spaces_literally` |
| Zero-provider Browse via key handler | `browse_zero_providers_opens_form_via_key_handler` |
| tmux launch + failure/cleanup, no tracking | `browse_form_prefills_session_dir_and_launches_yazi_in_tmux_without_tracking`, `browse_tmux_new_window_failure_surfaces_error_and_keeps_form` |
| Foreground suspend/run/restore; partial-suspend never launches | `browse_foreground_suspends_runs_and_restores`, `browse_foreground_spawn_failure_restores_and_surfaces_error`, `browse_partial_suspend_failure_never_launches` |
| Hostile filenames intact (outer argv) | `serialization_preserves_shell_hostile_args_and_env_and_cwd` (existing), `browse_launch_roots_yazi_with_private_profile` |
| Missing dependencies actionable (incl. pager) | `check_tools_reports_missing_then_accepts_all`, `browse_missing_tools_fail_actionably_without_launch` |
| Preserve existing provider tests | full suite 119/119 (one pre-existing antigravity `/proc` timing test flaked once under parallel load; passes in isolation; untouched) |

## Actual checks (2026-09-24, after review-2 corrections)

```
make tangle           15 files tangled
make check            cargo check: OK
make test             119 passed; 0 failed
make lint             cargo clippy -D warnings: clean
cargo clippy --all-targets -- -D warnings   clean
repeat-tangle fidelity                       byte-identical after second tangle
git diff --check                             clean
```

## Doc/source-verified vs executable-tested

**Doc/source-verified (upstream docs/source, 2026-09-24):**
- Yazi 26.9.1: `YAZI_CONFIG_HOME`, `[opener]`/`[open]` schema, `%sN`
  placeholders, shipped default `[open] rules` (`yazi-default.toml` on `main`).
- Glow (current `main`, `main.go`): `-p` pager mode; pager = `$PAGER` or
  `less -r`; `cobra.MaximumNArgs(1)`; `tryLoadConfigFromDefaultPlaces`
  PREPENDS `GLOW_CONFIG_HOME` (does not replace); `viper.AutomaticEnv` reads
  `GLOW_*` env. License: MIT.
- bat (README): `--paging=always`, `BAT_CONFIG_PATH`/`BAT_CONFIG_DIR`,
  `BAT_PAGER`. License: MIT OR Apache-2.0.
- less: `-R` preserves raw ANSI color. License GPL-2.0-or-later (system
  utility; never installed by Pinga).

**Executable-tested (this suite):**
- Pinga's outer `serialize_launch` preserves hostile argv (real `sh -c`
  recorder).
- Opener templates survive POSIX quoting for one hostile file at a time
  through a real `sh -c` recorder (single-file policy, `--`, path intact).
- Profile publication (concurrent, atomic), directory resolution, prefill/
  fallback, zero-provider key handling, and every failure path (invalid dir,
  missing tools incl. `less`, tmux failure, spawn failure, partial suspend)
  including rendered error visibility.

**PENDING (requires real tools; not fabricated):**
- Real `yazi`/`glow`/`less` interactive smoke: blocking openers in the same
  pane, `%s1` quoting end-to-end, glow's `MaximumNArgs(1)` and `GLOW_CONFIG_HOME`
  precedence against a hostile personal config fixture, `less -R` color, bat
  binary refusal, glow `--` support. Listed as pending, not passed.

## Dependency installation (Arch host; not executed)

- **Yazi**: `pacman -S yazi` or a named release binary
  (`https://github.com/sxyazi/yazi/releases`, e.g. v26.9.1).
- **Glow**: `pacman -S glow` or a release binary from
  `https://github.com/charmbracelet/glow/releases`.
- **bat**: `pacman -S bat` or a release binary from
  `https://github.com/sharkdp/bat/releases`.
- **less**: base system utility on Arch (`pacman -S less` if ever absent).

After installing, verify `yazi --version`, `glow --help`, `bat --version`,
`less --version`; the browse form's pre-launch check then passes. Debian/Ubuntu
package claims are not made for Yazi (not verified for a named supported
release).

## Manual test instructions

1. `make install` (or `cargo build --release` and run the binary).
2. Press `b`; confirm prefill (existing absolute session dir, else pinga's
   cwd); edit; Enter to launch Yazi in a new tmux window (or the foreground);
   Esc cancels.
3. In Yazi: open a `.md` file → Glow pager (`less -R` colors) in the same
   window; a code/text file → bat pager in the same window; an unsupported or
   binary file → clear refusal. Quit the viewer → back to Yazi; quit Yazi →
   back to pinga with a clean repaint.
4. Failure paths: point the form at a missing path (error RENDERED next to the
   form, edits kept), move `yazi`/`less` off PATH (actionable missing-tools
   error), or run in a terminal that fails suspend (error surfaced, nothing
   launched).

## Known limitations

- Real Yazi/Glow/less runtime behavior (blocking openers, `%s1` quoting, glow
  config precedence under a hostile fixture, `less -R` color, bat binary
  refusal, glow `--` support) is PENDING real-tool verification.
- The viewer is single-file (`%s1`): opening a multi-select shows the FIRST
  selected file; multi-file paging is intentionally not supported (glow's
  `MaximumNArgs(1)`).
- Yazi is a normal, writable file manager — not a read-only sandbox — and the
  chosen directory is not a filesystem confinement boundary (documented).
- bat's system-wide config (`/etc/bat/config`) is a bat feature that still
  applies; user config is replaced by our private `BAT_CONFIG_PATH`.
- One pre-existing antigravity `/proc` test is timing-sensitive under parallel
  test load (passes in isolation); not modified.