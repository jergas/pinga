# Antigravity integration evidence (PA-01, Phase B)

2026-09-23. Scope: identify the installed Antigravity product, inspect its
verified surfaces read-only, and build an optional adapter that satisfies the
provider contract where the product's real surface allows. The adapter is
compiled-in but NOT auto-registered.

## 1. Installed product (actual evidence)

`agy` is the Antigravity CLI (Google exa/jetski lineage), v1.2.9, installed at
`~/.local/bin/agy` (217 MB Go binary; `agy --version` → `1.2.9`; sha-checked
real binary, not a wrapper). It was installed but uninitialised at the start of
this review; it has since been initialised (onboarding completed, workspace
trusted). Verified read-only:

- `~/.gemini/antigravity-cli/` is the app data dir:
  - `conversation_summaries.db` — SQLite conversation index (the enumeration
    surface). Real schema (exact columns, NOT NULL defaults observed):
    `conversation_id` (TEXT PK), `title`, `preview`, `step_count`,
    `last_modified_time` (DATETIME), `workspace_uris`, `status`, `source`,
    `project_id`, `agent_name`, `parent_conversation_id`, `nesting_depth`,
    `battle_id`, `winning_conversation_id`, `not_fully_idle` (NUMERIC),
    `killed` (NUMERIC), `last_user_input_time`, `last_user_input_step_index`,
    `app_data_dir`, `group_id`. Currently 0 rows (fresh install) — the
    fresh-install path (empty list) is the live behaviour today.
  - `conversations/` (empty per-conversation store), `settings.json`,
    `jetski_state.pbtxt`, `installation_id`, `cli.log` → `log/cli-*.log`.
- CLI surface (from `agy --help` / `agy help`):
  - Resume an EXACT conversation by stable UUID: `--conversation <id>`.
  - Continue most recent: `--continue` / `-c`.
  - Create a new project/session: `--new-project`; project scoping `--project`,
    agent `--agent`, model `--model`, effort `--effort`, mode `--mode`.
  - No CLI rename flag (rename is a TUI `/rename` slash command only).
  - Subcommands: agent, models, mcp, plugin, remote-control, install, update,
    changelog. No session-listing subcommand — enumeration is the SQLite index.
- Data-dir override env var: `ANTIGRAVITY_APP_DATA_DIR` (verified in the
  binary) — used by the adapter as the narrow source env for launches.
- No conversation rows to inspect yet; the mapping below is driven by the real
  schema and the real flag set, and every claim is labelled with its evidence.

## 2. Capability mapping (verified support)

| Capability | Status | Evidence |
| --- | --- | --- |
| Session enumeration | Verified | `conversation_summaries` SQLite table (real schema, read-only query verified against the live DB) |
| Stable native IDs | Verified | `conversation_id` UUID column is the resume key |
| Source/profile separation | Partial | `project_id`, `agent_name`, `source` columns; `--project`/`--agent` flags |
| Creation | Verified (launch-to-create) | plain `agy` in cwd opens a new conversation in that workspace (agy never auto-resumes without `--continue`) |
| Resume of an EXACT conversation | Verified | `--conversation <id>` (exact UUID) |
| Rename | Unsupported | only TUI `/rename`; summary DB is a reconciled cache, so direct writes would be fabricated surface |
| Activity evidence | Verified | `not_fully_idle` / `killed` / `status` / `last_modified_time` / `last_user_input_time` |
| Launch arguments | Verified | `--conversation <id>` (+ `--project`), env `ANTIGRAVITY_APP_DATA_DIR` |

## 3. Adapter decision

`src/provider/antigravity.rs` (§5.3) implements the optional adapter:

- Compiled-in factory keyed on `type = "antigravity"`, registered in the
  factory map, NOT in `builtin_registry` (so it only exists when explicitly
  configured — never auto-registered alongside opencode/codex).
- `home` option: optional absolute app-data-dir override; defaults to
  `$HOME/.gemini/antigravity-cli`. Unknown options are rejected at the factory
  boundary even when disabled.
- `list()`: read-only SELECT over `conversation_summaries` mapping
  `conversation_id`→id, `title`→label (fallback `preview`), `workspace_uris`
  (first path) →directory, `agent_name`→agent, `last_modified_time`→updated_ms
  (Go-layout datetime parsed as UTC), `not_fully_idle && !killed`→active.
  Missing DB → empty list (fresh install), matching the live 0-row state.
- `resume_plan()`: `agy --conversation <id>` with cwd=directory and
  `ANTIGRAVITY_APP_DATA_DIR` pinned to the configured home.
