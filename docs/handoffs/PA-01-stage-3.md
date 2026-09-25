# PA-01 Stage 3 — configurable instances, generic views, stable tracking

Revision 1, 2026-09-22. READY. Implementer: same DeepSeek/OpenCode session,
High reasoning recommended. Architect: Codex. Stages 1–2 accepted.

Read AGENTS.md, memory index/gotchas/failed approaches, architecture revision 3,
and Stage 2 acceptance. Implement through blueprint prose and named chunks;
tangled sources are outputs. Preserve existing uncommitted work. One writer.
Complete the whole batch before returning; routine factoring is delegated.
No Pi/Antigravity, live provider mutation, installation, deployment or commits.

## Outcome and boundaries

A third provider must require an adapter and compiled-in factory registration,
not application/launcher branches. Support zero, one, two, or more configured
instances, including multiple instances of a type. Core UI, launch orchestration
and tracking use ProviderId/SessionKey; positions only address visible lists.
Keep accepted Stage 2 evidence, capability and failure semantics. New modules
for tracking/configuration are permitted and must be tangled from blueprint.

Implement in this order internally: configuration/factories, versioned store,
generic app/views, end-to-end fixtures. These are implementation checkpoints,
not requests for further permission. Stop only at the final review boundary.

## 1. Configuration and factory contract

Optional `providers` is an ordered TOML array of tables. Each entry has required
`id` and `type`, optional `label`, `enabled` (default true), and an `options`
table. IDs use existing ProviderId validation and must be unique across ALL
entries, including disabled ones. Explicit `providers = []` means no providers.

Example (documentation example, not a live config change):

    [[providers]]
    id = "work"
    type = "opencode"
    label = "Work"
    [providers.options]
    url = "http://127.0.0.1:4096"

    [[providers]]
    id = "local"
    type = "codex"
    [providers.options]
    home = "/example/codex-home"

If providers is absent, retain legacy defaults, fields and environment
overrides: opencode then codex, with their historical IDs. Explicit providers
are authoritative: legacy opencode_url/codex_home and PINGA_OPENCODE_URL do NOT
override their options. Existing naming-engine environment overrides still
apply. Explicit opencode options.url is required; explicit codex options.home
is required and absolute. No shell expansion. This avoids accidental routing
to a default server/home. Reject unknown options. Configured labels are owned
strings; absent labels use adapter defaults. Reject blank labels.

Use a small compiled-in type-key → factory registry. Adapter-specific options
are decoded/validated at that boundary; core Config stores a generic options
table. Unknown types/options and malformed entries are errors even if disabled
(so typos do not become latent). Disabled entries are validated but never
instantiated or polled. Do not silently fall back to defaults on invalid TOML,
unreadable existing files, or a missing explicitly requested PINGA_CONFIG file.
An absent default config file still uses defaults. Validate/build before raw
terminal mode. Report context without dumping configuration secrets.

IDs identify sources permanently: document that changing a server/home to a
different source requires a new ID. Renaming a label or reordering is safe.

## 2. Versioned tracking and migration — pinned policy

Extract a fallible store with an injectable directory. Use
`~/.local/state/pinga/tracking-v2.json` and `tracking-v2.lock`, not opened.json.
JSON envelope has `version: 2`, a monotonically allocated `next_id`, and tagged
records. Allocate stable unique record IDs under the shared lock, checked for
overflow. Known records carry validated SessionKey, window ID and lifecycle
state; pending records carry ProviderId, window ID, label and their own record
ID, with no fake native session ID. Opaque legacy records preserve otherwise
unmappable tuples. Pin the exact serialized schema in blueprint and fixtures.

All writes lock, reread, mutate and atomically replace under the lock. Return
errors for lock/read/parse/write/rename failures; never proceed unlocked or
convert corruption into an empty registry. Use a same-directory temp file,
flush/sync before rename, and handle durability errors honestly. Preserve the
last good in-memory view when reads fail. Unsupported versions/record variants
must fail without rewriting the file. Never hold the lock during external
provider/process calls.

When v2 does not exist, acquire v2 lock then legacy opened.lock, take one legacy
snapshot, validate it, and save its exact original bytes as
`opened-v1-migration-backup.json` before committing v2. Never overwrite an
existing conflicting backup. Crash/retry with an identical backup is safe.
Legacy tuple 0 always maps to opencode and 1 to codex, irrespective of current
config/order. Known indices with empty native IDs become unresolved pending
records; unknown indices remain opaque, including empty IDs. Preserve every
legacy tuple's information. Missing legacy file means an empty initial v2;
malformed legacy data aborts migration without replacing either data file.
Do not remap to custom IDs such as work/local.

