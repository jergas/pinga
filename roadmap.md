# pinga — roadmap

Updated 2026-10-04. The session console for opencode & codex, with bring-up and
reboot survival (R12). This document governs pinga's development priorities.
Deliver one bounded slice at a time; complete the initial milestone before
moving to the next priority. Task notes and evidence live in `docs/`.

## Changelog policy

Fully implemented features get a one-liner entry in [HISTORY.md](HISTORY.md),
with a date. Old entries are generally not touched, except for the very odd
correction when an entry was somehow mistaken. Task-level archival (verbatim
task text with evidence) remains available in `docs/` when needed.

## 1. Thin client: remote connection manager (multimachine)

The user's eris-hosted console should be reachable from a mac (and any other
machine) through pinga itself, instead of a manual `ssh`.

Initial milestone: a configured remote host (`eris`) whose public key pinga
generated and installed, tested with a `BatchMode` probe, and which
`pinga remote connect` attaches to by running the remote's own `pinga` (the
remote's bring-up + console) over `ssh -t`. Accepted 2026-10-04 (validated
mac → eris).

Steps: `[[remotes]]` config (name/host/user/port/key) in a pinga-owned file →
`pinga remote add|list` → per-host ed25519 key generation (`~/.ssh/pinga-<name>`,
created only if missing) → key installation (`ssh-copy-id`, interactive on first
use) → `pinga remote test` (BatchMode probe) → `pinga remote connect` (argv-
constructed `ssh -t`, never shell-interpolated). SSH options are explicit argv,
never a shell fragment. First remote release ships this.

## 2. Installer and GitHub

Publish the repository and make installation a single command.

Steps: push to a GitHub remote; README/AGENTS polish; an installer script
(build the release, install the binary, deploy the systemd units and enable
them) suitable for a fresh machine and for the mac; document the boot chain and
the drill (`kill tmux server` → `pinga`). A release tag per milestone once the
installer is stable.

## 3. codex server-side rename spike

The codex 0.160 app-server protocol has `ThreadSetName{name,threadId}` and a
`ThreadNameUpdatedNotification` (running clients would update), reachable via
`codex app-server proxy`. The remaining unknown is the wire framing (newline
JSON got no echo). Spike: discover the framing and handshake, then make the
codex adapter's rename talk to the running server first, falling back to the
direct SQLite write. Until then, records keep rename aliases so pinga is never
blindsided by its own renames.

## 4. Thick-lite: remote session listing

After the thin client: the mac shows eris's sessions locally — an ssh tunnel to
eris's :4096 for the opencode listing, and a small remote helper (ssh-executed)
for codex. Read-only listing first; opening stays `remote connect`.

## 5. Boot-path hardening and telemetry

The cold-drill story works (resurrect handshake, `RemainAfterExit`, in-place
session restore, console-first window), but the console-death investigation
showed how little visibility a pane process has. Keep the console-exit log and
phase tracing; add an optional `pinga doctor` that reports the boot chain state
(units, resurrect status file, socket, session/window layout) in one command —
useful before and after a reboot.

## 6. Documentation and website

Document the architecture (blueprint already does), the drill, and the boot
chain in the README; consider a project page only after the GitHub publish.