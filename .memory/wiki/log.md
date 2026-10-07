# Memory Update Log

## [2026-09-16] INIT | Created project memory vault
## [2026-09-16] SETUP | Initialised pinga vault via mnemosyne/init-memory-system.sh; recorded eris ergonomics + persistence architecture as ADR 0002, session gotchas, and mirrored notes into ai-memory (project pinga)
## [2026-09-16] FIX | Resolved opencode session split-brain (two servers on ses_f5416a477ffef4yNuMa5BLYWlJ); kept systemd :4096 backend + tmux client, exited stray TUI. Created tmux window layout in session `main`: `edgar` (opencode) / `codex` / `shell`
## [2026-09-17] TOOLING | Consolidated codex to the standalone 0.154.0 only: removed mise tool + pacman openai-codex (0.153.4); `command -v codex` now → ~/.local/bin/codex in every shell
## [2026-09-17] SPEC | Wrote pinga's literate blueprint (blueprint.md, ~1400 lines): requirements R1–R11, verified opencode/codex integration (§5), decisions D1–D7, 12 tanglable code chunks
## [2026-09-17] TOOLING | Added literate toolchain: tools/tangle.py (zero-dep), tools/tangle.lua (pandoc), Makefile (tangle/weave/check/test/lint). AGENTS.md build commands switched from pnpm placeholders to real ones
## [2026-09-17] BUILD | First tangle compile: fixed opencode rename borrow (E0515), codex Instantish FromStr (E0277), added tui::mod, wrote real layout_rects/hit_rect helpers, made handle_key arm-splitting clean. GATES GREEN: cargo check + clippy -D warnings + cargo test
## [2026-09-17] TEST | First manual run: R10 handoff works (codex resumed via pinga, pinga returned). Resumed thread was an EMPTY vscode seed (01a0ad0f) — codex exited cleanly (task_complete, exit 0), not a crash. Added has_conversation() seed-thread filter to provider::codex list() so empty threads don't appear resumable
## [2026-09-17] FIX | Rename editing: replaced blind String buffer with TextEdit line editor (char buffer + cursor, ←/→/Home/End/Delete/Backspace) + visible bottom overlay "rename: <text> ▌ [Enter apply · Esc cancel]". QUIT: teardown now also DisableMouseCapture + Show cursor (SGR mouse sequences were leaking to the shell after q), and q exits 0 instead of Rust printing Error: quit
## [2026-09-17] TEST | Rename confirmed working + persistent across quit/rerun (opencode re-read confirmation proves the write lands); q exits clean, no SGR mouse leak. Awaiting tmux-path (R9) test before commit
## [2026-09-17] COMMIT | Root commit 5858d62 "Add pinga: literate TUI console for opencode & codex sessions" (15 files, blueprint + tangle tooling + scaffold; src/ and target/ gitignored as derived)
## [2026-09-17] FIX | D8 one-window-per-session + select-on-click/open-on-double (per user choice): click selects only, double-click (same cell <=500ms) or Enter opens (lazygit pattern, r/other keys freed); open_selected routed through open_in_tmux_guarded: tracked window -> select, same-session pane/name heuristic -> adopt (unambiguous only), opencode active elsewhere -> refuse + f force, else new-window -P -F '#{window_id}' and track id; codex has no liveness so heuristic-only (documented). bare-terminal mode refuses active-elsewhere too. HELP updated; also fixed a ctor regression (naming: NameEngine::new(...) line). Gates green
## [2026-09-17] FIX | D8 v2 (two bugs from manual test): (1) mouse-initiated tmux actions deferred to button-Up — switching mid-double-click leaked the release/stray-press into the attach TUI (opencode read it as message click -> "Message Actions" popup); Plan enum (Select/Adopt/Spawn) + pending + execute, flushed on Up, on key, and in refresh; SWITCH_COOLDOWN swallows stray downs after a switch. (2) adopt heuristic now matches process ARGV (session id in `opencode attach ... -s <id>` / `codex resume <name>`) walking the pane pid tree via ps+pgrep (depth<=3), not window names — a manually-started window named "codex" had been spawning a duplicate copy. opencode marker = id (argv), codex marker = title-or-id. Gates green
## [2026-09-17] FIX | D8 v3 (user's 2:shell case): adopted-from-argv failed because opencode was attached WITHOUT -s (`opencode attach http://localhost:4096`), and this opencode build exposes NO per-session active signal (GET /session lacks `active`; verified). New fallback: find_opencode_attach_windows() walks panes for argv containing "opencode"+"attach"; adopt iff exactly ONE attach window AND target is newest-updated session (opencode bare attach binds to most recent); several windows or non-newest -> refuse + f (no silent copies). Cross-session/terminal opencode attachment is undetectable -> fresh window, documented in D8 + §15.5 (gap now uniform for both providers). Live-verified on eris: @2 adopted for ses_f5416a (newest). Gates green

## D8 v4 — false-refusal + sticky status + overflow (2026-09-18)
- open (focus==0 fallback): single attach window on a *different* (newest) session ⇒ that session is provably not open ⇒ spawn normally instead of refusing. Refuse only when ≥2 attach windows (ambiguous). "hello world…" (ses_f6979…) now opens despite 2:shell being attached to ses_f5416a.
- sticky status: `error` no longer cleared in refresh(); cleared on explicit key/mouse instead — refusal text persists until the user acts.
- overflow: header HELP + bottom error line `fit`-truncated to terminal width; rename line keeps cursor+hint visible by trimming after-cursor text.
- gates green (check/clippy/test).