Once v2 exists, NEVER reimport or write legacy opened.json. Old and new Pinga
versions track independently; simultaneous cross-version convergence is NOT
supported. Document that users should stop old instances before upgrading.
The separate file protects against incompatible old writers, but later legacy
updates are intentionally not merged. Recovery/rollback documentation must
explain backup preservation and that reverting a binary does not import v2
changes. Do not perform a live migration in this assignment.

Cooperative v2 instances must not overwrite one another: reconciliation applies
conditional changes only to the exact observed record ID/window/state. New or
replaced records added since inspection survive stale results. All instances
reload shared state each refresh. Unknown/disabled providers and legacy opaque
records survive untouched. Concurrent add/update/delete tests use isolated dirs.

## 3. Lifecycle integration

Use stable provider IDs in deferred plans, pending launches and persisted
records. No positional disk identity. Tracking failures are visible: if a
window was launched but recording failed, report that explicitly without
claiming a tracked success or automatically launching again.

Keep startup-only interruption classification tied to exact initial records
through failed lists/inspection. Intentional closes of records opened later
must not become interrupted. Once classified interrupted, retain that state
across subsequent refreshes/restarts until successfully resumed or the known
session disappears from a successful authoritative listing. This explicitly
fixes the transitional behavior where a second dead-window poll drops the
startup interruption. Do not grant startup eligibility to later/replacement
records. Unknown evidence never means closed. Local unobserved creations
retain Stage 2's merge-until-first-observed behavior.

Persist pending launches after successful window creation, keep them visible
after restart, and resolve only when successful listing + adapter evidence
uniquely prove one SessionKey in the exact pending window. Multiple/heuristic
matches remain pending. Resolution is one atomic record transition, never a
newest-session guess. Confirmed window death may remove an unresolved pending
record; failed inspection retains it. Unavailable providers are not reconciled.

## 4. Generic application and viewport

Replace two-provider fields/parallel arrays with per-provider view state:
descriptor/ID, snapshot, refresh status/error, selection, scrolling/group state.
Validate adapter listing identities and nonempty native IDs before accepting a
snapshot; malformed data fails only that provider's refresh and preserves its
last good state. Preserve selection by SessionKey when lists reorder, with a
bounded fallback when selected rows disappear. Errors remain provider-local.

Show at most two equal columns when body width is at least 80 cells; otherwise
show one. Existing two-provider wide-screen layout remains recognizable.
Left/right and Tab navigate the full enabled provider sequence (wrap at ends),
scrolling the provider viewport to keep focus visible. Mouse hit testing maps
visible rectangles to actual provider IDs; deferred actions retain their owner
when focus moves. Test narrow and zero-size areas without underflow/panics.
With zero enabled providers show a useful empty state and allow quit; provider
actions are harmless. Show provider position/count and configured labels.

Preserve grouping, row details, mouse timing, new-session forms and capability
guards generically. Move provider-name-specific presentation to generic styles
or view metadata; no type-name/instance-name branches in core action/rendering
logic. Keep domain types free of ratatui types. Do not add a styling framework.

## 5. Acceptance evidence and delivery

Retain prior regression tests; write sequence/failure tests before fixes. Tests
must exercise real orchestration, not merely construct types or fake the exact
result being asserted. All storage fixtures use temporary directories; no
real user config/state/home or network. Required coverage:

- Config absent vs empty; defaults/env precedence; malformed/duplicate/disabled
  entries; two instances of one type with distinct options; three fake factories.
- App with 0/1/2/3 providers: refresh, focus/viewport, mouse, forms/capabilities,
  deferred actions after focus change; ratatui TestBackend render assertions.
- Identical native IDs across providers, reorder/disable/re-enable, per-provider
  failures, selection retention, no cross-provider action or tracking updates.
- Legacy migration including unknown indices/empty IDs; exact backup; idempotent
  restart; malformed legacy/v2, unsupported version, failed IO/lock; old file
  remains untouched. Failures must prove original data survives.
- Two independent store instances with interleaved/concurrent writes and stale
  reconciliation; do not assert concurrency safety from sequential CRUD alone.
- Pending launch → persisted → restarted → ambiguous/failed evidence retained
  → unique confirmation resolved; interrupted state stable across several polls;
  later intentional close and replacement do not inherit startup eligibility.
- Third fake provider completes list/create/resume/rename/tracking workflow via
  generic core paths, plus unsupported-operation variant. No production fake.

Run make tangle/check/test/lint and git diff --check. Verify generated source
matches blueprint and a second tangle changes no outputs. Inspect remaining
OpenCode/Codex references: only adapters, composition, legacy migration, tests,
and explanatory prose may depend on provider names. Update blueprint examples
and operational docs, memory log, and PA-01-stage-3-report.md with actual test
names, command outcomes, affected chunks, and limitations. No live smoke test
is claimed. Return once the full batch passes for architect review.
