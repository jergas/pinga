# PA-01 Stage 2 implementation report

Task revision: 1. Status: CORRECTIONS APPLIED — ready for architect review
(R1–R5 per `PA-01-stage-2-review.md`, A–C per `PA-01-stage-2-review-2.md`,
D/E per `PA-01-stage-2-review-3.md`, endpoint-validation per
`PA-01-stage-2-review-4.md`).

## Corrections applied (fourth review — endpoint-validation invariant)

The endpoint parser is now a documented, bounded ASCII HTTP(S) subset that
returns Unknown for every unsupported form, so malformed evidence can never
establish "positively different" and erase tracking:

- **Scheme** must be exactly `http`/`https` (case-insensitive).
- **Non-ASCII, whitespace/control bytes, backslashes, userinfo, fragments, and
  bracketed/unbracketed IPv6** authorities are rejected as Unknown (never
  panicking on a multibyte host).
- **Host** must be a nonempty ASCII DNS/IPv4-shaped name (dot-separated nonempty
  labels of ASCII alphanumerics + internal hyphens; no leading/trailing hyphens,
  no other punctuation). All-numeric dotted hosts are accepted only as valid
  4-octet IPv4 (`127.0.0.999`, `999.1.1.1`, `1.2.3` are Unknown).
- **Port** is exactly one `:` followed by nonempty decimal digits parsing into a
  `u16` (`banana`, empty, `-1`, `99999` are Unknown).
- **Path/query** bytes and case are preserved; only the agreed trailing path
  slashes are normalized; malformed percent escapes are rejected (never decoded).
- Only after BOTH endpoints validate may comparison establish `Different`
  (the `localhost`↔`127.0.0.1` equivalence is preserved).
- Adapter tests (table-driven `endpoint_validation_subset_table` covering every
  rule plus valid equal/different, `malformed_endpoint_is_ambiguous_in_both_attach_shapes`
  including `http://bad host:4096`, `http://localhost:99999`, `1http://…`,
  `unicode_authority_does_not_panic_and_valid_different_server_never_matches`),
  policy test (`endpoint_rel` tri-state), and existing path/query/trailing-slash
  regressions.
- **Integrated test:** `malformed_endpoint_evidence_routes_through_adapter_into_reconciliation`
  registers the REAL `OpencodeProvider` in the app, feeds a live window whose argv
  is `opencode attach not-a-url -s ses_x`, and runs `compute_interrupted` with a
  successful provider list — the tracked record and its startup eligibility are
  both preserved (adapter output reaches the app; not a precomputed fake).
- Removed the unused-`mut` test warnings introduced by the list-fixture change.

## Corrections applied (D/E, third review)

### D — endpoint parsing is fallible without proving absence
- `endpoint_parts` is now genuinely bounded and non-panicking: the authority is
  cut at the byte index of the first `/`, `?`, or `#` (those are ASCII, so the
  index is a valid UTF-8 boundary even for a multibyte host like `http://é/abc`).
  Empty scheme, empty host (`http:///oops`, `http://:8080`), userinfo (`@`), and
  fragments (`#`) are rejected conservatively (return None → Unknown) rather
  than silently discarded into a claim of equivalence.
- Endpoint comparison is a tri-state `EndpointRel::{Equal, Different, Unknown}`.
  A parse failure is `Unknown`, never `Different`, so a malformed endpoint in an
  otherwise-accepted attach argv shape yields `Ambiguous` — tracking is never
  dropped on unparseable evidence. The obsolete `endpoints_match` bool (which
  mapped unknown → false) and the contradictory stacked normalization comments
  were removed.
- The host/loopback (`localhost`↔`127.0.0.1`), trailing-path-slash, and
  query/path case policies are preserved.
