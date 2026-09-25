# PA-01 Stage 3 implementation report (review: antigravity)

2026-09-23. Status: COMPLETED (corrections applied and gated) — ready for
architect review. All prior architect direct fixes preserved (read-only summary
SQLite, `ANTIGRAVITY_APP_DATA_DIR` collected alongside `CODEX_HOME`, malformed-row
errors propagate, plus the earlier Phase A–D and R1–R7 fixes).

Onboarding note: the earlier spike only established that `agy` was installed but
uninitialised; **initialisation was performed by the user** (separately, between
the first spike and this batch). This report does not claim user authorization
for any live launch, prompt, rename, install, or deployment. No credentials or
conversation contents appear here.

## Requirement → test/evidence map

Each review requirement maps to an actual test or evidence item below.

1. **Scrolling (failing-test-first)** — `long_list_scrolls_to_selection_and_click_dispatches_sessionkey`
   (TestBackend, 30 sessions + header + two-line detail rows, at short AND tall
   sizes: moves 25 rows below the viewport, asserts the selected row is actually
   RENDERED, then clicks the visible selected row and asserts the DISPATCHED
   SessionKey). One shared `list_layout` (visual rows, line heights, column inner
   height, selectable→visual mapping) drives `move_cursor`, `render_column`
   (draw + highlight) and `sel_from_visual` (hit-test); resize/group changes
   recompute through it (`column_inner_height` derives from `last_height` the
   same way render lays out the terminal). `move_cursor` no longer uses the full
   terminal height, no longer treats the selectable index as a visual index, and
   no longer waits for a full-window scan.
2. **Pending retry by explicit token** — `same_label_same_cwd_new_launches_are_distinct_until_explicit_token_retry`
   (two intentional launches sharing provider/label/cwd each spawn their own
   window, carry unique tokens; a third ordinary new still spawns; an explicit
   `retry_unrecorded(token)` reuses exactly that window and never spawns; recovery
   records it) and `pending_retry_liveness_error_retains_state_and_never_records`
   (failed inspection retains the recovery state and records nothing; confirmed
   death drops the entry). Known-key retry behavior is retained
   (`retry_after_tracking_failure_records_existing_window_without_respawn`).
3. **Deterministic file-store interleaving** — `deterministic_file_store_interleave_preserves_concurrent_replacement`
   uses a `RacingStore` seam around two REAL `FileTrackingStore` handles: the
   second handle deterministically commits a replacement + a pending INSIDE the
   first's read-modify-write (the exact conflicting timing), and the app's
   conditional commit preserves both. The app-level `reconcile_preserves_records_replaced_by_another_store`
   and the store-level interleave/stale-update tests remain.
4. **Antigravity parsing/evidence** — `first_workspace` decodes `file://` URIs
   (percent-decoding, host-less/localhost, `uri:` prefix), JSON arrays, and plain
   absolute paths; comma/newline and unknown forms yield None (never a guessed
   launch dir). `parse_go_datetime_ms` is a validated, checked parser (invalid
   dates, pre-epoch, offsets, >6-digit fractions → None). DB distinction:
   missing index → fresh empty; existing-but-unopenable → error.
   Tests: `first_workspace_decodes_file_uris_and_paths_but_not_guesses`,
   `parse_go_datetime_accepts_verified_form_and_rejects_invalid`,
   `missing_db_is_fresh_but_existing_unopenable_db_is_an_error`,
   `non_utf8_home_is_rejected_in_launch_env_not_lossy`,
   `malformed_summary_row_fails_the_snapshot`,
   `real_collector_reads_source_env_and_adapter_confirms` (REAL `/proc`
   collector → adapter env hand-off).
5. **Testing path** — `antigravity_two_configured_homes_are_distinct_instances`
   (complete opt-in config preserving OpenCode + Codex, two antigravity homes,
   per-instance source env, unsupported rename) and
   `real_antigravity_adapter_through_the_app_list_resume_track` (lists a seeded
   temp DB through the real adapter in the App, resumes via
   `agy --conversation <uuid>` with the pinned data dir, tracks the window).
   Complete opt-in config + manual checklist: `docs/antigravity-integration.md`
   (§4 config, §5 checklist with expected results and limitations).
6. **Honest status** — everything below is real: no live agy session was
   launched, no config was enabled, no deployment was performed. Claimed
   capability labels: `--conversation <id>` (from `agy --help`), the summary
   SQLite schema and `ANTIGRAVITY_APP_DATA_DIR` (read from the real binary/dir).
   Runtime-verified adapter behavior is covered by the tests above; live
   behavior once conversations exist is NOT yet exercised (documented in the
   checklist).

## Validation (real results)
- `make check`: ok
- `make test`: **97 passed, 0 failed**
- `make lint` (`-D warnings`): ok
- `cargo clippy --all-targets -- -D warnings`: ok (no warnings)
- `git diff --check`: clean
- Repeat `make tangle`: all generated files byte-for-byte identical
- Live read-only probe of the initialized data dir: the adapter's exact SELECT
  opens `~/.gemini/antigravity-cli/conversation_summaries.db` cleanly (0 rows
  today → empty list, the fresh-install path).
- Real `/proc` collector test verifies `ANTIGRAVITY_APP_DATA_DIR` and the agy
  argv reach the adapter through the production collector (not hand-built
  evidence).

## Completed / blocked

- COMPLETED: antigravity adapter (list/resume/create/match), scrolling layout,
  launch tokens + explicit retry, deterministic interleaving, two-homes config,
  app integration, opt-in config doc, manual checklist, all gates.
- BLOCKED (deliberately, not fabricated): live agy conversation launch and
  live second-source isolation have NOT been run — they would create live data
  and tokens, which this packet did not authorize. The checklist documents the
  exact steps and expected results for the architect/user to run.