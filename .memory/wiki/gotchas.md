# Environment & Library Gotchas

## sudoers entries with arguments match the exact full command line (2026-09-16)
On sudo 1.9.17p2, `edgar ALL=(root) NOPASSWD: /usr/bin/loginctl enable-linger`
matched only `sudo loginctl enable-linger`. An extra trailing argument
(`sudo loginctl enable-linger edgar`) still demanded a password. sudoers does
NOT tolerate trailing args on an entry that itself carries arguments — either
append a wildcard (`/usr/bin/loginctl enable-linger *`) or omit the argument
when the verb defaults to the invoking user.

## tpm's install_plugins cloned nothing from a non-interactive shell (2026-09-16)
`~/.tmux/plugins/tpm/bin/install_plugins` produced no plugins when run without
a tmux server. Fix: `git clone` tmux-resurrect and tmux-continuum directly into
`~/.tmux/plugins/` (config loads them via tpm from there).

## codex app-server daemon requires the official standalone install (2026-09-16)
`codex app-server daemon bootstrap|start` bails with "managed standalone Codex
install not found" unless `~/.codex/packages/standalone/current/codex` exists.
A mise-shim codex (`~/.local/bin/codex` → `mise x codex`) is refused; the
daemon must launch from that fixed path. Fix: official installer
(`curl -fsSL https://chatgpt.com/codex/install.sh | sh`) installs the
standalone binary (self-updating; replaces the PATH shim).

## codex: standalone is now the ONLY codex on eris (2026-09-17)
There were three codex binaries; mise and the pacman package shadowed the
standalone in non-login (tmux) shells. Consolidated to the standalone 0.154.0:
- removed the mise tool: deleted `codex = "latest"` from
  `~/.config/mise/config.toml`, `mise uninstall codex`, removed the stale
  `~/.local/share/mise/shims/codex`;
- removed the arch package: `sudo pacman -R openai-codex` (0.153.4, 293 MiB,
  Required By: none).
Result: `command -v codex` → `~/.local/bin/codex` →
`~/.codex/packages/standalone/current/` in login AND tmux/plain shells alike.
Self-updates (`codex update`) refresh the one standalone copy.

## opencode does not hot-reload config (2026-09-16)
Restart any running opencode sessions after MCP server, plugin, or AGENTS.md
changes — hooks and MCP registration only load on start.

## Do not nest terminal multiplexers
Running tmux inside zellij (or vice versa) breaks keybindings and screen
redraws. Pick one multiplexer per session.

## A "duplicated" opencode conversation = two servers on one session id (2026-09-16)
Resuming session id `ses_...` with a SECOND bare `opencode` (spawns its own
server) while the first TUI still runs = split-brain: the id is shared in
storage but the live turns live in each server's memory. One screen froze, the
other raced ahead — looks like the session was cloned. Fix: exactly ONE server
per session id (the systemd `opencode serve` on :4096); every client attaches to
it (`opencode attach http://127.0.0.1:4096 -s <id>`); close any stray bare
`opencode`. Verify with `pgrep -af opencode`.

## tmux multi-client: same session/window open in several terminals
Multiple clients can attach to one session, including the SAME window — it is
one pane process, so all screens stay synced. Only input isn't duplicated: type
in one client at a time per pane (concurrent keystrokes interleave). Different
terminals may show different windows of the same session.
opencode rename has NO documented v2 route in 1.18.29 — the six candidate forms
(POST/PATCH/PUT × /session/<id> and /session/<id>/rename) all return the SPA
HTML with HTTP 200 when a form is wrong (silent no-op). pinga's rename probes
all six and re-reads the session to confirm the title actually changed (rule in
blueprint §16.3). External rename for codex = append {"id","thread_name",
"updated_at"} to ~/.codex/session_index.jsonl (codex's own contract; newest
append wins).