- Tests: `malformed_endpoint_is_ambiguous_in_both_attach_shapes`,
  `unicode_authority_does_not_panic_and_valid_different_server_never_matches`
  (Unicode no-panic, `not-a-url`/`http:///oops`/`http://:8080`/userinfo all
  Unknown→Ambiguous, and a valid different server still no match), plus explicit
  `endpoint_rel` Equal/Different/Unknown assertions. Malformed evidence through
  reconciliation is covered by the app-level `reconcile_retains_unknown_and_drops_only_on_complete_proof`
  (unknown/ambiguous evidence retains the record and startup eligibility).

### E — retain a newly created identity independently of list visibility
- `create_new_session` now keeps locally-created known sessions in an explicit
  in-memory `locally_created: Vec<Session>` (keyed by their `SessionKey`
  identity). `refresh` merges them into each provider's successful snapshot,
  without duplicates, until the provider's authoritative listing has actually
  observed them; once observed, normal listing policy applies and the local set
  releases them. This is not a persisted successful-open record; the on-disk
  tuple format is unchanged.
- A retry resumes the retained identity via `resume_plan`, never calling `create`
  again.
- Tests:
  - `foreground_spawn_failure_retains_created_session_without_recreate` (now
    leaves the list EMPTY, proving retention is independent of list visibility),
  - `created_identity_retains_across_refresh_after_plan_and_tmux_spawn_failure`
    (immediate and subsequent refreshes, plus a retry that does not re-create),
  - `created_identity_eventually_listed_then_removed_without_duplicates`
    (merge while unobserved → no duplicate once listed → ordinary removal after).

## Corrections applied (A–C, second review)

### A — startup eligibility transitions
- `startup_eligible` is now keyed by `(provider, session id, window id)` so a
  replacement window never inherits an old record's unresolved startup state.
- Membership is preserved, never granted: `still_eligible.push` runs only for
  records that ALREADY held eligibility, so a later-opened record cannot acquire
  startup eligibility after a transient failure and be falsely flagged
  interrupted.
- Unknown evidence (no collection result) retains the record AND keeps its
  existing eligibility — it is never treated as confirmed reconciliation.
- Sequence tests (multi-call, not one-shot):
  - `later_open_never_acquires_startup_eligibility` — empty startup → later open
    → transient list failure → recovery → the later open is an intentional close,
    never interrupted.
  - `unknown_evidence_keeps_eligibility_then_interrupts_on_dead` — initial record
    → collection error with successful liveness → eligibility kept → later dead
    window at startup classification → interrupted.
  - `window_replacement_does_not_inherit_startup_eligibility` — initial record
    @1 (ambiguous, retained, eligible) + replacement window @2 for the same
    session opened later; @2's death is an intentional close, never inherited
    eligibility.
- Persisted tuple format unchanged.

### B — explicit adapter grammar
- Each adapter now matches only exact supported argv shapes:
  - opencode: `opencode attach <endpoint>` and `opencode attach <endpoint> -s <id>`;
  - codex: `codex resume <target>`.
- Recognized executable with unrecognized syntax → `Ambiguous` (unknown), never
  proof of absence. Leading/trailing unknown options, a dangling `-s`, duplicate
  `-s`, and resume-without-target all yield ambiguous. Only a fully understood
  form establishes a different session/server (no candidate for ours).
- OpenCode endpoint parsing separates the authority at the first `/`, `?`, or
  `#`; scheme/host are lowercased, the query/path bytes are preserved (case
  matters), and a trailing slash on a non-root path is normalized. `?Token=A`
  is no longer folded into the host.
- Tests: `unknown_options_and_dangling_duplicate_flags_are_ambiguous`,
  `query_bytes_and_trailing_slash_are_preserved_or_normalized`,
  `unknown_codex_syntax_is_ambiguous_not_absence`, plus the adapter grammar cases
  (absolute basename, id-less attach, different session/server). Reconciliation
  retains records on these unknown results (covered by the existing
  `reconcile_retains_unknown_and_drops_only_on_complete_proof` and the new A
  sequence tests).

