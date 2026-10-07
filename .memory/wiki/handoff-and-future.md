# Pinga — State of the Project, Future Directions & Handoff

Date: 2026-09-22
Author: DeepSeek (opencode agent)

This is the living handoff for anyone (human or agent) picking up **pinga** —
a literate-built TUI console for managing **opencode** and **codex** sessions.
Read `log.md` and `gotchas.md` for the blow-by-blow; this is the digest.

---

## 1. What pinga is

A full-TTY, ratatui-based console that lists opencode + codex sessions in two
side-by-side columns and lets you open, rename, suggest names, create new
sessions, and switch between them. The **architectural blueprint and literal
source of truth is `blueprint.md`**; `src/` is derived by `make tangle`.

Build / verify: `make tangle && make check && make lint && make test && make install`
(install drops `pinga` into `~/.local/bin` and deploys/enables the tmux-save timer).

There is exactly ONE persistent opencode server (systemd user unit on
`http://127.0.0.1:4096`) and one codex app-server daemon. Every client attaches
to the shared opencode server — never spawn a second bare `opencode`.

---

## 2. Summary of everything done (commit history)

- **`5858d62`** — Initial literate scaffold: blueprint → tangle, Makefile gates,
  config, model, providers (opencode over HTTP, codex from rollout files),
  naming engine, two-column TUI, inline rename.
- **`fb93a60`** — D8: click-to-open (single-click selects, quick second click
  opens), one-window-per-session enforcement in tmux (window tracking +
  argv-marker adoption + opencode bare-attach fallback), sticky status line,
  header/status width-fitting (unicode-width).
- **`0c9e325`** — `+ new session` row per column (opencode: `POST /session` then
  attach; codex: launch `cd <dir> && codex`); interrupted-session tracking via a
  persisted state file; force a full repaint after a bare-terminal suspend;
  `make install`/`uninstall`.
