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