### C — real application failure/capability coverage
- `suspend_for` now refuses to launch a client after terminal preparation fails,
  always attempts restoration, and surfaces combined launch+restoration errors
  (`partial_suspend_failure_does_not_launch_client`,
  `spawn_and_restore_failures_are_both_surfaced_and_cleanup_runs`). These test
  `App::suspend_for` directly (not the obsolete `run_guarded` helper).
- `open_session` returns `OpenResult::{Opened, Refused, Failed}` and checks the
  resume capability BEFORE asking for a plan
  (`resume_unsupported_is_refused_before_plan`).
- `create_new_session` distinguishes opened / refused / failed so a created
  known session followed by a foreground failure is retained in the snapshot and
  reported "created but could not be opened", with no re-create and no successful
  window record (`foreground_spawn_failure_retains_created_session_without_recreate`,
  `failed_tmux_spawn_creates_no_tracking_record`).
- New-session `current_dir` failure/non-UTF-8 is now an explicit error, not an
  empty-directory fallback.
- The injected app fixture is a valid two-slot registry; `FakeTmux` returns
  distinct window ids per launch (`multiple_pendings_have_distinct_window_ids`)
  and can fail a spawn; `FakeForeground`/`FakeTerminal` are configurable and
  record calls.

## Corrections applied (R1–R5)

### R1 — tracked window requires confirmed identity evidence
- `decide_open` now selects a tracked window only when it is alive AND has a
  Confirmed match; liveness alone no longer selects. Candidates are deduplicated
  by window id (strongest confidence wins). The regression test now asserts a
  live-but-unrelated tracked window is NOT selected (the confirmed candidate
  elsewhere is adopted instead), plus ambiguous-tracked/incomplete/force cases.

### R2 — failed/ambiguous inspection never erases tracking
- `TmuxCli` checks subprocess exit status on every command (`window_alive`,
  `list_window_ids`, `pane_root_pids`, `current_session`, `mouse_on`); a failed
  tmux command is an error (unknown), not empty/dead evidence.
- `compute_interrupted` treats `window_alive` errors as unknown (retain), and an
  Ambiguous/Heuristic match in a complete snapshot as uncertain (retain) — a
  record is dropped only on a COMPLETE inspection with no match at all.
- Startup interruption now uses per-record eligibility (`startup_eligible: Vec<(usize,String,String)>`,
  keyed by provider, session id, AND window id) initialized once from the startup
  records; eligibility is consumed only when
  that record's initial reconciliation was actually possible (kept through a
  failed window/proc inspection and through a provider list failure). Legacy
  out-of-range indices and legacy empty IDs are preserved.
- App-level fixtures cover each: unknown liveness, ambiguous identity, complete
  proof, legacy indices/empty ids, startup interruption, intentional close, and
  keeping eligibility through a list failure then interrupting.

### R3 — process evidence bounded, parsed, and interpreted safely
- `ProcFs::tree` marks the snapshot incomplete when bounded descendants exist
  beyond `max_depth` (no false "complete"); `parse_cmdline` preserves empty
  arguments and drops only the terminating NUL, returning unknown for
  truncated/non-UTF-8.
- Adapters match the executable by exact basename (absolute `/path/to/codex|opencode`
  works; never substring or shell text); unparseable client forms are Ambiguous
  (unknown), not proof of absence.
- OpenCode endpoint normalization lowercases scheme/host only, maps the exact
  loopback alias at the authority boundary, and preserves port/path/query
  case-sensitively; `localhost.example` vs `127.0.0.1.example` and `/A` vs `/a`
  never conflate.
- Codex title uniqueness uses the current successful snapshot; the app guards
  `match_session`/`open` with `provider_ok` so a stale (failed-list) snapshot
  never confirms a label.

### R4 — execution boundary made safe and tested
- `open_in_tmux` now invokes POSIX `sh` explicitly through tmux's multi-argument
  command interface (argv `["sh","-c",serialized]`), asserted via a fake tmux;
  the user's default shell is never used to interpret the fragment.
