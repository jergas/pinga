# ADR 0002: Persistent Cross-Machine Agent Sessions on eris

Status: Accepted
Date: 2026-09-16

## Context

Work happens on two machines: **eris** (Omarchy/Arch desktop) and a **laptop**
that reaches it over Tailscale. Requirements:

- carry an opencode session between a terminal on eris and an SSH session from
  the laptop;
- detach a session from one terminal and reattach it in another;
- survive reboots (and ideally boot without user login);
- switch between several opencode and codex sessions within one terminal
  without closing any of them.

## Decision

Three layers, each solving one concern:

### 1. Terminal multiplexers (screen + cross-agent switching)

- **tmux 3.7c** (already installed) is the dependable backbone: SSH-proof,
  scriptable, works on any TERM.
- **zellij 0.45.1** (installed from `extra`) is kept as a modern alternative —
  both are full-TTY TUIs, no GUI.
- Sessions are processes on eris; attach from eris itself or from the laptop
  (`ssh edgar@eris` then `tmux attach -t <name>`). One tmux window per agent
  (opencode, codex, shells) gives instant switching (Ctrl-b n/p) without
  restarting anything.
- **tmux-resurrect + tmux-continuum** (managed by tpm) auto-save layouts and
  restore them after reboot. Continuum is the automation layer over resurrect;
  they are complementary — only resurrect is needed for manual save/restore,
  continuum makes it automatic at tmux start.
- Do not nest tmux inside zellij (or vice versa); pick one per session.

### 2. Persistent backend servers (process-level reboot survival)

Run the agent backends as `systemd --user` services enabled in
`default.target`, plus `loginctl enable-linger edgar` so they start at boot
even with no login session:

- **opencode**: `opencode serve` as
  `~/.config/systemd/user/opencode.service` — Type=simple, Restart=on-failure,
  listens on `http://127.0.0.1:4096`. The TUI reconnects with `opencode attach`
  (or `opencode attach http://127.0.0.1:4096`). No extra install: the server is
  part of the opencode binary.
- **codex**: `codex app-server daemon` as
  `~/.config/systemd/user/codex-app-server.service` — Type=oneshot +
  RemainAfterExit wrapping `daemon start` (idempotent), because codex manages
  its daemon with a pid backend, not systemd. Requires the **official
  standalone install** (see gotchas).

### 3. sudoers scoping for the agent

- `/etc/sudoers.d/edgar-opencode` — `NOPASSWD: /usr/bin/systemctl,
  /usr/bin/pacman, /usr/bin/ss, /usr/bin/journalctl`.
- `/etc/sudoers.d/edgar-opencode-loginctl` — `NOPASSWD:
  /usr/bin/loginctl enable-linger, /usr/bin/loginctl disable-linger`.
- All `/etc/sudoers.d/` files union additively; permissions are the union of
  every line. One file per independently-revocable permission group (not per
  command). Scope verbs by writing them with the exact arguments.

## Consequences

- opencode/codex session state survives reboots; tmux screens are restored by
  resurrect+continuum.
- Without the codex daemon, codex continuity after reboot would be limited to
  `~/.codex/sessions` + `codex resume` (conversation survives, live TUI does
  not).
- sudoers entries that carry arguments match the full command line exactly
  (see gotchas) — trailing args must be added via wildcard or omitted.
- opencode requires a restart after MCP/plugin/AGENTS.md changes; hooks and
  MCP registration only load at start.

## Follow-up (2026-09-16): divergence incident + multi-client tmux

- Fired a second, bare `opencode` against the same session id while the original
  TUI was still running. Session id is a shared storage key, but the live turn
  lives in the server process → split-brain: the original terminal froze and a
  different continuation appeared there while the tmux client raced ahead.
  Resolution: kept the systemd backend on :4096 + the tmux (laptop) client,
  exited the stray TUI.
- Rule: exactly ONE opencode server per session id (the systemd one). Every
  client attaches to `http://127.0.0.1:4096`.
- tmux multi-client confirmed: the same session and the same window render in
  several terminals at once (one pane process, screens fully synced). Type in
  one client at a time per pane.
## Follow-up (2026-09-19): resurrect save gap + the real survival story

- The "tmux screens are restored by resurrect+continuum" claim was **never
  backed by a save file** — after the 2026-09-18 power failure, `~/.tmux/resurrect/`
  was empty, so no layout came back. Continuum only saves after a server has
  been up > its 15-min interval; a quick power loss kills the server first.
- Added a **systemd user timer** (`pinga-tmux-save.service` + `.timer`,
  OnCalendar=`*:0/10`) that snapshots the whole tmux server every 10 min via
  `tmux run-shell -t <any> ~/.tmux/plugins/tmux-resurrect/scripts/save.sh`.
  This is independent of tmux uptime. A save file now exists
  (`~/.tmux/resurrect/last`).
- Backends that DID survive the reboot (opencode on :4096, codex daemon, both
  systemd units + `enable-linger`) are the reliable half; tmux layout survival
  is now handled by the timer + resurrect restore on next tmux start.
- pinga's "+ new session" (opencode: POST /session; codex: `cd <dir> && codex`)
  and interrupted-session tracking (state file + startup-only flag) are wired
  into this persistence story.
