# HISTORY.md

Every fully implemented feature gets a one-liner entry here, with a date.
Old entries are generally not touched, except for the very odd correction if
an entry was somehow mistaken. See [roadmap.md](roadmap.md) for the policy and
pending work; the [blueprint](blueprint.md) is the architecture and source of
truth.

## 2026-09-17

- Initial console: literate blueprint with tangle toolchain, opencode/codex
  session lists, naming engine, tmux window handoff.

## 2026-09-18

- Click-to-open sessions with one-window-per-session enforcement (D8).

## 2026-09-19

- "+ new session" row with name+cwd forms, interrupted-session tracking, and
  `make install` (real `pinga` command, tmux reboot-survival timer).

## 2026-09-20

- Cooperative state file, grouped session lists, modal forms, two-line/bottom
  detail, `g`/`d`/`i` keys, codex thread names from SQLite.

## 2026-09-22

- Provider abstraction: stable IDs, registry, capabilities, structured launch
  plans, evidence-based adoption (PA-01 stages 1–3).

## 2026-09-23

- Optional antigravity (agy) provider adapter, compiled-in, opt-in.

## 2026-09-24

- External project browser (`b`): Yazi rooted in the chosen directory with
  markdown/code viewers and full tool isolation (PB-01).

## 2026-09-26

- Browser contrast polish: private Yazi theme pinning (PB-02).

## 2026-10-03

- Reboot bring-up (R12): resurrect handshake, in-place session restore with
  window identity, one console per session, boot units.

## 2026-10-04

- Cold-drill fixes: `RemainAfterExit` (systemd was killing the restore
  server), `restart`-based resurrect request, console-first window, move-
  window no-swap park, renumber quirk defeat, console exit telemetry.
- Rename resilience: alias matching keeps renamed sessions running; tmux
  window labels follow renames; auto-track keeps hand-opened sessions tracked.
- Thin client: remote connection manager — per-host ssh keys, key
  installation, BatchMode probes, and `pinga remote connect` into a remote
  console (validated mac → eris).