- Shared `validate_launch` rejects NUL in program/args/cwd/env and validates env
  names for BOTH foreground and tmux execution. A non-UTF-8 `current_dir` is
  rejected rather than `to_string_lossy`-converted.
- The real suspend/run/restore sequence is behind an injectable `Terminal` seam;
  `suspend_for` always attempts cleanup after partial suspension and after a
  spawn failure, and surfaces combined launch+restoration errors. `refresh()`
  runs after foreground return in both the resume and creation paths (verified
  through app-level tests).

### R5 — application orchestration tested via dependency injection
- `App::with` accepts an injected `ProviderRegistry`, `Launcher` (with seams),
  `OpenedStore`, and `Terminal`; `App::new` wires the real defaults. A new
  `OpenedStore` trait (real flock-ed `opened.json`, in-memory for tests) keeps
  the storage format unchanged.
- `PendingLaunch` now carries a stable `ProviderId`, not a positional index.
- `KnownSession` creation constructs and validates a `SessionKey` (nonempty
  native id) at the boundary before tracking, and retains the created identity
  across plan/spawn failure.
- Visible unresolved status: a compact "N pending launch(es)…" line renders when
  pendings exist. Capabilities drive the new-row (dimmed when unsupported),
  rename/suggest handlers (refused when unsupported), and the new-session form
  (explains applies_title/applies_cwd).
- App-level tests (via injected fakes) cover: known-session create records a
  window without a retry; plan/spawn failure retains the created identity with
  no record and no re-create; multiple launch-to-create pendings accumulate with
  distinct tokens and no empty-id records; pending status is visible; unsupported
  new/rename are refused before side effects; a deferred plan keeps its provider
  after focus changes; and reconciliation retention/interruption scenarios.
- A fake third provider drives the same lifecycle/evidence path through the
  registry with no provider-specific app branch.

## Baseline

- Starting HEAD: `e81cef7d78ef76e58bc421dc67d552de842284ef` (unchanged across
  Stage 1; the working tree already contained Stage 1's uncommitted changes,
  which were preserved).
- Pre-existing modified/untracked paths: `blueprint.md`,
  `.memory/wiki/{gotchas,index,log}.md`, `.memory/wiki/notes/`, `docs/`.
