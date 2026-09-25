# Provider abstraction architecture

Design: PA-01, revision 3, 2026-09-22.
Owner: architect session (Codex); implementation: DeepSeek in OpenCode.
Status: Stages 1 and 2 accepted. Stage 3 is assigned by
`docs/handoffs/PA-01-stage-3.md`, revision 1, which pins configuration, viewport,
and versioned tracking/migration policy. Stage 4 remains unassigned.

## Purpose and source of truth

Make a new harness an adapter plus registration, without teaching the TUI or
launcher its storage format, executable syntax, or session lifecycle.
The user accepted compiled-in providers, the existing literate workflow, and
separate architecture/implementation agents. Pi and Antigravity are future
consumers of the boundary, not implementations in this assignment.

This document describes the target and migration sequence. `blueprint.md`
remains the executable source of truth. As a stage lands, update its relevant
blueprint prose and chunks together. Do not describe unfinished stages as
implemented. This document has no tanglable code blocks.

## Boundaries

| Component | Owns |
| --- | --- |
| Provider adapter | Storage/API integration, native IDs, capabilities, creation/resume semantics, interpretation of process evidence |
| Provider registry | Unique instance identities, ordered enumeration, lookup, compiled-in factory registration |
| Application | Selection, refresh policy, capability-driven actions, choosing among confirmed/ambiguous attachment results |
| Launcher | Process/tmux inspection, terminal handoff, execution of structured launch requests |
| Tracking store | Versioned persisted records, locking, migration, atomic writes |
| Naming engine | Existing label suggestion behavior; independent of provider registration |

The core must eventually have no OpenCode/Codex branches. Explicit adapter
imports and factory registration are allowed at the composition boundary.
Test fixtures and documented legacy migrations may also name built-ins.
Do not substitute string comparisons for today's enum matches throughout the
app: that would preserve the coupling behind a different representation.

## Identity and registration

- `ProviderId`: an owned, validated string identifying a configured provider
  instance, distinct from its display label and position. Accept nonempty
  lowercase ASCII letters/digits plus `.`, `_`, `-`; reject whitespace and
  other characters. The default instance IDs are exactly `opencode` and `codex`.
- Provider type: a stable string factory key. Initially `opencode` and `codex`;
  later two instances may use the same type with distinct instance IDs.
- `SessionKey`: `(ProviderId, native session ID)`. Native IDs are opaque;
  labels and inherited titles never substitute for identity. Known sessions
  must have nonempty native IDs. Display labels need not be unique.
- `Session` carries its provider instance ID and native ID. Keep the existing
  optional metadata fields during migration; provider-neutral cleanup of
  those fields is not a prerequisite.
- `ProviderDescriptor` exposes instance ID, provider type, and display name.
  The completed design also exposes capabilities. UI styling stays in the UI;
  provider domain types must not depend on ratatui.
- Registry stores `Box<dyn Provider>` with deterministic iteration order and
  lookup by instance ID. Reject duplicate instance IDs; do not overwrite or
  silently choose one. Missing lookup returns absence/error, never a fallback.
- A small built-in composition function constructs the two current adapters
  from existing config and registers them in the historical order. In a later
  stage, compiled-in factories consume per-instance configuration. Dynamic
  libraries, subprocess plugin protocols, discovery/install tooling, async
  runtimes, and a generic plugin framework are out of scope.

## Capabilities and operations (after Stage 1)

Listing is the minimum provider operation. Explicit capabilities govern
rename, resume, and new-session UI affordances. Unsupported is distinct from a
failed supported operation; errors preserve useful provider context.

New-session behavior must cover both existing models:

1. Create through a provider API and obtain a known session, then launch it.
2. Launch a client that creates a session whose ID is initially unknown.

Represent the second case as a pending launch with its own identity and window
reference, not `Session { id: "" }`. Resolve it only from unambiguous evidence;
do not assume that whichever session is newest belongs to that launch. It is
acceptable to keep it explicitly unresolved when the harness supplies no proof.
Provider failures and launcher failures are separate: a server-created session
must not be hidden or silently recreated if opening its terminal fails.

Capabilities should describe whether creation can apply the requested title
and directory. OpenCode currently does not honor the requested directory on
the observed shared server; Codex currently uses the requested title only as
a window label. Do not present either as guaranteed native-session metadata.

Launch requests contain executable, argument vector, cwd, and explicit env
overrides. The launcher uses process APIs directly where possible and performs
any required shell serialization once at the tmux boundary. Never concatenate
unquoted provider/user values into executable shell text.

The provider contract returns records/evidence; it does not manipulate ratatui
state, choose windows, or write Pinga's opened-session registry.

## Attachment evidence (after Stage 1)

The launcher collects a generic snapshot of windows and process argument
vectors. Providers interpret that snapshot in their own syntax, returning
confirmed matches, ambiguous candidates, or unknown/no evidence. Argument
boundaries matter: substring presence alone is not proof of session identity.