## D8 v5 + COMMIT fb93a60 (2026-09-18)
- header overflow root cause: prefix " pinga " + " · " = 10 cols but only 8 reserved; now reserved via UnicodeWidthStr::width and fit() is column-aware (wide glyphs count 2) using unicode-width = 0.1 (pinned to ratatui's version to dedupe).
- COMMIT fb93a60 "D8: click-to-open sessions with one-window-per-session enforcement" (4 files, +346/-26). Everything D8 in one commit. Remaining: proper codex manual test; user's older codex session may have been lost when other codex versions were uninstalled.

## [2026-09-19] STEP -1 | pinga: "+ new session" + interrupted-session tracking
- "-1a" — each column now has a "+ new session" row (visual row 0). Selecting it (Enter/dbl-click) opens a name+cwd form (Tab/Enter move name->cwd, Enter on cwd submits). opencode: POST /session (title+dir) then attach a window (verified: DELETE /session/:id works for cleanup). codex: opens `cd <dir> && codex` (codex has no server-side create; app-server protocol is IDE-oriented). Provider trait gained a default-error `create()`, overridden for opencode.
- "-1b" — opened sessions persist to ~/.local/state/pinga/opened.json (dirs::state_dir). On each refresh pinga reconciles: tracked-but-gone-from-server -> dropped + one-time "removed from tracking" message; tracked-but-window-dead -> shown as "⚠ interrupted" resume row at top of column. Visual list is now VRow{New, Int, Sess} (always len+1 rows). Verified end-to-end in a throwaway tmux harness (create -> kill session -> restart shows interrupted; delete server-side -> reconcile message).
- Selection bounds unchanged (visual_rows length == len+1 always). Sticky status message reapplies on re-entry.

## [2026-09-19] STEPS 0-2 | pinga command, tmux 'pinga' session, reboot survival
- STEP 0 — Makefile gained `install`/`uninstall` (tangle -> `cargo build --release` -> `install -Dm755 target/release/pinga ~/.local/bin/pinga`). `pinga` is now a real command on PATH. Fixed stale-binary trap: `make check/test` don't produce the executable; use `cargo build` or `make install`.
- STEP 1 — created tmux session `pinga` with ONE window running the installed `pinga` (pinga opens all other sessions as windows).
- STEP 2 — reboot survival: found `~/.tmux/resurrect/` had NO save file (why the 2026-09-18 power failure lost the layout). Added systemd user service+timer `pinga-tmux-save` (OnCalendar=`*:0/10`) calling resurrect `save.sh` via `tmux run-shell`; verified it writes a snapshot. Timer enabled; next run 23:30.
- STEP 3 — documented the reality in ADR-0002 + gotchas (resurrect save gap, codex daemon socket, interrupted-session startup-only flag).

## [2026-09-20] PLAN | cooperative concurrency + grouping + modals + keys + installer
- A. opened.json is now a SHARED cooperative registry: every write is atomic (tmp+rename) and guarded by an flock (`fs2`); all mutations go through `update_opened(closure)` (lock -> read -> apply -> write -> return). Every instance reloads the registry at the top of each refresh, so concurrent instances converge ("state follows me"). Verified: instance 2 shows instance 1's opened session under "running".
- B. Columns now group sessions under subheaders: `+ new session` / `interrupted` / `running` / `closed`. `running` = alive window (from opened) + hand-opened via a new `launcher::scan_attached()` argv walk. Selection (move_cursor) skips headers; ListState drives scroll-to-selection.
- C. Two-line rows by default (title+age / dim id); config `list_detail="two-line"|"bottom"` + runtime `d` toggle (bottom shows the selected id on the status line). codex provider now parses `cwd`, `model`, and `session_id` from the rollout (session_meta) so detail is complete.
- D. Rename + new-session forms are centred modal dialogs by default (config `forms="modal"|"inline"`); the `i` key opens a full-info modal (id, session id, thread, slug, directory, model, agent).
- E. Keys: `g` manual refresh, `d` toggle detail, `i` info.
- F. Installer: vendored `deploy/pinga-tmux-save.{sh,service,timer}`; `make install` deploys pinga + the timer and `systemctl --user enable --now`s it (non-fatal if no systemd user session); `make uninstall` removes them.
- Verified in a throwaway tmux harness: grouping, two-line/bottom toggle, info modal, modal form, concurrency, `g`.

## [2026-09-22] FIX | codex thread names + id parsing
- Root cause: codex 0.155 no longer writes `~/.codex/sessions/session_index.jsonl` (which pinga read for names) — names now live in the app-server state DB `~/.codex/state_*.sqlite` → `threads` table (`name`/`title` columns).
- ALSO a parsing bug: `rollout_title_id` returned only the LAST 12 chars of the thread UUID, so codex ids looked "shortened" and never matched the threads table (full UUID) — hence no names resolved.
- Fix: codex provider now reads `state_*.sqlite` (found by glob + `threads` table check) via `rusqlite` (bundled) and joins rollout ids (now full trailing UUID) to it. Display name order: `name` -> `title` -> id. Also pulls cwd/model/created/updated from the DB.
- pinga's codex rename now UPDATEs the threads `name` column (so pinga-set names are the thread name /status shows), falling back to a session_index.jsonl append if the thread isn't in the DB yet.
- New dep: rusqlite 0.31 (bundled). Verified: open session now shows "Review Mnemosyne memory"; `i` modal shows id, session id, thread, directory, model.

## [2026-09-22] codex display fallback refined
- Display order confirmed: pinga/codex thread `name` -> codex `title` -> id.
- Tried deriving a title from the rollout's first user message for nameless+titleless threads, but it picked up injected system prompts (AGENTS.md, <recommended_plugins>) as misleading titles — reverted. When the DB has neither name nor title the thread genuinely has none (mostly subagent/automated threads), so the id is the honest fallback.
- IMPORTANT: user must RESTART pinga to pick up the codex-name fix — a running old binary still shows truncated ids and puts the id in the rename dialogue. Renaming is safe: it only writes the threads.name label, never the conversation.

## [2026-09-22] codex sub-thread name inheritance
- User's open session showed an id in the list + rename dialogue. Root cause: it was thread 01a0c060, a NAMELESS sub-agent of 01a0bc60 ("Review Mnemosyne memory") — codex names live per-thread, and that thread has none of its own.
- Fix: codex provider reads `thread_spawn_edges` (child->parent) from state_5.sqlite and, for a thread with no name/title, walks up the parent chain to the nearest named ancestor, so sub-thread conversations show their parent's name instead of a bare id. Verified: 01a0c060, 01a0bd52 (children of 01a0bc60) now show "Review Mnemosyne memory"; rename prefills the name.
- Also ruled out "different versions": only one `pinga` binary exists (match of target/release), debug + release both read the DB identically.

## [2026-09-22] FIX: rename/click hit the wrong session (off-by-one with headers)
- Symptom: renaming a session changed a DIFFERENT list item (the top of a same-named group); the selected row's rename prefilled/acted on another session.
- Root cause: `sel` was an index into `visual_rows` (which INCLUDES group subheaders), but the highlight used a selectable-only count (headers excluded). With a header present they diverged by the number of headers, so `focused_session()` (rename target, `i` modal) returned a session off from the highlighted one.
- Fix: `sel` is now consistently an index into SELECTABLE space (New + sessions, headers excluded): `selectable_sessions()` orders sessions (interrupted/running/closed), `focused_session` maps sel via it, `move_cursor` clamps in selectable space, mouse clicks convert visual→selectable via `sel_from_visual`, refresh just clamps range. Verified: sel1→01a0c060, sel2→01a0bc60, sel3→01a0bd52; rename prefills the selected thread's name.

## [2026-09-22] rename no longer reshuffles the list
- Symptom: after a rename the session seemed to "switch places"; user suspected it renamed a different session.
- Root cause: pinga's codex rename bumped `updated_at_ms`, and the list sorts by `updated_at_ms DESC` — so every rename moved the session to the top. Combined with several threads sharing one display name (sub-threads inheriting the parent's name), this made it look like the wrong row was renamed. The rename itself targets the highlighted row correctly.
- Fix: rename only sets `name` (does NOT touch `updated_at_ms`), so renames never reorder the list. Added a stable id tiebreak to the codex sort so equal timestamps don't jitter. Verified: renaming 01a0bd52 left updated_at_ms identical.
- The user's suggested "order by session ID" was superseded by fixing the reorder at the root; kept the useful most-recent-first sort. Offer id-ordering as an option if still wanted.

## [2026-09-22] mouse defaults to ON when available
- pinga's mouse now defaults to ON when a mouse looks usable: in tmux, only if tmux's mouse mode is on (tmux must forward events); standalone, always on (modern terminals report mouse). Enabled via a startup EnableMouseCapture when the default is on. 'm' still toggles.
- Found: tmux.conf already has `set -g mouse on`. If the user still sees no mouse over macOS+ssh, it's the terminal/ssh not sending mouse events (terminal-side), not pinga.
- New launcher helper: `tmux_mouse_on()` (reads `tmux show -g mouse`).

## [2026-09-22] DOCS | Reconcile blueprint prose with current implementation
- Corrected Codex SQLite metadata/rename, inherited labels, full UUIDs, legacy fallback limitations, diagram, contracts, and planned acceptance checks.
- Documented existing two-provider coupling, creation behavior, naming/auto-rename gaps, terminal handoff, and actual tangle/check workflow. No executable chunks changed.
- User accepted compiled-in provider registration for the forthcoming abstraction; implementation remains deferred until the architecture is agreed. Preserve the existing literate workflow for the implementation handoff.
- Validation: all 12 executable chunks identical to HEAD; make tangle left all 12 generated files byte-for-byte unchanged; git diff --check passed.

## [2026-09-22] DESIGN | PA-01 architecture and Stage 1 DeepSeek handoff
- Prepared docs/provider-architecture.md revision 1, a bounded Stage 1 task, and an explicitly not-started report template. Added memory index/pointer.
- Stage 1: validated stable IDs, trait-object provider registry, built-in composition, and fixture tests. Existing UI/launcher/tracking behavior remains transitional; later stages require separate reviewed tasks.
- Chose a fresh DeepSeek/OpenCode session and one implementation writer in the current checkout. User supplies a short kickoff; no agent message was sent and no implementation was started.

## [2026-09-22] IMPL | PA-01 Stage 1 landed: provider identity + registry (DeepSeek/OpenCode)
- Implemented Stage 1 through blueprint chunks, not src/ directly: `core-model`, `prov-mod`, `prov-opencode`, `prov-codex`, `prov-codex-tests`, `tui-app`, `core-main`.
- Added `ProviderId` (validated lowercase id), `SessionKey`, `Session.provider_id`, `ProviderDescriptor`; removed `ProviderKind` and `AnyProvider`. Trait `kind()` -> `descriptor()`.
- `ProviderRegistry` (Box<dyn Provider>, ordered, duplicate-ID error, lookup by id) + `builtin_registry(cfg)` composition. App routes through the registry by index; `App::new` now fallible, error propagates via existing terminal cleanup.
- Validation: 11 automated tests pass (identity, registry, dispatch/failure isolation, built-in composition, opencode `from_value` + codex temp-home `list()` identity fixtures); `make check/test/lint` green; repeat tangle byte-identical; `git diff --check` clean. `ProviderKind`/`AnyProvider` absent from src; no concrete adapter ctors in app.
- Report: docs/handoffs/PA-01-stage-1-report.md. Ready for architect review; three-provider UI and later stages remain separate reviewed tasks.

## [2026-09-22] REVIEW-FIX | PA-01 Stage 1 corrections R1/R2 (DeepSeek/OpenCode)
- R1: made `SessionKey` fields private with immutable `provider()`/`native_id()` accessors; validated constructor remains the only construction path. Temporary sibling-module compile probe confirmed both bypass forms rejected (E0451 construct, E0616 field access); probe removed, tree re-tangled.
- R2: added `builtin_composition_wires_config_into_adapters` (non-default OpenCode URL + temp Codex home fixture through `builtin_registry`); rewrote dispatch test with recorded create/rename (recipient+args) via `Arc<Mutex<Calls>>` and a separate `CreateFake` for successful create, base `Fake` keeps default unsupported create; fixture sessions now carry the fake's real provider id; duplicate test verifies the original's behavior survives a distinguishable replacement.
- Gates green: check ok, 12 tests pass, lint ok, repeat tangle byte-identical, `git diff --check` clean. Report updated with evidence and new test count. Ready for architect re-review; no Stage 2 work started.

## [2026-09-22] IMPL | PA-01 Stage 2 landed: capabilities, structured launches, evidence (DeepSeek/OpenCode)
- Replaced `attach_command`/server-only-`create` with `ProviderCapabilities`, `resume_plan -> LaunchRequest`, `create -> CreateOutcome::{KnownSession,LaunchToCreate}`, `match_session -> Vec<WindowMatch>`; added typed `Unsupported` (distinct from failure) and `check_session_belongs`.
- Launcher rewritten with injectable `ProcReader` (NUL-delimited /proc cmdline + bounded children), `Tmux`, and `Foreground` seams; generic `ProcessEvidence` collector; POSIX-sh `exec` serializer at the tmux boundary; `run_guarded` guarantees terminal restoration on spawn failure; explicit `decide_open` adoption policy replaces silent newest-session auto-adoption with a warning + force.
- App dispatches new-session/resume generically; KnownSession retained + opened (created-but-not-opened on plan/launch failure); LaunchToCreate tracked as in-memory `PendingLaunch` (never empty native ID; removed only on confirmed window death). Refresh retains last snapshot on failure and keeps first-reconcile eligibility; reconciliation uses adapter evidence and only drops a tracked client on complete proof it ended.
- Gates: check ok, 25 tests pass (from 12), lint ok, repeat tangle byte-identical, `git diff --check` clean. Report: docs/handoffs/PA-01-stage-2-report.md. App event-loop not unit-tested (reads real opened.json / real launcher); seams + policy are. Ready for architect review; Stage 3 out of scope.

