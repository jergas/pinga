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