Core policy selects a confirmed existing window, adopts an unambiguous native
match, refuses ambiguous adoption unless the user forces a fresh launch, and
otherwise follows the existing open policy. Unknown activity must not be
converted to a claim that a session is definitely closed.

Existing OpenCode newest-session heuristics must be explicitly represented as
heuristics, owned by that adapter. Stage 2 explicitly replaces heuristic-only
automatic adoption with an uncertainty warning and force-to-open option.
Codex inherited display titles are not unique; keep title ambiguity visible.
Changing Codex resume to UUIDs needs adapter verification and is not authorized
by Stage 1.

## Configuration, UI, and persistence (Stage 3 target)

Stage 3 configuration supplies an ordered list of enabled provider
instances: unique ID, type, display metadata, and adapter-specific options.
If absent, preserve the existing config fields, environment overrides, and
default OpenCode/Codex order. Validate explicit provider configuration rather
than silently replacing invalid configuration with defaults. The Stage 3 packet pins the schema and precedence: explicit provider entries
are authoritative; absent entries preserve legacy behavior.

Replace parallel provider arrays with per-provider view state. Preserve the
two-column default. A bounded viewport over an arbitrary provider list should
support additional providers without squeezing every provider onto one screen;
exact navigation/layout details belong in the UI stage task. Unsupported
actions must not look operational. Failures stay local to their provider.

Persist stable `SessionKey`s rather than view indices. A later migration must:

- Recognize the legacy `(provider_index, session_id, tmux_window_id)` tuples;
  map historical 0 to `opencode` and 1 to `codex`, never to new display order.
- Preserve disabled/unavailable/unknown provider records without indexing
  arrays or dropping data. Handle legacy empty IDs explicitly as unresolved.
- Treat a failed refresh as unavailable data, not an empty successful listing.
- Reconcile a provider only after a successful authoritative snapshot. Initial
  reconciliation must remain pending for that provider through transient errors.
- Preserve startup-only interrupted detection and cooperative multi-instance
  updates. Fail locking explicitly; never write unlocked after lock failure.
- Define a versioned format, backup/recovery, and behavior with old Pinga
  processes before deployment. Atomic rename does not make incompatible old
  and new writers safe together.

Stage 1 does not touch persisted data or permit reordering/disabling built-ins.

## Stage 3 decisions (authorized implementation target)

The Stage 3 packet is normative for implementation details. Providers use
compiled-in factories and optional ordered per-instance configuration; explicit
empty configuration is valid. The viewport shows at most two providers, one on
narrow terminals. Persisted identity never depends on display order.

Tracking uses a separate tracking-v2.json/lock with fallible locked operations,
record IDs, known/pending/opaque legacy records, and stale-update protection.
Migration takes one legacy snapshot under locks and preserves its exact bytes
before committing v2. Legacy files are never rewritten or reimported once v2
exists. Old/new binaries track independently; concurrent cross-version
convergence is unsupported. Stop old instances before deployment. The task
implements and tests migration only against temporary fixtures.

A startup interruption, once established, remains until successful resume or
authoritative removal; subsequent dead-window polls must not erase it. This
clarifies the target beyond Stage 2's transitional startup classification.
Pending launches persist and resolve only from unique confirmed identity.

## Stages and review boundaries

| Stage | Deliverable | Runtime impact |
| --- | --- | --- |
| 1 — accepted | Stable identity, object-safe provider dispatch, validated registry, built-in composition, fixture tests | Fixed UI and numeric tracking remain transitional |
| 2 — accepted | Capabilities, structured launches, explicit creation outcomes, provider-owned attachment evidence | Full integration under the Stage 2 packet; pending launches remain in memory until Stage 3 |
| 3 — assigned | Generic provider views/config, stable tracking migration, third-provider end-to-end fixture | Separate v2 file, one-time backed-up legacy snapshot; no live migration in assignment |
| 4 — not assigned | Pi / Antigravity reconnaissance and adapters | Verify each actual harness integration surface; no assumptions from its product name |

A review gate means stop after the assigned stage and report; it does not mean
ask permission before routine implementation choices within that stage.

## Required eventual evidence

Demonstrate a third fake provider without provider-specific application or
launcher branches. Cover duplicate IDs, reordered/disabled instances, identical
native IDs across providers, failed refresh retention, migration round trips,
unsupported operations, pending creation, ambiguous attachment, and launch
arguments containing spaces/quotes. Preserve existing OpenCode single-server
behavior, Codex sorting/naming, grouping, selection, mouse timing, and terminal
restoration. Stage 1's smaller required test set is in its task packet.

Message transport and cross-agent orchestration remain separate work. The
current workflow uses a repo task, an explicit user kickoff in OpenCode, and a
repo completion report. Mnemosyne indexes context; it is not the task dispatcher.