## [2026-09-22] REVIEW-FIX | PA-01 Stage 2 corrections R1-R5 (DeepSeek/OpenCode)
- R1: `decide_open` now selects a tracked window only on Confirmed evidence (liveness alone insufficient), dedups candidate window ids.
- R2: TmuxCli checks subprocess exit status; `compute_interrupted` treats window_alive errors and ambiguous/heuristic matches as unknown (retain), drops only on a complete no-match; per-record `startup_eligible` consumes only when that record's initial reconcile was possible.
- R3: `ProcFs::tree` marks bounded-descendant truncation incomplete; `parse_cmdline` preserves empty args and rejects truncated/non-UTF-8; adapters match exact executable basename and return Ambiguous for unparseable forms; OpenCode endpoint normalizes scheme/host only (path case + host-prefix preserved); codex uniqueness guarded against stale snapshots via `provider_ok`.
- R4: `open_in_tmux` invokes POSIX sh explicitly via tmux's argv interface (fake-tmux asserted); shared `validate_launch` rejects NUL in program/args/cwd/env; non-UTF-8 cwd rejected; real suspend/run/restore behind injectable `Terminal` seam; refresh after foreground return in both paths.
- R5: `App::with` injects registry/launcher/`OpenedStore`/`Terminal`; `PendingLaunch` carries ProviderId; KnownSession validates a nonempty SessionKey at the boundary; visible pending status; capability-driven new-row/rename/form hints; app-level orchestration tests + fake third provider.
- Gates: check ok, 44 tests pass (from 25), lint ok, repeat tangle byte-identical, `git diff --check` clean. Report updated with R1-R5 evidence. Ready for architect re-review; Stage 3 out of scope.

## [2026-09-22] REVIEW-FIX | PA-01 Stage 2 corrections A-C (second review, DeepSeek/OpenCode)
- A: startup eligibility now keyed by (provider, session id, window id); membership preserved, never granted to a later record; unknown evidence (no collection) retains the record AND keeps eligibility. Sequence tests: later open never gains eligibility, unknown evidence keeps it then interrupts on a later dead window, window replacement never inherits eligibility.
- B: adapters match only exact supported argv shapes (opencode attach [id-less or -s id]; codex resume <target>); recognized exe + unknown syntax => Ambiguous (never absence); dangling/duplicate -s, leading/trailing unknown options, resume-without-target all ambiguous. OpenCode endpoint parsing splits authority at first '/'/'?'/'#', preserves query bytes + path case, normalizes non-root trailing slash; root `?Token=A` no longer folded into host.
- C: `suspend_for` refuses to launch after a failed suspension, always restores, surfaces combined launch+restore errors (tested via `App::suspend_for`, not `run_guarded`); `open_session` returns OpenResult::{Opened,Refused,Failed} and checks resume capability before planning; `create_new_session` reports created-but-not-opened and retains identity on foreground/tmux spawn failure with no re-create and no record; current_dir failure/non-UTF-8 is an explicit error; two-slot test fixture; distinct fake window ids per launch.
- Gates: check ok, 56 tests pass (from 44), lint ok, repeat tangle byte-identical, `git diff --check` clean. Report updated with A-C evidence table. Ready for architect re-review; Stage 3 out of scope.

## [2026-09-22] REVIEW-FIX | PA-01 Stage 2 corrections D/E (third review, DeepSeek/OpenCode)
- D: `endpoint_parts` made genuinely bounded and non-panicking (byte-index authority cut at first `/`/`?`/`#` so multibyte hosts like `http://é/abc` no longer panic); empty scheme/host, userinfo, and fragments rejected as Unknown. Endpoint comparison is a tri-state `EndpointRel::{Equal,Different,Unknown}`; a malformed endpoint in an otherwise-accepted attach shape is Unknown→Ambiguous, never "positively different", so tracking is never dropped on unparseable evidence. Removed the obsolete `endpoints_match` bool and the contradictory stacked comments.
- E: `create_new_session` keeps locally-created known sessions in an in-memory `locally_created` set (keyed by SessionKey identity); `refresh` merges them into successful snapshots without duplicates until the authoritative list observes them (then normal policy applies). A created identity now survives an empty list + plan/tmux spawn failure across immediate/subsequent refreshes; retry resumes without re-creating; eventual list visibility yields no duplicate rows and then ordinary removal.
- Gates: check ok, 60 tests pass (from 56), lint ok, repeat tangle byte-identical, `git diff --check` clean. Report updated with D/E evidence + corrected startup_eligible tuple description. Ready for architect review; Stage 3 out of scope.

## [2026-09-22] REVIEW-FIX | PA-01 Stage 2 endpoint-validation invariant (fourth review, DeepSeek/OpenCode)
- `endpoint_parts` is now a documented bounded ASCII HTTP(S) subset: scheme exactly http/https; reject non-ASCII/whitespace/control/backslash/userinfo/fragment/IPv6 as Unknown (never panicking on multibyte hosts); host must be DNS/IPv4-shaped (dot-separated alnum labels + internal hyphens, no leading/trailing hyphens; all-numeric dotted hosts only as valid 4-octet IPv4); port exactly one ':' + decimal u16; path/query preserved with only agreed trailing-slash normalization; malformed percent escapes rejected. Unknown endpoint in an accepted attach shape is Ambiguous (never Different), so malformed evidence cannot erase tracking.
- Added table-driven `endpoint_validation_subset_table` covering every rule + valid equal/different; extended malformed-ambiguous cases (`http://bad host:4096`, `http://localhost:99999`, `1http://…`, Unicode no-panic); integrated `malformed_endpoint_evidence_routes_through_adapter_into_reconciliation` registering the REAL opencode adapter in the app and preserving record + startup eligibility on malformed argv through `compute_interrupted`. Removed unused-mut test warnings.
- Gates: check ok, 62 tests pass (from 60), lint ok, repeat tangle byte-identical, `git diff --check` clean. Report updated. Ready for architect review; Stage 3 out of scope.

## [2026-09-22] IMPL | PA-01 Stage 3 landed: configurable instances, generic views, stable tracking (DeepSeek/OpenCode)
- Config: optional `[[providers]]` (id/type/label/enabled/options), fallible load (missing explicit PINGA_CONFIG / invalid TOML are errors), explicit providers authoritative over legacy fields + env; validation (unique IDs incl. disabled, blank labels, unknown type/options even when disabled).
- Factories: compiled-in type-key→factory registry; `build_registry` (explicit providers in order, skip disabled) vs `builtin_registry` (legacy). `ProviderDescriptor.display_name` now owned String; adapters parse/validate `url` (opencode) and absolute `home` (codex).
- Tracking: new `core::tracking` — `tracking-v2.json`/`.lock` with pinned envelope (version 2, next_id, tagged known/pending/opaque records), locked reread-mutate-atomic-write (temp+sync+rename), last-good view on read failure, monotonic ids under lock, one-shot legacy migration with exact-bytes backup (`opened-v1-migration-backup.json`, never overwritten), 0→opencode/1→codex, empty ids→pending, unknown indices→opaque; legacy never rewritten once v2 exists.
- App: per-provider views replace parallel arrays; viewport shows ≤2 columns (1 on narrow), focus wraps full sequence scrolling the viewport; mouse maps visible rects to providers; deferred plans keep provider; empty state for zero providers; listing identity/nonempty-id validation is provider-local; pending persisted, visible after restart, resolved only on unique confirmed evidence; interruption retained across polls (fixes second-poll drop); later opens never inherit startup eligibility.
- Gates: check ok, 63 tests pass (from 62), lint ok, repeat tangle byte-identical, `git diff --check` clean. Report: docs/handoffs/PA-01-stage-3-report.md. No live migration; ready for architect review.

## [2026-09-22] REVIEW-FIX | PA-01 Stage 3 corrections R1-R7 (DeepSeek/OpenCode)
- R1: exact one-read legacy migration snapshot under both locks; durable conflict-checked backup (conflicting backup aborts, identical retry safe, atomic publish + dir sync). R2: validate persisted envelope invariants on decode+commit (nonzero unique ids, next_id > max, provider ids, nonempty native ids); read failures surfaced (app keeps last-good); MemStore allocates ids + validates. R3: reconcile computes plans outside the lock and applies only to the exact observed record id/window/state; startup eligibility keyed by record id; pendings preserved while provider unavailable; commit-failure does not consume eligibility/notices.
- R4: codex resume+create launch plans carry CODEX_HOME; ProcEvidence narrow env (CODEX_HOME from /proc/environ); codex source discrimination (differing home never confirmed, unestablished source ambiguous). R5: selection preserved by SessionKey across reorder; per-view scroll drives render + mouse; spawn/tracking failure reports the launched window; foreground launch-to-create returns failure honestly. R6: config read-error semantics (only NotFound defaults), secret-safe parse diagnostics, registry built before raw mode. R7: restored behavioral regression coverage, clippy --all-targets clean.
- Gates: check ok, 74 tests pass, lint ok, clippy --all-targets ok, repeat tangle byte-identical, `git diff --check` clean. Report updated. Ready for architect review; Stage 4 unassigned.