- Baseline commands: `make tangle` ok; `make check` ok; `make test` ok
  (**12 passed**, 0 failed — Stage 1's count); `make lint` ok. No pre-existing
  failures.

## Implementation

All executable changes were made through `blueprint.md` chunks and regenerated
with `make tangle`. Chunks changed/added: `core-model`, `prov-mod`,
`prov-opencode`, `prov-codex`, `prov-codex-tests`, `core-launcher`, `tui-app`.
Prose updated: §6 (architecture), §7 (module map), §8 (D10), §9.1/§9.2 (data
contracts), §11.4 (provider trait), §11.8 (launcher), §13 (test plan).

Provider contract and error types (`prov-mod`, `core-model`):
- `ProviderCapabilities { rename, resume, new_session: NewSessionCapability {
  supported, applies_title, applies_cwd } }` — named fields, not booleans.
- `LaunchRequest { program, args, cwd, env }` (no shell fragment);
  `CreateOutcome::{KnownSession(Session), LaunchToCreate(LaunchRequest)}`;
  `MatchConfidence::{Confirmed, Heuristic, Ambiguous}`, `WindowMatch`,
  `ProcEvidence`, `WindowEvidence`, `ProcessEvidence`.
- `Unsupported { what }` implements `std::error::Error` and is carried inside
  anyhow so `downcast_ref::<Unsupported>()` distinguishes it from operational
  failure. `check_session_belongs` rejects a session of another instance before
  any side effect. Trait methods `descriptor/capabilities/list/rename/
  resume_plan/create/match_session`; `attach_command` and the server-only
  `create` are removed.

Adapters:
- OpenCode: `create` → `KnownSession` (server ignores requested cwd,
  `applies_title`); `resume_plan` → structured `opencode attach <base> -s <id>`;
  evidence requires exact attach syntax + configured server (trailing-slash and
  localhost/127.0.0.1 normalized; different endpoints never match); id-less
  attach is only `Ambiguous`.
- Codex: `create` → `LaunchToCreate` (`codex` in requested cwd, title is a
  window label, `applies_cwd`); `resume_plan` → `codex resume <title-or-uuid>`;
  evidence confirms exact UUID, and a resume title only when it uniquely matches
  the current snapshot (duplicate/inherited titles → `Ambiguous`, never "first
  list entry").

Application lifecycle (`tui-app`):
- New-session and resume dispatch generically through `Provider`; capabilities
  gate the "+ new session" form and refuse unsupported creation. No
  provider-name/index checks remain for lifecycle/evidence (only fixed labels/
  colors/columns and legacy index mapping stay, explicitly allowed until Stage 3).
- `KnownSession` flow retains the session in the snapshot, then opens it; a
  plan/launch failure reports "created but could not be opened" while keeping
  the identity; no duplicate creation on retry; a failed create records nothing;
  a failed launch records no window.
- `LaunchToCreate` flow launches the plan and records an in-memory `PendingLaunch`
  (unique token, provider, tmux window id) — never an empty/fabricated native ID
  in `SessionKey`/`opened.json`. Multiple pendings are kept in a list; a pending
  is removed only on confirmed window death (kept through failed inspection).
  Unresolved pendings are not persisted (deliberate Stage 2 limitation; Stage 3
  supplies the versioned format). Legacy empty-ID records are preserved and
  never treated as known sessions.
- Deferred (mouse) `Plan` variants each carry their provider index and launch
  data, so executing one never uses a later-focused column (verified by
  `deferred_plan_keeps_its_provider_after_focus_change`).
- `refresh` retains the last snapshot on failure (`provider_ok[p]`), distinguishing
  failure from a successful empty list, and skips destructive reconciliation for
  a failed provider while keeping per-record startup eligibility
  (`startup_eligible`). Out-of-range legacy indices and empty IDs are retained.
- `compute_running`/`compute_interrupted` use adapter evidence; only a Confirmed
  match marks a session running; a tracked client is dropped only when a
  complete inspection proves it ended (unknown/incomplete retains it);
  startup interrupted detection is preserved per provider.

Launcher/evidence (`core-launcher`):
- Injectable seams `ProcReader` (real: NUL-delimited `/proc/<pid>/cmdline` +
  `/proc/<pid>/task/<pid>/children`, bounded), `Tmux` facade, and `Foreground`
  runner (real: `std::process::Command` with inherited stdio; `status()` errors
  only on spawn failure). The collector has no provider/executable rules and
  reports completeness/errors.
- Foreground runs use `Command` directly (args/current_dir/envs); restoration
  runs on both child-return and spawn-failure via `run_guarded` (never `?` past
  restoration); alternate-screen behavior preserved.
- The tmux boundary serializes once to POSIX `sh` (`exec` with every program and
  argument single-quoted including empties, cwd via `cd`, env overrides on the
  `exec`, env names validated, NUL rejected); tmux exit status and returned
  window id are both checked; no retries.
- Explicit `decide_open` adoption policy (tracked-select / single-confirmed
  adopt / uncertain refuse + force / complete-empty spawn with active refusal /
  incomplete refuse) replaces the old silent newest-session auto-adoption.

Intentional transitional coupling retained: two-column layout, fixed labels/
colors, numeric provider positions in `opened.json`, registry index access, and
the two built-in adapters. Pending launches are in-memory only.

## Acceptance evidence

Requirement-to-test mapping (all automated, offline; no live server, real Codex
home, tmux manipulation, or interactive terminal):

| Task §5 group | Tests |
| --- | --- |
| Capabilities affect handlers; unsupported ≠ failure | `lookup_dispatches_operations_and_distinguishes_unsupported`, codex `resume_plan_uses_title_or_uuid_and_create_is_launch_to_create` (capabilities), app `unsupported_new_session_is_refused_before_create`, `rename_handler_refuses_when_unsupported` |
| Both creation outcomes, cross-provider rejection, multiple pendings | `create_known_session_records_window_without_recreate`, `create_known_session_plan_failure_retains_without_recreate`, `create_launch_to_create_accumulates_multiple_pendings`, `cross_provider_session_is_rejected_before_side_effects` |
| Direct/serialized execution preserving hostile args | `serialization_preserves_shell_hostile_args_and_env_and_cwd`, `serialization_rejects_nul_anywhere_and_invalid_env_names` |
| tmux boundary uses POSIX sh explicitly | `open_in_tmux_invokes_posix_sh_explicitly` (fake tmux asserts argv `["sh","-c",…]`) |
| Terminal-restoration on spawn failure + real seam | `restoration_runs_on_both_success_and_spawn_failure`, `suspend_for` behind injectable `Terminal` seam |
| Evidence fixtures | opencode `exact_id_on_configured_server_is_confirmed`, `trailing_slash_and_localhost_are_equivalent_but_not_different_servers`, `endpoint_normalization_is_case_sensitive_for_paths_and_host_prefixes`, `absolute_executable_path_matches_by_basename`, `unparseable_attach_is_ambiguous`, `id_less_attach_is_ambiguous_not_confirmed`, `different_session_id_is_not_a_match_for_ours`; codex `exact_uuid_is_confirmed`, `absolute_executable_path_and_unknown_forms`, `unique_resume_title_is_confirmed_duplicate_is_ambiguous` |
| Adoption policy incl. force + tracked-identity + dedup | `adoption_policy_requires_confirmed_evidence_for_tracked_window`, `adoption_policy_covers_remaining_cases_and_dedups` |
| Process collector | `parse_cmdline_preserves_empty_args_and_rejects_truncated_or_non_utf8`, `collect_evidence_aggregates_panes_and_marks_incomplete` |
| Failed refresh/inspection retention + startup eligibility | app `reconcile_retains_unknown_and_drops_only_on_complete_proof`, `reconcile_preserves_legacy_unknown_indices_and_empty_ids`, `reconcile_interrupts_at_startup_then_drops_on_later_close`, `reconcile_keeps_startup_eligibility_through_list_failure_then_interrupts` |
| Deferred action keeps provider after focus change | app `deferred_plan_keeps_its_provider_after_focus_change` |
| Visible pending status | app `pending_status_is_visible` |
| Third fake adapter through lifecycle | app tests drive a fake provider through create/resume/match via the registry with no provider-specific app branch |

Gates (real results):
- `make check`: ok
- `make test`: **62 passed, 0 failed** (was 60 after D/E; 56 after A–C)
- `make lint`: ok (`cargo clippy -- -D warnings`)
- `git diff --check`: clean
- Repeat `make tangle`: sha256 of all generated files byte-for-byte identical
- No `ProviderKind`/`AnyProvider`/`attach_command`/`did_startup_reconcile` in
  `src/`; no concrete adapter constructors in `src/tui`/`src/main`; no
  `opencode`/`codex` lifecycle/evidence branches in the app.

## Observable changes and limitations

- Authorized behavior change: the old OpenCode newest-session heuristic that
  silently adopted an id-less attach window is now explicit — an id-less attach
  is `Ambiguous` and the adoption policy refuses automatic adoption/spawn with
  an uncertainty warning, requiring `f` for a fresh launch. Unrecognized native
  command syntax is also `Ambiguous` (unknown), never treated as proof of
  absence.
- Pending (launch-to-create) launches are in-memory only and are NOT recovered
  as pending after a Pinga restart (documented temporary limitation; Stage 3
  provides the versioned persisted format). Legacy empty-ID opened records are
  preserved but not treated as known sessions; `opened.json` tuple format is
  unchanged; no sidecar registry was added.
- Terminal restoration runs on both success and spawn failure behind the
  injectable `Terminal` seam; `suspend_for` refuses to launch after a failed
  suspension, always attempts cleanup, and surfaces combined launch+restoration
  errors.
- Fixture assertions vs tested production paths: the A/B/C tests exercise the
  actual production methods (`App::suspend_for`, `App::open_session`,
  `App::create_new_session`, `App::compute_interrupted`) through injected
  launcher/store/terminal seams; the `run_guarded` helper remains only as a
  lower-level launcher unit test and is not claimed as the application
  restoration path.
- Remaining limitations: the full `App` event loop (key/mouse/render) is still a
  manual smoke-test item — the injected-seam tests cover the orchestration
  methods directly, but not the ratatui render path. Pending launches are
  in-memory only and are not recovered as pending after a Pinga restart (Stage 3
  supplies the versioned format). No live provider writes, tmux manipulation, or
  interactive terminal were used in tests.

## Deviations/questions and reviewer entry points

- No material architectural conflict required escalation; no scope change. The
  injectable construction (`App::with`, `Launcher::with_seams`, `OpenedStore`,
  `Terminal`) is the bounded testability refactor the review authorized; the
  storage format and production defaults are unchanged.
- Proposals for later stages (not done here): persist pendings in a versioned
  format (Stage 3); derive app labels/colors from descriptors when generic
  provider views land.
- Reviewer entry points:
  - Chunks: `core-model`, `prov-mod`, `prov-opencode`, `prov-codex`,
    `prov-codex-tests`, `core-launcher`, `tui-app`.
  - Most useful tests: `adoption_policy_requires_confirmed_evidence_for_tracked_window`,
    `open_in_tmux_invokes_posix_sh_explicitly`,
    `parse_cmdline_preserves_empty_args_and_rejects_truncated_or_non_utf8`,
    `collect_evidence_aggregates_panes_and_marks_incomplete`,
    `endpoint_normalization_is_case_sensitive_for_paths_and_host_prefixes`,
    `unknown_options_and_dangling_duplicate_flags_are_ambiguous`,
    `unknown_codex_syntax_is_ambiguous_not_absence`,
    `later_open_never_acquires_startup_eligibility`,
    `unknown_evidence_keeps_eligibility_then_interrupts_on_dead`,
    `window_replacement_does_not_inherit_startup_eligibility`,
    `partial_suspend_failure_does_not_launch_client`,
    `spawn_and_restore_failures_are_both_surfaced_and_cleanup_runs`,
    `foreground_spawn_failure_retains_created_session_without_recreate`,
    `resume_unsupported_is_refused_before_plan`,
    `failed_tmux_spawn_creates_no_tracking_record`,
    `multiple_pendings_have_distinct_window_ids`,
    `malformed_endpoint_is_ambiguous_in_both_attach_shapes`,
    `unicode_authority_does_not_panic_and_valid_different_server_never_matches`,
    `endpoint_validation_subset_table`,
    `malformed_endpoint_evidence_routes_through_adapter_into_reconciliation`,
    `created_identity_retains_across_refresh_after_plan_and_tmux_spawn_failure`,
    `created_identity_eventually_listed_then_removed_without_duplicates`.
  - Review the app's `open_session`/`create_new_session`/`refresh`/`execute`/
    `compute_interrupted`/`suspend_for` and the launcher's
    `decide_open`/`serialize_launch`/`collect_evidence`/`open_in_tmux` for the
    lifecycle, evidence, and execution-boundary integration.

Stage 2 corrections (R1–R5, A–C, and D/E) are complete and ready for architect
review. Stage 3 (generic provider views/config and the stable tracking
migration) is out of scope and was not started. Nothing was committed, installed,
or run against live provider sessions.