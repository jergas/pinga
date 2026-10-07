# Pinga

A terminal session manager for OpenCode, Codex and Antigravity sessions: list,
resume and rename them, open sessions in tmux windows, and bring the whole
console back after a reboot — locally or from another machine.

## What it does

- **Session console** — opencode / codex / antigravity (`agy`) columns,
  arrows/click navigation, Enter or double-click opens a session in its own
  tmux window (or the current terminal outside tmux).
- **Rename that never loses a session** — renames apply server-side (or to
  the codex thread DB), update the tmux window label, and keep the old name as
  an alias so a client still running under its former title stays matched.
- **Auto-track** — sessions you open by hand are recorded when observed
  running, so they survive reboots like any tracked session.
- **Project browser** (`b`) — launch Yazi rooted in a directory with
  Markdown/code viewers (needs Yazi, Glow, bat, less).
- **Reboot bring-up** — after a power loss or a reboot, `pinga` asks the
  systemd restore service for the tmux-resurrect replay, recreates the session
  and console, and restarts every tracked session **in the window it was in**
  before the interruption.
- **Thin client** — from another machine (e.g. a Mac), pinga manages a
  per-host ssh key and connects into the remote console: no manual `ssh`.

## Install

Requires Rust/Cargo, Python 3 (for the literate tangle), and `tmux` on the
host that runs the console. On Linux with systemd, the boot units are deployed
and enabled:

```sh
make install
```

On machines without systemd (e.g. macOS) only the binary is installed; the
units stay in `deploy/`.

## Command line

| Command | What it does |
|---------|--------------|
| `pinga` | the console; outside tmux, brings the session up and attaches |
| `pinga up` | headless bring-up (used by the boot unit) |
| `pinga remote list` | configured remotes + reachability probe |
| `pinga remote add <name> <host> [user]` | register a remote host |
| `pinga remote keygen <name>` | generate the per-host ed25519 key (only if missing) |
| `pinga remote install-key <name>` | install the public key (`ssh-copy-id`, one password prompt) |
| `pinga remote test <name>` | `BatchMode` reachability check |
| `pinga remote connect <name>` | ssh to the remote and run its own `pinga` — the remote console |

### Thin client quickstart (e.g. Mac → eris)

```sh
pinga remote add eris 100.115.173.85 edgar
pinga remote install-key eris     # one password prompt
pinga remote connect eris         # you are now in the eris console
```

Remotes live in `~/.config/pinga/remotes.toml` (pinga-owned, hand-editable).

## Configuration

`~/.config/pinga/config.toml` — `tmux_session` (the single session pinga owns,
default `main`), naming engines, and an explicit `[[providers]]` list
(opencode, codex, and opt-in antigravity). Without a provider list, the legacy
opencode + codex defaults apply. `PINGA_CONFIG` points elsewhere.

## Reboot survival (the drill)

After a reboot or a killed tmux server, just run `pinga`. The boot chain is:

1. `opencode.service` — the shared opencode server (sessions persist on disk).
2. `pinga-tmux-restore.service` — asks tmux-resurrect to replay the last saved
   layout (`RemainAfterExit` keeps the replayed server alive).
3. `pinga-up.service` — `pinga up`: ensures the session + console window,
   then restarts tracked sessions in their pre-reboot windows (by name/index)
   and reports exactly what happened.

Sessions not running are reported, never silently launched — reopen them from
the console's list. The console is always the session's first window.

## Development

[blueprint.md](blueprint.md) is both the architectural document and the
literate source; `src/` is derived. Edit the blueprint, then:

```sh
make tangle
make check test lint
```

Feature history: [HISTORY.md](HISTORY.md). Priorities: [roadmap.md](roadmap.md).

## License

AGPLv3-or-later — see [LICENSE](LICENSE).