## [2026-09-22] REVIEW-FIX | PA-01 Stage 3 corrections A-D (second review, DeepSeek/OpenCode)
- A: refresh captures the tracking snapshot BEFORE listing providers; records added concurrently fall outside the observed generation and are preserved by the conditional commit. Startup eligibility seeded at construction (never inherited by later records). Plans carry eligible/preserve intent; still/gone derived only from APPLIED outcomes; failed commit consumes nothing.
- B: launched-but-unrecorded windows kept in an explicit list; retry records the existing window without respawning; removed only on successful recording or confirmed death. Retry test checks create/spawn/tracking counters across persistent failure and recovery.
- C: per-view scroll drives both rendered row window and mouse hit-testing; selection preserved after regroup. (True multi-line item-height accounting remains a documented limitation.)
- D: MemStore stores an Envelope behind the mutex retaining next_id across deletion; codex source comparison is conservative (only validated exact absolute match is Same; else Unknown, never a positive Different); restored combined-cleanup, ambiguous-evidence reconciliation, foreground-honesty, and capability/pending regression tests.
- Gates: check ok, 78 tests pass, lint ok, clippy --all-targets ok, repeat tangle byte-identical, `git diff --check` clean. Report updated. Ready for architect review; Stage 4 unassigned.

## [2026-09-22] REVIEW | PA-01 Stage 1 changes requested
- Independent check/test/lint passed (11 tests); generated source matched blueprint and repeat tangling was byte-identical. Executable changes stayed in Stage 1 scope.
- R1: SessionKey public fields bypass its nonempty-ID constructor check; confirmed direct construction and mutation in a compiled temporary probe.
- R2: complete custom-config composition, successful create/rename dispatch, and distinguishable duplicate non-replacement acceptance tests; current report overstates this coverage.
- Review/correction packet: docs/handoffs/PA-01-stage-1-review.md. No implementation edits by architect; Stage 2 remains unassigned.

## [2026-09-22] REVIEW | PA-01 Stage 1 accepted after corrections
- R1 resolved: private SessionKey fields/read-only accessors; independent compile probes rejected both bypass forms (E0451/E0616).
- R2 resolved: custom config wiring, recorded successful rename/create dispatch, and distinguishable duplicate rejection tests.
- Independent check/test/lint passed (12 tests), generated-source fidelity and repeat tangling passed, git diff --check clean. No implementation edits or deployment by architect.
- Acceptance: docs/handoffs/PA-01-stage-1-review-2.md. Next is a bounded Stage 2 packet; no Stage 2 implementation is assigned yet.

## [2026-09-22] DESIGN | PA-01 Stage 2 full integration handoff
- Prepared Stage 2 task/report template; architecture revision 2 assigns capabilities, structured execution, explicit creation outcomes, and adapter-owned attachment evidence together, with one final review.
- Pinned conservative adoption, terminal restoration, creation failure handling, in-memory pending-launch limitation, and retention on failed observation. Stage 3 owns persisted-format migration and generic views/config.
- Same DeepSeek/OpenCode implementation session; larger autonomous batch per user request, no implementation or messaging by architect. Task: docs/handoffs/PA-01-stage-2.md.

## [2026-09-22] REVIEW | Stage 2 consolidated corrections requested
- Independent check/test/lint, whitespace, and tangle fidelity passed (25 tests). Stage 2 not accepted.
- R1–R5 in docs/handoffs/PA-01-stage-2-review.md: require positive tracked-window identity; preserve tracking/startup eligibility through unknown inspection; correct process/URL evidence; test real shell/terminal boundaries; finish capability/pending/lifecycle integration and app tests.
- DeepSeek authorized to inject storage/launcher/terminal dependencies and correct the entire affected flow in one batch. Stage 3 deferred; architect changed no executable code.

## [2026-09-22] REVIEW | Stage 2 second review: three remaining correction groups
- Independent gates pass (44 tests, lint/check, generated fidelity/repeat tangle, diff whitespace). Prior tracked-window identity and shell-boundary fixes improved.
- Startup eligibility is still granted to later records on transient failure and lost on total evidence failure; a temporary-copy regression test reproduced the former.
- Unknown CLI forms still become absence; actual application terminal/spawn error tests and resume capability guard remain incomplete; report overstates this evidence.
- Active packet: docs/handoffs/PA-01-stage-2-review-2.md (A–C). No production source edits by architect. Stage 3 unassigned.

## [2026-09-22] REVIEW | Stage 2 third review: endpoint and creation retention blockers
- Independent 56 tests/check/lint, repeat-tangle fidelity and whitespace gates pass.
- Reproduced Unicode-host parser panic and acceptance of an empty authority in a temporary Rust probe; malformed endpoints still become proof of absence.
- Created identity retention still depends on immediate list visibility; current test preloads the created session and masks snapshot replacement.
- Correction packet: docs/handoffs/PA-01-stage-2-review-3.md (D/E). Same implementer; no executable source edits or Stage 3 assignment.

## [2026-09-22] REVIEW | Stage 2 fourth review: endpoint validation remains
- 60 tests/check/lint and tangle/whitespace gates pass; test compile has unused-mut warnings. Creation retention accepted.
- Temporary unchanged-parser probes show malformed host, alphabetic/overflowing port and invalid scheme all return Different, not Unknown.
- Active packet PA-01-stage-2-review-4.md pins conservative URL grammar and real adapter-to-app evidence coverage. No executable edits. Recommend implementer High reasoning.

## [2026-09-22] REVIEW | Stage 2 accepted; Stage 3 assigned
- 62 tests and check/lint, whitespace and repeat-tangle fidelity pass without prior test warnings. Real OpenCode adapter evidence reaches app reconciliation in regression test.
- Acceptance: docs/handoffs/PA-01-stage-2-review-5.md. Stage 3 packet and report template prepared; architecture revision 3.
- Decisions: compiled-in factories with explicit per-instance config; bounded generic viewport; separate v2 tracking file with one-time locked legacy snapshot and exact backup, no cross-version convergence. Stable interrupted state and pending persistence required.
- Same High-reasoning DeepSeek session, full batch delegated; no source edits or live state migration by architect.

## [2026-09-22] REVIEW | Stage 3 correction batch; small UI fixes applied directly
- Independent baseline: 63 tests/check/lint and tangle/whitespace gates pass, with 11 test compile warnings. Structural work substantial but not accepted.
- R1–R7: migration snapshot/backup correctness, persisted invariants/read errors, conditional reconciliation outside locks, per-instance Codex source, UI selection/scrolling and launch errors, config loading, restored regression coverage/report accuracy.
- Architect directly corrected positional colors, per-column new capability styling and capability-driven modal notes in blueprint; added real TestBackend modal test. 64 tests pass.
- Active packet docs/handoffs/PA-01-stage-3-review.md; same High implementer. No live state touched.

## [2026-09-22] REVIEW | Stage 3 second review and bounded direct fixes
- Baseline 74 tests plus check/all-target clippy/fidelity/whitespace pass. Migration snapshot and validated conditional writes improved; remaining A–D packet created.
- Architect fixes through blueprint: propagate directory sync errors, Unknown for absent Codex source metadata, safe empty-view cursor movement, preserve new-session-row selection; regression assertions added.
- Remaining lifecycle race/retry/layout/fixture issues assigned in PA-01-stage-3-review-2.md. No live migration or deployment.

## [2026-09-22] REVIEW | Stage 3 closure plus bounded Antigravity spike assigned
- 78 tests/all-target lint/fidelity/whitespace pass; layout explicitly incomplete and retry test re-creates against a fixed-ID fake. Stage 3 not accepted.
- Combined packet PA-01-stage-3-review-3-antigravity.md closes layout/retry/interleaving gaps then authorizes read-only Antigravity investigation and optional fixture-tested adapter. No live mutation/deployment.
- No code edits by architect this round; combined batch conserves review round trips.

## [2026-09-22] IMPL | PA-01 Stage 3 Phase A closure + Antigravity spike (DeepSeek/OpenCode)
- A1: real-height line-based scroll/mouse mapping (removed VISIBLE_ROWS; item heights incl. headers/two-line rows; render + selection highlight + hit-testing share one mapping; zero-provider guard).
- A2: launch recovery by re-opening the retained session; bypasses evidence/adoption; never calls create again; distinct-ID fake test asserts create count stays 1 across persistent failure + recovery.
- A3: unrecorded pending identity = provider+label+cwd; liveness checked at retry (confirmed death not recorded; failed inspection retains).
- A4: interleaving replacement test via shared store handles; pending/ambiguous/combined-cleanup sequences restored.
- A5: removal notice is an accurate generic reason, not "deleted from server".
- Phase B: discovered NO installed Antigravity product (only empty cache staging dir + passive ai-memory hooks documenting a JSON-stdout event contract). No verified session surface -> no adapter implemented (evidence + blocker in docs/antigravity-integration.md), plus manual test checklist + opt-in config shape.
- Gates: check ok, 78 tests pass, lint ok, clippy --all-targets ok, repeat tangle byte-identical, `git diff --check` clean. Report updated. Ready for architect review; Stage 4/Pi unassigned.