- `create()`: LaunchToCreate of plain `agy` in the requested cwd.
- `rename`: unsupported (capability flag off) — honest, no fabricated surface.
- `match_session()`: `agy --conversation <id>` is Confirmed on exact UUID;
  `--continue`/`-c` (most-recent resume) is Ambiguous; other `agy` argv is
  Ambiguous (recognized exe, unknown syntax); foreign data dir → Ambiguous
  (conservative, mirrors codex's CODEX_HOME policy).

## 4. Config (optional, opt-in)

An explicit `[[providers]]` list REPLACES the built-in defaults (opencode +
codex), so a COMPLETE opt-in config must preserve the existing providers. This
is the full, ready-to-uncomment form (nothing is enabled by default; the
antigravity entry only exists when the list is active):

```toml
[[providers]]
id = "opencode"
type = "opencode"
[providers.options]
url = "http://127.0.0.1:4096"

[[providers]]
id = "codex"
type = "codex"
[providers.options]
home = "/home/edgar/.codex"

# Optional: add one antigravity instance per data dir you want to track.
[[providers]]
id = "agy"
type = "antigravity"
label = "Antigravity"
[providers.options]
home = "/home/edgar/.gemini/antigravity-cli"   # optional; default as above
```

A second antigravity instance on a DIFFERENT data dir coexists as its own
instance (distinct id/label/source env):

```toml
[[providers]]
id = "agy-other"
type = "antigravity"
label = "Other"
[providers.options]
home = "/tmp/other-antigravity"
```

## 5. Manual Antigravity test checklist

Expected results assume a conversation has actually been created with `agy`
(the summary DB currently has 0 rows — an empty list is correct until then).
Do not enable the config above or run these yourself until authorized; this
list documents what a live check would verify.

| # | Action | Expected result | Limitation |
| --- | --- | --- | --- |
| 1 | Enable the complete opt-in config; start pinga | The antigravity column lists any `conversation_summaries` rows newest-first with titles/previews, status dot, and age; opencode + codex columns unchanged | Requires at least one real conversation; empty DB → empty column (fresh-install path) |
| 2 | Press `g` (refresh) while agy is running a conversation | `running` group appears for that session (Confirmed window evidence) | Requires tmux + agy actually running; evidence comes from `/proc` argv/env |
| 3 | Select a conversation and press Enter | A NEW tmux window runs `agy --conversation <uuid>` with `ANTIGRAVITY_APP_DATA_DIR` pinned to the configured home; a Known tracked record lands | Exact-UUID resume verified; do not run interactively in an unattended test |
| 4 | Create a new session (Enter on `+ new session`) | A new tmux window runs plain `agy` in the chosen cwd (new conversation, no `--continue`) | Launch-to-create; the new session appears after its first listing |
| 5 | Configure a SECOND home; start a second pinga instance on it | The two instances never cross-track: same-named conversations stay in their own instance's records | Source env pinning is the only isolation; verified by the two-homes config test |
| 6 | Tracking write fails (disk error) after a window launches | Error names the launched window; the pending state is retained with a unique token; an EXPLICIT retry (by token) records the existing window — ordinary new still spawns new | Retry is token-addressed; the liveness error path retains the recovery state |
| 7 | Scroll a long list below the viewport at short and tall sizes; click the visible selected row | The selected row stays visible (rendered text); the click dispatches that session's key | Headers + two-line (detail) rows are counted by line height in the shared layout |
| 8 | Rename a conversation | Unsupported (error, capability flag off) | Only the TUI `/rename` exists; the summary DB is a reconciled cache, so direct writes would be fabricated surface |

## 5b. User-facing limits (minimum publishable scope)

- A newly created plain-agy launch (`+ new session`) cannot prove which native
  conversation it will produce. Pinga conservatively reports such a launch as
  Ambiguous and never infers identity from cwd, title or time. Appearing in the
  summary index makes the conversation listable, but does not identify its
  original window. Resuming it through Pinga with its exact ID makes subsequent
  window tracking possible.
- Native conversation titles are owned by Antigravity (agy's TUI `/rename`
  command only). A Pinga "new session" name labels the tmux window only; it
  does not change or predict the native conversation title. Renaming through
  Pinga is intentionally unsupported.

## 6. Tests and validation

- Unit + integration tests (temp-dir fixture DBs): list mapping/sort/instance-id,
  fresh install → empty, inaccessible DB → error, resume argv+env, create plan,
  argv/data-dir window matching, workspace URI decoding (spaces/commas/escaped),
  checked datetime (invalid/pre-epoch/offset/fraction), option validation,
  non-UTF-8 home rejection, a REAL `/proc` collector → adapter env hand-off, a
  two-configured-homes config test, and an end-to-end app test that lists,
  resumes and tracks a session through the real adapter.
- Deterministic file-store interleaving and explicit launch-token retry tests
  exercise the conflicting timing (not edits between complete refreshes).
- Live read-only check against the initialized data dir: the exact SELECT the
  adapter runs opens the real DB cleanly (0 rows today = empty list, correct
  for a fresh install).
- All gates pass (check/lint/clippy `--all-targets` clean; repeat tangle
  byte-identical; `git diff --check` clean).
- NOT exercised: launching a real conversation (would create live data/tokens)
  and rename (unsupported). Once conversations exist, `list()` is expected to
  surface them with no code change.