- **`e81cef7`** — the big batch:
  - **Cooperative concurrency** — `opened.json` is a shared registry guarded by
    an exclusive `flock` (fs2) with atomic tmp+rename writes; every instance
    reloads it each refresh and mutates via `update_opened`, so several pinga
    instances converge ("state follows me"). Verified with two instances.
  - **Grouped lists** — columns show subheaders `+ new session` /
    `interrupted` / `running` / `closed`. `running` is detected both from pinga's
    tracked windows and a one-pass `scan_attached()` argv walk (catches
    hand-opened sessions).
  - **Selection off-by-one fix** — `sel` is consistently **selectable-indexed**
    (headers excluded) across navigation, `focused_session`, mouse clicks and
    refresh. This fixed a nasty bug where rename/`i`/click hit a *different*
    row than the one highlighted whenever a subheader was present.
  - **Two-line / bottom display** — two-line rows by default (title + age / dim
    id); `d` toggles to "bottom" mode (selected id on the status line); config
    `list_detail`.
  - **`i` info modal** — shows every known field (id, session id, thread,
    slug, directory, model, agent).
  - **`g` manual refresh**, **modal forms** (rename + new-session are centred
    dialogs by default; config `forms = "modal" | "inline"`).
  - **codex names** — codex 0.155 keeps thread names in the app-server state DB
    `~/.codex/state_*.sqlite` (`threads` table), NOT the old
    `session_index.jsonl`. pinga now reads that via `rusqlite` (bundled).
    Display order: `name` → `title` → **inherited parent name** (sub-agent
    threads inherit their spawn-parent's name via `thread_spawn_edges`) → id.
    Fixed a **truncated-UUID parsing bug** in `rollout_title_id` (was returning
    only the last 12 chars of the thread id, so ids never matched the DB).
  - **Rename no longer reshuffles** — the codex rename only writes
    `threads.name` and does NOT bump `updated_at_ms`, so renames never reorder
    the recency-sorted list (previously every rename jumped the session to the
    top, which — combined with identical inherited names — looked like the wrong
    session was renamed).
  - **Mouse defaults ON** when usable — in tmux only if tmux mouse mode is on
    (it is: `set -g mouse on`); standalone always on. `m` toggles.
  - **Installer** vendors `deploy/pinga-tmux-save.{service,timer,script}` and
    enables the timer (reboot survival).

Also done earlier this session (outside commits):
- **tmux reboot survival** — added systemd user service+timer `pinga-tmux-save`
  (every 10 min) calling tmux-resurrect's `save.sh` via `tmux run-shell`. Root
  cause of the earlier power-loss window loss: **no save file had ever been
  written** (continuum's first save waits 15 min of server uptime). The backend
  servers (opencode :4096, codex daemon) survived reboot via `enable-linger`.
- Investigated the **codex app-server protocol** (`thread/list` JSON-RPC over the
  unix socket) — it works but is fragile to talk to; reading `state_*.sqlite`
  directly proved more reliable.

---

## 3. Future directions

1. **Mouse over macOS+SSH+tmux** — pinga now defaults mouse on, but mouse still
   "kinda works" for the user on a macOS laptop over SSH in tmux. Suspect the
   terminal/SSH client isn't forwarding mouse events; tmux.conf already has
   `set -g mouse on`. Investigate terminal-side (iTerm2/Terminal.app mouse
   reporting) before blaming pinga.
2. **Proper codex manual test** — codex open/rename on a real session was never
   fully exercised by the user (they were "too tired" / cautious about their
   important session). Worth a dedicated test now that targeting is fixed.
3. **codex app-server protocol as a future source** — `thread/list` (and
   `thread/name/set`) over the daemon socket would be the *official* interface
   instead of reading `state_*.sqlite` directly. Fragile but more future-proof
   if codex changes its DB layout. `generate-json-schema` gives the full protocol
   (`thread/list`, `thread/read`, `thread/name/set`, …).
4. **Order-by-session-id option** — the user suggested it to stop reorder-on-
   rename; that was superseded by fixing the reorder at the root (don't bump
   `updated_at_ms`). Offer a config switch if the user still wants a strict,
   never-reorders order (sacrificing recency).
5. **"pinga name" registry** — the user's stated preference was "pinga name,
   thread name, thread title". Currently pinga-set names and codex thread names
   share the same `name` field. Could maintain a pinga-side name registry
   separate from codex's, layered on top.
6. **codex session_id** — codex distinguishes thread `id` from `session_id`
   (a session groups several threads/sub-agents). Only partially surfaced (in
   the `i` modal); could be shown in the list when relevant.

## 4. Ideas pinga could grow into

- **Status/dashboard bar** — opencode's `/session` API returns `cost`, `tokens`
  (input/output/cache) and `model`. Show per-session token/cost and a running
  total.
- **Session detail at a glance** — model, agent, directory, age already in the
  model; could add a persistent footer/metadata pane instead of only the `i` modal.
- **Filtering / search** — filter a column by text; show only running/closed.
- **Pinning / favourites** — pin important sessions to the top.
- **Activity alerts** — watch SSE `/event` for `message.part.*` and flash when a
  session completes a turn (server-side activity marker; not attachment).
- **Keybinding configurability** — move hardcoded keys behind a config map.
- **Multi-server / multi-machine** — the ADR-0002 already plans eris + a laptop
  over Tailscale; pinga could switch between server bases.
- **Read-only inspect mode** vs attach (useful before committing to opening).
- **History/export** — write a transcript of sessions to a file.
- **Cooperative multi-instance dashboards** — one "hub" pinga and a read-only
  "monitor" pinga sharing the same state (already partly possible).

## 5. Famous last words to future incarnations

- **Edit `blueprint.md`, never `src/`.** `src/` is regenerated by `make tangle`.
  If you edit `src/` your changes vanish on the next tangle.
- **Run the gates before committing:** `make tangle && make check && make lint && make test`. And **never commit without the user explicitly asking.**
- **One opencode server per session id.** The systemd server on `:4096` is the
  only server; attach with `opencode attach http://127.0.0.1:4096 -s <id>`.
  Never read `opencode.db` while attached. A second bare `opencode` = split-brain.
- **codex names live in `~/.codex/state_*.sqlite` (`threads`), not
  `session_index.jsonl`.** A thread's id is the FULL trailing UUID in the rollout
  filename (8-4-4-4-12), not the last 12 hex chars — that mistake cost hours.
- **`opened.json` is cooperative.** Mutate it only through `update_opened`
  (flock + atomic rename). Never `std::fs::write` it directly — concurrent pinga
  instances will clobber each other.
- **Keep `sel` selectable-indexed** (New + sessions, headers excluded). Mixing it
  with the visual-row index caused the off-by-one "renamed the wrong session"
  bug. Any new feature that adds non-selectable rows must preserve this.
- **Renaming must not bump `updated_at_ms`** for codex, or the recency sort
  reshuffles the list and same-named sessions become untrackable.
- **Respect the two run modes**: tmux (`in_tmux()` → create/select windows) vs
  bare terminal (`suspend_for` → take the terminal, come back). Most bugs in the
  early UI were from one mode working and the other not.
- **The user is cautious** and wants to verify before you commit; they work over a
  macOS laptop → SSH → tmux on eris. Pause for verification at runtime points.
- **ai-memory is NOT session-aware** — always pass `workspace` + `project`
  explicitly when using it.
- **Useful memory sources**: `.memory/wiki/{log,gotchas,failed_approaches}.md`
  and the ADRs. The tangle tool is `tools/tangle.py`.

---

_Last modified 2026-09-22. Update this file as the project evolves — it is the
first thing a future incarnation should read._
### Addendum (2026-10-03): tmux auto-restore
tmux-resurrect/continuum **auto-restore on server start does not fire** here
(tpm loads no plugins on a fresh server). Reboot survival relies on a systemd
user service **`pinga-tmux-restore`** (deploy/; runs once at boot, starts a
tmux server if none, runs resurrect `restore.sh` from `~/.tmux/resurrect/last`)
plus the save timer `pinga-tmux-save` (every 10 min). `make install` deploys
and enables both. Do not assume continuum auto-restores.