## [2026-09-23] IMPL | PA-01 Phase B corrected: Antigravity IS installed as `agy` v1.2.9 (was uninitialised)
- Correction: earlier report claimed no Antigravity product. Wrong — `~/.local/bin/agy` (Google exa/jetski lineage) exists; the app data dir ~/.gemini/antigravity-cli/ was empty until initialisation. Verified `--conversation <id>` exact resume, `--continue`, `--new-project`, `conversation_summaries.db` SQLite index, and `ANTIGRAVITY_APP_DATA_DIR` env override.
- Implemented optional adapter src/provider/antigravity.rs (blueprint §5.3): compiled-in factory for type "antigravity", NOT auto-registered (builtin_registry stays opencode+codex). list() reads the summary SQLite read-only; resume = agy --conversation <id>; create = plain agy in cwd; match_session confirms exact UUID, conservative on --continue/unknown argv, foreign data dir -> Ambiguous (mirrors codex CODEX_HOME). Rename honestly unsupported (TUI /rename only; summary DB is a reconciled cache).
- Docs corrected: docs/antigravity-integration.md rewritten with real evidence + config example; report Phase B + validation updated (84 tests, +6 adapter tests).

## [2026-09-23] REVIEW | Antigravity prototype corrections and direct boundary fixes
- Optional agy adapter submitted; baseline tests/all-target lint/fidelity passed. Stage 3/layout/retry acceptance remains pending.
- Architect corrected launcher source metadata collection for agy, SQLite read-only open, and propagation of malformed rows; added malformed-row regression.
- Active packet docs/handoffs/PA-01-antigravity-review.md covers remaining core/layout/retry and adapter path/time/evidence/integration issues. No live provider operation by architect.

## [2026-09-23] IMPL | PA-01 antigravity review batch — corrections complete
- Scrolling: one shared list_layout (visual rows, line heights, column inner height from last_height; selectable->visual mapping) drives move_cursor/render/highlight/hit-test; long-list TestBackend test asserts RENDERED text + DISPATCHED SessionKey at short/tall sizes with headers + two-line rows.
- Launch recovery: pending launches get unique tokens; retry is explicit (retry_unrecorded(token)); ordinary new always spawns; known-key retry preserved; liveness error retains state (tested incl. failed inspection + confirmed death).
- Deterministic file-store interleaving: RacingStore seam commits a concurrent replacement via a second real FileTrackingStore INSIDE the first read-modify-write; conditional commit preserves it.
- Antigravity parsing: first_workspace decodes file:// URIs/percent/JSON/bare paths; comma+unknown -> None. parse_go_datetime_ms is checked/validated (invalid, pre-epoch, offset, >6-digit frac -> None). Missing DB = fresh; existing-but-unopenable = error. Non-UTF-8 home rejected, not lossy. REAL /proc collector -> adapter env test.
- Testing path: two-homes config test + real-adapter-through-app list/resume/track; complete opt-in config + manual checklist in docs/antigravity-integration.md; report rewritten with requirement->test map + honest completed/blocked. Gates: 97 tests, lint/clippy clean, idempotent tangle, diff-check clean.

## [2026-09-23] REVIEW | Candidate ready for supervised Antigravity smoke test
- Final batch reviewed; direct fixes expose pending-token retry via p and bound timestamp conversion.
- Sample opt-in config and isolated-tracking manual test instructions prepared in PA-01-manual-test-ready.md. No live launch, normal config change or deployment.
- Runtime behavior remains unverified until user performs disposable conversation/new/list/exact-resume checks.

## [2026-09-23] DIAGNOSE | First Antigravity live smoke: empty index
- User opened agy from Pinga and refreshed with g; no listed session. Read-only query confirms configured conversation_summaries table has 0 rows; conversations directory has 0 files.
- No evidence yet of adapter filtering a persisted conversation. Asked whether a first message was sent; opening a client alone may not persist a conversation (hypothesis, not verified). No live data or code changed.

## [2026-09-23] PAUSE | Provider development paused for message passing
- User confirmed live agy creation after first message, automatic listing, exact conversation resume, and existing-window selection for resumed clients.
- Known limitations: native creation window lacks provable session identity; entered name is tmux label, not native title.
- User requests suspension of this line and discussion of separate-session/project message passing. Checkpoint saved; no further provider implementation.

## [2026-09-24] ASSIGN | PB-01 external project browser
- User confirmed scope and remaining limits 30%/85%. Original prompts establish FOSS requirement, copyleft preference, and external-browser-first scope; Mnemosyne local-folder/sync remains separate.
- Packet docs/handoffs/PB-01-project-browser.md revision 1. Confirmed builder ses_f317e9fbeffe9uLy8WUt4vc05Z, title test-messaging, DeepSeek V4 Flash High; API status idle before dispatch.
- Direct native prompt_async returned HTTP 204 for pinga-pb01-assignment-01. Delivery submitted, not yet acknowledged/completed. Reply to architect 01a0cb2e-e31c-7e33-8094-ac926ac14b53 via existing native queue.
- No dependency install/live config edits/deployment. Provider development remains paused.

## [2026-09-24] BUILD | PB-01/1 external project browser implemented (submitted for review)

`b` opens a Browse project directory form (prefill = focused session dir or pinga cwd);
launch Yazi rooted there via the existing LaunchRequest seams (new tmux window, or
foreground suspend/restore). Markdown->Glow (-p), text/code->bat (--paging=always) as
Yazi 26.9.1 block openers in the SAME window; wildcard fallback lets bat refuse
binaries clearly. Private Yazi profile via YAZI_CONFIG_HOME under PINGA_STATE_DIR
(persistent, never deleted). No tracking writes/provider calls; tools checked early.
New generated module src/browse.rs; app integration in src/tui/app.rs
(EditState::Browse, injectable tools_check seam, state_dir).
Gates green: tangle (15 files), cargo check, 108 tests, clippy --all-targets -D
warnings, repeat-tangle fidelity, git diff --check. Only bat on PATH; no real
Yazi/Glow smoke claimed; install instructions in docs/handoffs/PB-01-report.md.
Report: docs/handoffs/PB-01-report.md (SUBMITTED, not accepted).

## [2026-09-24] REVIEW | PB-01 corrections dispatched
- Independent 108 tests/all-target lint/fidelity/whitespace pass. Not accepted: Browse errors hidden behind form; Yazi default opener precedence; missing Glow/bat isolation; profile publication race and root/path issues.
- Packet docs/handoffs/PB-01-review-1.md sent to existing DeepSeek builder ses_f317e9fbeffe9uLy8WUt4vc05Z (user elected to retain that builder after routing correction). Native prompt_async HTTP 204, message pinga-pb01-review-01. No install or global edits.

## [2026-09-24] FIX | PB-01 review-1 corrections applied (119 tests)

Fixed per docs/handoffs/PB-01-review-1.md: errors render beside the editable form
(modal+inline, rendered-buffer tests); Yazi [open] rules fully overridden (no default
editors/xdg-open/extractors ahead), -- end-of-options before %s, unsupported -> clear
refusal; full three-tool isolation (YAZI_CONFIG_HOME, GLOW_CONFIG_HOME,
BAT_CONFIG_PATH, BAT_PAGER/PAGER); unique-temp atomic profile publication
(concurrent-writer test); canonical-absolute paths + reject non-UTF-8; PINGA_STATE_DIR
scoped to browsing only (tracking reverted to platform state dir); prefill requires an
existing dir (fallback to cwd tested); literal paths preserve leading/trailing spaces;
zero-provider key-handler test; real failure-path tests (tmux failure, spawn failure
+restore, partial suspend never launches). Report updated with doc-verified vs
executable-tested split; Debian Yazi install claim removed (Arch host).

## [2026-09-24] REVIEW | PB-01 viewer boundary follow-up
- 119 tests/all-target lint/whitespace pass. Earlier defects improved.
- Upstream Glow source shows config-home prepends paths (empty dir not isolation), MaximumNArgs(1), and color-aware pager needs. Active packet PB-01-review-2.md dispatched natively HTTP 204 to same DeepSeek builder, message pinga-pb01-review-02. No installs/global edits.

## [2026-09-24] FIX | PB-01 review-2 viewer boundary corrections (119 tests)

Per docs/handoffs/PB-01-review-2.md: published valid minimal glow.yml (glow
PREPENDS GLOW_CONFIG_HOME, empty dir falls through to personal config) and
neutralized ambient GLOW_* (GLOW_TUI=false); single-file viewer policy %s1
glow/bat (cobra MaximumNArgs(1) forbids multi-file), recorder test re-labelled
and re-scoped to one hostile file at a time; color-preserving pager pinned to
less -R (PAGER/BAT_PAGER) with LESS="" to neutralize ambient immediate-exit
flags, less added to the pre-launch tool check; fallback failures user-visible.
Source-reviewed glow main.go (current main). No installs/global edits. Report
updated: docs/handoffs/PB-01-report.md.

## [2026-09-24] REVIEW | PB-01 candidate ready for real-tool smoke
- Independent 119 tests/all-target lint/fidelity/whitespace pass; reviewed final viewer-boundary changes. No further builder assignment.
- bat/less installed; local Arch metadata offers yazi 26.9.1-2 and glow 3.0.0-2 (MIT). Request user approval for system package installation outside prior no-install batch.
- docs/handoffs/PB-01-smoke-ready.md records outstanding executable/interactivity tests; no installation/deployment performed.

## [2026-09-24] TEST | Installed viewer smoke
- User installed Yazi/Glow. Verified Yazi 26.9.1 and Glow 3.0.0; cargo build passes. Real Glow/bat process tests with private configs and a recording pager render a Markdown filename containing quotes/spaces/Unicode successfully. Interactive Yazi routing/return still pending user test.
- Bare glow --version attempted default config creation, blocked by sandbox; isolated private-config invocation passed without error. No global configuration changed by architect.

## [2026-09-24] ACCEPT | Browser live smoke passes; contrast polish deferred
- User confirms browser/viewer/return flow works. Reports low-contrast blue/white information widgets at lower-left/right; owning tool not yet verified.
- Explicitly defer contrast work due to remaining limits 19%/13%. Recorded only, no implementation changes.

## [2026-09-26] FIX | PB-02/1 pre-push closure (120 tests)

Task 1 (contrast): identified the owning UI as Yazi's shipped status bar —
yazi-config/preset/theme-dark.toml [mode] normal_main = { bg = "blue", bold = true }
(bare blue bg + default white fg) at the lower-right mode block, with the
lower-left status info under [status] overall. Fixed via a private profile
theme.toml (new THEME_TOML published by ensure_profile) pinning explicit
high-contrast fg/bg pairs for [status] overall + [mode] normal_main/alt.
Smallest local adjustment; no global theme changes/new deps; regression asserts
no unrelated widgets are restyled.

Task 2 (provider loose ends): no small release-blocking production defect found
(unwraps/expects are test-only). Limits already conservatively handled
(plain-agy launches Ambiguous, never inferred by cwd/title/time; rename
unsupported; title labels window only). Added explicit user-facing limits note
to docs/antigravity-integration.md (5b). No new providers/title hacks/
speculative identity.

Gates green: tangle 15 files, cargo check, 120/120 tests, clippy --all-targets
-D warnings, repeat-tangle fidelity, git diff --check. No commits/push/install.
Report: docs/handoffs/PB-02-report.md.

Review correction: viewer dependencies and PB-01 user smoke were already complete;
only new contrast needs visual confirmation. Listing does not identify the original
plain-agy window; exact-ID resume enables tracking. No Git remote configured.

## [2026-09-24] FIX | PB-02/2 contrast regression (120 tests)

User live test FAILED the first PB-02 contrast patch: corner indicators
(disappeared). Verified against installed Yazi 26.9.1 in an isolated PTY:
overriding ANY [status] table (even overall alone) hides the right 1/ tab
indicator and adds a left separator; [mode] alone is safe. Narrowed THEME_TOML
to [mode]-only (normal_main white on #2d5aa0); re-verified PTY status row
byte-identical to baseline with indicators restored and mode block recolored.
Lower-left status colors remain Yazi defaults (reported uncertainty; a [status]
override is unsafe in 26.9.1). Provider limits unchanged (docs/antigravity-
integration.md 5b). Gates green: tangle, cargo check, 120/120, clippy
--all-targets -D warnings, fidelity, diff --check. No commits/push/install.
Report: docs/handoffs/PB-02-report.md.

## [2026-09-26] UPDATE | Browser green/purple palette
User clarified the contrast concern is in the directory browser and requested
green/purple. Set normal_main to pale green on dark purple and normal_alt to
pale purple on dark green; retain the mode-only override and default status layout.

User confirmed good browser contrast; slightly deepened green/purple text to
#a5e5aa and #d3a4ef so their hues are more apparent, keeping dark backgrounds.

## [2026-09-26] ACCEPT | Browser palette approved
User accepted the final green/purple colors. Preparing the authorized public
jergas/pinga repository and push; provider limitations remain documented.

## [2026-09-27] BUG | Newly launched Codex session absent from Pinga list
User opened the new Astra "fresh architect" session through Pinga's new-session
function in the current tmux session, but it does not appear in Pinga's session
list. User supplied the live thread ID: 01a0e595-aede-70f0-9436-bf8a2ba09bd1.
Recorded for investigation; not reproduced or diagnosed. Do not assume this is
the earlier Antigravity pre-first-message listing behavior. Check discovery,
refresh, and active Codex storage/config scope when investigating.

## [2026-09-28] CHECKPOINT | Ready for tmux restart
Pinga provider/browser/README work is published and accepted. Both Pinga DeepSeek
implementers have completed their assigned batches and were idle at verification.
Preserved Fresh's recoverable transcript and cross-project restart notes under
ignored .memory/tmp/restart-2026-09-28/ (outside system /tmp). Missing newly-created
Codex session discovery remains a recorded, undiagnosed bug; no fix attempted.

## [2026-09-22] HANDOFF | wrote handoff-and-future.md + linked in index
Comprehensive state-of-project / roadmap / last-words doc written to
.memory/wiki/handoff-and-future.md and linked from index.md. Covers: what pinga
is, commit-history summary, future directions (mouse-over-ssh, codex manual
test, codex app-server protocol, order-by-id option, pinga-name registry,
session_id surfacing), feature ideas (status/token dashboard, filtering,
pinning, SSE activity alerts, configurable keys, multi-server), and "famous
last words" for future incarnations (literate build discipline, gates before
commit, one-opencode-server rule, codex state DB + full-UUID gotcha,
update_opened-only mutations, selectable-indexed sel, no-reorder rename,
tmux-vs-bare modes, cautious-user working style, ai-memory scope).

## [2026-10-03] tmux auto-restore broken + systemd restore service
- After a reboot, tmux-resurrect did NOT auto-restore: tpm loads no plugins on a
  fresh server, so continuum's @continuum-restore never fires. The session was
  only recoverable by manually running tmux-resurrect's restore.sh.
- Fix: added `deploy/pinga-tmux-restore` + `pinga-tmux-restore.service`
  (systemd user unit, WantedBy=default.target, runs once at boot): starts a
  tmux server if none, runs resurrect restore from ~/.tmux/resurrect/last,
  drops the bootstrap session. `make install` deploys + enables it.
- Restored the user's `pinga` session (11 windows) manually; verified the
  restore script works; save timer still active (every 10 min).

## [2026-10-03] FIX: dead tracked windows poisoned every open + scope notes
- Symptom: opening ANY session refused with "cannot inspect running windows
  right now; f to force". Root cause: after the reboot + tmux-resurrect restore,
  tracking-v2.json held stale window ids (@17/@45/@51) that no longer exist.
  `collect_evidence` added those tracked windows to the scan list, their
  `pane_root_pids` lookup failed, and the failure marked the WHOLE evidence
  incomplete -> decide_open -> RefuseIncomplete for every session.
- Fix: `collect_evidence` now only scans tracked windows that still exist
  (`window_alive`); dead stale ids are skipped so the scan stays complete.
  Interrupted sessions then open normally (verified: pinga-subagent + a closed
  session both spawned windows; the opened interrupted session left the
  interrupted group).
- ALSO (issue 1): a bare `opencode` serves sessions scoped to its cwd's
  PROJECT (opencode.db is per-project); from /home/edgar it shows the global 15,
  but from a project dir (e.g. /home/edgar/projects/pinga) /sessions is EMPTY.
  The shared :4096 server (cwd=/home/edgar) is the global store. Use
  `opencode attach http://127.0.0.1:4096` (which pinga does) or run from
  /home/edgar. The stale tmux window running bare `opencode -s <id>` (own dead
  server) should be closed and reopened via pinga.

## [2026-10-03] FIX: bare `opencode -s <id>` windows made every open "uncertain"
- Symptom: after a reboot + restore, opening ANY session refused with
  "uncertain whether already open elsewhere" even for sessions known closed.
- Root cause: the restored tmux layout had a window running bare
  `opencode -s <id>` (no endpoint). OpencodeProvider::match_session treated any
  unrecognized opencode argv shape as AMBIGUOUS evidence, so that one window
  made every opencode session look "maybe open elsewhere" -> RefuseUncertain.
- Fix: recognize `opencode -s <id>` as an explicit-session form: confirmed when
  the id matches the target session, no candidate otherwise (mirrors the
  `attach <endpoint> -s <id>` handling). Verified in a reproduction session
  (bare `opencode -s <id>` window present; opening a different session spawned
  a window). 120 tests pass.
- NOTE for future agents: NEVER run `pgrep -af "opencode" | xargs kill` — it
  also kills the agent's own opencode client (the session quit when I did this).
  The user's own clients may also run `opencode -s <id>`; use tmux pane kills.

## [2026-10-03] IMPL | R12 reboot bring-up: `pinga up` + bare-pinga boot/attach (D12)
- D12 design agreed with user: layered restore (opencode.service -> tmux-resurrect replay -> `pinga up` reconcile); one tmux session (default `main`, config `tmux_session`/`PINGA_TMUX_SESSION`); window 0 = pinga TUI (recursive invocation); resurrect stays as the layout safety net for manual windows.
- New `core::bringup` (src/bringup.rs): ensure_session (has-session/new-session detached + TUI window verified by pane argv, created if missing) + reconcile of tracking-v2.json Known/open records: adopt on exactly one Confirmed window (repairs stale window ids — resurrect reassigns them), launch via resume_plan when missing (only on complete evidence + session in listing, listing retried 3x/2s for boot races), defer otherwise (ambiguous/incomplete/listing failure/gone). Never launches blind.
- Tmux trait grew has_session/new_session/attach/list_windows; Launcher gained collect_evidence_in + open_in_tmux_in (named-session variants); tracking gained set_window + state_dir().
- CLI: bare `pinga` outside tmux = bring-up then attach; inside tmux = console unchanged; `pinga up` = headless bring-up (systemd). deploy/pinga-up.service + make install/uninstall wiring.
- Gates green: 133 tests, clippy --all-targets -D warnings, repeat tangle fidelity, release build. Not committed; NOT run live (would create the session / launch real agents on the user's machine).

## [2026-10-03] IMPL | Single console per tmux session (D12 follow-up)
- Answering lifecycle design questions: quitting the console never tears the tmux session down (agents + manual windows outlive it; restart in the same window just resumes — store is durable); no quit prompt (quick q stays quick); full teardown stays an explicit tmux action, not a quit side-effect.
- New guard: `bringup::other_tui_in` — pane-argv scan of the current session for another pinga console, self-excluding by pid; `auto_mode` inside tmux refuses with the running window's id. Restart-in-place (no other instance) passes, so quit+restart just works. Incomplete evidence never refuses (duplicate console is benign via the cooperative store).
- Gates green: 136 tests, clippy --all-targets -D warnings, release build. Not committed; not run live.

## [2026-10-03] IMPL | Second-console refusal now redirects to the running console
- User asked whether a refused second pinga should switch to the running console's window: yes — it fulfills the user's intent (they typed pinga wanting the console) and mirrors D8's select-instead-of-duplicate. New `bringup::guard_console` (other_tui_in scan + best-effort `select_window`), returns ConsoleGuard{window, switched}; auto_mode prints where it went and exits 0; switch failure tells the user to select manually.
- Gates green: 138 tests, clippy --all-targets -D warnings, release build. Not committed; not run live.

## [2026-10-03] FIX | Second-console guard defeated by bare argv0; session name mismatch
- User reproduced: quit console, restarted, opened a NEW window and ran pinga → a second console came up instead of redirecting. Root cause: a manually-started console has argv[0] = bare "pinga" (verified: pid cmdline = `pinga`), while the guard compared argv[0] against the FULL canonical path — no match → guard saw "free". The boot TUI window matches because it's `sh -c "exec '<exe>'"` (full path).
- Fix: new `argv_is_pinga` helper — full path OR basename match (same convention as the provider adapters). Used by both `other_tui_in` and `ensure_session`'s TUI-present check (the latter had the same latent bug for resurrect-replayed windows). Tests: bare name, relative path, canonical path, near-miss names (pinga-tmux-save), empty argv.
- ALSO: user's real tmux session is named `pinga`, but bring-up defaulted to `main` — at boot `pinga up` would have created a SECOND session alongside the resurrected one. Created ~/.config/pinga/config.toml with `tmux_session = "pinga"`.
- Gates green: 140 tests, clippy -D warnings. Installed. The running console is still the OLD binary — quit+restart to pick up the guard fix.

## [2026-10-03] FIX | Guard message shows tmux's index:name label, not the raw window id
- User: the redirect worked but printed "window @2" while tmux's status bar shows "1:edgar". New `Tmux::window_label` (display-message -t <win> -p '#{window_index}:#{window_name}'); ConsoleGuard carries label (best-effort, None if tmux can't report); auto_mode prints the label with the @id as fallback.
- Gates green: 140 tests, clippy -D warnings, installed to ~/.local/bin/pinga.

## [2026-10-03] DESIGN | Bring-up never auto-launches; this session IS ses_f5416a
- User's design choice (revises D12): a session not running in the tmux session must NOT be auto-relaunched by bring-up — it stays in the console's list, where the user relaunches it explicitly. Bring-up's reconcile now only verifies/adopts/repairs bookkeeping and REPORTS not-running records (`RestoreAction::NotRunning`); the launch branch (resume_plan + open_in_tmux_in) is removed. `Launched` variant removed; print_report prints "not running — reopen from the console's list".
- Also corrected a wrong claim: ses_f5416a477ffef4yNuMa5BLYWlJ ("pinga - 2026-09-16T20:29:52.392Z", slug witty-rocket) IS THIS conversation — verified my own client process argv is `opencode -s ses_f5416a477ffef4yNuMa5BLYWlJ` (bare -s form). My earlier pgrep missed it because it grepped "opencode attach"; the bare `-s` client carries no "attach" token (the form the 2026-10-03 match fix recognizes). Record 9's window @5 is current; bring-up would have adopted it, not launched anything.
- Gates green: 140 tests, clippy -D warnings, installed.

## [2026-10-03] IMPL | Restore sessions into their pre-reboot windows (resurrect only brings back shells)
- User's requirement: resurrect replays windows+shell history but never the agents; pinga must restart every session IN THE WINDOW IT WAS IN before interruption. New design: records carry a restore-stable window identity — (window_index, window_name), which tmux-resurrect replays while reassigning @ids.
- Schema: TrackedRecord::Known gains #[serde(default)] window_index/window_name (additive, v2 stays; old files parse). Captured at record_launch + Plan::Adopt (best-effort, launcher.window_index_name). Backfill pass in reconcile for records lacking identity (live window lookup) — ran live: records 7/9/16 now carry idx 3 "markdown" / 2 "pinga" / 9 "yazi".
- New Tmux seam methods: window_index_name, session_windows (id|index|name), respawn_pane (-k in place). Reconcile's no-match branch now tries restore_into_window: find the window by stored index/name, respawn the resume_plan command ONLY if the pane is an idle shell (single shell-rooted process — is_idle_shell); busy windows are refused (never kill user work); no identity/candidate → NotRunning (list, user relaunches). RestoreAction::Restored + report line "restarted in place".
- Live `pinga up`: all 3 records adopted as already running; identities backfilled. Gates: 144 tests, clippy -D warnings, installed.

## [2026-10-04] FIX | Boot troubleshooting round (first real reboot)
Symptom: session+console came up, but only the pinga window; this conversation + markdown/yazi showed interrupted; codex sessions missing entirely.
Root causes (all evidenced):
1. tmux-resurrect restore silently did nothing at boot (journal shows service exit 0; `tmux run-shell` swallows restore.sh's failures). The script works standalone AND under systemd-run — boot-specific failure remains unexplained; now INSTRUMENTED (deploy/pinga-tmux-restore logs the save path, restore.sh output, and resulting sessions to the journal).
2. opencode.service marked Started 10s before its HTTP listener came up (05:06:50 vs 05:07:11); pinga-up's 3x2s retry expired first. LIST_RETRIES 3 -> 15 (30s).
3. With no restored windows, restore-into-window had nothing to restore into. New fallback: when the recorded window identity has no matching window, RECREATE it with the recorded name and start the session in it (tracked sessions now come back even without resurrect). Records 7/16 were already marked interrupted by the console (respected — user's choice to resume).
4. Codex sessions were NEVER tracked (hand-opened; scan_attached is ephemeral). New auto-track: the console records any session observed running with exactly one Confirmed window (complete evidence only), capturing window identity — so hand-opened sessions survive reboots too. Test: observed_running_session_is_auto_tracked_and_never_duplicated.
Schema: Known gains #[serde(default)] window_index/window_name (additive). Gates: 146 tests, clippy -D warnings, installed. Not committed.

## [2026-10-04] FIX | Why records were dropped: the rename disease (user caught my error)
- User corrected me: the codex sessions were opened RECENTLY (Oct 3 ~20:08-20:37, during restart testing), not in the distant past — and they WERE opened from pinga. Evidence: pre-reboot resurrect save names those windows "Ask DeepSeek for architecture report" etc., while the threads are now named "Trickster/Mundito/Yatagarasu architect" — the threads were RENAMED after opening. codex resume argv carries the OLD title; match_session compares against session.id/CURRENT title → no candidate → the reconcile's "window alive but not running_here, complete, not uncertain" branch REMOVED the record within hours of every rename.
- Root mechanism (the "disease"): records are keyed by raw @id and the reconcile only inspects the RECORD's own window; anything that makes the provider return no candidate for that window (rename, reused window, id reassigned by a server restart) reads as "session ended" → silent drop, even while the session runs in that very window.
- Fixes: (1) codex adapter — a resume target matching NO current session is Ambiguous (stale name could be ours), never a clean negative; a target that provably belongs to another snapshot session stays a clean negative. (2) app reconcile — before Remove in the alive-but-not-running_here branch, if the session has exactly one Confirmed match in ANOTHER window, re-point the record there (with fresh identity) instead of dropping.
- Tests: renamed_thread_with_stale_resume_target_is_ambiguous_not_absent (codex), plus prior auto-track. Gates: 147 tests (3 consecutive clean runs), clippy -D warnings, installed.

## [2026-10-04] IMPL | Rename consistency + agy provider enabled
- User confirmed: the codex sessions were renamed BY HIM for meaningful names. Answer to "why does rename leave inconsistent state": rename already flows through the abstracted Provider::rename trait (D10) — opencode renames server-side via verified HTTP, codex writes threads.name in SQLite (the running app-server reads the SAME file, so the server is renamed; the client TUI may cache the old title in-memory — upstream behavior), agy honestly unsupported (recon: TUI-internal /rename; summary DB is a derived cache). The VISIBLE inconsistency was the tmux window label keeping the old name.
- Fix: after a successful provider rename, pinga now also renames the tracked tmux window (rename-window, 24-char label convention) and refreshes the record's restore identity — `rename_tracked_window`. New Tmux::rename_window seam. Test: rename_also_renames_the_tracked_window_and_refreshes_identity.
- codex app-server control-socket rename (so the RUNNING client updates): not attempted — recon (D3/§5.2) found the protocol IDE-oriented; the DB write reaches the server. Bounded recon proposed as follow-up if the user wants the live client's in-memory title to change.
- agy provider ENABLED: ~/.config/pinga/config.toml now lists explicit providers (opencode/codex/agy antigravity home ~/.gemini/antigravity-cli) — agy 1.2.9 installed. Restart pinga to pick it up.
- Gates: 148 tests, clippy -D warnings, installed.

## [2026-10-04] IMPL | Aliases + resurrect handshake + codex rename recon
- Aliases (the "not blindsided by my own rename" fix): TrackedRecord::Known gains #[serde(default)] aliases; rename_tracked_window stores the OLD title; new Provider::match_session_aliased (default = match_session) lets the codex adapter confirm a `resume <target>` whose target is one of pinga's recorded old names; reconcile + compute_running use it, so a renamed session stays CONFIRMED (running group) instead of falling to ambiguous/closed while its client still runs under the old argv title.
- Resurrect handshake (user's requirement): when `pinga` (outside tmux) finds no session, it asks FIRST via the new injectable Resurrect seam (Launcher::with_resurrect; real = systemctl --user start pinga-tmux-restore.service, blocking on the oneshot); the deploy script now writes ~/.local/state/pinga/restore-status.txt (OK n sessions / FAIL reason / SKIP reason); pinga reads it, reports it ("resurrect service: …"), and only falls back to creating its own session when the service failed. If the resurrect brought the session up, pinga skips creation entirely.
- codex rename recon: the 0.160 app-server protocol (generate-json-schema + strings) HAS ThreadSetName{name,threadId} + ThreadNameUpdatedNotification (pushed to running clients) + `codex app-server proxy` to inject bytes; Initialize handshake required. Wire framing unknown (newline-JSON got no echo) — follow-up spike before implementing server-side rename.
- agy: registry builds fine with the explicit config; the third column exists but the viewport shows 2 columns — wrap focus to see it.
- Gates: 149 tests, clippy -D warnings, installed.

## [2026-10-04] FIX | "create window failed: index N in use" (tmux renumber quirk)
- Symptom: after quitting the console (its window closed, leaving indexes [1,2] with 0 free), `pinga` outside tmux failed with `tmux new-window failed: create window failed: index 1 in use`; user had to attach manually. Reproduced with a bare `tmux new-window -t pinga`.
- Root cause: with `renumber-windows on`, after a window closes tmux's internal next-index counter points at an occupied index (1) while 0 is actually free — plain `new-window -t <session>` dies.
- Fix: `TmuxCli::new_window` now computes a gap-filling free index itself (list-windows indexes -> `next_free_index`, pure fn + unit test) and creates via `-t <session>:<index>`; falls back to tmux's choice if the listing can't be read.
- Verified live: console recreated at index 0. Gates: 150 tests, clippy -D warnings, installed.

## [2026-10-04] FIX | Kill-server test: resurrect WORKED; conversation missed by index collision
- User's test: I killed the tmux server; user invoked `pinga` to recreate. User concluded resurrect failed; the journal proves otherwise: pinga-tmux-restore.service restored `pinga: 3 window(s)` at 06:24:42 (status "OK 1 sessions"). What didn't come back was the conversation CLIENT — resurrect replays shells — and pinga's restore-in-place then missed it: the record's identity (idx 1, name "pinga - 2026-09-16T20:29") collided with the FRESH session's console (base-index 1 → console at index 1, name "pinga"); the index-only match found a busy window → Deferred forever → user restarted the conversation manually (record 19). Codex was recreated via the create-fallback (record 18 -> idx 0 "Pinga architect", running).
- Fix: restore_into_window now distinguishes name-match (strong) from index-only (weak): name+busy -> Deferred (never kill); index-only+busy -> fall through to create-fallback with the recorded name (a live client would have been adopted earlier). Test: index_collision_with_a_busy_console_falls_back_to_recreation.
- Gates: 151 tests, clippy -D warnings, installed. renumber-windows set off in ~/.config/tmux/tmux.conf (line 69) + live server.

## [2026-10-04] ROOT CAUSE FOUND | systemd kills the restore service's tmux server (cgroup teardown)
- The user's drill (kill server -> invoke pinga) + the 06:24 report ("no server running" twice, yet the service journal showed pinga: 3 window(s) and status OK) exposed the real bug behind EVERY "resurrect did nothing" mystery: systemd user ONESHOT units tear down their cgroup when the unit completes — killing any tmux server the script spawned. At boot (05:06) the restored layout died with the unit; at 06:24 the 3 restored windows died ~1s after restore.
- Proven with isolated tests: default KillMode -> fresh server dead after unit finishes; KillMode=process -> still dead; RemainAfterExit=yes -> unit stays active(exited), server SURVIVES. (Earlier -S tests were invalid: tmux can't create the socket dir when the parent was rm'd — the "deaths" were never-started servers.)
- Fix: pinga-tmux-restore.service gains RemainAfterExit=yes. Deployed + daemon-reloaded.
- Also confirmed the collision fix works live: the user's 06:46:36 `pinga` brought back console + codex + THIS conversation automatically (create-fallback), all 3 windows alive (attached).
- Note to self: my shell's $TMUX overrides TMUX_TMPDIR; and I twice killed the user's real server with tmux kill-server while probing — never run kill-server without -S and a real isolation check.

## [2026-10-04] IMPL | Console is always the session's first window
- User: "when pinga restores the windows, it should make sure to put itself in the first one." ensure_session now returns the FOUND console window id (not just created); bring_up ends by move_window_to_front (tmux move-window -t <session>:0, no-op when already first). New Tmux seam + test (bring_up_moves_the_console_to_the_first_window). 152 tests, clippy clean, installed.

## [2026-10-04] FIX | resurrect request was a silent no-op (systemctl start on active(exited) unit)
- The definitive cold-start drill mostly passed: the session came back in the same window order, console running, both agents back. But the RESTORE itself never ran at 06:51 — pinga created the session itself. Cause: with RemainAfterExit=yes the unit stays active(exited) after the 06:46 run, and `systemctl start` on an already-active unit is a no-op that does NOT re-run ExecStart.
- Fix: request_resurrect now uses `systemctl --user restart pinga-tmux-restore.service` (re-runs even when active(exited); identical to start when inactive). Note: the 06:58 service run restored INTO the already-existing session without damage — restart-on-bring-up is safe.
- Also noted: the move-to-front fix wasn't exercised (the 06:51 pinga predated it; the 06:58 invocation was inside tmux → guard redirect). Next outside bring-up will move the console to index 0.
- Gates: 152 tests, clippy clean, installed.

## [2026-10-04] FIX | Console deaths during drills — resolved via the resurrect-success TUI check
- Symptom: consoles created during cold drills (kill server -> invoke pinga) came up and then exited cleanly (no error, no exit-log entry). Killed the ssh AND eris drills; my own synthetic drills survived, so I instrumented console-exit.log (unconditional) + phase logs + a strace watcher on every pinga process.
- Findings: the 07:32 drill's console DID log a full startup ("app.run() entered") and never returned -> mid-run kill. But the full service timeline showed each drill restoring fine; the resurrect-success path in ensure_session returned EARLY (Ok(false, None, resurrect)) WITHOUT the TUI check — so post-restore drills either created the console in a different flow or not at all ("pinga is dead" was sometimes 'no console at all').
- Fix: ensure_session's resurrect-success path now falls through to a shared ensure_tui_window (verify console argv, create if missing) — every drill creates the console identically via new_window into the restored session.
- RESULT: the next drill's console SURVIVED (3+ min watch, past every previous death window, zero signals, full startup logged, strace armed). Console alive at 0:pinga; window order: 0:pinga, 2:conversation, 4:codex (+ leftover 3:pinga corpse shell, user may tidy).
- Instrumentation kept: console-exit.log (unconditional), quit-key logging, phase logs; strace watcher in /tmp/opencode/trace stays armed for the next death, if any.
- Gates: 152 tests, clippy clean, installed.

## [2026-10-04] PREP + IMPL | Repo governance + thin-client first slice
- Added LICENSE (AGPLv3-or-later), roadmap.md (priorities: 1 thin client, 2 installer+GitHub, 3 codex server-side rename spike, 4 thick-lite listing, 5 boot telemetry/doctor, 6 docs), HISTORY.md (one-liner-per-feature changelog with dates; old entries immutable except odd corrections), and recorded the policy in AGENTS.md (Changelog & Roadmap Policy) so all agents see it.
- Thin client (roadmap 1) FIRST slice landed: `core::remote` (blueprint §11.8d, src/remote.rs) — pinga-owned ~/.config/pinga/remotes.toml (atomic save), per-host ed25519 keys (~/.ssh/pinga-<name>, generated only if missing, never overwritten), pure argv builders (test/connect/install/keygen — no shell interpolation), CLI `pinga remote list|add|keygen|install-key|test|connect`. Live smoke: add + keygen + test (BatchMode host-key refusal is the correct fail-safe). 157 tests, clippy clean, installed. Remotes file set to eris 100.115.173.85 (the mac's Tailscale address).
- HISTORY/roadmap/LICENSE/AGENTS changes are UNCOMMITTED; thin client needs the mac-side install-key + connect validation before its HISTORY entry.

## [2026-10-04] FIX | thin-client mac onboarding: missing-tmux message + target/ sync lessons
- Mac `make install` produced "zsh: exec format error": target/ was synced by Syncthing (sync root = ~/projects, no .stignore), so the mac installed eris's Linux ELF. Fix: /pinga/target in ~/projects/.stignore (per-device — mac needs its own), and Makefile portable for BSD install (mkdir -p + -m, no -D) + units only deployed when systemctl exists (mac prints a note only).
- Second mac issue: bare `pinga` failed with raw spawn ENOENT (no tmux on macOS). Fix: bring_up detects io::ErrorKind::NotFound in the error chain (is_tmux_missing, unit-tested) and prints "tmux is not installed on this machine... use `pinga remote connect <name>`". Verified by simulating PATH without tmux.
- Next: mac flow = remote add eris 100.115.173.85 edgar -> install-key (password once) -> connect.
