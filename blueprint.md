# pinga — A Session Console for opencode & codex

**Status:** working draft · **Owner:** edgar · **Date:** 2026-09-17
**Type:** literate-programming architectural blueprint (Option 2: pure Markdown + tangle)

## 1. What this document is

`pinga` is a small TUI console that manages opencode and codex sessions side by
side: it lists them, suggests short names for them (via a local Ollama model or
a keyed API), renames them automatically and/or manually, and hands control of
the terminal — or a new tmux window — to whichever session you pick.

This file is *the* specification **and** the source of truth for the code:

- **prose** explains the architecture and records decisions;
- **code chunks** are fenced blocks tagged with `path="…"` that **tangle** into
  real source files under `src/`.

Rebuild the source from this document at any time:

```sh
make tangle    # python3 tools/tangle.py blueprint.md  (zero deps, always works)
make weave     # optional: pandoc --standalone -o blueprint.html   (needs pandoc)
```

`make check` / `make test` are the CI-style gates that keep the tangled code in
shape. The whole toolchain is open source (see §4).

## 2. Why literate programming for pinga

The tool does one small job across two *moving, proprietary-ish*
CLIs (opencode, codex) whose storage formats and HTTP surfaces we had to reverse
from the running system. The integration facts (what returns real JSON vs the
SPA HTML fallback, where codex keeps thread names, what a rename touches) are
exactly the knowledge that decays if only stored in someone's head. Encoding
them as executable, tanglable chunks means the blueprint *is* the integration
knowledge, and the implementation cannot drift from it while `make tangle` is
the build step.

## 3. Requirements (from eris session 2026-09-17, verbatim intent)

These record intended behavior, not completion status. In particular, R4's
recent-user-text input and R5's automatic trigger are not implemented (see §12).

| # | Requirement | Acceptance signal |
|---|-------------|-------------------|
| R1 | Manage **opencode** and **codex** sessions | Both session lists appear, one column each |
| R2 | Takes an **API key** | Config `api_key` / `PINGA_API_KEY`; used for the remote name engine |
| R3 | Connect a **local Ollama** model for suggestions | `ollama_base_url` + `ollama_model`; engine uses it when reachable |
| R4 | Suggest **short, relevant session names** | Name engine returns ≤ 40 chars from the session's recent user text |
| R5 | Offer **automatic and/or manual rename** | `auto_rename` toggle + `r` manual with prefilled suggestion |
| R6 | Run **in and out of tmux** | `in_tmux()` branches launcher behavior |
| R7 | Two **scrollable columns** (opencode \| codex) | Left/right lists scroll independently, wheel + `PgUp/PgDn` |
| R8 | Navigate with **arrows**, plus **mouse** | Up/Down move selection; click selects, double-click or Enter opens; wheel scrolls |
| R9 | In tmux: open session in **another window** of the same session | `tmux new-window -t <current session> -n <label> "<attach cmd>"` |
| R10 | Own terminal: **pass control** of the terminal to the session, return when it exits | Suspend alt-screen + raw mode → run attach cmd with inherited stdio → re-enter |
| R11 | **Mostly purple and green**, good readability | Palette in §14; text pairs meet WCAG-AA-ish contrast on the dark background |

Non-goals (out of scope): editing session content, multi-machine sync, a web
UI, or supporting zsh-era multiplexers beyond tmux.

## 4. Stack (open source only)

| Layer | Choice | License | Why |
|-------|--------|---------|-----|
| Language | Rust 1.98 (present on eris) | MIT/Apache-2.0 | One small static binary; precise terminal control for R10 |
| TUI | ratatui 0.29 + crossterm 0.28 | MIT | Scrollable widgets, mouse capture, custom styles — the closest fit to R7/R8/R11 |
| HTTP | ureq 2 (blocking) | MIT/Apache-2.0 | No runtime/tokio; a poll-every-N-seconds TUI doesn't need async |
| Serialize | serde + serde_json + toml | MIT/Apache-2.0 | Config + JSON parsing |
| Paths/errors | dirs 5, anyhow | MIT/Apache-2.0 | Ergonomics |
| Weaver/tangle | pandoc (optional) + stdlib Python | GPL-2+ / PSF | Option-2 literate workflow; python tangle is the dependency-free default |
| Underlying agents | opencode (server), codex (standalone) | (upstream) Apache-2.0, Apache-2.0 | We attach to them; we never fork their binaries |

Deferred (optional, all open source): `ollama` daemon (MIT) for R3; a terminal
emulator supporting truecolor for the full palette.

## 5. Integration surface (eris recon, updated through 2026-09-22)

The original recon was performed on eris on 2026-09-17. The Codex notes were
updated after the 2026-09-22 storage changes. These are version-specific
observations and descriptions of the current adapter, not guarantees about
future upstream releases.

### 5.1 opencode (v1.18.29)

- Persistent server: `opencode serve` as systemd user unit
  `~/.config/systemd/user/opencode.service`, listens on `http://127.0.0.1:4096`.
- **Compat JSON API** (routes without the `/api/` prefix return bare JSON; they
  are what the web client and this console hit):
  - `GET /session` → `[ { id, slug, projectID, directory, path, summary, cost,
    tokens{input,output,…}, title, agent, model, version, time{created,updated}
    } ]` — newest first, **this is pinga's list source**.
  - `GET /session/<id>` → same object, single.
  - Rename: **no dedicated route exists in the v1.18.29 v2 API group**
    (`/api/session*` — verified from the tag source: create/list/active/get/
    switchAgent/switchModel/prompt/compact/wait/revert*/context/history/events/
    interrupt/message — *no rename*). Empirically, one of
    `POST|PATCH|PUT /session/<id>` or `/session/<id>/rename` with body
    `{"title":"…"}` mutates the title (sets it; rapid serial repetition of all
    six restored the original value exactly). The adapter tries these routes
    in order and verifies each apparent success; the exact route remains unpinned.
  - Catch: unhandled POST routes return the SPA `index.html` (HTTP 200!) — a
    rename that "succeeds" against a wrong path changes nothing. Always verify
    by re-reading `GET /session/<id>`.
  - Storage: `~/.local/share/opencode/opencode.db` (SQLite, `session` table with
    `title`, `agent`, `model`, `time_created`, `time_updated`, token/cost
    columns). Reading it **live on an attached server risks racing** the
    server's own writes — use the HTTP API, never the DB file.
- Attach client: `opencode attach http://127.0.0.1:4096 -s <id>` (client TUI;
  exits cleanly when the user quits session view — good for R10).

### 5.2 codex (0.155 storage, observed 2026-09-22)

- Home: `~/.codex/`. The adapter finds a `state_*.sqlite` database containing
  a `threads` table and reads `name`, `title`, `cwd`, `model`, `created_at_ms`,
  and `updated_at_ms`. The numeric filename suffix is not fixed.
- Rollouts: `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl` — uuid is
  the FULL trailing UUID and is joined to `threads.id`. The rollout tree
  determines which sessions are listed; empty seed threads are filtered out.
  Rollout metadata supplies fallback cwd/session ID/model, and file mtime
  supplies the fallback updated time.
- Display label: nonblank `name`, then nonblank `title`, then the nearest
  named ancestor through `thread_spawn_edges`, finally the thread ID. The
  adapter does not derive labels from the first user message.
- Resume: the adapter emits `codex resume <display-title>` when a title is
  available, otherwise `codex resume <uuid>`. Inherited titles may be shared
  by several threads; title-based resume is not a unique identity guarantee.
- Rename: `UPDATE threads SET name = ? WHERE id = ?`, without changing
  `updated_at_ms`, so renaming does not reorder the recency list. If no row
  is updated (including database errors), the current adapter falls back to
  appending `{"id","thread_name","updated_at"}` to `session_index.jsonl`.
  This is a legacy fallback: listing does not read it, and it does not prove
  that the current Codex UI will display the new name.
- New session: the app launches `cd <dir> && codex`; the requested name is
  the window label, not an assigned thread name. The session ID is initially
  unknown. The Codex adapter does not implement programmatic `create()`.

### 5.3 tmux

- Inside tmux, `$TMUX` is set; current session name via
  `tmux display-message -p '#{S}'`; a new window in it via
  `tmux new-window -t <name> -n <label> '<command>'`.

### 5.4 The one-server rule (from the split-brain incident, 2026-09-16)

Never spawn a second bare opencode server against a session id that a live
server already owns: session ids are shared in storage, live turns live in the
server process → two servers on one id = diverged screens. **pinga's opencode
attach commands are always client-mode against the configured shared server**
(`opencode attach <url> -s <id>`), never bare `opencode`. This is a hard design
constraint, not a runtime preference.

## 6. Architecture

```
                       ┌──────────────────────────────┐
  Ollama/API key ─────►│  naming::NameEngine          │  short labels
                       │  base_url + key + model      │◄── seed = title/slug/id
                       └──────────────┬───────────────┘
                                      │ suggest(title) / rename(sess,title)
┌──────────┐  HTTP /session  ┌────────▼───────────────────────────┐
│opencode  │◄── GET/POST ────│  provider::opencode               │
│ :4096    │                 │  list / rename / attach_cmd       │
└──────────┘                 └───────────────┬───────────────────┘
                             provider trait  │ Session list
┌──────────┐  files:          ┌──────────────▼───────────────────┐
│ codex    │◄─state SQLite    │  provider::codex                 │
│ ~/.codex │   + rollouts     │  list / rename(DB) / attach      │
└──────────┘                  └───────────────┬──────────────────┘
                                             │
                        ┌────────────────────▼──────────────────────┐
                        │  tui::app  (ratatui)                      │
                        │  2 scrollable columns  ◄─ refresh loop    │
                        │  arrows + mouse                            │
                        └────────────────────┬──────────────────────┘
                                             │ open(session)
                        ┌────────────────────▼──────────────────────┐
                        │  launcher                                 │
                        │  in tmux?  new-window  :  take the tty    │
                        └───────────────────┬───────────────────────┘
                                            ▼
                     "opencode attach …" | "codex resume …"
```

Three layers, each independently testable:

1. **providers** — turn the §5 surfaces into a shared `Provider` trait;
2. **naming** — suggest a short title from the current title, slug, or ID;
3. **tui + launcher** — present, navigate, and hand off.

The abstraction is partial by design (PA-01): the provider list is a registry
of `Box<dyn Provider>` objects, sessions carry a validated `ProviderId` plus
their opaque native ID, and a small composition function builds the two
built-ins from config. Since Stage 2 the provider contract exposes explicit
capabilities, structured `LaunchRequest`s, an explicit create outcome
(`KnownSession` or `LaunchToCreate`), and provider-owned interpretation of a
generic process snapshot into `WindowMatch` candidates with a match confidence.
The app dispatches new-session/resume generically through the registry and uses
the explicit adoption policy (§11.8) instead of any silent heuristic. The app
still hardcodes the two historical positions, fixed labels/colors/columns, and
numeric provider positions in window tracking — those known couplings remain
for later stages. Pending launches live only in memory until Stage 3.

The refresh loop is a simple poll: on input idle (and right after any
return-to-console or rename) every provider's `list()` is re-run; both columns
re-render from the latest snapshots. A failed refresh is not an empty list: the
last successful snapshot is retained and destructive reconciliation is skipped
for that provider. No threads, no async — `crossterm` `event::poll(timeout)`
doubles as the tick. Provider and naming calls are synchronous and can block
input while they run.

## 7. Module map (chunks → files)

| Chunk | File | Responsibility |
|-------|------|----------------|
| `pkg::manifest` | `Cargo.toml` | deps, metadata |
| `core::config` | `src/config.rs` | config load, env overrides, optional `[[providers]]` |
| `core::model` | `src/model.rs` | `ProviderId`, `SessionKey`, `Session`, launch/creation/evidence types |
| `prov::mod` | `src/provider/mod.rs` | `Provider` trait + capabilities, `ProviderDescriptor`, registry, factories + composition |
| `prov::opencode` | `src/provider/opencode.rs` | §5.1 adapter (HTTP): resume/create/evidence, factory |
| `prov::codex` | `src/provider/codex.rs` | §5.2 adapter (SQLite metadata + rollout files): resume/create/evidence, factory |
| `prov::antigravity` | `src/provider/antigravity.rs` | §5.3 optional adapter (SQLite summary index + `agy` resume/create/evidence), compiled-in, NOT auto-registered |
| `name::engine` | `src/naming.rs` | Ollama/keyed suggestion + heuristic fallback |
| `core::launcher` | `src/launcher.rs` | evidence collector, foreground runner, tmux ops, POSIX-sh serializer, adoption policy |
| `core::tracking` | `src/tracking.rs` | versioned v2 store, locked atomic writes, legacy migration + backup |
| `tui::theme` | `src/tui/theme.rs` | purple/green palette (§14) |
| `tui::app` | `src/tui/app.rs` | the console: per-provider views, viewport, keys, mouse, handoff loop |
| `core::main` | `src/main.rs` | entrypoint: terminal init, run, teardown |

## 8. Decisions (recorded as record, revisit only with evidence)

- **D1 Rust/ratatui.** Alternatives considered: Python/Textual (quick but slow
  startup, heavier runtime for a tool whose whole value is snappiness) and
  Go/bubbletea (Go not installed on eris; same order of effort as Rust). Rust +
  ratatui gives out-of-the-box mouse + scrollable widgets and native tty
  handoff. Revisit if the console grows into something that needs Python's
  ecosystem.
- **D2 HTTP API over SQLite for opencode.** Live-reading `opencode.db` while the
  server writes risks torn reads (we observed title writes not sticking from
  the *API* even — see §5.1; direct DB writes would be worse). Read via
  `GET /session`; rename via verified compat-route probing (§5.1) and verify by
  re-reading.
- **D3 codex rename = update SQLite `threads.name` (revised 2026-09-22).**
  Supersedes the original `session_index.jsonl` design for Codex 0.155.
  Preserve `updated_at_ms`; use the full UUID to address the thread. The
  implementation retains a legacy index append fallback with the limitations
  in §5.2; it does not use the app-server control socket for renaming.
- **D4 Naming is a single `NameEngine`.** One client, two endpoints: local
  `ollama_base_url` (no key) or remote `api_base_url` (with `api_key`); both
  speak the OpenAI-compatible `POST /v1/chat/completions`, so there's one code
  path. When neither is reachable the engine degrades to a heuristic tag —
  the console must still work offline, it just won't suggest well.
- **D5 The launcher decides by `$TMUX`.** Presence of the env var → window; its
  absence → take the terminal. Covered in §10.
- **D6 Palette: opencode=purple, codex=green.** The two accent families are the
  column identities (mnemonic, see §14 for exact values) — everything else is
  neutrals chosen for contrast.
- **D7 Literate workflow = `make tangle` gate.** `src/` is derived. Run
  `make tangle` before `make check`, `make test`, and `make lint`; those three
  targets do not tangle automatically. `make install` does. No CI workflow is
  currently checked in. Prose must also be reviewed against the code chunks:
  tangling alone cannot detect outdated architectural explanations.
- **D8 One window per session, adopt-or-refuse.** Re-opening never spawns a
  duplicate. Priority, per provider: (1) a tmux window pinga created (tracked
  by window id) is selected again; (2) an untracked same-session window whose
  process argv carries the session marker — `-s <id>` in `opencode attach`, or
  the resume name in `codex resume <name>` — is adopted when unambiguous (the
  pane's process tree is walked, so a TUI launched in a shell counts); (3)
  opencode-only fallback: **no `-s` in the argv**, but exactly one `opencode
  attach` window exists and this session is the newest-updated (`opencode`
  bare `attach` binds to the most recent session) -> adopt it; several attach
  windows are refused as ambiguous; one attached to a different session lets
  the requested session open normally. This
  opencode build exposes **no** per-session attachment signal, so anything
  cross-terminal is undetectable and deliberately opens a fresh window
  (documented gap); (4) otherwise a fresh window is created and tracked.
  `f` forces past any refusal. codex has no liveness signal at all: only the
  argv marker can adopt an already-open codex thread. Mouse: single
  click selects, double-click (same cell, ≤ 500 ms) opens; `Enter` always
  opens. Double-open is separate from repeat-open: the guard above is also
  enforced for double-clicks.
- **D9 Provider registry over a closed enum (PA-01 Stage 1).** The provider list
  is a `ProviderRegistry` of `Box<dyn Provider>` keyed by a validated
  `ProviderId`; `ProviderKind` and `AnyProvider` are removed. Session identity is
  `SessionKey = (ProviderId, native id)`. A built-in composition function builds
  exactly OpenCode then Codex from existing config. Registry index access
  survives only for the app's transitional two-provider UI/tracking order.
- **D10 Structured launches, explicit creation, and evidence-based adoption
  (PA-01 Stage 2).** `attach_command`/server-only-`create` are replaced by
  explicit `ProviderCapabilities`, a pure `resume_plan` returning a structured
  `LaunchRequest` (no shell fragment), and `create` returning
  `CreateOutcome::KnownSession | LaunchToCreate`. Providers own interpretation of
  a generic `ProcessEvidence` snapshot into `WindowMatch` candidates with a match
  confidence. The launcher serializes once to POSIX `sh` at the tmux boundary and
  runs foreground launches via `Command`. The explicit `decide_open` policy
  replaces the old silent newest-session auto-adoption with an uncertainty
  warning + force-to-open. New-session and resume dispatch generically; pending
  (launch-to-create) launches are in-memory only until Stage 3.

## 9. Data contracts

### 9.1 `Session` (provider-agnostic)

```text
provider_id ProviderId          # validated instance id (opencode | codex | …)
id          ses_… | <codex thread uuid>
title       Option<String>      # codex: name -> title -> ancestor label
slug        Option<String>      # opencode only
directory, session_id, agent, model: Option<String>
created_ms, updated_ms: Option<u64>
active      bool
```

`display_title()`: `title` → `slug` → full `id`. `short_id()` is a separate
helper. Codex labels can be inherited from an ancestor (§5.2); they are not
necessarily the thread's own name or a unique identifier. `SessionKey` pairs a
`ProviderId` with a nonempty native `id`; labels never substitute for identity.

### 9.2 `Provider`

```text
descriptor()             -> ProviderDescriptor   # id + type key + display name
capabilities()           -> ProviderCapabilities # rename/resume + new-session (title/cwd semantics)
list()                   -> Result<Vec<Session>>
rename(&Session,&str)    -> Result<()>   # opencode verifies; codex has legacy fallback
resume_plan(&Session)    -> Result<LaunchRequest>   # pure plan, no side effects
create(name, dir)        -> Result<CreateOutcome>   # KnownSession | LaunchToCreate
match_session(&Session,&[Session],&ProcessEvidence) -> Vec<WindowMatch>
```

`ProviderDescriptor` identity must match the `provider_id` stamped on the
provider's sessions. Unsupported operations return an identifiable `Unsupported`
error (distinct from operational failure). A `LaunchRequest` is a structured
executable/argv/cwd/env plan with no shell fragment; a `CreateOutcome` is either
a known server-side session or a plan to launch a client that mints an
initially-unknown session. OpenCode posts the title and directory to `/session`
(returns a known session; the server ignores the requested cwd), while Codex
returns a launch-to-create plan (`codex` in the requested cwd; title is a window
label only).

### 9.3 `NameEngine`

```text
suggest(seed: &str) -> String   # ≤ 40 chars, no quotes/newlines
configured?  base_url + key + model  → remote path
otherwise    call heuristic(seed)     → kebab of up to 6 words
```

The suggestion prompt (system turn) is:
"Answer with a short, descriptive session title, 2-6 words. No quotes, no
markdown, no punctuation explosion." + one user turn with the seed.

## 10. Handoff semantics (R9/R10)

Conceptual flow across the app's guarded open and launcher helpers:

```text
if in_tmux():
    session_name = tmux display-message -p '#{S}'            # current
    tmux new-window -t <session_name> -n <label> '<cmd>'     # R9
else:
    suspend()          # disable raw mode + mouse capture, show cursor (R10)
    run_in_foreground('<cmd>')  # sh -c, inherited stdio; blocks
    restore()          # restore raw/mouse, clear screen, request full redraw
    refresh()          # lists may have changed under us
```

The current `suspend_for` disables raw mode and mouse capture, shows the
cursor, runs the child with inherited stdio, then restores raw mode and mouse
capture as configured. It clears the screen and requests a full repaint.
It does not leave/re-enter the alternate screen around the child. This is the
"pass control, return when it exits" behavior of R10:
`opencode attach` / `codex resume` are TUI clients that exit on quit.

## 11. The literate implementation

The chunks below are the source. Prose between them explains why each file
looks the way it does. Tangle in document order; every `path=` opens/creates a
file, later occurrences append.

### 11.1 Package manifest

**Dependencies are deliberately small**: `ratatui`/`crossterm` for the
console, `ureq` for sync HTTP to the opencode server and the name engines,
`serde*`/`toml` for config and JSON, `dirs`/`anyhow` for ergonomics. No async
runtime.

``` {.toml #pkg-manifest path="Cargo.toml"}
[package]
name = "pinga"
version = "0.1.0"
edition = "2021"
description = "TUI console managing opencode and codex sessions"

[dependencies]
anyhow = "1"
crossterm = "0.28"
dirs = "5"
ratatui = "0.29"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
toml = "0.8"
unicode-width = "0.1"
fs2 = "0.4"
rusqlite = { version = "0.31", features = ["bundled"] }
ureq = { version = "2", default-features = false, features = ["json"] }
```

### 11.2 Configuration (`core::config`)

Reading order: default `~/.config/pinga/config.toml` (parsed leniently), then
environment overrides. `PINGA_API_KEY` is the primary secret channel so the
key never needs to live in the repo the keyboard trusts least.

``` {.rust #core-config path="src/config.rs"}
use serde::Deserialize;
use std::collections::BTreeMap;
use std::path::PathBuf;

/// One configured provider instance (Stage 3). `id` and `type` are required;
/// `label`, `enabled`, and `options` are optional. IDs must be unique across
/// ALL entries, including disabled ones.
#[derive(Debug, Clone, Deserialize)]
pub struct ProviderEntry {
    pub id: String,
    #[serde(rename = "type")]
    pub type_key: String,
    #[serde(default)]
    pub label: Option<String>,
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default)]
    pub options: BTreeMap<String, toml::Value>,
}

fn default_true() -> bool { true }

/// Adapter-specific options, carried generically by config and decoded by the
/// compiled-in factory for each `type`.
pub type ProviderOptions = BTreeMap<String, toml::Value>;

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct Config {
    pub opencode_url: String,          // legacy shared opencode server base URL
    pub codex_home: PathBuf,           // legacy ~/.codex
    /// Optional ordered provider configuration. When present (even empty), it is
    /// authoritative and legacy opencode_url/codex_home and PINGA_OPENCODE_URL do
    /// NOT override its options. When absent, legacy defaults apply.
    pub providers: Option<Vec<ProviderEntry>>,
    pub ollama_base_url: Option<String>, // local engine (no key)
    pub ollama_model: Option<String>,
    pub api_base_url: Option<String>,  // keyed OpenAI-compatible engine
    pub api_model: Option<String>,
    pub api_key: Option<String>,
    pub auto_rename: bool,             // auto-suggest names for newer sessions
    pub refresh_secs: u64,
    pub theme: String,                 // "magic" (the purple/green palette)
    pub list_detail: String,           // "two-line" (default) | "bottom" — codex row layout
    pub forms: String,                 // "modal" (default) | "inline" — form dialog style
}

impl Default for Config {
    fn default() -> Self {
        let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("."));
        Self {
            opencode_url: "http://127.0.0.1:4096".into(),
            codex_home: home.join(".codex"),
            providers: None,
            ollama_base_url: Some("http://127.0.0.1:11434".into()),
            ollama_model: Some("llama3.2".into()),
            api_base_url: None,
            api_model: None,
            api_key: None,
            auto_rename: false,
            refresh_secs: 5,
            theme: "magic".into(),
            list_detail: "two-line".into(),
            forms: "modal".into(),
        }
    }
}

impl Config {
    /// Load config from `$PINGA_CONFIG` (missing file there is an ERROR, never a
    /// silent default) or the default config path (missing file uses defaults).
    /// Invalid TOML, unknown provider types/options, duplicate or invalid IDs,
    /// and blank labels are hard errors; explicit providers are authoritative.
    pub fn load() -> anyhow::Result<Self> {
        let explicit = std::env::var("PINGA_CONFIG").ok();
        let path = match &explicit {
            Some(p) => PathBuf::from(p),
            None => dirs::config_dir().unwrap_or_default().join("pinga/config.toml"),
        };
        let raw = match std::fs::read_to_string(&path) {
            Ok(r) => r,
            Err(e) if explicit.is_some() => {
                return Err(anyhow::anyhow!("cannot read config {}: {e}", path.display()));
            }
            // Only a missing DEFAULT config permits defaults; permission/read
            // errors must fail rather than silently degrade.
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => String::new(),
            Err(e) => return Err(anyhow::anyhow!("cannot read config {}: {e}", path.display())),
        };
        let mut cfg: Config = toml::from_str(&raw).map_err(|e| {
            // Avoid echoing raw TOML source lines (which may contain secrets):
            // keep only the message header (line/column) from the parser.
            let head = e.to_string().lines().next().unwrap_or("invalid TOML").to_string();
            anyhow::anyhow!("invalid config {}: {head}", path.display())
        })?;
        if let Ok(k) = std::env::var("PINGA_API_KEY") { cfg.api_key = Some(k); }
        if cfg.providers.is_none() {
            // Legacy mode: env overrides still apply to the legacy fields.
            if let Ok(u) = std::env::var("PINGA_OPENCODE_URL") { cfg.opencode_url = u; }
        }
        if let Ok(m) = std::env::var("PINGA_MODEL") {
            if cfg.ollama_base_url.is_some() { cfg.ollama_model = Some(m.clone()); }
            if cfg.api_base_url.is_some() { cfg.api_model = Some(m); }
        }
        cfg.validate()?;
        Ok(cfg)
    }

    /// Validate explicit provider entries: unique IDs (including disabled),
    /// valid ID syntax, non-blank labels, and enabled-only option checks.
    pub fn validate(&self) -> anyhow::Result<()> {
        let Some(entries) = &self.providers else { return Ok(()) };
        let mut seen = std::collections::HashSet::new();
        for e in entries {
            crate::model::ProviderId::new(&e.id)
                .map_err(|_| anyhow::anyhow!("invalid provider id {:?}", e.id))?;
            if !seen.insert(e.id.clone()) {
                return Err(anyhow::anyhow!("duplicate provider id {:?}", e.id));
            }
            if let Some(l) = &e.label {
                if l.trim().is_empty() {
                    return Err(anyhow::anyhow!("blank label for provider {:?}", e.id));
                }
            }
            // Unknown types and unknown options are errors even when disabled
            // (so typos do not become latent), enforced by the factory boundary.
            crate::provider::validate_entry(e)?;
        }
        Ok(())
    }

    /// Preferred engine parameters: (base_url, Optional API key, model).
    pub fn naming_endpoint(&self) -> Option<(String, Option<String>, String)> {
        if let (Some(base), Some(model)) = (&self.ollama_base_url, &self.ollama_model) {
            return Some((base.clone(), None, model.clone()));
        }
        if let (Some(base), Some(model)) = (&self.api_base_url, &self.api_model) {
            return Some((base.clone(), self.api_key.clone(), model.clone()));
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn load_str(s: &str) -> anyhow::Result<Config> {
        let cfg: Config = toml::from_str(s)
            .map_err(|e| anyhow::anyhow!("toml: {e}"))?;
        cfg.validate()?;
        Ok(cfg)
    }

    #[test]
    fn absent_config_defaults() {
        // Default Config has no explicit providers -> legacy mode.
        assert!(Config::default().providers.is_none());
        assert_eq!(Config::default().opencode_url, "http://127.0.0.1:4096");
    }

    #[test]
    fn explicit_empty_providers_is_authoritative_empty() {
        let cfg = load_str("providers = []").unwrap();
        assert_eq!(cfg.providers.as_ref().map(Vec::len), Some(0));
    }

    #[test]
    fn two_instances_of_one_type_with_distinct_options() {
        let cfg = load_str(r#"
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
        "#).unwrap();
        let e = cfg.providers.as_ref().unwrap();
        assert_eq!(e.len(), 2);
        assert_eq!(e[0].id, "work");
        assert_eq!(e[0].type_key, "opencode");
        assert_eq!(e[0].label.as_deref(), Some("Work"));
        assert_eq!(e[0].options["url"].as_str(), Some("http://127.0.0.1:4096"));
        assert!(e[1].enabled);
    }

    #[test]
    fn duplicate_ids_rejected_even_with_different_types() {
        assert!(load_str(r#"
            [[providers]]
            id = "same"
            type = "opencode"
            [providers.options]
            url = "http://a"

            [[providers]]
            id = "same"
            type = "codex"
            [providers.options]
            home = "/tmp"
        "#).is_err());
    }

    #[test]
    fn disabled_entries_still_validated() {
        // Disabled entry with an invalid id is still rejected (not latent).
        assert!(load_str(r#"
            [[providers]]
            id = "bad id"
            type = "opencode"
            enabled = false
        "#).is_err());
        // Disabled entry with an unknown type is still rejected.
        assert!(load_str(r#"
            [[providers]]
            id = "x"
            type = "nope"
            enabled = false
        "#).is_err());
        // Valid disabled entry parses.
        let cfg = load_str(r#"
            [[providers]]
            id = "off"
            type = "codex"
            enabled = false
            [providers.options]
            home = "/tmp/off"
        "#).unwrap();
        assert!(!cfg.providers.as_ref().unwrap()[0].enabled);
    }

    #[test]
    fn antigravity_is_a_registered_factory_type_not_auto_registered() {
        // The optional antigravity adapter is compiled-in: an explicit entry
        // with type "antigravity" validates (home optional, defaults to the
        // product data dir). It is NOT in builtin_registry, so absent explicit
        // providers the default registry stays opencode + codex only.
        let cfg = load_str(r#"
            [[providers]]
            id = "agy"
            type = "antigravity"
            label = "Antigravity"
        "#).unwrap();
        let e = cfg.providers.as_ref().unwrap();
        assert_eq!(e[0].type_key, "antigravity");
        // Enabled explicit entry builds through the factory boundary.
        let reg = crate::provider::build_registry(&cfg).unwrap();
        assert_eq!(reg.len(), 1);
        assert!(reg.get(&crate::model::ProviderId::new("agy").unwrap()).is_some());
        // Legacy default composition never includes it.
        let legacy = crate::provider::builtin_registry(&Config::default()).unwrap();
        assert!(legacy.iter().all(|p| p.descriptor().type_key != "antigravity"));
    }

    #[test]
    fn antigravity_two_configured_homes_are_distinct_instances() {
        // A COMPLETE opt-in config: the existing OpenCode + Codex providers are
        // PRESERVED (an explicit provider list replaces the defaults), and two
        // antigravity instances on DIFFERENT data dirs coexist as distinct
        // instances with their own ids/labels/sources.
        let cfg = load_str(r#"
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

            [[providers]]
            id = "agy-main"
            type = "antigravity"
            label = "Antigravity"
            [providers.options]
            home = "/home/edgar/.gemini/antigravity-cli"

            [[providers]]
            id = "agy-other"
            type = "antigravity"
            label = "Other"
            [providers.options]
            home = "/tmp/other-antigravity"
        "#).unwrap();
        let e = cfg.providers.as_ref().unwrap();
        assert_eq!(e.len(), 4);
        // The explicit list is authoritative and preserves the legacy providers.
        let reg = crate::provider::build_registry(&cfg).unwrap();
        assert_eq!(reg.len(), 4);
        let types: Vec<&str> = reg.iter().map(|p| p.descriptor().type_key).collect();
        assert!(types.iter().filter(|t| **t == "antigravity").count() == 2);
        assert!(types.contains(&"opencode") && types.contains(&"codex"));
        // Each antigravity instance pins its OWN source env so launches never
        // cross data dirs.
        let main = reg.get(&crate::model::ProviderId::new("agy-main").unwrap()).unwrap();
        let other = reg.get(&crate::model::ProviderId::new("agy-other").unwrap()).unwrap();
        let s = crate::model::Session {
            provider_id: crate::model::ProviderId::new("agy-main").unwrap(),
            id: "sess".into(), title: None, slug: None, directory: None,
            session_id: None, agent: None, model: None, created_ms: None,
            updated_ms: None, active: false,
        };
        let plan = main.resume_plan(&s).unwrap();
        assert!(plan.env.iter().any(|(k, v)| k == "ANTIGRAVITY_APP_DATA_DIR"
            && v == "/home/edgar/.gemini/antigravity-cli"));
        let plan2 = other.resume_plan(&s).unwrap();
        assert!(plan2.env.iter().any(|(k, v)| k == "ANTIGRAVITY_APP_DATA_DIR"
            && v == "/tmp/other-antigravity"));
        // Rename is honestly unsupported on the antigravity adapter.
        assert!(!main.capabilities().rename);
        let err = main.rename(&s, "X").err().unwrap();
        assert!(err.to_string().contains("unsupported"), "rename unsupported: {err}");
    }

    #[test]
    fn blank_label_rejected() {
        assert!(load_str(r#"
            [[providers]]
            id = "a"
            type = "opencode"
            label = "  "
            [providers.options]
            url = "http://x"
        "#).is_err());
    }
}
```

### 11.3 The session model (`core::model`)

A tiny, provider-agnostic view. `display_title`, `short_id`, and `age` keep the
TUI free of formatting policy.

``` {.rust #core-model path="src/model.rs"}
use std::fmt;
use std::time::{SystemTime, UNIX_EPOCH};

/// A validated, owned identifier for a configured provider instance. Distinct
/// from the display label and from the position in the registry. Accepts
/// nonempty lowercase ASCII letters/digits plus `.`, `_`, `-`; rejects
/// whitespace and any other character.
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord, serde::Serialize, serde::Deserialize)]
pub struct ProviderId(String);

impl ProviderId {
    pub fn new(s: &str) -> anyhow::Result<Self> {
        let valid = !s.is_empty()
            && s.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit()
                || c == '.' || c == '_' || c == '-');
        if valid {
            Ok(ProviderId(s.to_string()))
        } else {
            Err(anyhow::anyhow!("invalid provider id {s:?}"))
        }
    }
    pub fn as_str(&self) -> &str { &self.0 }
}

impl fmt::Display for ProviderId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// Stable identity of a known session: the provider instance plus its opaque
/// native session ID. Labels and inherited titles never substitute for this.
/// A known key always carries a nonempty native ID.
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct SessionKey {
    provider: ProviderId,
    native_id: String,
}

impl SessionKey {
    pub fn new(provider: ProviderId, native_id: String) -> anyhow::Result<Self> {
        if native_id.is_empty() {
            return Err(anyhow::anyhow!("session key requires a nonempty native id"));
        }
        Ok(SessionKey { provider, native_id })
    }

    pub fn provider(&self) -> &ProviderId { &self.provider }
    pub fn native_id(&self) -> &str { &self.native_id }
}

#[derive(Debug, Clone)]
pub struct Session {
    pub provider_id: ProviderId,
    pub id: String,
    pub title: Option<String>,
    pub slug: Option<String>,
    pub directory: Option<String>,
    pub session_id: Option<String>,   // codex's session (may group several threads)
    pub agent: Option<String>,
    pub model: Option<String>,
    pub created_ms: Option<u64>,
    pub updated_ms: Option<u64>,
    pub active: bool,
}

impl Session {
    pub fn display_title(&self) -> &str {
        self.title.as_deref()
            .or(self.slug.as_deref())
            .unwrap_or(&self.id)
    }

    pub fn short_id(&self) -> String {
        if self.id.len() <= 12 { return self.id.clone(); }
        self.id[..12].to_string()
    }

    pub fn age(&self, now_ms: u64) -> String {
        let Some(up) = self.updated_ms else { return "?".into() };
        let s = now_ms.saturating_sub(up) / 1000;
        if s < 60 { format!("{s}s") }
        else if s < 3600 { format!("{}m", s / 60) }
        else if s < 86_400 { format!("{}h", s / 3600) }
        else { format!("{}d", s / 86_400) }
    }
}

/// "Now" in the same `u64` epoch-millis scale providers use.
pub fn now_ms() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0)
}

/// A structured launch request: executable, argument vector, optional working
/// directory, and explicit environment overrides. There is no executable shell
/// fragment; providers never serialize to shell text themselves, and the
/// launcher serializes at the tmux boundary only.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LaunchRequest {
    pub program: String,
    pub args: Vec<String>,
    pub cwd: Option<String>,
    pub env: Vec<(String, String)>,
}

/// The outcome of asking a provider to create a new session: either a known
/// server-side session, or a plan to launch a client that will mint a session
/// whose ID is initially unknown.
#[derive(Debug, Clone)]
pub enum CreateOutcome {
    KnownSession(Session),
    LaunchToCreate(LaunchRequest),
}

/// How confidently a window's process evidence identifies a particular session.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MatchConfidence {
    Confirmed,
    Heuristic,
    Ambiguous,
}

/// A candidate window a provider says may be running the session in question,
/// with the confidence of that identification.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WindowMatch {
    pub window_id: String,
    pub confidence: MatchConfidence,
}

/// One process's real argument vector (NUL-delimited, never whitespace-split)
/// plus a narrowly selected set of source metadata environment values (e.g.
/// `CODEX_HOME`). Full process environments are never collected.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProcEvidence {
    pub pid: u64,
    pub argv: Vec<String>,
    pub env: Vec<(String, String)>,
}

/// One tmux window's process evidence.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WindowEvidence {
    pub window_id: String,
    pub procs: Vec<ProcEvidence>,
}

/// A generic snapshot of windows and process argument vectors plus how complete
/// the inspection was. The collector contains no provider or executable rules;
/// providers interpret this in their own syntax.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ProcessEvidence {
    pub windows: Vec<WindowEvidence>,
    pub complete: bool,
    pub errors: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn provider_id_accepts_documented_syntax() {
        for ok in ["opencode", "codex", "my-provider_2", "a.b-c", "a"] {
            let id = ProviderId::new(ok).expect("should accept");
            assert_eq!(id.as_str(), ok);
            assert_eq!(id.to_string(), ok);
        }
    }

    #[test]
    fn provider_id_rejects_invalid_ids() {
        for bad in ["", "OpenCode", "two words", "trailing ", "semi;", "sla/sh", "🚀", "t\u{20}ab"] {
            assert!(ProviderId::new(bad).is_err(), "{bad:?} should be rejected");
        }
    }

    #[test]
    fn session_key_distinguishes_providers_and_rejects_empty_native() {
        let a = ProviderId::new("a").unwrap();
        let b = ProviderId::new("b").unwrap();
        let key1 = SessionKey::new(a.clone(), "same-native".into()).unwrap();
        let key2 = SessionKey::new(b, "same-native".into()).unwrap();
        assert_ne!(key1, key2);
        assert_eq!(key1, SessionKey::new(a, "same-native".into()).unwrap());
        assert!(SessionKey::new(ProviderId::new("a").unwrap(), String::new()).is_err());
        // Immutable accessors reflect the validated construction.
        let key = SessionKey::new(ProviderId::new("a").unwrap(), "n1".into()).unwrap();
        assert_eq!(key.provider(), &ProviderId::new("a").unwrap());
        assert_eq!(key.native_id(), "n1");
    }
}
```

### 11.4 The provider trait (`prov::mod`)

`Provider` is the seam that keeps §5 knowledge inside two adapters and the
console free of opencode/codex specifics. Since PA-01 Stage 2 the contract
carries explicit capabilities, a pure `resume_plan` returning a structured
`LaunchRequest` (no shell fragment), an explicit `create` outcome
(`KnownSession` or `LaunchToCreate`), and provider-owned interpretation of a
generic `ProcessEvidence` snapshot into `WindowMatch` candidates with a match
confidence. Unsupported operations are an identifiable `Unsupported` error,
distinct from an operational failure. The adapters are boxed in a
`ProviderRegistry` keyed by a validated `ProviderId`; a `ProviderDescriptor`
exposes each instance's ID, type key, and display name, and a `builtin_registry`
composition function constructs OpenCode then Codex from config.

``` {.rust #prov-mod path="src/provider/mod.rs"}
pub mod antigravity;
pub mod codex;
pub mod opencode;

use std::collections::HashMap;
use std::fmt;

use crate::config::{Config, ProviderEntry, ProviderOptions};
use crate::model::{
    CreateOutcome, LaunchRequest, ProcessEvidence, ProviderId, Session, WindowMatch,
};

/// Immutable metadata about a registered provider instance: its validated
/// instance ID, a stable type key (`opencode`/`codex`), and a display name
/// (configured label or the adapter default). Descriptor identity must match
/// the `provider_id` stamped on its sessions.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProviderDescriptor {
    pub id: ProviderId,
    pub type_key: &'static str,
    pub display_name: String,
}

/// What a new-session request means for a harness: whether it maps onto a known
/// server-side session or a client-launch plan, and which of the requested
/// title/working-directory the harness honors as native session metadata.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NewSessionCapability {
    pub supported: bool,
    /// Whether creation applies the requested native title to the session.
    pub applies_title: bool,
    /// Whether creation applies the requested working directory.
    pub applies_cwd: bool,
}

/// Explicit capabilities that drive which actions/affordances are available.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ProviderCapabilities {
    pub rename: bool,
    pub resume: bool,
    pub new_session: NewSessionCapability,
}

/// An identifiable "unsupported" category, distinct from an operational failure.
/// Carried inside an anyhow error so `err.downcast_ref::<Unsupported>()`
/// distinguishes the two.
#[derive(Debug)]
pub struct Unsupported { pub what: &'static str }

impl fmt::Display for Unsupported {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "unsupported operation: {}", self.what)
    }
}
impl std::error::Error for Unsupported {}

pub fn unsupported(what: &'static str) -> anyhow::Error {
    anyhow::Error::new(Unsupported { what })
}

/// Reject a session that does not belong to `provider` before any side effect.
pub fn check_session_belongs(provider: &dyn Provider, session: &Session) -> anyhow::Result<()> {
    let expect = provider.descriptor().id;
    if session.provider_id == expect {
        Ok(())
    } else {
        Err(anyhow::anyhow!(
            "session {} belongs to {}, not {}", session.id, session.provider_id, expect))
    }
}

pub trait Provider: Send + Sync {
    fn descriptor(&self) -> ProviderDescriptor;
    fn capabilities(&self) -> ProviderCapabilities;
    fn list(&self) -> anyhow::Result<Vec<Session>>;
    fn rename(&self, _session: &Session, _title: &str) -> anyhow::Result<()> {
        Err(unsupported("rename"))
    }
    /// A pure resume plan (no side effects) for an existing session.
    fn resume_plan(&self, _session: &Session) -> anyhow::Result<LaunchRequest> {
        Err(unsupported("resume"))
    }
    /// Create a new session, returning a known session or a launch-to-create plan.
    fn create(&self, _name: &str, _dir: &str) -> anyhow::Result<CreateOutcome> {
        Err(unsupported("new session"))
    }
    /// Interpret a generic process snapshot for one session, returning candidate
    /// windows and their match confidence. `snapshot` is the provider's current
    /// successful listing, used for label-uniqueness checks.
    fn match_session(
        &self,
        _session: &Session,
        _snapshot: &[Session],
        _evidence: &ProcessEvidence,
    ) -> Vec<WindowMatch> {
        Vec::new()
    }
}

/// Owns the boxed provider objects in deterministic registration order. Lookup
/// is by instance ID; duplicate registration is rejected and never overwrites
/// or reorders the existing registrations.
#[derive(Default)]
pub struct ProviderRegistry {
    providers: Vec<Box<dyn Provider>>,
}

impl ProviderRegistry {
    pub fn new() -> Self { Self::default() }

    pub fn register(&mut self, provider: Box<dyn Provider>) -> anyhow::Result<()> {
        let id = provider.descriptor().id;
        if self.providers.iter().any(|p| p.descriptor().id == id) {
            return Err(anyhow::anyhow!("duplicate provider id {id}"));
        }
        self.providers.push(provider);
        Ok(())
    }

    /// Lookup by instance ID; returns None (never a fallback) when unknown.
    pub fn get(&self, id: &ProviderId) -> Option<&dyn Provider> {
        self.providers.iter().find(|p| p.descriptor().id == *id).map(|p| p.as_ref())
    }

    /// Ordered access by registration index. The app's UI and numeric tracking
    /// still rely on the historical two-provider order during this transitional
    /// stage, so index access is retained here for that consumer.
    pub fn get_index(&self, i: usize) -> Option<&dyn Provider> {
        self.providers.get(i).map(|p| p.as_ref())
    }

    pub fn iter(&self) -> impl Iterator<Item = &dyn Provider> {
        self.providers.iter().map(|p| p.as_ref())
    }

    pub fn len(&self) -> usize { self.providers.len() }
    pub fn is_empty(&self) -> bool { self.providers.is_empty() }
}

/// The built-in composition boundary: build the historical OpenCode-then-Codex
/// registry from legacy config fields. Errors propagate rather than silently
/// skipping either adapter.
pub fn builtin_registry(cfg: &Config) -> anyhow::Result<ProviderRegistry> {
    let mut reg = ProviderRegistry::new();
    reg.register(Box::new(opencode::OpencodeProvider::new(
        &cfg.opencode_url, ProviderId::new("opencode")?)))?;
    reg.register(Box::new(codex::CodexProvider::new(
        &cfg.codex_home, ProviderId::new("codex")?)))?;
    Ok(reg)
}

/// A compiled-in factory: build a provider instance from validated options.
/// Adapter-specific options are decoded and validated at this boundary.
pub type Factory = fn(id: ProviderId, label: Option<String>, options: &ProviderOptions)
    -> anyhow::Result<Box<dyn Provider>>;

/// The small compiled-in type-key -> factory registry.
fn factories() -> HashMap<&'static str, Factory> {
    let mut m = HashMap::new();
    m.insert("opencode", opencode::OpencodeProvider::factory as Factory);
    m.insert("codex", codex::CodexProvider::factory as Factory);
    m.insert("antigravity", antigravity::AntigravityProvider::factory as Factory);
    m
}

/// Validate one configured entry at the factory boundary: the type must exist
/// and its options must decode, so typos do not become latent — even for
/// disabled entries (which are validated but never instantiated or polled).
pub fn validate_entry(entry: &ProviderEntry) -> anyhow::Result<()> {
    let table = factories();
    let f = *table.get(entry.type_key.as_str()).ok_or_else(|| {
        anyhow::anyhow!("unknown provider type {:?}", entry.type_key)
    })?;
    // Decode/validate options without constructing a live adapter.
    let _ = (f)(ProviderId::new(&entry.id)?, entry.label.clone(), &entry.options)?;
    Ok(())
}

/// Build the registry from configuration. Explicit `providers` (even empty) is
/// authoritative; its entries are validated, disabled entries are skipped, and
/// options are decoded per type. When `providers` is absent, legacy defaults,
/// fields, and environment overrides apply in the historical order.
pub fn build_registry(cfg: &Config) -> anyhow::Result<ProviderRegistry> {
    let Some(entries) = &cfg.providers else {
        return builtin_registry(cfg);
    };
    let mut reg = ProviderRegistry::new();
    for e in entries {
        let id = ProviderId::new(&e.id)
            .map_err(|_| anyhow::anyhow!("invalid provider id {:?}", e.id))?;
        if !e.enabled { continue; }
        let table = factories();
        let f = *table.get(e.type_key.as_str()).ok_or_else(|| {
            anyhow::anyhow!("unknown provider type {:?}", e.type_key)
        })?;
        let provider = (f)(id, e.label.clone(), &e.options)?;
        reg.register(provider)?;
    }
    Ok(reg)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{MatchConfidence, ProcEvidence, ProcessEvidence, Session, WindowEvidence};
    use rusqlite::Connection;
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::sync::Mutex;

    #[derive(Clone, Copy, PartialEq, Eq)]
    enum CreateMode { Known, LaunchToCreate, Unsupported }

    /// A scriptable fake adapter so registry behavior and the Stage 2 contract
    /// are exercised without any live server, codex home, tmux server, or API.
    struct Fake {
        id: &'static str,
        create_mode: CreateMode,
        resume_ok: bool,
        renamed: Mutex<Vec<(String, String)>>,
    }

    impl Fake {
        fn new(id: &'static str) -> Self {
            Self { id, create_mode: CreateMode::Unsupported, resume_ok: false,
                   renamed: Mutex::new(Vec::new()) }
        }
    }

    impl Provider for Fake {
        fn descriptor(&self) -> ProviderDescriptor {
            ProviderDescriptor { id: ProviderId::new(self.id).expect("fake id valid"),
                                 type_key: "fake", display_name: self.id.to_string() }
        }
        fn capabilities(&self) -> ProviderCapabilities {
            ProviderCapabilities {
                rename: true,
                resume: self.resume_ok,
                new_session: NewSessionCapability {
                    supported: self.create_mode != CreateMode::Unsupported,
                    applies_title: false,
                    applies_cwd: false,
                },
            }
        }
        fn list(&self) -> anyhow::Result<Vec<Session>> { Ok(Vec::new()) }
        fn rename(&self, s: &Session, t: &str) -> anyhow::Result<()> {
            self.renamed.lock().unwrap().push((s.id.clone(), t.to_string()));
            Ok(())
        }
        fn resume_plan(&self, _s: &Session) -> anyhow::Result<LaunchRequest> {
            if self.resume_ok {
                Ok(LaunchRequest { program: self.id.into(), args: vec!["resume".into()],
                                   cwd: None, env: vec![] })
            } else {
                Err(unsupported("resume"))
            }
        }
        fn create(&self, _name: &str, _dir: &str) -> anyhow::Result<CreateOutcome> {
            match self.create_mode {
                CreateMode::Known => Ok(CreateOutcome::KnownSession(fake_session(self.id, "known-1"))),
                CreateMode::LaunchToCreate => Ok(CreateOutcome::LaunchToCreate(LaunchRequest {
                    program: self.id.into(), args: vec![], cwd: Some("/tmp".into()), env: vec![],
                })),
                CreateMode::Unsupported => Err(unsupported("new session")),
            }
        }
        fn match_session(&self, s: &Session, _snap: &[Session], ev: &ProcessEvidence) -> Vec<WindowMatch> {
            let mut out = Vec::new();
            for w in &ev.windows {
                if w.procs.iter().any(|p| p.argv.first().map(|a| a == self.id).unwrap_or(false)
                    && p.argv.iter().any(|a| a == &s.id)) {
                    out.push(WindowMatch { window_id: w.window_id.clone(), confidence: MatchConfidence::Confirmed });
                }
            }
            out
        }
    }

    fn fake_session(fake_id: &str, native: &str) -> Session {
        Session {
            provider_id: ProviderId::new(fake_id).expect("valid"),
            id: native.to_string(),
            title: None, slug: None, directory: None, session_id: None,
            agent: None, model: None, created_ms: None, updated_ms: None, active: false,
        }
    }

    struct TempDir(PathBuf);

    impl TempDir {
        fn new() -> Self {
            let nanos = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default().as_nanos();
            let p = std::env::temp_dir().join(format!("pinga-registry-test-{}-{}", std::process::id(), nanos));
            std::fs::create_dir_all(&p).expect("create temp dir");
            TempDir(p)
        }
        fn path(&self) -> &Path { &self.0 }
    }

    impl Drop for TempDir {
        fn drop(&mut self) { let _ = std::fs::remove_dir_all(&self.0); }
    }

    const UUID: &str = "11111111-2222-3333-4444-555555555555";

    fn write_codex_fixture(home: &Path) {
        let day = home.join("sessions").join("2026").join("09").join("22");
        fs::create_dir_all(&day).expect("rollout dirs");
        fs::write(day.join(format!("rollout-2026-09-22T00-00-00-{UUID}.jsonl")), concat!(
            "{\"type\":\"session_meta\",\"payload\":{\"cwd\":\"/tmp\",\"session_id\":\"sess1\",\"model\":\"model-x\"}}\n",
            "{\"type\":\"user\",\"payload\":{\"content\":\"hi\"}}\n",
        )).expect("write rollout");
        let conn = Connection::open(home.join("state_0.sqlite")).expect("open db");
        conn.execute_batch(&format!(
            "CREATE TABLE threads (id TEXT PRIMARY KEY, name TEXT, title TEXT, cwd TEXT, model TEXT, created_at_ms INTEGER, updated_at_ms INTEGER); \
             INSERT INTO threads (id, name, cwd, model, created_at_ms, updated_at_ms) VALUES ('{UUID}', 'Fixture Name', '/tmp', 'model-x', 1, 2);"
        )).expect("seed threads");
    }

    #[test]
    fn registry_supports_three_fakes_in_insertion_order() {
        let mut reg = ProviderRegistry::new();
        for id in ["one", "two", "three"] {
            reg.register(Box::new(Fake::new(id))).expect("register");
        }
        assert_eq!(reg.len(), 3);
        let ids: Vec<String> = reg.iter().map(|p| p.descriptor().id.to_string()).collect();
        assert_eq!(ids, ["one", "two", "three"]);
    }

    #[test]
    fn duplicate_registration_fails_without_replacing_the_original() {
        let mut reg = ProviderRegistry::new();
        let mut orig = Fake::new("one");
        orig.create_mode = CreateMode::Known;
        reg.register(Box::new(orig)).expect("register");
        // A distinguishable replacement with the same id must be rejected and
        // the original's behavior retained.
        let mut replacement = Fake::new("one");
        replacement.create_mode = CreateMode::LaunchToCreate;
        assert!(reg.register(Box::new(replacement)).is_err());
        assert_eq!(reg.len(), 1);
        let one = reg.get(&ProviderId::new("one").expect("valid")).expect("present");
        match one.create("n", "d").unwrap() {
            CreateOutcome::KnownSession(_) => {}
            _ => panic!("original create behavior must remain after rejected duplicate"),
        }
    }

    #[test]
    fn unknown_lookup_is_absent() {
        let mut reg = ProviderRegistry::new();
        reg.register(Box::new(Fake::new("one"))).expect("register");
        assert!(reg.get(&ProviderId::new("nope").expect("valid")).is_none());
        assert!(reg.get_index(1).is_none());
    }

    #[test]
    fn lookup_dispatches_operations_and_distinguishes_unsupported() {
        let mut reg = ProviderRegistry::new();
        let mut a = Fake::new("alpha");
        a.resume_ok = true;
        a.create_mode = CreateMode::Known;
        reg.register(Box::new(a)).expect("register");
        reg.register(Box::new(Fake::new("beta"))).expect("register");

        let alpha = reg.get(&ProviderId::new("alpha").expect("valid")).expect("present");
        // resume reaches alpha and returns its structured plan
        let plan = alpha.resume_plan(&fake_session("alpha", "s1")).unwrap();
        assert_eq!(plan.program, "alpha");
        // create reaches alpha -> KnownSession
        match alpha.create("p", "/d").unwrap() {
            CreateOutcome::KnownSession(s) => {
                assert_eq!(s.provider_id, ProviderId::new("alpha").expect("valid"));
                assert_eq!(s.id, "known-1");
            }
            _ => panic!("expected KnownSession"),
        }
        alpha.rename(&fake_session("alpha", "s1"), "T").unwrap();

        // unsupported is identifiable and distinct from an operational failure
        let beta = reg.get(&ProviderId::new("beta").expect("valid")).expect("present");
        let err = beta.resume_plan(&fake_session("beta", "s2")).unwrap_err();
        assert!(err.downcast_ref::<Unsupported>().is_some());
        let err2 = beta.create("p", "/d").unwrap_err();
        assert!(err2.downcast_ref::<Unsupported>().is_some());
        // capabilities reflect the same story
        assert!(!beta.capabilities().new_session.supported);
        assert!(!beta.capabilities().resume);
    }

    #[test]
    fn match_session_dispatch_and_identity() {
        let mut reg = ProviderRegistry::new();
        let mut a = Fake::new("alpha");
        a.resume_ok = true;
        reg.register(Box::new(a)).expect("register");
        let alpha = reg.get(&ProviderId::new("alpha").expect("valid")).expect("present");
        let ev = ProcessEvidence {
            windows: vec![WindowEvidence {
                window_id: "@1".into(),
                procs: vec![ProcEvidence { pid: 42, argv: vec!["alpha".into(), "ses-9".into()], env: vec![], }],
            }],
            complete: true,
            errors: vec![],
        };
        let m = alpha.match_session(&fake_session("alpha", "ses-9"), &[], &ev);
        assert_eq!(m.len(), 1);
        assert_eq!(m[0].window_id, "@1");
        assert_eq!(m[0].confidence, MatchConfidence::Confirmed);
    }

    #[test]
    fn cross_provider_session_is_rejected_before_side_effects() {
        let mut reg = ProviderRegistry::new();
        reg.register(Box::new(Fake::new("one"))).expect("register");
        let one = reg.get(&ProviderId::new("one").expect("valid")).expect("present");
        // A session stamped with a *different* provider id must be refused.
        let foreign = fake_session("two", "s-other");
        assert!(check_session_belongs(one, &foreign).is_err());
        // Its own session is accepted.
        let own = fake_session("one", "s-own");
        assert!(check_session_belongs(one, &own).is_ok());
    }

    #[test]
    fn builtin_composition_preserves_default_ids_order_and_types() {
        let reg = builtin_registry(&Config::default()).expect("builtins");
        assert_eq!(reg.len(), 2);
        let ids: Vec<String> = reg.iter().map(|p| p.descriptor().id.to_string()).collect();
        assert_eq!(ids, ["opencode", "codex"]);
        let types: Vec<&str> = reg.iter().map(|p| p.descriptor().type_key).collect();
        assert_eq!(types, ["opencode", "codex"]);
    }

    #[test]
    #[allow(clippy::field_reassign_with_default)]
    fn builtin_composition_wires_config_into_adapters() {
        let tmp = TempDir::new();
        write_codex_fixture(tmp.path());

        let mut cfg = Config::default();
        cfg.opencode_url = "http://127.0.0.1:6555".into();
        cfg.codex_home = tmp.path().to_path_buf();
        let reg = builtin_registry(&cfg).expect("builtins");

        // OpenCode resume plan must carry the configured URL.
        let oc = reg.get(&ProviderId::new("opencode").expect("valid")).expect("present");
        let plan = oc.resume_plan(&fake_session("opencode", "ses_1")).unwrap();
        assert!(plan.args.iter().any(|a| a == "http://127.0.0.1:6555"),
                "resume plan should use the configured url, got: {plan:?}");

        // Codex listing must read the temp fixture, never the real home.
        let cx = reg.get(&ProviderId::new("codex").expect("valid")).expect("present");
        let sessions = cx.list().expect("list temp codex home");
        assert_eq!(sessions.len(), 1);
        assert_eq!(sessions[0].provider_id, ProviderId::new("codex").expect("valid"));
        assert_eq!(sessions[0].title.as_deref(), Some("Fixture Name"));
    }
}
```

### 11.5 opencode adapter (`prov::opencode`)

**Only ever talks HTTP to the shared server.** `GET /session` is the list
source. Rename uses the empirically-pinned compat route (probe all six forms,
§5.1) and then re-reads the session to confirm the write actually landed —
because a miss returns the SPA HTML with HTTP 200 and silently does nothing.

**Endpoint subset (documented contract).** Evidence matching understands a
bounded ASCII HTTP(S) endpoint: `http|https` scheme, a DNS/IPv4-shaped host
(valid 4-octet IPv4 only for all-numeric dotted hosts), an optional decimal
`u16` port, and a preserved path/query with agreed trailing-slash normalization
and valid percent escapes. Every other form (non-ASCII/whitespace/control,
backslashes, userinfo, fragments, IPv6, malformed ports/hosts, invalid numeric
IPv4, bad escapes) is conservatively `Unknown` → ambiguous, never a positively
different server, so malformed process evidence can never erase tracking.

``` {.rust #prov-opencode path="src/provider/opencode.rs"}
use anyhow::{anyhow, Result};
use serde_json::Value;
use std::time::Duration;
use ureq::{Agent, AgentBuilder};

use crate::model::{
    CreateOutcome, LaunchRequest, MatchConfidence, ProcessEvidence, ProviderId, Session,
    WindowMatch,
};
use crate::config::ProviderOptions;
use crate::provider::{NewSessionCapability, ProviderCapabilities, ProviderDescriptor};

/// Bounded, conservative ASCII HTTP(S) endpoint parser.
///
/// Supported subset (exactly):
///   `http`|`https`://`host`[:`port`][`/`path][`?`query]
///
/// Validation (per PA-01 Stage 2 review 4):
///   1. scheme is exactly `http` or `https` (case-insensitive);
///   2. non-ASCII, whitespace/control bytes, backslashes, userinfo (`@`),
///      fragments (`#`), and bracketed/unbracketed IPv6 authorities are
///      rejected as Unknown (Unicode hosts never panic — they are Unknown);
///   3. host is a nonempty ASCII DNS/IPv4-shaped name: dot-separated nonempty
///      labels of ASCII alphanumerics and internal hyphens (no leading/trailing
///      hyphens, no other punctuation). An all-numeric dot host is accepted only
///      as a valid 4-octet IPv4 (reject invalid numeric IPv4, never claim it is
///      another server);
///   4. an optional port is exactly one `:` followed by nonempty decimal digits
///      parsing into a u16 (alphabetic, empty, signed, or overflowing ports are
///      Unknown);
///   5. path/query bytes and case are preserved; only the agreed trailing path
///      slashes are normalized. Malformed percent escapes are rejected (never
///      decoded or reinterpreted);
///   6. only after BOTH endpoints validate may comparison establish Different.
///
/// Returns None (Unknown) for every unsupported form; wider URL support is not
/// required at this stage.
fn endpoint_parts(url: &str) -> Option<(String, String, String)> {
    let (scheme, rest) = url.split_once("://")?;
    let scheme_l = scheme.to_ascii_lowercase();
    if scheme_l != "http" && scheme_l != "https" { return None; }
    // Rule 2: reject non-ASCII, whitespace/control, backslash, userinfo, and
    // fragments across the whole remainder (before any byte indexing, so a
    // multibyte host is Unknown, never a panic).
    if rest.bytes().any(|b| b >= 0x80 || b.is_ascii_whitespace()
        || b.is_ascii_control() || b == b'\\' || b == b'@' || b == b'#') {
        return None;
    }
    // The authority ends at the first '/' or '?' (ASCII, safe byte index).
    let cut = rest.as_bytes().iter()
        .position(|&b| b == b'/' || b == b'?')
        .unwrap_or(rest.len());
    let authority = &rest[..cut];
    let suffix = &rest[cut..];
    if authority.is_empty() { return None; } // e.g. http:///oops
    // Rule 4: optional port — exactly one ':' followed by a decimal u16.
    let (host, port) = match authority.rfind(':') {
        Some(i) => {
            let h = &authority[..i];
            let p = &authority[i + 1..];
            // A second ':' in the host means an IPv6-shaped authority: Unknown.
            if h.contains(':') { return None; }
            if p.is_empty() || !p.bytes().all(|b| b.is_ascii_digit()) { return None; }
            let port: u16 = p.parse().ok()?; // overflow -> Unknown
            (h, port.to_string())
        }
        None => (authority, String::new()),
    };
    // Rule 3: host shape.
    validate_host(host)?;
    // Rule 5: preserve path/query bytes + case; normalize trailing path slashes;
    // reject malformed percent escapes.
    let (path_part, query_part) = match suffix.find('?') {
        Some(i) => (&suffix[..i], &suffix[i..]),
        None => (suffix, ""),
    };
    validate_percent_escapes(path_part)?;
    validate_percent_escapes(query_part)?;
    let mut path = path_part.to_string();
    while path.len() > 1 && path.ends_with('/') { path.pop(); }
    if path.is_empty() { path = "/".to_string(); }
    Some((scheme_l, host.to_ascii_lowercase(), format!("{port}{path}{query_part}")))
}

/// Rule 3: a nonempty ASCII DNS/IPv4-shaped hostname. Rejects invalid numeric
/// IPv4 addresses rather than claiming they identify another server.
fn validate_host(host: &str) -> Option<()> {
    if host.is_empty() { return None; }
    if !host.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'-') {
        return None;
    }
    let labels: Vec<&str> = host.split('.').collect();
    for label in &labels {
        if label.is_empty() { return None; }                       // a..b, trailing dot
        let bytes = label.as_bytes();
        if bytes[0] == b'-' || bytes[bytes.len() - 1] == b'-' { return None; } // -bad, bad-
    }
    // An all-numeric dotted host must be a valid 4-octet IPv4.
    if host.bytes().all(|b| b.is_ascii_digit() || b == b'.') {
        if labels.len() != 4 { return None; }
        for p in labels {
            if p.is_empty() || p.parse::<u8>().is_err() { return None; } // 999, 1.2.3
        }
    }
    Some(())
}

/// Rule 5: reject malformed percent escapes without decoding them.
fn validate_percent_escapes(s: &str) -> Option<()> {
    let b = s.as_bytes();
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' {
            if i + 2 >= b.len() { return None; }
            if !b[i + 1].is_ascii_hexdigit() || !b[i + 2].is_ascii_hexdigit() {
                return None;
            }
            i += 3;
        } else {
            i += 1;
        }
    }
    Some(())
}

/// How one endpoint relates to the configured server endpoint.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum EndpointRel {
    Equal,
    /// Positively a different server (both endpoints parse cleanly).
    Different,
    /// At least one endpoint is malformed/unsupported; unknown, not absence.
    Unknown,
}

/// Compare two endpoints. A parse failure is `Unknown`, never `Different`, so an
/// unparseable endpoint cannot be used to conclude the session is not running.
fn endpoint_rel(a: &str, b: &str) -> EndpointRel {
    let (Some((sa, ha, ra)), Some((sb, hb, rb))) = (endpoint_parts(a), endpoint_parts(b)) else {
        return EndpointRel::Unknown;
    };
    if sa == sb && loopback_alias(&ha) == loopback_alias(&hb) && ra == rb {
        EndpointRel::Equal
    } else {
        EndpointRel::Different
    }
}

fn loopback_alias(host: &str) -> &str {
    match host {
        "localhost" => "127.0.0.1",
        other => other,
    }
}

/// Exact executable basename (never a substring match, never shell text).
fn prog_name(argv0: &str) -> &str {
    argv0.rsplit('/').next().unwrap_or(argv0)
}

pub struct OpencodeProvider {
    base: String,
    id: ProviderId,
    label: String,
    agent: Agent,
}

impl OpencodeProvider {
    pub fn new(base: &str, id: ProviderId) -> Self {
        Self { base: base.trim_end_matches('/').to_string(), id,
               label: "opencode".into(),
               agent: AgentBuilder::new().timeout(Duration::from_secs(5)).build() }
    }

    /// Decode and validate `opencode` options (Stage 3): `url` is required.
    pub fn parse_options(options: &ProviderOptions) -> anyhow::Result<String> {
        for key in options.keys() {
            if key != "url" {
                return Err(anyhow::anyhow!("unknown opencode option {key:?}"));
            }
        }
        let url = options.get("url").ok_or_else(|| anyhow!("opencode requires option url"))?
            .as_str().ok_or_else(|| anyhow!("opencode url must be a string"))?
            .to_string();
        if url.trim().is_empty() {
            return Err(anyhow!("opencode url must be nonempty"));
        }
        Ok(url)
    }

    /// Compiled-in factory: validate options and construct the adapter. The
    /// configured label (or default) becomes the owned descriptor display name.
    pub fn factory(id: ProviderId, label: Option<String>, options: &ProviderOptions)
        -> anyhow::Result<Box<dyn crate::provider::Provider>> {
        let url = Self::parse_options(options)?;
        let mut p = Self::new(&url, id);
        p.label = label.unwrap_or_else(|| "opencode".into());
        Ok(Box::new(p))
    }

    fn session_url(&self, id: &str, suffix: &str) -> String {
        format!("{}/session/{}{}", self.base, id, suffix)
    }

    fn list(&self) -> Result<Vec<Session>> {
        let body: Value = self.agent.get(&format!("{}/session", self.base)).call()?
            .into_json()?;
        let arr = body.as_array().ok_or_else(|| anyhow!("GET /session: expected array"))?;
        let mut out = Vec::with_capacity(arr.len());
        for v in arr {
            let id = v["id"].as_str().unwrap_or_default().to_string();
            let title = v.get("title").and_then(|t| t.as_str()).map(str::to_string);
            let slug = v.get("slug").and_then(|t| t.as_str()).map(str::to_string);
            let directory = v.get("directory").and_then(|t| t.as_str()).map(str::to_string);
            let agent = v.get("agent").and_then(|t| t.as_str()).map(str::to_string);
            let model = v.get("model").and_then(|t| t["id"].as_str()).map(str::to_string);
            let created_ms = v["time"]["created"].as_u64();
            let updated_ms = v["time"]["updated"].as_u64();
            out.push(Session {
                provider_id: self.id.clone(),
                id,
                title,
                slug,
                directory,
                session_id: None,
                agent,
                model,
                created_ms,
                updated_ms,
                active: v.get("active").and_then(|a| a.as_bool()).unwrap_or(false),
            });
        }
        out.sort_by_key(|s| std::cmp::Reverse(s.updated_ms.unwrap_or(0)));
        Ok(out)
    }

    fn rename(&self, s: &Session, title: &str) -> Result<()> {
        let payload = serde_json::json!({ "title": title });
        let mut last_err = None;
        for path in ["", "/rename"] {
            for method in ["POST", "PATCH", "PUT"] {
                let url = self.session_url(&s.id, path);
                match self.request(method, &url, &payload) {
                    Ok(()) => {
                        // confirm the write landed (SPA fallback lies with 200)
                        if let Some(sess) = self.by_id(&s.id)? {
                            if sess.title.as_deref() == Some(title) { return Ok(()); }
                        }
                    }
                    Err(e) => last_err = Some(e.to_string()),
                }
            }
        }
        Err(anyhow!("opencode rename failed: {}", last_err.unwrap_or_else(|| "no route matched".into())))
    }

    fn request(&self, method: &str, url: &str, payload: &Value) -> Result<()> {
        let resp = match method {
            "POST" => self.agent.post(url).send_json(payload)?,
            "PATCH" => self.agent.patch(url).send_json(payload)?,
            "PUT" => self.agent.put(url).send_json(payload)?,
            _ => return Err(anyhow!("bad method")),
        };
        resp.into_string()?; // drain; body is ignored either way
        Ok(())
    }

    fn by_id(&self, id: &str) -> Result<Option<Session>> {
        let body: Value = self.agent.get(&self.session_url(id, "")).call()?.into_json()?;
        if body.get("error").is_some() { return Ok(None); }
        Ok(Some(Self::from_value(&self.id, body)))
    }

    fn from_value(id: &ProviderId, v: Value) -> Session {
        Session {
            provider_id: id.clone(),
            id: v["id"].as_str().unwrap_or_default().to_string(),
            title: v.get("title").and_then(|t| t.as_str()).map(str::to_string),
            slug: v.get("slug").and_then(|t| t.as_str()).map(str::to_string),
            directory: v.get("directory").and_then(|t| t.as_str()).map(str::to_string),
            session_id: None,
            agent: v.get("agent").and_then(|t| t.as_str()).map(str::to_string),
            model: v.get("model").and_then(|t| t["id"].as_str()).map(str::to_string),
            created_ms: v["time"]["created"].as_u64(),
            updated_ms: v["time"]["updated"].as_u64(),
            active: false,
        }
    }

    fn capabilities(&self) -> ProviderCapabilities {
        ProviderCapabilities {
            rename: true,
            resume: true,
            new_session: NewSessionCapability { supported: true, applies_title: true, applies_cwd: false },
        }
    }

    /// Pure resume plan: client-mode attach to the ONE shared server, which is
    /// exactly how an existing session is opened (never a bare opencode that
    /// could spawn a second server on a live id).
    fn resume_plan(&self, s: &Session) -> Result<LaunchRequest> {
        Ok(LaunchRequest {
            program: "opencode".into(),
            args: vec!["attach".into(), self.base.clone(), "-s".into(), s.id.clone()],
            cwd: None,
            env: vec![],
        })
    }

    /// Create a fresh session on the shared server (a known session). The server
    /// binds sessions to its own cwd — the requested directory is not honoured,
    /// so `applies_cwd` is false. Title lands directly.
    fn create(&self, name: &str, dir: &str) -> Result<CreateOutcome> {
        let payload = serde_json::json!({ "directory": dir, "title": name });
        let body: Value = self.agent.post(&format!("{}/session", self.base))
            .send_json(&payload)?
            .into_json()?;
        if body.get("id").and_then(|i| i.as_str()).unwrap_or_default().is_empty() {
            return Err(anyhow!("POST /session returned no id"));
        }
        Ok(CreateOutcome::KnownSession(Self::from_value(&self.id, body)))
    }

    /// Interpret a generic process snapshot for one session using a small explicit
    /// grammar. Only the fully-understood forms establish a confirmed match or a
    /// positively different session/server; the executable being recognized but
    /// the syntax NOT being a supported form is ambiguous/unknown (never treated
    /// as proof of absence). The executable is matched by exact basename.
    fn match_session(&self, session: &Session, _snapshot: &[Session],
                     evidence: &ProcessEvidence) -> Vec<WindowMatch> {
        let mut out: Vec<WindowMatch> = Vec::new();
        for w in &evidence.windows {
            let mut confirmed = false;
            let mut ambiguous = false;
            for p in &w.procs {
                let argv = &p.argv;
                let Some(first) = argv.first() else { continue };
                if prog_name(first) != "opencode" { continue; }
                // Supported forms (exact argv shapes):
                //   opencode attach <endpoint>            -> id-less attach
                //   opencode attach <endpoint> -s <id>    -> explicit session
                // Anything else on the opencode executable is unknown syntax.
                match argv.as_slice() {
                    [_, attach, endpoint] if attach == "attach" => {
                        // An id-less attach on our server is ambiguous; a
                        // malformed endpoint is UNKNOWN (also ambiguous), never
                        // proof of absence.
                        match endpoint_rel(endpoint, &self.base) {
                            EndpointRel::Equal | EndpointRel::Unknown => ambiguous = true,
                            EndpointRel::Different => {} // positively another server
                        }
                    }
                    [_, attach, endpoint, dash_s, id] if attach == "attach" && dash_s == "-s" => {
                        match endpoint_rel(endpoint, &self.base) {
                            EndpointRel::Equal => {
                                if id == &session.id { confirmed = true; }
                                // a fully understood attach to our server for a
                                // different session: no candidate for ours.
                            }
                            EndpointRel::Different => {} // positively another server
                            EndpointRel::Unknown => ambiguous = true, // malformed endpoint
                        }
                    }
                    [_, dash_s, id] if dash_s == "-s" => {
                        // A bare `opencode -s <id>` (no endpoint) resumes that
                        // explicit session in its own out-of-band server. It is
                        // positive evidence about THAT session only: confirmed
                        // for ours when the id matches; otherwise it is another
                        // session and no candidate for ours. Without this, a
                        // single such window (e.g. stale after tmux-resurrect)
                        // made EVERY session open ambiguous.
                        if id == &session.id { confirmed = true; }
                    }
                    _ => { ambiguous = true; } // recognized exe, unknown syntax
                }
            }
            if confirmed {
                out.push(WindowMatch { window_id: w.window_id.clone(), confidence: MatchConfidence::Confirmed });
            } else if ambiguous {
                out.push(WindowMatch { window_id: w.window_id.clone(), confidence: MatchConfidence::Ambiguous });
            }
        }
        out
    }
}

impl crate::provider::Provider for OpencodeProvider {
    fn descriptor(&self) -> ProviderDescriptor {
        ProviderDescriptor { id: self.id.clone(), type_key: "opencode", display_name: self.label.clone() }
    }
    fn capabilities(&self) -> ProviderCapabilities { self.capabilities() }
    fn list(&self) -> Result<Vec<Session>> { self.list() }
    fn rename(&self, s: &Session, t: &str) -> Result<()> { self.rename(s, t) }
    fn resume_plan(&self, s: &Session) -> Result<LaunchRequest> { self.resume_plan(s) }
    fn create(&self, name: &str, dir: &str) -> Result<CreateOutcome> { self.create(name, dir) }
    fn match_session(&self, session: &Session, _snapshot: &[Session], evidence: &ProcessEvidence) -> Vec<WindowMatch> {
        self.match_session(session, _snapshot, evidence)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{ProcEvidence, WindowEvidence};

    fn session(id: &str) -> Session {
        Session {
            provider_id: ProviderId::new("opencode").unwrap(),
            id: id.to_string(),
            title: None, slug: None, directory: None, session_id: None,
            agent: None, model: None, created_ms: None, updated_ms: None, active: false,
        }
    }

    fn evidence(windows: Vec<(String, Vec<Vec<String>>)>, complete: bool) -> ProcessEvidence {
        ProcessEvidence {
            windows: windows.into_iter().map(|(wid, procs)| WindowEvidence {
                window_id: wid,
                procs: procs.into_iter().enumerate().map(|(i, argv)| ProcEvidence { pid: i as u64, argv, env: vec![], }).collect(),
            }).collect(),
            complete,
            errors: vec![],
        }
    }

    #[test]
    fn exact_id_on_configured_server_is_confirmed() {
        let p = OpencodeProvider::new("http://127.0.0.1:4096", ProviderId::new("opencode").unwrap());
        let ev = evidence(vec![("@1".into(), vec![vec!["opencode".into(), "attach".into(),
            "http://127.0.0.1:4096".into(), "-s".into(), "ses_x".into()]])], true);
        let m = p.match_session(&session("ses_x"), &[], &ev);
        assert_eq!(m.len(), 1);
        assert_eq!(m[0].window_id, "@1");
        assert_eq!(m[0].confidence, MatchConfidence::Confirmed);
    }

    #[test]
    fn trailing_slash_and_localhost_are_equivalent_but_not_different_servers() {
        let p = OpencodeProvider::new("http://127.0.0.1:4096", ProviderId::new("opencode").unwrap());
        // localhost:4096 with a trailing slash still matches our 127.0.0.1:4096.
        let ev = evidence(vec![("@1".into(), vec![vec!["opencode".into(), "attach".into(),
            "http://localhost:4096/".into(), "-s".into(), "ses_x".into()]])], true);
        assert_eq!(p.match_session(&session("ses_x"), &[], &ev).len(), 1);
        // A different port must not match.
        let ev2 = evidence(vec![("@2".into(), vec![vec!["opencode".into(), "attach".into(),
            "http://127.0.0.1:5000".into(), "-s".into(), "ses_x".into()]])], true);
        assert!(p.match_session(&session("ses_x"), &[], &ev2).is_empty());
    }

    #[test]
    fn endpoint_normalization_is_case_sensitive_for_paths_and_host_prefixes() {
        let p = OpencodeProvider::new("http://127.0.0.1:4096/Proj", ProviderId::new("opencode").unwrap());
        // A case-sensitive path difference must NOT match.
        let ev = evidence(vec![("@1".into(), vec![vec!["opencode".into(), "attach".into(),
            "http://127.0.0.1:4096/proj".into(), "-s".into(), "ses_x".into()]])], true);
        assert!(p.match_session(&session("ses_x"), &[], &ev).is_empty(),
            "path case must be preserved");
        // Exact path matches.
        let ev2 = evidence(vec![("@2".into(), vec![vec!["opencode".into(), "attach".into(),
            "http://127.0.0.1:4096/Proj".into(), "-s".into(), "ses_x".into()]])], true);
        assert_eq!(p.match_session(&session("ses_x"), &[], &ev2).len(), 1);
        // A host that merely PREFIXES localhost must NOT be conflated.
        let p2 = OpencodeProvider::new("http://localhost.example:4096", ProviderId::new("opencode").unwrap());
        let ev3 = evidence(vec![("@3".into(), vec![vec!["opencode".into(), "attach".into(),
            "http://127.0.0.1.example:4096".into(), "-s".into(), "ses_x".into()]])], true);
        assert!(p2.match_session(&session("ses_x"), &[], &ev3).is_empty(),
            "localhost.example vs 127.0.0.1.example are different hosts");
    }

    #[test]
    fn absolute_executable_path_matches_by_basename() {
        let p = OpencodeProvider::new("http://127.0.0.1:4096", ProviderId::new("opencode").unwrap());
        let ev = evidence(vec![("@1".into(), vec![vec!["/usr/bin/opencode".into(), "attach".into(),
            "http://127.0.0.1:4096".into(), "-s".into(), "ses_x".into()]])], true);
        assert_eq!(p.match_session(&session("ses_x"), &[], &ev).len(), 1);
    }

    #[test]
    fn unparseable_attach_is_ambiguous() {
        let p = OpencodeProvider::new("http://127.0.0.1:4096", ProviderId::new("opencode").unwrap());
        // attach with no endpoint: unknown, not proof of absence
        let ev = evidence(vec![("@1".into(), vec![vec!["opencode".into(), "attach".into()]])], true);
        let m = p.match_session(&session("ses_x"), &[], &ev);
        assert_eq!(m.len(), 1);
        assert_eq!(m[0].confidence, MatchConfidence::Ambiguous);
    }

    #[test]
    fn id_less_attach_is_ambiguous_not_confirmed() {
        let p = OpencodeProvider::new("http://127.0.0.1:4096", ProviderId::new("opencode").unwrap());
        let ev = evidence(vec![("@1".into(), vec![vec!["opencode".into(), "attach".into(),
            "http://127.0.0.1:4096".into()]])], true);
        let m = p.match_session(&session("ses_x"), &[], &ev);
        assert_eq!(m.len(), 1);
        assert_eq!(m[0].confidence, MatchConfidence::Ambiguous);
    }

    #[test]
    fn different_session_id_is_not_a_match_for_ours() {
        let p = OpencodeProvider::new("http://127.0.0.1:4096", ProviderId::new("opencode").unwrap());
        let ev = evidence(vec![("@1".into(), vec![vec!["opencode".into(), "attach".into(),
            "http://127.0.0.1:4096".into(), "-s".into(), "ses_other".into()]])], true);
        assert!(p.match_session(&session("ses_x"), &[], &ev).is_empty());
    }

    #[test]
    fn unknown_options_and_dangling_duplicate_flags_are_ambiguous() {
        let p = OpencodeProvider::new("http://127.0.0.1:4096", ProviderId::new("opencode").unwrap());
        // recognized executable but unrecognized syntax -> ambiguous, never absence
        let cases: Vec<Vec<String>> = vec![
            vec!["opencode".into(), "--unknown".into(), "attach".into(),
                 "http://127.0.0.1:4096".into(), "-s".into(), "ses_x".into()],
            vec!["opencode".into(), "attach".into(), "http://127.0.0.1:4096".into(), "-s".into()],
            vec!["opencode".into(), "attach".into(), "http://127.0.0.1:4096".into(),
                 "-s".into(), "ses_x".into(), "extra".into()],
            vec!["opencode".into(), "attach".into(), "http://127.0.0.1:4096".into(),
                 "-s".into(), "ses_x".into(), "-s".into(), "ses_x".into()],
            vec!["opencode".into()],
        ];
        for argv in cases {
            let ev = evidence(vec![("@1".into(), vec![argv])], true);
            let m = p.match_session(&session("ses_x"), &[], &ev);
            assert_eq!(m.len(), 1, "unrecognized syntax must be ambiguous: {ev:?}");
            assert_eq!(m[0].confidence, MatchConfidence::Ambiguous);
        }
    }

    #[test]
    fn query_bytes_and_trailing_slash_are_preserved_or_normalized() {
        // Trailing slash on a non-root path is normalized (equiv).
        let p = OpencodeProvider::new("http://127.0.0.1:4096/Proj", ProviderId::new("opencode").unwrap());
        let ev = evidence(vec![("@1".into(), vec![vec!["opencode".into(), "attach".into(),
            "http://127.0.0.1:4096/Proj/".into(), "-s".into(), "ses_x".into()]])], true);
        assert_eq!(p.match_session(&session("ses_x"), &[], &ev).len(), 1,
            "non-root trailing slash should match");

        // Query bytes are preserved (case-sensitive), never part of the host.
        let p2 = OpencodeProvider::new("http://127.0.0.1:4096/Proj?Token=A", ProviderId::new("opencode").unwrap());
        let same = evidence(vec![("@1".into(), vec![vec!["opencode".into(), "attach".into(),
            "http://127.0.0.1:4096/Proj?Token=A".into(), "-s".into(), "ses_x".into()]])], true);
        assert_eq!(p2.match_session(&session("ses_x"), &[], &same).len(), 1);
        let diff_case = evidence(vec![("@2".into(), vec![vec!["opencode".into(), "attach".into(),
            "http://127.0.0.1:4096/Proj?token=a".into(), "-s".into(), "ses_x".into()]])], true);
        assert!(p2.match_session(&session("ses_x"), &[], &diff_case).is_empty(),
            "query case must be preserved");

        // A root URL with a query is not conflated with the same path sans query.
        let p3 = OpencodeProvider::new("http://127.0.0.1:4096/", ProviderId::new("opencode").unwrap());
        let root_query = evidence(vec![("@3".into(), vec![vec!["opencode".into(), "attach".into(),
            "http://127.0.0.1:4096?Token=A".into(), "-s".into(), "ses_x".into()]])], true);
        assert!(p3.match_session(&session("ses_x"), &[], &root_query).is_empty(),
            "a query must not be folded into the host/path");
    }

    #[test]
    fn malformed_endpoint_is_ambiguous_in_both_attach_shapes() {
        let p = OpencodeProvider::new("http://127.0.0.1:4096", ProviderId::new("opencode").unwrap());
        // An unparseable endpoint in an otherwise-accepted attach argv shape is
        // UNKNOWN -> ambiguous, never "positively different" (so tracking is not
        // dropped).
        let cases: Vec<Vec<String>> = vec![
            vec!["opencode".into(), "attach".into(), "not-a-url".into(), "-s".into(), "ses_x".into()],
            vec!["opencode".into(), "attach".into(), "not-a-url".into()],
            vec!["opencode".into(), "attach".into(), "http:///oops".into(), "-s".into(), "ses_x".into()],
            vec!["opencode".into(), "attach".into(), "http://:8080".into(), "-s".into(), "ses_x".into()],
            vec!["opencode".into(), "attach".into(), "http://user@host:4096".into(), "-s".into(), "ses_x".into()],
            vec!["opencode".into(), "attach".into(), "http://bad host:4096".into(), "-s".into(), "ses_x".into()],
            vec!["opencode".into(), "attach".into(), "http://localhost:99999".into(), "-s".into(), "ses_x".into()],
            vec!["opencode".into(), "attach".into(), "1http://localhost:4096".into()],
        ];
        for argv in cases {
            let ev = evidence(vec![("@1".into(), vec![argv])], true);
            let m = p.match_session(&session("ses_x"), &[], &ev);
            assert_eq!(m.len(), 1, "malformed endpoint must be ambiguous: {ev:?}");
            assert_eq!(m[0].confidence, MatchConfidence::Ambiguous);
        }
    }

    #[test]
    fn endpoint_validation_subset_table() {
        // Each case is `endpoint_rel(url, "http://localhost:4096")`.
        let cases: &[(&str, EndpointRel)] = &[
            // valid equal/different
            ("http://localhost:4096", EndpointRel::Equal),
            ("http://127.0.0.1:4096", EndpointRel::Equal),
            ("http://LOCALHOST:4096", EndpointRel::Equal),
            ("http://localhost:5000", EndpointRel::Different),
            ("http://127.0.0.1:5000", EndpointRel::Different),
            ("https://localhost:4096", EndpointRel::Different),
            ("http://localhost:4096/Proj", EndpointRel::Different), // different path vs root
            ("http://localhost:4096/Proj?Token=A", EndpointRel::Different),
            // unsupported scheme
            ("ftp://localhost:4096", EndpointRel::Unknown),
            ("1http://localhost:4096", EndpointRel::Unknown),
            ("httpX://localhost:4096", EndpointRel::Unknown),
            ("://localhost:4096", EndpointRel::Unknown),
            // non-ASCII / whitespace / control / backslash / userinfo / fragment / IPv6
            ("http://é/abc", EndpointRel::Unknown),
            ("http://bad host:4096", EndpointRel::Unknown),
            ("http://bad\thost:4096", EndpointRel::Unknown),
            ("http://bad\\host:4096", EndpointRel::Unknown),
            ("http://user@host:4096", EndpointRel::Unknown),
            ("http://host:4096/#frag", EndpointRel::Unknown),
            ("http://[::1]:4096", EndpointRel::Unknown),
            ("http://::1:4096", EndpointRel::Unknown),
            // host label rules
            ("http://-bad:4096", EndpointRel::Unknown),
            ("http://bad-:4096", EndpointRel::Unknown),
            ("http://a..b:4096", EndpointRel::Unknown),
            ("http://a_b:4096", EndpointRel::Unknown),
            ("http://127.0.0.999:4096", EndpointRel::Unknown),
            ("http://999.1.1.1:4096", EndpointRel::Unknown),
            ("http://1.2.3:4096", EndpointRel::Unknown),
            // port rules
            ("http://localhost:banana", EndpointRel::Unknown),
            ("http://localhost:99999", EndpointRel::Unknown),
            ("http://localhost:", EndpointRel::Unknown),
            ("http://localhost:-1", EndpointRel::Unknown),
            // malformed percent escapes
            ("http://localhost:4096/%zz", EndpointRel::Unknown),
            ("http://localhost:4096/%2", EndpointRel::Unknown),
            // missing authority
            ("http:///oops", EndpointRel::Unknown),
            ("http://:8080", EndpointRel::Unknown),
        ];
        for (url, expect) in cases {
            assert_eq!(endpoint_rel(url, "http://localhost:4096"), *expect, "case {url:?}");
        }
        // Trailing-slash equivalence on a non-root path (the agreed normalization).
        assert_eq!(endpoint_rel("http://localhost:4096/Proj/", "http://localhost:4096/Proj"),
                   EndpointRel::Equal, "non-root trailing slash normalized");
    }

    #[test]
    fn unicode_authority_does_not_panic_and_valid_different_server_never_matches() {
        let p = OpencodeProvider::new("http://127.0.0.1:4096", ProviderId::new("opencode").unwrap());
        // A multibyte host must not panic; it is Unknown -> ambiguous, never
        // "positively different".
        let ev = evidence(vec![("@1".into(), vec![vec!["opencode".into(), "attach".into(),
            "http://é/abc".into(), "-s".into(), "ses_x".into()]])], true);
        let m = p.match_session(&session("ses_x"), &[], &ev);
        assert_eq!(m.len(), 1, "Unicode host must be Unknown/ambiguous, not absence");
        assert_eq!(m[0].confidence, MatchConfidence::Ambiguous);
        // A valid, positively different server still produces no candidate.
        let other = evidence(vec![("@2".into(), vec![vec!["opencode".into(), "attach".into(),
            "http://127.0.0.1:5000".into(), "-s".into(), "ses_x".into()]])], true);
        assert!(p.match_session(&session("ses_x"), &[], &other).is_empty(),
            "a valid different server is positively different, not a match");
        // Explicit tri-state relation checks.
        assert_eq!(endpoint_rel("http://127.0.0.1:4096", "http://127.0.0.1:4096"), EndpointRel::Equal);
        assert_eq!(endpoint_rel("http://localhost:4096", "http://127.0.0.1:4096"), EndpointRel::Equal);
        assert_eq!(endpoint_rel("http://127.0.0.1:4096", "http://127.0.0.1:5000"), EndpointRel::Different);
        assert_eq!(endpoint_rel("not-a-url", "http://127.0.0.1:4096"), EndpointRel::Unknown);
        assert_eq!(endpoint_rel("http:///oops", "http://127.0.0.1:4096"), EndpointRel::Unknown);
    }

    #[test]
    fn fixture_sessions_carry_configured_instance_id() {
        let id = ProviderId::new("alt").unwrap();
        let v = serde_json::json!({ "id": "ses_abc", "title": "T", "time": { "created": 1, "updated": 2 } });
        let s = OpencodeProvider::from_value(&id, v);
        assert_eq!(s.provider_id, id);
        assert_eq!(s.id, "ses_abc");
    }

    #[test]
    fn resume_plan_is_a_structured_attach() {
        let p = OpencodeProvider::new("http://127.0.0.1:4096", ProviderId::new("opencode").unwrap());
        let plan = p.resume_plan(&session("ses_x")).unwrap();
        assert_eq!(plan.program, "opencode");
        assert_eq!(plan.args, vec!["attach", "http://127.0.0.1:4096", "-s", "ses_x"]);
    }
}
```

### 11.6 codex adapter (`prov::codex`)

Thread names/titles, working dir, model and timestamps are read from the
app-server's **state DB** (`~/.codex/state_*.sqlite` → `threads` table). That is
where codex 0.155 keeps them — the old `session_index.jsonl` is no longer
written, so listing is built by scanning the rollout tree (for real,
non-seed threads) and joining each rollout id against the DB. Renaming writes
the thread `name` column (what `/status` and the UI show). `attach_command`
uses the resolved display title (including inherited titles) for `codex resume`,
falling back to the UUID. See §5.2 for the legacy rename fallback and the
limitations of resuming by a non-unique display title.

``` {.rust #prov-codex path="src/provider/codex.rs"}
use anyhow::{anyhow, Context, Result};
use rusqlite::{params, Connection};
use serde_json::Value;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::model::{
    CreateOutcome, LaunchRequest, MatchConfidence, ProcessEvidence, ProviderId, Session,
    WindowMatch,
};
use crate::config::ProviderOptions;
use crate::provider::{NewSessionCapability, ProviderCapabilities, ProviderDescriptor};

/// Thread metadata as stored in the app-server state DB `threads` table.
struct ThreadMeta {
    name: Option<String>,   // short thread name (set via /status or pinga)
    title: Option<String>,  // longer title / first-prompt preview
    cwd: Option<String>,
    model: Option<String>,
    created_ms: Option<u64>,
    updated_ms: Option<u64>,
}

impl ThreadMeta {
    /// Display name, preferring a short name over the long title.
    fn display(&self) -> Option<String> {
        self.name.clone().filter(|n| !n.trim().is_empty())
            .or_else(|| self.title.clone().filter(|t| !t.trim().is_empty()))
    }
}

pub struct CodexProvider { home: PathBuf, id: ProviderId, label: String }

impl CodexProvider {
    pub fn new(home: &Path, id: ProviderId) -> Self {
        Self { home: home.to_path_buf(), id, label: "codex".into() }
    }

    /// Decode and validate `codex` options (Stage 3): `home` is required and
    /// must be absolute.
    pub fn parse_options(options: &ProviderOptions) -> anyhow::Result<PathBuf> {
        for key in options.keys() {
            if key != "home" {
                return Err(anyhow::anyhow!("unknown codex option {key:?}"));
            }
        }
        let home = options.get("home").ok_or_else(|| anyhow!("codex requires option home"))?
            .as_str().ok_or_else(|| anyhow!("codex home must be a string"))?;
        if home.trim().is_empty() {
            return Err(anyhow!("codex home must be nonempty"));
        }
        let p = PathBuf::from(home);
        if !p.is_absolute() {
            return Err(anyhow!("codex home must be an absolute path: {home:?}"));
        }
        Ok(p)
    }

    /// Compiled-in factory: validate options and construct the adapter.
    pub fn factory(id: ProviderId, label: Option<String>, options: &ProviderOptions)
        -> anyhow::Result<Box<dyn crate::provider::Provider>> {
        let home = Self::parse_options(options)?;
        let mut p = Self::new(&home, id);
        p.label = label.unwrap_or_else(|| "codex".into());
        Ok(Box::new(p))
    }

    /// Locate the app-server state DB: `~/.codex/state_*.sqlite` that has a
    /// `threads` table (the numeric suffix changes between codex releases).
    fn state_db_path(&self) -> Option<PathBuf> {
        let dir = self.home.as_path();
        let mut found: Option<PathBuf> = None;
        if let Ok(rd) = fs::read_dir(dir) {
            for e in rd.flatten() {
                let name = e.file_name().to_string_lossy().to_string();
                if name.starts_with("state_") && name.ends_with(".sqlite") {
                    // only accept if it actually exposes `threads`
                    if let Ok(conn) = Connection::open(e.path()) {
                        let has = conn.query_row(
                            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='threads'",
                            [], |_| Ok(())).is_ok();
                        if has { found = Some(e.path()); break; }
                    }
                }
            }
        }
        found
    }

    /// Load all threads from the state DB into an id -> metadata map.
    fn thread_meta(&self) -> HashMap<String, ThreadMeta> {
        let mut map = HashMap::new();
        let Some(db) = self.state_db_path() else { return map };
        let Ok(conn) = Connection::open(&db) else { return map };
        let query = "SELECT id, name, title, cwd, model, created_at_ms, updated_at_ms FROM threads";
        let Ok(mut stmt) = conn.prepare(query) else { return map };
        let rows = stmt.query_map([], |row| {
            let id: String = row.get(0)?;
            let meta = ThreadMeta {
                name: row.get::<_, Option<String>>(1)?,
                title: row.get::<_, Option<String>>(2)?,
                cwd: row.get::<_, Option<String>>(3)?,
                model: row.get::<_, Option<String>>(4)?,
                created_ms: row.get::<_, Option<i64>>(5)?.map(|v| v as u64),
                updated_ms: row.get::<_, Option<i64>>(6)?.map(|v| v as u64),
            };
            Ok((id, meta))
        });
        if let Ok(rows) = rows {
            for r in rows.flatten() { map.insert(r.0, r.1); }
        }
        map
    }

    /// child thread id -> parent thread id, from the app-server's spawn edges.
    /// Nameless sub-agent threads inherit their parent's name so they don't
    /// show a bare id (e.g. the sub-thread of "Review Mnemosyne memory").
    fn parents(&self) -> HashMap<String, String> {
        let mut map = HashMap::new();
        let Some(db) = self.state_db_path() else { return map };
        if let Ok(conn) = Connection::open(&db) {
            let query = "SELECT child_thread_id, parent_thread_id FROM thread_spawn_edges";
            if let Ok(mut stmt) = conn.prepare(query) {
                if let Ok(rows) = stmt.query_map([], |row| {
                    Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
                }) {
                    for r in rows.flatten() { map.insert(r.0, r.1); }
                }
            }
        }
        map
    }

    /// Walk up the spawn-parent chain to the nearest ancestor that has a
    /// display name, so a nameless sub-agent shows its parent conversation's
    /// name instead of a bare id.
    fn inherited_name(&self, id: &str, meta: &HashMap<String, ThreadMeta>,
                      parents: &HashMap<String, String>) -> Option<String> {
        let mut cur = id;
        let mut seen = std::collections::HashSet::new();
        while seen.insert(cur.to_string()) {
            let Some(pid) = parents.get(cur) else { break };
            if let Some(m) = meta.get(pid) {
                if let Some(n) = m.display() { return Some(n); }
            }
            cur = pid;
        }
        None
    }

    fn list(&self) -> Result<Vec<Session>> {
        let meta = self.thread_meta();
        let parents = self.parents();
        // rollout tree provides id + fallback timestamps + first-prompt seed
        let mut out: Vec<Session> = Vec::new();
        for rollout in self.rollouts()? {
            // Skip seed threads: sessions spawned empty by the vscode originator
            // are a single session_meta line, and codex's resume of an empty
            // thread ends the TUI immediately (observed on eris 2026-09-17).
            if !has_conversation(&rollout) { continue; }
            let id = rollout_title_id(&rollout).unwrap_or_default();
            let m = meta.get(&id);
            // Display name: pinga/codex name, else codex title, else an
            // inherited parent name for nameless sub-agent threads, else id.
            let title = m.and_then(|m| m.display())
                .or_else(|| self.inherited_name(&id, &meta, &parents));
            let updated = m.and_then(|m| m.updated_ms)
                .or_else(|| file_mtime_ms(&rollout));
            let (directory, session_id, model) = rollout_cwd_session_model(&rollout);
            out.push(Session {
                provider_id: self.id.clone(),
                id,
                title,
                slug: None,
                directory: m.and_then(|m| m.cwd.clone()).or(directory),
                session_id,
                agent: None,
                model: m.and_then(|m| m.model.clone()).or(model),
                created_ms: m.and_then(|m| m.created_ms),
                updated_ms: updated,
                active: false,
            });
        }
        // Most-recent first, with a stable id tiebreak so equal timestamps don't
        // jitter between refreshes (and renames never move a row, since they no
        // longer bump updated_at_ms).
        out.sort_by(|a, b| {
            b.updated_ms.unwrap_or(0).cmp(&a.updated_ms.unwrap_or(0))
                .then_with(|| a.id.cmp(&b.id))
        });
        Ok(out)
    }

    // ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl, newest first
    fn rollouts(&self) -> Result<Vec<PathBuf>> {
        let root = self.home.join("sessions");
        let mut out = Vec::new();
        if !root.exists() { return Ok(out); }
        for y in fs::read_dir(&root)? {
            let y = y?; if !y.file_type()?.is_dir() { continue; }
            for m in fs::read_dir(y.path())? {
                let m = m?; if !m.file_type()?.is_dir() { continue; }
                for d in fs::read_dir(m.path())? {
                    let d = d?; if !d.file_type()?.is_dir() { continue; }
                    for f in fs::read_dir(d.path())? {
                        let f = f?;
                        if f.file_name().to_string_lossy().starts_with("rollout-")
                            && f.path().extension().is_some_and(|e| e == "jsonl") {
                            out.push(f.path());
                        }
                    }
                }
            }
        }
        out.sort();
        Ok(out)
    }

    fn rename(&self, s: &Session, title: &str) -> Result<()> {
        // Codex 0.155 keeps the thread name in the app-server state DB `threads`
        // table — that is what /status and the UI show. Write it there. (The old
        // session_index.jsonl append is gone in this codex, so nothing reads it.)
        if let Some(db) = self.state_db_path() {
            if let Ok(conn) = Connection::open(&db) {
                // Renaming only sets the label — do NOT bump updated_at_ms, or
                // the session would jump to the top of the recency sort and the
                // list would visibly reshuffle on every rename.
                let n = conn.execute(
                    "UPDATE threads SET name = ?1 WHERE id = ?2",
                    params![title, s.id],
                ).unwrap_or(0);
                if n > 0 { return Ok(()); }
            }
        }
        // Fallback: thread not (yet) in the state DB — keep an index append so
        // a name still survives the gap.
        let line = serde_json::json!({
            "id": s.id,
            "thread_name": title,
            "updated_at": rfc3339_now(),
        });
        use std::io::Write;
        let mut f = fs::OpenOptions::new()
            .create(true).append(true).open(self.home.join("session_index.jsonl"))
            .with_context(|| "open codex session_index.jsonl")?;
        writeln!(f, "{line}")?;
        Ok(())
    }

    fn capabilities(&self) -> ProviderCapabilities {
        ProviderCapabilities {
            rename: true,
            resume: true,
            new_session: NewSessionCapability { supported: true, applies_title: false, applies_cwd: true },
        }
    }

    /// Pure resume plan: `codex resume <title-or-uuid>`. The resume target is
    /// the resolved display title when present, otherwise the UUID. We do not
    /// assume an unverified CLI change.
    fn resume_plan(&self, s: &Session) -> Result<LaunchRequest> {
        let target = match &s.title {
            Some(name) if !name.trim().is_empty() => name.clone(),
            _ => s.id.clone(),
        };
        Ok(LaunchRequest {
            program: "codex".into(),
            args: vec!["resume".into(), target],
            cwd: s.directory.clone(),
            env: self.source_env(),
        })
    }

    /// New-session creation is a launch-to-create plan: open `codex` in the
    /// requested cwd and let it mint a thread whose ID is initially unknown.
    /// The requested title is used only as a window label by the app, not as
    /// native session metadata. The configured home is wired into the launch so
    /// a non-default instance runs against its own source, not the ambient one.
    fn create(&self, _name: &str, dir: &str) -> Result<CreateOutcome> {
        let cwd = if dir.trim().is_empty() { None } else { Some(dir.trim().to_string()) };
        Ok(CreateOutcome::LaunchToCreate(LaunchRequest {
            program: "codex".into(),
            args: vec![],
            cwd,
            env: self.source_env(),
        }))
    }

    /// The narrow source environment wired into every launch so a non-default
    /// codex instance runs against its configured home. Unrepresentable paths
    /// (non-UTF-8) are rejected at construction.
    fn source_env(&self) -> Vec<(String, String)> {
        let home = self.home.to_string_lossy().into_owned();
        vec![("CODEX_HOME".to_string(), home)]
    }

    /// Interpret a generic process snapshot for one session. An exact UUID match
    /// is confirmed. A resume title is confirmed only when it uniquely
    /// identifies the session in the current successful snapshot; duplicate or
    /// inherited shared titles yield ambiguity (never "pick the first list
    /// entry"). Source discrimination: a process whose `CODEX_HOME` (if present)
    /// names a DIFFERENT home is not this instance; an absent source env for a
    /// non-default home is Unknown (ambiguous), never a confirmed adoption.
    fn match_session(&self, session: &Session, snapshot: &[Session],
                     evidence: &ProcessEvidence) -> Vec<WindowMatch> {
        let mut out: Vec<WindowMatch> = Vec::new();
        for w in &evidence.windows {
            let mut confirmed = false;
            let mut ambiguous = false;
            for p in &w.procs {
                let argv = &p.argv;
                let Some(first) = argv.first() else { continue };
                if prog_name(first) != "codex" { continue; }
                // Source discrimination: a differing home is positively not this
                // instance; an unestablished source cannot confirm anything.
                match source_rel(&self.home, &p.env) {
                    SourceRel::Unknown => { ambiguous = true; continue; }
                    SourceRel::Same => {}
                }
                // Supported form (exact argv shape): `codex resume <target>`.
                // Any other form on the codex executable is unknown syntax.
                match argv.as_slice() {
                    [_, resume, target] if resume == "resume" => {
                        if target == &session.id {
                            confirmed = true; // exact UUID
                        } else if session.title.as_deref() == Some(target.as_str()) {
                            // title match: confirmed only if unique in the snapshot
                            let count = snapshot.iter()
                                .filter(|s| s.title.as_deref() == Some(target.as_str()))
                                .count();
                            if count == 1 { confirmed = true; } else { ambiguous = true; }
                        }
                        // a fully understood resume of another session: no
                        // candidate for ours.
                    }
                    _ => { ambiguous = true; } // recognized exe, unknown syntax
                }
            }
            if confirmed {
                out.push(WindowMatch { window_id: w.window_id.clone(), confidence: MatchConfidence::Confirmed });
            } else if ambiguous {
                out.push(WindowMatch { window_id: w.window_id.clone(), confidence: MatchConfidence::Ambiguous });
            }
        }
        out
    }
}

/// How a process's narrow source env relates to a codex home. A matching
/// `CODEX_HOME` is Same; a different one is Different (positively not this
/// instance); absent/unreadable env is Unknown for every home.
/// Conservatively compare a process's narrow `CODEX_HOME` source metadata to a
/// configured home. Only a validated absolute, non-empty path that EXACTLY
/// matches the configured home is `Same`. Relative, empty, nonrepresentable, or
/// merely textually-different paths cannot prove another source (symlinks and
/// equivalent spellings are unverified without canonicalization), so they are
/// `Unknown` — never a positive cross-instance `Different`.
fn source_rel(home: &Path, env: &[(String, String)]) -> SourceRel {
    let ours = home.to_string_lossy().into_owned();
    match env.iter().find(|(k, _)| k == "CODEX_HOME").map(|(_, v)| v.as_str()) {
        Some(t) if !t.is_empty() && Path::new(t).is_absolute() && t == ours => SourceRel::Same,
        // Missing metadata also represents an unreadable process environment and
        // cannot prove that the process uses our default home.
        _ => SourceRel::Unknown,
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SourceRel { Same, Unknown }

fn prog_name(argv0: &str) -> &str {
    argv0.rsplit('/').next().unwrap_or(argv0)
}

fn file_mtime_ms(p: &Path) -> Option<u64> {
    fs::metadata(p).ok()
        .and_then(|m| m.modified().ok())
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as u64)
}

fn rfc3339_now() -> String {
    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default();
    format!("{}.{}Z", chrono_free::iso(now.as_secs()), now.subsec_millis())
}

// Tiny UTC formatter to dodge a chrono dependency; swap if prettiness becomes a goal.
mod chrono_free {
    pub fn iso(unix: u64) -> String {
        // days since epoch -> civil date via inverse of days_from_civil
        let z = (unix / 86400) as i64 + 719468;
        let era = if z >= 0 { z } else { z - 146096 } / 146097;
        let doe = z - era * 146097;
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        let y = yoe + era * 400;
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        let mp = (5 * doy + 2) / 153;
        let d = doy - (153 * mp + 2) / 5 + 1;
        let mo = if mp < 10 { mp + 3 } else { mp - 9 };
        let y = if mo <= 2 { y + 1 } else { y };
        let t = unix % 86400;
        let (h, mi, s) = (t / 3600, (t % 3600) / 60, t % 60);
        format!("{y:04}-{mo:02}-{d:02}T{h:02}:{mi:02}:{s:02}")
    }
}

fn rollout_title_id(p: &Path) -> Option<String> {
    // rollout-2026-09-19T23-38-41-01a0bd52-e4d4-7f43-af6f-462ea7e8fa57.jsonl
    // The thread id is the trailing UUID (8-4-4-4-12). Take the last five
    // '-' segments (not just the last one — a truncated id wouldn't match the
    // app-server threads table, so no names would resolve).
    let stem = p.file_stem()?.to_string_lossy();
    let mut segs: Vec<&str> = stem.rsplitn(6, '-').collect();
    if segs.len() < 5 { return None; }
    segs.truncate(5);
    segs.reverse();
    Some(segs.join("-"))
}

/// True when the rollout contains something besides the initial session_meta
/// line (i.e. the thread has actually been conversed with or resumed).
fn has_conversation(p: &Path) -> bool {
    fs::read_to_string(p)
        .map(|s| s.lines().any(|l| match serde_json::from_str::<Value>(l) {
            Ok(v) => v["type"] != "session_meta",
            Err(_) => false,
        }))
        .unwrap_or(false)
}

/// Pull the working directory, codex session id, and model from a rollout's
/// session_meta / payload lines (best effort). `session_id` groups a thread
/// (and any subagents) under one session; the model surfaces in a later line.
fn rollout_cwd_session_model(p: &Path) -> (Option<String>, Option<String>, Option<String>) {
    let mut cwd = None;
    let mut session_id = None;
    let mut model = None;
    if let Ok(raw) = fs::read_to_string(p) {
        for line in raw.lines() {
            let Ok(v) = serde_json::from_str::<Value>(line) else { continue };
            let payload = &v["payload"];
            if v["type"] == "session_meta" {
                if cwd.is_none() { cwd = payload.get("cwd").and_then(|c| c.as_str()).map(str::to_string); }
                if session_id.is_none() { session_id = payload.get("session_id").and_then(|c| c.as_str()).map(str::to_string); }
            }
            if model.is_none() { model = payload.get("model").and_then(|m| m.as_str()).map(str::to_string); }
            if cwd.is_some() && session_id.is_some() && model.is_some() { break; }
        }
    }
    (cwd, session_id, model)
}

/// Best-effort display title from a rollout: the first non-injected user
/// message. Skips system/plugin prompts (which start with `<`, e.g.
/// `<recommended_plugins>`), collapses whitespace, and caps the length. Returns
/// None for threads with no real user text (subagent/empty threads), so the
/// caller falls back to the id.
impl crate::provider::Provider for CodexProvider {
    fn descriptor(&self) -> ProviderDescriptor {
        ProviderDescriptor { id: self.id.clone(), type_key: "codex", display_name: self.label.clone() }
    }
    fn capabilities(&self) -> ProviderCapabilities { self.capabilities() }
    fn list(&self) -> Result<Vec<Session>> { self.list() }
    fn rename(&self, s: &Session, t: &str) -> Result<()> { self.rename(s, t) }
    fn resume_plan(&self, s: &Session) -> Result<LaunchRequest> { self.resume_plan(s) }
    fn create(&self, name: &str, dir: &str) -> Result<CreateOutcome> { self.create(name, dir) }
    fn match_session(&self, session: &Session, _snapshot: &[Session], evidence: &ProcessEvidence) -> Vec<WindowMatch> {
        self.match_session(session, _snapshot, evidence)
    }
}
```

> **Note (tests).** The codex fixture test lives in the next chunk block appended
> to `prov::codex` so its temp-dir helpers stay co-located with the adapter.


## 5.3 Antigravity adapter (optional, compiled-in)

`agy` is the Antigravity CLI (Google exa/jetski lineage, v1.2.9 observed on eris
2026-09-23). It keeps its conversation index in an SQLite database named
`conversation_summaries.db` under the app data dir (default
`~/.gemini/antigravity-cli`), whose `conversation_summaries` table carries the
stable conversation UUID (`conversation_id`), the display `title`, an activity
clock (`last_modified_time`, `last_user_input_time`), liveness signals
(`not_fully_idle`, `killed`), source separation (`project_id`, `agent_name`),
and the workspace URIs. The data dir is overridable with the
`ANTIGRAVITY_APP_DATA_DIR` environment variable (verified in the binary).

This adapter is compiled-in but NOT auto-registered: it only exists when an
explicit `[[providers]]` entry with `type = "antigravity"` is configured. It is
not part of `builtin_registry` (which stays OpenCode-then-Codex).

``` {.rust #prov-antigravity path="src/provider/antigravity.rs"}
use anyhow::{anyhow, Context, Result};
use rusqlite::Connection;
use std::fs;
use std::path::{Path, PathBuf};

use crate::config::ProviderOptions;
use crate::model::{
    CreateOutcome, LaunchRequest, MatchConfidence, ProcessEvidence, ProviderId, Session,
    WindowMatch,
};
use crate::provider::{
    NewSessionCapability, ProviderCapabilities, ProviderDescriptor,
};

/// The Antigravity adapter: reads the `conversation_summaries.db` SQLite index
/// under an app data dir. Default data dir is `~/.gemini/antigravity-cli`
/// (observed on eris 2026-09-23 for agy 1.2.9); `home` overrides it and is
/// wired to launched processes via `ANTIGRAVITY_APP_DATA_DIR`.
pub struct AntigravityProvider {
    home: PathBuf,
    id: ProviderId,
    label: String,
}

impl AntigravityProvider {
    pub fn new(home: &Path, id: ProviderId) -> Self {
        Self { home: home.to_path_buf(), id, label: "antigravity".into() }
    }

    /// Default app data dir. `agy` is a gemini-cli-family product; the observed
    /// data root on eris is `$HOME/.gemini/antigravity-cli`.
    fn default_home() -> PathBuf {
        if let Ok(h) = std::env::var("HOME") {
            return PathBuf::from(h).join(".gemini").join("antigravity-cli");
        }
        PathBuf::from(".")
    }

    /// Decode and validate `antigravity` options: optional absolute `home`.
    pub fn parse_options(options: &ProviderOptions) -> anyhow::Result<PathBuf> {
        for key in options.keys() {
            if key != "home" {
                return Err(anyhow::anyhow!("unknown antigravity option {key:?}"));
            }
        }
        let Some(home) = options.get("home") else {
            return Ok(Self::default_home());
        };
        let home = home.as_str().ok_or_else(|| anyhow!("antigravity home must be a string"))?;
        if home.trim().is_empty() {
            return Err(anyhow!("antigravity home must be nonempty"));
        }
        let p = PathBuf::from(home);
        if !p.is_absolute() {
            return Err(anyhow!("antigravity home must be an absolute path: {home:?}"));
        }
        Ok(p)
    }

    /// Compiled-in factory: validate options and construct the adapter. Only
    /// reached through an explicit `[[providers]]` entry.
    pub fn factory(id: ProviderId, label: Option<String>, options: &ProviderOptions)
        -> anyhow::Result<Box<dyn crate::provider::Provider>> {
        let home = Self::parse_options(options)?;
        let mut p = Self::new(&home, id);
        p.label = label.unwrap_or_else(|| "antigravity".into());
        Ok(Box::new(p))
    }

    /// Path of the conversation summary SQLite index inside the data dir.
    fn db_path(&self) -> PathBuf { self.home.join("conversation_summaries.db") }

    fn list(&self) -> Result<Vec<Session>> {
        let db = self.db_path();
        // A MISSING index is a fresh install -> empty list. An index that exists
        // but cannot be inspected (permissions, corruption, io) is an ERROR,
        // never silently treated as fresh.
        match fs::metadata(&db) {
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
            Err(e) => return Err(anyhow!("cannot inspect antigravity summary db {}: {e}", db.display())),
            Ok(_) => {}
        }
        let conn = Connection::open_with_flags(&db, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)
            .with_context(|| format!("open antigravity summary db {}", db.display()))?;
        let query = "SELECT conversation_id, title, preview, last_modified_time, \
                     workspace_uris, project_id, agent_name, not_fully_idle, killed \
                     FROM conversation_summaries";
        let mut stmt = conn.prepare(query)
            .with_context(|| "prepare conversation_summaries select")?;
        let rows = stmt.query_map([], |row| {
            let active = row.get::<_, i64>(7).unwrap_or(0) != 0
                && row.get::<_, i64>(8).unwrap_or(0) == 0;
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?,
                row.get::<_, String>(2)?, row.get::<_, Option<String>>(3)?,
                row.get::<_, String>(4)?, row.get::<_, String>(5)?,
                row.get::<_, String>(6)?, active))
        })?;
        let mut out = Vec::new();
        for r in rows {
            let (id, title, preview, modified, workspaces, _project, agent, active) =
                r.with_context(|| "decode antigravity summary row")?;
            let title = if title.trim().is_empty() {
                Some(preview).filter(|p| !p.trim().is_empty())
            } else { Some(title) };
            out.push(Session {
                provider_id: self.id.clone(),
                id,
                title,
                slug: None,
                directory: first_workspace(&workspaces),
                session_id: None,
                agent: if agent.trim().is_empty() { None } else { Some(agent) },
                model: None,
                created_ms: None,
                updated_ms: modified.and_then(|m| parse_go_datetime_ms(&m)),
                active,
            });
        }
        out.sort_by(|a, b| {
            b.updated_ms.unwrap_or(0).cmp(&a.updated_ms.unwrap_or(0))
                .then_with(|| a.id.cmp(&b.id))
        });
        Ok(out)
    }

    fn capabilities(&self) -> ProviderCapabilities {
        // Rename is unsupported: agy has no CLI rename flag (only the TUI
        // /rename slash command), and the summary DB is a reconciled cache, so
        // writing `title` there directly would be fabricated surface.
        ProviderCapabilities {
            rename: false,
            resume: true,
            new_session: NewSessionCapability { supported: true, applies_title: false, applies_cwd: true },
        }
    }

    /// Pure resume plan: `agy --conversation <id>` resumes the exact
    /// conversation by its stable UUID.
    fn resume_plan(&self, s: &Session) -> Result<LaunchRequest> {
        Ok(LaunchRequest {
            program: "agy".into(),
            args: vec!["--conversation".into(), s.id.clone()],
            cwd: s.directory.clone(),
            env: self.source_env()?,
        })
    }

    /// New-session creation is a launch-to-create plan: plain `agy` started in
    /// the requested cwd opens a NEW conversation in that workspace (agy never
    /// auto-resumes unless `--continue`/`-c` is passed). The requested title is
    /// used only as a window label, not native session metadata.
    fn create(&self, _name: &str, dir: &str) -> Result<CreateOutcome> {
        let cwd = if dir.trim().is_empty() { None } else { Some(dir.trim().to_string()) };
        Ok(CreateOutcome::LaunchToCreate(LaunchRequest {
            program: "agy".into(),
            args: vec![],
            cwd,
            env: self.source_env()?,
        }))
    }

    /// Narrow source environment: pin the data dir so a non-default instance
    /// runs against its own summary index (verified env var). A home that is
    /// not valid UTF-8 is rejected (never lossily substituted), since the env
    /// value must round-trip identically to the configured data dir.
    fn source_env(&self) -> Result<Vec<(String, String)>> {
        let home = self.home.to_str()
            .ok_or_else(|| anyhow!("antigravity home is not valid UTF-8: {:?}", self.home))?;
        Ok(vec![("ANTIGRAVITY_APP_DATA_DIR".to_string(), home.to_string())])
    }

    /// Interpret a generic process snapshot for one session.
    /// - `agy --conversation <id>`: confirmed when `<id>` equals the session's
    ///   native UUID; a fully-understood resume of another session yields no
    ///   candidate for ours.
    /// - `agy --continue` / `agy -c`: resumes the MOST RECENT conversation,
    ///   which is not provable to be ours -> Ambiguous.
    /// - any other `agy` argv: recognized executable, unknown syntax -> Ambiguous.
    ///
    /// Source discrimination: a process whose `ANTIGRAVITY_APP_DATA_DIR` (if
    /// present) names a different data dir is not this instance; absent source
    /// env is Unknown (ambiguous), never a confirmed adoption.
    fn match_session(&self, session: &Session, _snapshot: &[Session],
                     evidence: &ProcessEvidence) -> Vec<WindowMatch> {
        let mut out: Vec<WindowMatch> = Vec::new();
        for w in &evidence.windows {
            let mut confirmed = false;
            let mut ambiguous = false;
            for p in &w.procs {
                let argv = &p.argv;
                let Some(first) = argv.first() else { continue };
                if prog_name(first) != "agy" { continue; }
                match source_rel(&self.home, &p.env) {
                    SourceRel::Unknown => { ambiguous = true; continue; }
                    SourceRel::Same => {}
                }
                match argv.as_slice() {
                    [_, flag, target] if flag == "--conversation" => {
                        if target == &session.id {
                            confirmed = true;
                        }
                        // a fully-understood resume of another session: no
                        // candidate for ours
                    }
                    [_, flag] if flag == "-c" || flag == "--continue" => {
                        // most-recent resume is not attributable to a specific
                        // session
                        ambiguous = true;
                    }
                    _ => { ambiguous = true; } // recognized exe, unknown syntax
                }
            }
            if confirmed {
                out.push(WindowMatch { window_id: w.window_id.clone(), confidence: MatchConfidence::Confirmed });
            } else if ambiguous {
                out.push(WindowMatch { window_id: w.window_id.clone(), confidence: MatchConfidence::Ambiguous });
            }
        }
        out
    }
}

/// How a process's narrow source env relates to a data dir. A matching
/// `ANTIGRAVITY_APP_DATA_DIR` is Same; absent/unreadable env is Unknown for
/// every data dir (mirrors the codex `CODEX_HOME` policy).
fn source_rel(home: &Path, env: &[(String, String)]) -> SourceRel {
    // A home that is not valid UTF-8 cannot be compared faithfully -> Unknown.
    let Some(ours) = home.to_str() else { return SourceRel::Unknown };
    match env.iter().find(|(k, _)| k == "ANTIGRAVITY_APP_DATA_DIR").map(|(_, v)| v.as_str()) {
        Some(t) if !t.is_empty() && Path::new(t).is_absolute() && t == ours => SourceRel::Same,
        _ => SourceRel::Unknown,
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SourceRel { Same, Unknown }

fn prog_name(argv0: &str) -> &str {
    argv0.rsplit('/').next().unwrap_or(argv0)
}

/// Decode one workspace value. Only two forms are understood:
/// - a `file://` URI (percent-decoded), optionally `uri:`-prefixed;
/// - a plain absolute path.
///
/// Anything else (protocols we do not know, bare names, ambiguous lists) is
/// None. We deliberately do NOT guess comma/newline splitting: a real path may
/// legitimately contain a comma, so splitting a non-JSON string corrupts it.
/// (The encoding of the real column is unobserved — the summary table is
/// empty on eris — so only forms we can decode unambiguously are accepted.)
fn first_workspace(raw: &str) -> Option<String> {
    let raw = raw.trim();
    if raw.is_empty() { return None; }
    // A JSON array of workspace strings is the one multi-value shape we accept.
    if raw.starts_with('[') {
        let v: serde_json::Value = serde_json::from_str(raw).ok()?;
        let arr = v.as_array()?;
        for e in arr {
            let s = e.as_str()?;
            if let Some(p) = decode_workspace(s) { return Some(p); }
        }
        return None;
    }
    decode_workspace(raw)
}

/// Decode a single workspace value: `file://` URI (percent-decoded, host-less
/// or localhost only) or a plain absolute path. `uri:` prefix is stripped first.
fn decode_workspace(s: &str) -> Option<String> {
    let s = s.trim();
    let s = s.strip_prefix("uri:").unwrap_or(s).trim();
    if s.is_empty() { return None; }
    if let Some(rest) = s.strip_prefix("file://") {
        // file:///path -> path; file://localhost/path -> path; any other host
        // (remote) is not a local cwd.
        // localhost/ and a bare host-less path are both local; any other
        // authority host is not a local cwd.
        let stripped = rest.strip_prefix("localhost/")
            .or_else(|| rest.strip_prefix('/'))?;
        let rest = format!("/{stripped}");
        return percent_decode(&rest).filter(|p| p.starts_with('/'));
    }
    // A plain absolute path is accepted verbatim (percent sequences are NOT
    // decoded for plain paths — they may be literal characters), UNLESS it
    // contains a comma or newline: such a value is ambiguous with a list, so
    // it yields None rather than a guessed launch directory.
    if s.starts_with('/') && !s.contains([',', '\n']) { return Some(s.to_string()); }
    None
}

/// Percent-decode a file URI path (%XX -> byte). Invalid or trailing lone `%`
/// sequences fail the whole decode (None), never a half-decoded path.
fn percent_decode(s: &str) -> Option<String> {
    let bytes = s.as_bytes();
    let mut out: Vec<u8> = Vec::with_capacity(bytes.len());
    let mut i = 0usize;
    while i < bytes.len() {
        match bytes[i] {
            b'%' => {
                let hex = bytes.get(i + 1..i + 3)?;
                let hi = hex_char(hex[0])?;
                let lo = hex_char(hex[1])?;
                out.push((hi << 4) | lo);
                i += 3;
            }
            b => { out.push(b); i += 1; }
        }
    }
    String::from_utf8(out).ok()
}

fn hex_char(b: u8) -> Option<u8> {
    match b {
        b'0'..=b'9' => Some(b - b'0'),
        b'a'..=b'f' => Some(b - b'a' + 10),
        b'A'..=b'F' => Some(b - b'A' + 10),
        _ => None,
    }
}

/// Parse the agy summary timestamp with a validated, checked parser. Supported
/// form (verified against the schema): `YYYY-MM-DD HH:MM:SS[.ffffff]` UTC, plus
/// the ` +0000 UTC` suffix the product writes. Invalid, pre-epoch, offset,
/// out-of-range, or over-precise timestamps yield None — never a wrong or
/// overflowed clock.
/// Days in a Gregorian month for a given year (leap-aware).
fn days_in_month(y: i64, m: u32) -> u32 {
    match m {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 => if (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 { 29 } else { 28 },
        _ => 0,
    }
}

fn parse_go_datetime_ms(s: &str) -> Option<u64> {
    let s = s.trim();
    // Accept an explicit trailing " +0000 UTC" (the product's serialization);
    // any other offset is NOT the supported format and is rejected.
    let s = if let Some(t) = s.strip_suffix(" +0000 UTC") { t } else { s };
    // A `+`/`Z`/`T` marks an offset or ISO separator we do not support; dashes
    // are part of the verified YYYY-MM-DD form and are allowed.
    if s.contains(['+', 'Z', 'T']) { return None; }
    let (date, time) = s.split_once(' ')?;
    let mut parts = date.split('-');
    let y: i64 = parts.next()?.parse().ok()?;
    if !(1970..=9999).contains(&y) { return None; }
    let mo: u32 = parts.next()?.parse().ok()?;
    let d: u32 = parts.next()?.parse().ok()?;
    if !(1..=12).contains(&mo) || !(1..=31).contains(&d) { return None; }
    let mut t = time.split('.');
    let hms = t.next()?;
    let mut hp = hms.split(':');
    let hh: u32 = hp.next()?.parse().ok()?;
    let mi: u32 = hp.next()?.parse().ok()?;
    let ss: u32 = hp.next()?.parse().ok()?;
    if hh > 23 || mi > 59 || ss > 59 { return None; }
    // Fraction: 1..=6 digits (microsecond precision). Longer is unsupported.
    let mut micros = 0u32;
    if let Some(f) = t.next() {
        if f.is_empty() || f.len() > 6 || !f.bytes().all(|b| b.is_ascii_digit()) { return None; }
        micros = f.parse::<u32>().ok()? * 10u32.pow(6 - f.len() as u32);
    }
    if t.next().is_some() { return None; } // more than one fraction part
    // Checked civil conversion; guard against pre-epoch and arithmetic overflow.
    let days = days_from_civil(y, mo, d)?;
    let secs = days.checked_mul(86_400)?
        .checked_add(i64::from(hh) * 3600)?
        .checked_add(i64::from(mi) * 60)?
        .checked_add(i64::from(ss))?;
    if secs < 0 { return None; } // pre-epoch not representable in this u64 millis scale
    (secs as u64).checked_mul(1_000)?.checked_add(u64::from(micros / 1000))
}

/// days since epoch for a civil date, with validation. Returns None for dates
/// that are out of the representable range (so invalid dates are not normalized
/// into a plausible-but-wrong instant).
fn days_from_civil(y: i64, m: u32, d: u32) -> Option<i64> {
    if !(1..=12).contains(&m) { return None; }
    if d < 1 || d > days_in_month(y, m) { return None; }
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (i64::from(m) + 9) % 12;
    let doy = (153 * mp + 2) / 5 + i64::from(d) - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era.checked_mul(146_097)?.checked_add(doe)?.checked_sub(719_468)
}

impl crate::provider::Provider for AntigravityProvider {
    fn descriptor(&self) -> ProviderDescriptor {
        ProviderDescriptor { id: self.id.clone(), type_key: "antigravity", display_name: self.label.clone() }
    }
    fn capabilities(&self) -> ProviderCapabilities { self.capabilities() }
    fn list(&self) -> Result<Vec<Session>> { self.list() }
    fn resume_plan(&self, s: &Session) -> Result<LaunchRequest> { self.resume_plan(s) }
    fn create(&self, name: &str, dir: &str) -> Result<CreateOutcome> { self.create(name, dir) }
    fn match_session(&self, session: &Session, _snapshot: &[Session], evidence: &ProcessEvidence) -> Vec<WindowMatch> {
        self.match_session(session, _snapshot, evidence)
    }
}
```



``` {.rust #prov-antigravity-tests append="src/provider/antigravity.rs"}
#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{MatchConfidence, ProcEvidence, ProcessEvidence, WindowEvidence};
    use rusqlite::Connection;
    use std::path::PathBuf;

    struct TempDir(PathBuf);

    impl TempDir {
        fn new() -> Self {
            let nanos = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_nanos();
            let p = std::env::temp_dir().join(format!("pinga-agy-test-{}-{}", std::process::id(), nanos));
            std::fs::create_dir_all(&p).expect("create temp dir");
            TempDir(p)
        }
        fn path(&self) -> &Path { &self.0 }
    }

    impl Drop for TempDir {
        fn drop(&mut self) { let _ = std::fs::remove_dir_all(&self.0); }
    }

    const UUID_A: &str = "aaaaaaaa-0000-0000-0000-000000000001";
    const UUID_B: &str = "bbbbbbbb-0000-0000-0000-000000000002";

    type Row<'a> = (&'a str, &'a str, &'a str, &'a str, &'a str, &'a str, &'a str, bool);

    fn seed(db: &Path, rows: &[Row<'_>]) {
        let conn = Connection::open(db).expect("open db");
        conn.execute_batch("CREATE TABLE IF NOT EXISTS conversation_summaries (            conversation_id TEXT PRIMARY KEY, title TEXT NOT NULL DEFAULT '',             preview TEXT NOT NULL DEFAULT '', step_count INTEGER NOT NULL DEFAULT 0,             last_modified_time DATETIME NOT NULL, workspace_uris TEXT NOT NULL DEFAULT '',             status TEXT NOT NULL DEFAULT '', source TEXT NOT NULL DEFAULT '',             project_id TEXT NOT NULL DEFAULT '', agent_name TEXT NOT NULL DEFAULT '',             parent_conversation_id TEXT NOT NULL DEFAULT '', nesting_depth INTEGER NOT NULL DEFAULT 0,             battle_id TEXT NOT NULL DEFAULT '', winning_conversation_id TEXT NOT NULL DEFAULT '',             not_fully_idle NUMERIC NOT NULL DEFAULT false, killed NUMERIC NOT NULL DEFAULT false,             last_user_input_time DATETIME NOT NULL DEFAULT '', last_user_input_step_index INTEGER NOT NULL DEFAULT -1,             app_data_dir TEXT NOT NULL DEFAULT '', group_id TEXT NOT NULL DEFAULT '')")
            .expect("create table");
        for (id, title, preview, modified, uris, project, agent, active) in rows {
            conn.execute("INSERT OR REPLACE INTO conversation_summaries                 (conversation_id, title, preview, last_modified_time, workspace_uris,                  project_id, agent_name, not_fully_idle, killed)                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 0)",
                rusqlite::params![id, title, preview, modified, uris, project, agent, if *active { 1 } else { 0 }])
                .expect("insert row");
        }
    }

    fn provider(home: &Path) -> AntigravityProvider {
        AntigravityProvider::new(home, ProviderId::new("antigravity").unwrap())
    }

    /// list() maps the summary DB onto sessions stamped with the configured
    /// instance id, newest first, with a real (active) vs idle (inactive) split,
    /// titles falling back to preview, and a workspace path extracted.
    #[test]
    fn lists_summary_db_sessions_newest_first_with_instance_id() {
        let tmp = TempDir::new();
        let db = tmp.path().join("conversation_summaries.db");
        seed(&db, &[
            (UUID_A, "Alpha", "", "2026-09-23 01:00:05.123456", "/home/u/w/a", "p1", "agent-x", true),
            (UUID_B, "", "beta preview", "2026-09-23 00:59:00", "[\"/home/u/w/b\"]", "p2", "", false),
        ]);
        let p = provider(tmp.path());
        let s = p.list().expect("list");
        assert_eq!(s.len(), 2);
        assert_eq!(s[0].id, UUID_A);
        assert_eq!(s[0].title.as_deref(), Some("Alpha"));
        assert_eq!(s[0].provider_id.as_str(), "antigravity");
        assert!(s[0].active);
        assert_eq!(s[0].updated_ms, Some(1790125205123));
        assert_eq!(s[0].directory.as_deref(), Some("/home/u/w/a"));
        assert_eq!(s[0].agent.as_deref(), Some("agent-x"));
        assert_eq!(s[1].id, UUID_B);
        assert_eq!(s[1].title.as_deref(), Some("beta preview"));
        assert!(!s[1].active);
        assert_eq!(s[1].directory.as_deref(), Some("/home/u/w/b"));
    }

    /// A missing summary DB yields an empty list (a fresh install), not an error.
    #[test]
    fn malformed_summary_row_fails_the_snapshot() {
        let temp = TempDir::new();
        let db = temp.path().join("conversation_summaries.db");
        seed(&db, &[]);
        let conn = Connection::open(&db).unwrap();
        conn.execute("INSERT INTO conversation_summaries (conversation_id, title, last_modified_time) VALUES ('bad', X'FF', '2026-09-23 00:00:00')", []).unwrap();
        drop(conn);
        assert!(provider(temp.path()).list().is_err(),
            "a decode failure must not become a successful empty/partial snapshot");
    }

    #[test]
    fn empty_home_lists_nothing() {
        let tmp = TempDir::new();
        let p = provider(tmp.path());
        assert!(p.list().expect("list").is_empty());
    }

    /// Resume is `agy --conversation <uuid>`, cwd = session workspace, and the
    /// data dir is pinned via ANTIGRAVITY_APP_DATA_DIR.
    #[test]
    fn resume_plan_uses_conversation_flag_and_pins_data_dir() {
        let tmp = TempDir::new();
        let p = provider(tmp.path());
        let s = Session {
            provider_id: p.id.clone(), id: UUID_A.to_string(), title: None, slug: None,
            directory: Some("/home/u/w/a".into()), session_id: None, agent: None, model: None,
            created_ms: None, updated_ms: None, active: false,
        };
        let plan = p.resume_plan(&s).expect("resume plan");
        assert_eq!(plan.program, "agy");
        assert_eq!(plan.args, vec!["--conversation", UUID_A]);
        assert_eq!(plan.cwd.as_deref(), Some("/home/u/w/a"));
        assert!(plan.env.iter().any(|(k, v)|
            k == "ANTIGRAVITY_APP_DATA_DIR" && v == tmp.path().to_string_lossy().as_ref()));
    }

    /// Creation is a launch-to-create plan in the requested cwd; the data dir
    /// env is pinned and the title is not native metadata.
    #[test]
    fn create_launches_agy_in_requested_cwd() {
        let tmp = TempDir::new();
        let p = provider(tmp.path());
        let o = p.create("Some Title", "/tmp").expect("create");
        let crate::model::CreateOutcome::LaunchToCreate(plan) = o else { panic!("launch-to-create") };
        assert_eq!(plan.program, "agy");
        assert_eq!(plan.args, Vec::<String>::new());
        assert_eq!(plan.cwd.as_deref(), Some("/tmp"));
        assert!(plan.env.iter().any(|(k, v)|
            k == "ANTIGRAVITY_APP_DATA_DIR" && v == tmp.path().to_string_lossy().as_ref()));
    }

    /// `--conversation <uuid>` is a Confirmed match for that session (exact id),
    /// Ambiguous for a different session; `--continue` and bare `agy` are
    /// Ambiguous (most-recent / unknown-syntax), and a differing data dir is not
    /// this instance (no candidate).
    #[test]
    fn matches_agy_windows_by_conversation_flag_and_data_dir() {
        let tmp = TempDir::new();
        let p = provider(tmp.path());
        let ours = Session {
            provider_id: p.id.clone(), id: UUID_A.to_string(), title: Some("Alpha".into()),
            slug: None, directory: None, session_id: None, agent: None, model: None,
            created_ms: None, updated_ms: None, active: false,
        };
        let other = Session {
            provider_id: p.id.clone(), id: UUID_B.to_string(), title: None,
            slug: None, directory: None, session_id: None, agent: None, model: None,
            created_ms: None, updated_ms: None, active: false,
        };
        let snapshot = vec![ours.clone(), other.clone()];
        let ev = |argv: &[&str], env: &[(&str, &str)]| ProcessEvidence {
            windows: vec![WindowEvidence {
                window_id: "@9".into(),
                procs: vec![ProcEvidence {
                    pid: 1,
                    argv: argv.iter().map(|s| s.to_string()).collect(),
                    env: env.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect(),
                }],
            }],
            complete: true,
            errors: vec![],
        };
        let home = tmp.path().to_string_lossy().into_owned();
        // exact conversation resume, same data dir -> Confirmed for ours, none for other
        let m = p.match_session(&ours, &snapshot, &ev(&["/usr/bin/agy", "--conversation", UUID_A], &[("ANTIGRAVITY_APP_DATA_DIR", home.as_str())]));
        assert_eq!(m.len(), 1);
        assert_eq!(m[0].confidence, MatchConfidence::Confirmed);
        let m = p.match_session(&other, &snapshot, &ev(&["/usr/bin/agy", "--conversation", UUID_A], &[("ANTIGRAVITY_APP_DATA_DIR", home.as_str())]));
        assert!(m.is_empty());
        // continue / bare agy -> Ambiguous
        for argv in [vec!["agy", "--continue"], vec!["agy", "-c"], vec!["agy"]] {
            let m = p.match_session(&ours, &snapshot,
                &ev(&argv.to_vec(), &[("ANTIGRAVITY_APP_DATA_DIR", home.as_str())]));
            assert_eq!(m.len(), 1, "argv {argv:?} should be ambiguous");
            assert_eq!(m[0].confidence, MatchConfidence::Ambiguous);
        }
        // foreign data dir -> not provably ours (conservative), Ambiguous
        let m = p.match_session(&ours, &snapshot,
            &ev(&["agy", "--conversation", UUID_A], &[("ANTIGRAVITY_APP_DATA_DIR", "/elsewhere")]));
        assert_eq!(m.len(), 1);
        assert_eq!(m[0].confidence, MatchConfidence::Ambiguous);
    }

    /// Options: `home` is optional (defaults to the product data dir) and must
    /// be absolute when supplied; unknown options are rejected at the boundary.
    #[test]
    fn parse_options_validates_home_and_rejects_unknown() {
        use std::collections::BTreeMap;
        let mut unknown = BTreeMap::new();
        unknown.insert("nope".to_string(), toml::Value::Boolean(true));
        assert!(AntigravityProvider::parse_options(&unknown).is_err());
        let mut rel = BTreeMap::new();
        rel.insert("home".to_string(), toml::Value::String("rel/dir".into()));
        assert!(AntigravityProvider::parse_options(&rel).is_err());
        let mut abs = BTreeMap::new();
        abs.insert("home".to_string(), toml::Value::String("/abs/dir".into()));
        assert_eq!(AntigravityProvider::parse_options(&abs).unwrap(), PathBuf::from("/abs/dir"));
        // omitted home -> default under $HOME/.gemini/antigravity-cli
        let empty = BTreeMap::new();
        assert_eq!(AntigravityProvider::parse_options(&empty).unwrap(),
                   std::env::var("HOME").map(|h| PathBuf::from(h).join(".gemini").join("antigravity-cli")).unwrap());
    }

    // ---- workspace URI decoding (synthetic fixtures) ------------------------

    #[test]
    fn first_workspace_decodes_file_uris_and_paths_but_not_guesses() {
        // file:// URIs are percent-decoded; host-less and localhost are local.
        assert_eq!(first_workspace("file:///home/u/w/with%20space"), Some("/home/u/w/with space".into()));
        assert_eq!(first_workspace("file://localhost/home/u/w/a"), Some("/home/u/w/a".into()));
        assert_eq!(first_workspace("uri:file:///home/u/w/a"), Some("/home/u/w/a".into()));
        // plain absolute paths pass through (percent sequences stay literal).
        assert_eq!(first_workspace("/home/u/w/a"), Some("/home/u/w/a".into()));
        // JSON arrays: first decodable entry wins.
        assert_eq!(first_workspace(r#"["file:///a%20b","file:///c"]"#), Some("/a b".into()));
        // A comma in a plain path is ambiguous with a list: never a guessed
        // single path, and never a corrupted comma-split either.
        assert_eq!(first_workspace("/a,/b"), None);
        assert_eq!(first_workspace("/home/u/we,ird"), None);
        // Unknown protocols / bare names / empty -> None.
        assert_eq!(first_workspace("https://x/y"), None);
        assert_eq!(first_workspace("somename"), None);
        assert_eq!(first_workspace(""), None);
        // Invalid percent-encoding fails the whole decode.
        assert_eq!(first_workspace("file:///a%2"), None);
        // A remote authority host is not a local cwd.
        assert_eq!(first_workspace("file://remotehost/path"), None);
    }

    // ---- checked datetime parsing -------------------------------------------

    #[test]
    fn parse_go_datetime_accepts_verified_form_and_rejects_invalid() {
        // Supported form: YYYY-MM-DD HH:MM:SS[.ffffff] UTC.
        assert_eq!(parse_go_datetime_ms("2026-09-23 01:00:05"), Some(1790125205000));
        assert_eq!(parse_go_datetime_ms("2026-09-23 01:00:05.123456"), Some(1790125205123));
        assert_eq!(parse_go_datetime_ms("2026-09-23 01:00:05 +0000 UTC"), Some(1790125205000));
        // Fraction precision: 1..6 digits are scaled, longer is unsupported.
        assert_eq!(parse_go_datetime_ms("2026-09-23 01:00:05.1"), Some(1790125205100));
        assert_eq!(parse_go_datetime_ms("2026-09-23 01:00:05.1234567"), None);
        // Pre-epoch is not representable in the u64 millis scale.
        assert_eq!(parse_go_datetime_ms("1969-12-31 23:59:59"), None);
        // Any explicit offset is not the supported format.
        assert_eq!(parse_go_datetime_ms("2026-09-23 01:00:05 +0200"), None);
        assert_eq!(parse_go_datetime_ms("2026-09-23T01:00:05Z"), None);
        // Out-of-range fields and malformed inputs -> None, never normalized.
        assert_eq!(parse_go_datetime_ms("2026-13-01 00:00:00"), None);
        assert_eq!(parse_go_datetime_ms("2026-02-31 00:00:00"), None);
        assert_eq!(parse_go_datetime_ms("2026-09-23 25:00:00"), None);
        assert_eq!(parse_go_datetime_ms("2026-09-23 00:61:00"), None);
        assert_eq!(parse_go_datetime_ms("not a date"), None);
        assert_eq!(parse_go_datetime_ms(""), None);
    }

    // ---- DB access distinction ----------------------------------------------

    #[test]
    fn missing_db_is_fresh_but_existing_unopenable_db_is_an_error() {
        let tmp = TempDir::new();
        let p = provider(tmp.path());
        assert!(p.list().expect("missing db is fresh").is_empty());
        // A directory (exists, not a readable sqlite db) is an inspection error.
        let dir_db = tmp.path().join("conversation_summaries.db");
        std::fs::create_dir(&dir_db).unwrap();
        assert!(p.list().is_err(), "an existing but unopenable path must be an error, not empty");
    }

    // ---- non-UTF-8 home rejection -------------------------------------------

    #[test]
    fn non_utf8_home_is_rejected_in_launch_env_not_lossy() {
        use std::os::unix::ffi::OsStringExt;
        let tmp = TempDir::new();
        let bad = tmp.path().join(std::ffi::OsString::from_vec(vec![0x2f, 0x78, 0xff]));
        let p = AntigravityProvider::new(&bad, ProviderId::new("antigravity").unwrap());
        let s = Session {
            provider_id: p.id.clone(), id: UUID_A.to_string(), title: None, slug: None,
            directory: None, session_id: None, agent: None, model: None,
            created_ms: None, updated_ms: None, active: false,
        };
        assert!(p.resume_plan(&s).is_err(), "non-UTF-8 home must fail, not lossy-convert");
        assert!(p.create("n", "/tmp").is_err());
    }

    // ---- REAL collector -> adapter env path ---------------------------------

    /// Spawn a real short-lived `agy`-shaped process carrying a
    /// `ANTIGRAVITY_APP_DATA_DIR`, read it back through the REAL `/proc`
    /// collector (`ProcFs`), and assert the adapter confirms the exact
    /// conversation from the collected evidence. This exercises the
    /// collector -> adapter env hand-off end to end, not a hand-built
    /// ProcEvidence.
    #[test]
    fn real_collector_reads_source_env_and_adapter_confirms() {
        use crate::launcher::{ProcFs, ProcReader};
        use std::process::{Command, Stdio};
        use std::time::Duration;
        let tmp = TempDir::new();
        let data_dir = tmp.path().join("data");
        std::fs::create_dir_all(&data_dir).unwrap();
        let ddir = data_dir.to_string_lossy().into_owned();
        // A real `agy`-named executable: a symlink to /bin/sleep so argv[0]
        // basename is "agy" and it stays alive for /proc to expose argv+env.
        let agy = tmp.path().join("agy");
        #[cfg(unix)]
        std::os::unix::fs::symlink("/bin/sleep", &agy).unwrap();
        // sleep accepts only a duration; argv[0] basename is still "agy" and
        // the env var is what the collector must carry (exact-conversation argv
        // shapes are covered by the hand-built ProcEvidence tests above).
        let mut child = Command::new(&agy)
            .arg("5")
            .env("ANTIGRAVITY_APP_DATA_DIR", &ddir)
            .stdout(Stdio::null()).stderr(Stdio::null())
            .spawn().expect("spawn real agy-shaped process");
        let pid = child.id() as u64;
        let collector = ProcFs;
        // Give /proc a moment to expose the exec'd argv.
        std::thread::sleep(Duration::from_millis(150));
        let tree = collector.tree(pid, 3);
        let ev = ProcessEvidence {
            windows: vec![WindowEvidence {
                window_id: "@1".into(),
                procs: tree.procs.clone(),
            }],
            complete: tree.complete,
            errors: vec![],
        };
        let _ = child.kill();
        let _ = child.wait();
        // The real collector must have surfaced BOTH the agy argv and the env.
        assert!(ev.windows[0].procs.iter().any(|p| p.argv.first().map(|a| a.ends_with("agy")).unwrap_or(false)),
            "real collector saw the agy process: {:?}", ev.windows[0].procs);
        assert!(ev.windows[0].procs.iter().flat_map(|p| &p.env)
            .any(|(k, v)| k == "ANTIGRAVITY_APP_DATA_DIR" && v == &ddir),
            "real collector carried ANTIGRAVITY_APP_DATA_DIR: {:?}", ev.windows[0].procs);
        // Feed the collected evidence into the adapter on the SAME home: the env
        // must be read (Same source), so the window is a candidate (Ambiguous
        // for the non-conversation argv — a recognised agy of unknown syntax).
        let home = tmp.path().join("home");
        std::fs::create_dir_all(&home).unwrap();
        let p = provider(&home);
        let ours = Session {
            provider_id: p.id.clone(), id: UUID_A.to_string(), title: None, slug: None,
            directory: None, session_id: None, agent: None, model: None,
            created_ms: None, updated_ms: None, active: false,
        };
        let m = p.match_session(&ours, std::slice::from_ref(&ours), &ev);
        assert_eq!(m.len(), 1, "adapter consumed the REAL collector evidence");
        assert_eq!(m[0].confidence, MatchConfidence::Ambiguous,
            "non-conversation argv is ambiguous, never a false confirmation");
    }
}

```
``` {.rust #prov-codex-tests append="src/provider/codex.rs"}
#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{MatchConfidence, ProcEvidence, ProcessEvidence, WindowEvidence};
    use rusqlite::Connection;
    use std::path::PathBuf;

    struct TempDir(PathBuf);

    impl TempDir {
        fn new() -> Self {
            let nanos = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_nanos();
            let p = std::env::temp_dir().join(format!("pinga-codex-test-{}-{}", std::process::id(), nanos));
            std::fs::create_dir_all(&p).expect("create temp dir");
            TempDir(p)
        }
        fn path(&self) -> &Path { &self.0 }
    }

    impl Drop for TempDir {
        fn drop(&mut self) { let _ = std::fs::remove_dir_all(&self.0); }
    }

    const UUID: &str = "11111111-2222-3333-4444-555555555555";

    /// A minimal real codex home: one non-seed rollout whose full UUID joins to
    /// a `threads` row in a `state_*.sqlite`. `list()` must stamp the provider's
    /// configured (non-default) instance id onto the returned session — no live
    /// codex, tmux server, or the user's real `~/.codex`.
    #[test]
    fn fixture_sessions_carry_configured_instance_id() {
        let tmp = TempDir::new();
        let day = tmp.path().join("sessions").join("2026").join("09").join("22");
        std::fs::create_dir_all(&day).expect("rollout dirs");
        let rollout = day.join(format!("rollout-2026-09-22T00-00-00-{UUID}.jsonl"));
        std::fs::write(&rollout, concat!(
            "{\"type\":\"session_meta\",\"payload\":{\"cwd\":\"/tmp\",\"session_id\":\"sess1\",\"model\":\"model-x\"}}\n",
            "{\"type\":\"user\",\"payload\":{\"content\":\"hi\"}}\n",
        )).expect("write rollout");

        let db_path = tmp.path().join("state_0.sqlite");
        {
            let conn = Connection::open(&db_path).expect("open db");
            conn.execute_batch(&format!(
                "CREATE TABLE threads (id TEXT PRIMARY KEY, name TEXT, title TEXT, cwd TEXT, model TEXT, created_at_ms INTEGER, updated_at_ms INTEGER); \
                 INSERT INTO threads (id, name, cwd, model, created_at_ms, updated_at_ms) VALUES ('{UUID}', 'Fake Name', '/tmp', 'model-x', 1, 2);"
            )).expect("seed threads");
        }

        let provider = CodexProvider::new(tmp.path(), ProviderId::new("alt-codex").unwrap());
        let sessions = provider.list().expect("list temp codex home");
        assert_eq!(sessions.len(), 1);
        assert_eq!(sessions[0].provider_id, ProviderId::new("alt-codex").unwrap());
        assert_eq!(sessions[0].id, UUID);
        assert_eq!(sessions[0].title.as_deref(), Some("Fake Name"));
    }

    fn session(id: &str, title: Option<&str>) -> Session {
        Session {
            provider_id: ProviderId::new("codex").unwrap(),
            id: id.to_string(),
            title: title.map(str::to_string),
            slug: None, directory: None, session_id: None,
            agent: None, model: None, created_ms: None, updated_ms: None, active: false,
        }
    }

    const TEST_HOME: &str = "/nonexistent";

    fn ev(windows: Vec<(String, Vec<Vec<String>>)>) -> ProcessEvidence {
        ProcessEvidence {
            windows: windows.into_iter().map(|(wid, procs)| WindowEvidence {
                window_id: wid,
                procs: procs.into_iter().enumerate().map(|(i, argv)| ProcEvidence {
                    pid: i as u64, argv, env: vec![("CODEX_HOME".into(), TEST_HOME.into())],
                }).collect(),
            }).collect(),
            complete: true,
            errors: vec![],
        }
    }

    #[test]
    fn exact_uuid_is_confirmed() {
        let p = CodexProvider::new(Path::new("/nonexistent"), ProviderId::new("codex").unwrap());
        let s = session(UUID, Some("Fake"));
        let e = ev(vec![("@1".into(), vec![vec!["codex".into(), "resume".into(), UUID.into()]])]);
        let m = p.match_session(&s, std::slice::from_ref(&s), &e);
        assert_eq!(m.len(), 1);
        assert_eq!(m[0].confidence, MatchConfidence::Confirmed);
    }

    #[test]
    fn absolute_executable_path_and_unknown_forms() {
        let p = CodexProvider::new(Path::new("/nonexistent"), ProviderId::new("codex").unwrap());
        let s = session(UUID, Some("Fake"));
        // absolute executable path matches by basename
        let e = ev(vec![("@1".into(), vec![vec!["/usr/local/bin/codex".into(), "resume".into(), UUID.into()]])]);
        assert_eq!(p.match_session(&s, std::slice::from_ref(&s), &e)[0].confidence, MatchConfidence::Confirmed);
        // resume with no target is unknown -> ambiguous, never proof of absence
        let e2 = ev(vec![("@2".into(), vec![vec!["codex".into(), "resume".into()]])]);
        assert_eq!(p.match_session(&s, std::slice::from_ref(&s), &e2)[0].confidence, MatchConfidence::Ambiguous);
    }

    #[test]
    fn unknown_codex_syntax_is_ambiguous_not_absence() {
        let p = CodexProvider::new(Path::new("/nonexistent"), ProviderId::new("codex").unwrap());
        let s = session(UUID, Some("Fake"));
        // recognized executable but unrecognized syntax -> ambiguous
        let cases: Vec<Vec<String>> = vec![
            vec!["codex".into(), "--unknown-option".into(), "resume".into(), UUID.into()],
            vec!["codex".into(), "resume".into(), UUID.into(), "extra".into()],
            vec!["codex".into(), "resume".into(), "-s".into(), UUID.into()],
            vec!["codex".into(), "resume".into()],
            vec!["codex".into()],
        ];
        for argv in cases {
            let e = ev(vec![("@1".into(), vec![argv])]);
            let m = p.match_session(&s, std::slice::from_ref(&s), &e);
            assert_eq!(m.len(), 1, "unrecognized codex syntax must be ambiguous: {e:?}");
            assert_eq!(m[0].confidence, MatchConfidence::Ambiguous);
        }
    }

    #[test]
    fn unique_resume_title_is_confirmed_duplicate_is_ambiguous() {
        let p = CodexProvider::new(Path::new("/nonexistent"), ProviderId::new("codex").unwrap());
        let target = session("11111111-2222-3333-4444-aaaaaaaaaaaa", Some("Shared Name"));
        // unique in snapshot -> confirmed
        let snap = vec![target.clone(), session("22222222-2222-3333-4444-bbbbbbbbbbbb", Some("Other"))];
        let e = ev(vec![("@1".into(), vec![vec!["codex".into(), "resume".into(), "Shared Name".into()]])]);
        let m = p.match_session(&target, &snap, &e);
        assert_eq!(m.len(), 1);
        assert_eq!(m[0].confidence, MatchConfidence::Confirmed);
        // duplicate/inherited shared title -> ambiguous, not "first match wins"
        let snap2 = vec![
            target.clone(),
            session("22222222-2222-3333-4444-bbbbbbbbbbbb", Some("Shared Name")),
        ];
        let m2 = p.match_session(&target, &snap2, &e);
        assert_eq!(m2.len(), 1);
        assert_eq!(m2[0].confidence, MatchConfidence::Ambiguous);
    }

    #[test]
    fn resume_plan_uses_title_or_uuid_and_create_is_launch_to_create() {
        let p = CodexProvider::new(Path::new("/nonexistent"), ProviderId::new("codex").unwrap());
        let with_title = session(UUID, Some("My Thread"));
        let plan = p.resume_plan(&with_title).unwrap();
        assert_eq!(plan.program, "codex");
        assert_eq!(plan.args, vec!["resume", "My Thread"]);
        assert_eq!(plan.env, vec![("CODEX_HOME".to_string(), TEST_HOME.to_string())],
            "resume launch carries the configured home");
        let untitled = session(UUID, None);
        let plan2 = p.resume_plan(&untitled).unwrap();
        assert_eq!(plan2.args, vec!["resume", UUID]);
        // create is a launch-to-create plan carrying the requested cwd AND home
        match p.create("name", "/tmp/work dir").unwrap() {
            CreateOutcome::LaunchToCreate(lr) => {
                assert_eq!(lr.program, "codex");
                assert_eq!(lr.cwd.as_deref(), Some("/tmp/work dir"));
                assert_eq!(lr.env, vec![("CODEX_HOME".to_string(), TEST_HOME.to_string())]);
            }
            _ => panic!("codex create must be LaunchToCreate"),
        }
        // capabilities reflect title-not-applied, cwd-applied
        let caps = p.capabilities();
        assert!(caps.new_session.supported);
        assert!(!caps.new_session.applies_title);
        assert!(caps.new_session.applies_cwd);
    }

    #[test]
    fn missing_source_metadata_is_unknown_even_for_default_home() {
        let home = dirs::home_dir().unwrap_or_default().join(".codex");
        assert_eq!(source_rel(&home, &[]), SourceRel::Unknown);
    }

    #[test]
    fn two_codex_homes_do_not_cross_confirm() {
        let home_a = "/tmp/codex-home-a";
        let home_b = "/tmp/codex-home-b";
        let a = CodexProvider::new(Path::new(home_a), ProviderId::new("a").unwrap());
        let b = CodexProvider::new(Path::new(home_b), ProviderId::new("b").unwrap());
        let s = session(UUID, Some("Shared"));
        // Evidence with home_a's CODEX_HOME: confirmed for a, never for b.
        let ev_a = ProcessEvidence { windows: vec![WindowEvidence { window_id: "@1".into(), procs: vec![
            ProcEvidence { pid: 1, argv: vec!["codex".into(), "resume".into(), UUID.into()],
                           env: vec![("CODEX_HOME".into(), home_a.into())] }] }],
            complete: true, errors: vec![] };
        let m_a = a.match_session(&s, std::slice::from_ref(&s), &ev_a);
        assert_eq!(m_a.len(), 1);
        assert_eq!(m_a[0].confidence, MatchConfidence::Confirmed);
        let m_b = b.match_session(&s, std::slice::from_ref(&s), &ev_a);
        assert!(!m_b.iter().any(|m| m.confidence == MatchConfidence::Confirmed),
            "a different configured home must never produce a cross-instance confirmed adoption");
        // A relative/empty CODEX_HOME cannot prove another source: Unknown.
        let ev_rel = ProcessEvidence { windows: vec![WindowEvidence { window_id: "@3".into(), procs: vec![
            ProcEvidence { pid: 3, argv: vec!["codex".into(), "resume".into(), UUID.into()],
                           env: vec![("CODEX_HOME".into(), "relative/path".into())] }] }],
            complete: true, errors: vec![] };
        let m_rel = a.match_session(&s, std::slice::from_ref(&s), &ev_rel);
        assert_eq!(m_rel.len(), 1);
        assert_eq!(m_rel[0].confidence, MatchConfidence::Ambiguous,
            "relative CODEX_HOME is Unknown, never a confirmed adoption");
        // Evidence with NO source env: both non-default homes are Unknown/ambiguous.
        let ev_none = ProcessEvidence { windows: vec![WindowEvidence { window_id: "@2".into(), procs: vec![
            ProcEvidence { pid: 2, argv: vec!["codex".into(), "resume".into(), UUID.into()], env: vec![] }] }],
            complete: true, errors: vec![] };
        for p in [&a, &b] {
            let m = p.match_session(&s, std::slice::from_ref(&s), &ev_none);
            assert_eq!(m.len(), 1);
            assert_eq!(m[0].confidence, MatchConfidence::Ambiguous,
                "unestablished source is ambiguous, never confirmed");
        }
    }
}
```

> **Hmm.** The RFC3339 handling in `prov::codex` got fat. That's a judgement
> call to avoid pulling `chrono` into a blueprint whose point is tiny+fast. If
> implementers find the hand-rolled math fiddly, the honest move is to accept a
> time crate and delete both `mod`s — the contract (parse/format RFC3339) stays
> unchanged. This is exactly the kind of call a blueprint should surface.

### 11.7 Name engine (`name::engine`)

One code path for Ollama (no key) and keyed remotes: both expose
`POST {base}/v1/chat/completions` with a Bearer key optional. Degrades to the
kebab heuristic when unreachable, so the console is never hostage to a service.

``` {.rust #name-engine path="src/naming.rs"}
use std::time::Duration;
use ureq::{Agent, AgentBuilder};

const NAMING_PROMPT: &str =
    "Answer with a short, descriptive session title, 2-6 words. No quotes, \
     no markdown, no punctuation explosion. Reply with the title only.";

pub struct NameEngine {
    base: Option<String>,
    key: Option<String>,
    model: String,
    agent: Agent,
}

impl NameEngine {
    pub fn new(base: Option<String>, key: Option<String>, model: String) -> Self {
        Self { base, key, model, agent: AgentBuilder::new().timeout(Duration::from_secs(8)).build() }
    }

    pub fn suggest(&self, seed: &str) -> String {
        let trimmed = seed.trim();
        if trimmed.is_empty() { return "untitled".into(); }
        if let Some(base) = &self.base {
            if let Ok(name) = self.remote(base, trimmed) {
                return name;
            }
        }
        heuristic(trimmed)
    }

    fn remote(&self, base: &str, seed: &str) -> anyhow::Result<String> {
        let url = format!("{}/v1/chat/completions", base.trim_end_matches('/'));
        let body = serde_json::json!({
            "model": self.model,
            "messages": [
                { "role": "system", "content": NAMING_PROMPT },
                { "role": "user", "content": format!("Session's recent request:\n{seed}") },
            ],
            "temperature": 0.2,
            "max_tokens": 24,
        });
        let mut req = self.agent.post(&url);
        if let Some(k) = &self.key {
            let auth = format!("Bearer {k}");
            req = req.set("Authorization", &auth);
        }
        let resp: serde_json::Value = req.send_json(&body)?.into_json()?;
        let text = resp["choices"][0]["message"]["content"].as_str().unwrap_or_default();
        let clean = text.split_whitespace().collect::<Vec<_>>().join(" ");
        Ok(if clean.chars().count() > 40 { clean.chars().take(40).collect() } else { clean })
    }
}

/// Offline fallback: first words, lower-cased, kebab, hard-capped at 40 chars.
fn heuristic(seed: &str) -> String {
    let mut out = String::new();
    for w in seed.split_whitespace().take(6) {
        let w = w.trim_matches(|c: char| !c.is_alphanumeric()).to_lowercase();
        if w.is_empty() { continue; }
        if !out.is_empty() { out.push('-'); }
        out.push_str(&w);
        if out.chars().count() >= 40 { break; }
    }
    if out.chars().count() > 40 { out.chars().take(40).collect() } else { out }
}
```

### 11.8 Launcher (`core::launcher`)

Decides tmux-window vs take-the-terminal **solely** on the presence of `$TMUX`
(an empty string counts as inside — tmux does set it to a non-empty value, but
the belt-and-braces check avoids the classic `${TMUX:+…}` footgun).

Since PA-01 Stage 2 the launcher owns injectable seams — a `ProcReader` (real:
NUL-delimited `/proc/<pid>/cmdline` with empty args preserved and bounded
descendants, truncated/unreadable scans reported incomplete), a `Tmux` facade
that checks subprocess exit status (never treating a failed command as empty
evidence), a `Foreground` runner (real: `std::process::Command` with inherited
stdio), and a `Terminal` suspend/restore seam. It collects a generic
`ProcessEvidence` snapshot (current-session windows plus explicitly tracked
windows, with completeness/errors), runs foreground launches, and opens new
tmux windows by explicitly invoking POSIX `sh` through tmux's multi-argument
command interface (never the user's default shell), serializing the launch once
to an `exec` command (quoting every program/argument, preserving cwd/env,
validating env names, rejecting NUL anywhere). Shared `validate_launch` guards
both foreground and tmux execution. The explicit `decide_open` adoption policy
selects a tracked window only on confirmed evidence, deduplicates candidates,
and refuses heuristic/ambiguous identity unless forced.

``` {.rust #core-launcher path="src/launcher.rs"}
use anyhow::{anyhow, Result};
use std::collections::HashSet;
use std::process::Command;

use crossterm::cursor::Show;
use crossterm::event::{DisableMouseCapture, EnableMouseCapture};
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, Clear, ClearType};

use crate::model::{
    LaunchRequest, MatchConfidence, ProcEvidence, ProcessEvidence, WindowEvidence, WindowMatch,
};

// ---- Process collection (injectable for fixtures) ---------------------------

/// A bounded process tree: real argument vectors plus whether every read
/// succeeded (truncated/unreadable scans are reported as incomplete).
#[derive(Clone)]
pub struct ProcTree {
    pub procs: Vec<ProcEvidence>,
    pub complete: bool,
}

/// Reads a process tree from a root pid. Injectable so fixtures need no /proc.
pub trait ProcReader: Send + Sync {
    fn tree(&self, root: u64, max_depth: u32) -> ProcTree;
}

/// Real reader: NUL-delimited `/proc/<pid>/cmdline` and `/proc/<pid>/task/<pid>/children`.
pub struct ProcFs;

/// Parse NUL-delimited `/proc/<pid>/cmdline` bytes into an argv, dropping only
/// the single terminating NUL and preserving empty arguments. Returns None for a
/// truncated (no trailing NUL) or non-UTF-8 argv, which the caller treats as
/// unknown.
fn parse_cmdline(raw: &[u8]) -> Option<Vec<String>> {
    if !raw.ends_with(b"\0") { return None; } // truncated -> not a full argv
    let body = &raw[..raw.len() - 1];
    let mut argv = Vec::new();
    for part in body.split(|b| *b == 0) {
        // Non-UTF-8 tokens cannot be represented faithfully; treat as unknown.
        argv.push(String::from_utf8(part.to_vec()).ok()?);
    }
    Some(argv)
}

fn read_cmdline(pid: u64) -> Option<Vec<String>> {
    parse_cmdline(&std::fs::read(format!("/proc/{pid}/cmdline")).ok()?)
}

/// Narrow source-metadata environment values for a process. Only well-known
/// source keys (`CODEX_HOME` and `ANTIGRAVITY_APP_DATA_DIR`) are read from `/proc/<pid>/environ`;
/// the full environment is never collected or logged.
fn read_source_env(pid: u64) -> Vec<(String, String)> {
    let Some(raw) = std::fs::read(format!("/proc/{pid}/environ")).ok() else { return Vec::new() };
    let mut out = Vec::new();
    for entry in raw.split(|b| *b == 0) {
        if entry.is_empty() { continue; }
        let Ok(s) = std::str::from_utf8(entry) else { continue };
        if let Some((k, v)) = s.split_once('=') {
            if k == "CODEX_HOME" || k == "ANTIGRAVITY_APP_DATA_DIR" {
                out.push((k.to_string(), v.to_string()));
            }
        }
    }
    out
}

fn read_children(pid: u64) -> Option<Vec<u64>> {
    let raw = std::fs::read(format!("/proc/{pid}/task/{pid}/children")).ok()?;
    Some(String::from_utf8_lossy(&raw).split_whitespace().filter_map(|t| t.parse().ok()).collect())
}

impl ProcReader for ProcFs {
    fn tree(&self, root: u64, max_depth: u32) -> ProcTree {
        let mut procs = Vec::new();
        let mut complete = true;
        let mut seen: HashSet<u64> = HashSet::new();
        let mut stack: Vec<(u64, u32)> = vec![(root, 0)];
        while let Some((pid, depth)) = stack.pop() {
            if !seen.insert(pid) { continue; }
            if read_cmdline(pid).map(|argv| procs.push(ProcEvidence { pid, argv, env: read_source_env(pid) })).is_none() {
                complete = false;
            }
            match read_children(pid) {
                Some(children) => {
                    if depth < max_depth {
                        for c in children { stack.push((c, depth + 1)); }
                    } else if !children.is_empty() {
                        // Deeper descendants exist but we stopped: truncated.
                        complete = false;
                    }
                }
                None => complete = false,
            }
        }
        ProcTree { procs, complete }
    }
}

// ---- tmux (injectable for fixtures) -----------------------------------------

/// The tmux-facing surface of the launcher. Injectable so no test touches a
/// real tmux server. `new_window` takes the command as an explicit argv so the
/// caller controls exactly how the client is invoked (POSIX sh, not the user's
/// default shell).
pub trait Tmux: Send + Sync {
    fn in_tmux(&self) -> bool;
    fn current_session(&self) -> Result<String>;
    fn new_window(&self, session: &str, label: &str, command: &[String]) -> Result<String>;
    fn select_window(&self, win: &str) -> Result<()>;
    fn window_alive(&self, win: &str) -> Result<bool>;
    fn mouse_on(&self) -> Result<bool>;
    fn list_window_ids(&self, all: bool) -> Result<Vec<String>>;
    fn pane_root_pids(&self, win: &str) -> Result<Vec<u64>>;
}

pub struct TmuxCli;

impl Tmux for TmuxCli {
    fn in_tmux(&self) -> bool {
        match std::env::var_os("TMUX") {
            Some(v) => !v.is_empty(),
            None => false,
        }
    }
    fn current_session(&self) -> Result<String> {
        let out = Command::new("tmux").args(["display-message", "-p", "#{S}"]).output()?;
        if !out.status.success() {
            return Err(anyhow!("tmux display-message failed: {}", String::from_utf8_lossy(&out.stderr).trim()));
        }
        Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
    }
    fn new_window(&self, session: &str, label: &str, command: &[String]) -> Result<String> {
        let mut args: Vec<String> = vec![
            "new-window".into(), "-P".into(), "-F".into(), "#{window_id}".into(),
            "-t".into(), session.into(), "-n".into(), label.into(),
        ];
        args.extend(command.iter().cloned());
        let out = Command::new("tmux").args(&args).output()?;
        if !out.status.success() {
            return Err(anyhow!("tmux new-window failed: {}", String::from_utf8_lossy(&out.stderr).trim()));
        }
        let id = String::from_utf8_lossy(&out.stdout).trim().to_string();
        if id.is_empty() { return Err(anyhow!("tmux new-window returned no window id")); }
        Ok(id)
    }
    fn select_window(&self, win: &str) -> Result<()> {
        let status = Command::new("tmux").args(["select-window", "-t", win]).status()?;
        if !status.success() { return Err(anyhow!("tmux select-window failed")); }
        Ok(())
    }
    fn window_alive(&self, win: &str) -> Result<bool> {
        let out = Command::new("tmux").args(["list-windows", "-a", "-F", "#{window_id}"]).output()?;
        if !out.status.success() {
            return Err(anyhow!("tmux list-windows failed"));
        }
        let hay = String::from_utf8_lossy(&out.stdout);
        Ok(hay.lines().any(|line| line.trim() == win))
    }
    fn mouse_on(&self) -> Result<bool> {
        let out = Command::new("tmux").args(["show", "-g", "mouse"]).output()?;
        if !out.status.success() { return Err(anyhow!("tmux show failed")); }
        Ok(String::from_utf8_lossy(&out.stdout).trim().ends_with("on"))
    }
    fn list_window_ids(&self, all: bool) -> Result<Vec<String>> {
        let mut args: Vec<String> = vec!["list-windows".into()];
        if all { args.push("-a".into()); }
        args.push("-F".into());
        args.push("#{window_id}".into());
        let out = Command::new("tmux").args(&args).output()?;
        if !out.status.success() { return Err(anyhow!("tmux list-windows failed")); }
        Ok(String::from_utf8_lossy(&out.stdout).lines()
            .map(|l| l.trim().to_string()).filter(|l| !l.is_empty()).collect())
    }
    fn pane_root_pids(&self, win: &str) -> Result<Vec<u64>> {
        let out = Command::new("tmux").args(["list-panes", "-t", win, "-F", "#{pane_pid}"]).output()?;
        if !out.status.success() { return Err(anyhow!("tmux list-panes failed")); }
        Ok(String::from_utf8_lossy(&out.stdout).lines()
            .filter_map(|l| l.trim().parse::<u64>().ok()).collect())
    }
}

// ---- foreground execution (injectable for fixtures) -------------------------

/// Runs a launch request in the foreground with inherited stdio.
pub trait Foreground: Send + Sync {
    fn run(&self, req: &LaunchRequest) -> Result<()>;
}

pub struct StdioRunner;

impl Foreground for StdioRunner {
    fn run(&self, req: &LaunchRequest) -> Result<()> {
        validate_launch(req)?;
        let mut cmd = Command::new(&req.program);
        cmd.args(&req.args);
        if let Some(cwd) = &req.cwd { cmd.current_dir(cwd); }
        for (k, v) in &req.env { cmd.env(k, v); }
        // status() only errors on spawn failure; a normal/nonzero child exit is
        // a normal way to return control to pinga.
        cmd.status()?;
        Ok(())
    }
}

// ---- terminal control (injectable for fixtures) -----------------------------

/// The suspend/run/restore terminal seam. `suspend` leaves raw mode for the
/// child; `restore` always repairs raw/cursor/mouse state and requests a
/// repaint. Injectable so the production orchestration can be tested without an
/// interactive terminal.
pub trait Terminal: Send + Sync {
    fn suspend(&self) -> Result<()>;
    fn restore(&self, mouse_on: bool) -> Result<()>;
}

pub struct RealTerminal;

impl Terminal for RealTerminal {
    fn suspend(&self) -> Result<()> {
        disable_raw_mode()?;
        crossterm::execute!(std::io::stdout(), Show, DisableMouseCapture)?;
        Ok(())
    }
    fn restore(&self, mouse_on: bool) -> Result<()> {
        let mut errs: Vec<String> = Vec::new();
        if let Err(e) = enable_raw_mode() { errs.push(format!("raw: {e}")); }
        if let Err(e) = crossterm::execute!(std::io::stdout(), Clear(ClearType::All)) {
            errs.push(format!("clear: {e}"));
        }
        if mouse_on {
            if let Err(e) = crossterm::execute!(std::io::stdout(), EnableMouseCapture) {
                errs.push(format!("mouse: {e}"));
            }
        }
        if errs.is_empty() { Ok(()) } else { Err(anyhow!(errs.join("; "))) }
    }
}

// ---- Launcher facade --------------------------------------------------------

pub struct Launcher {
    proc_reader: Box<dyn ProcReader>,
    tmux: Box<dyn Tmux>,
    foreground: Box<dyn Foreground>,
}

impl Launcher {
    pub fn real() -> Self {
        Self { proc_reader: Box::new(ProcFs), tmux: Box::new(TmuxCli), foreground: Box::new(StdioRunner) }
    }

    /// Construct with injected seams (for application-level fixtures).
    pub fn with_seams(proc_reader: Box<dyn ProcReader>, tmux: Box<dyn Tmux>,
                      foreground: Box<dyn Foreground>) -> Self {
        Self { proc_reader, tmux, foreground }
    }

    pub fn in_tmux(&self) -> bool { self.tmux.in_tmux() }
    pub fn mouse_on(&self) -> Result<bool> { self.tmux.mouse_on() }
    pub fn window_alive(&self, win: &str) -> Result<bool> { self.tmux.window_alive(win) }
    pub fn select_window(&self, win: &str) -> Result<()> { self.tmux.select_window(win) }

    /// Collect a generic process snapshot: every window in the current tmux
    /// session plus any explicitly tracked windows (which may live in other
    /// tmux sessions), with inspection completeness/errors.
    pub fn collect_evidence(&self, tracked_windows: &[String]) -> Result<ProcessEvidence> {
        let mut ids = self.tmux.list_window_ids(false)?;
        for w in tracked_windows {
            if !ids.iter().any(|i| i == w) {
                // Only scan tracked windows that still EXIST. A dead window's
                // pane lookup would fail and mark the whole evidence incomplete,
                // refusing every open — e.g. stale window ids after a
                // tmux-resurrect restore, where ids are reassigned and @17 may
                // no longer exist at all. A tracked window that is alive in
                // another session is still scanned.
                if self.tmux.window_alive(w).unwrap_or(false) {
                    ids.push(w.clone());
                }
            }
        }
        let mut windows = Vec::new();
        let mut complete = true;
        let mut errors = Vec::new();
        for wid in ids {
            match self.tmux.pane_root_pids(&wid) {
                Ok(roots) => {
                    let mut procs = Vec::new();
                    for root in roots {
                        let tree = self.proc_reader.tree(root, 3);
                        if !tree.complete { complete = false; }
                        procs.extend(tree.procs);
                    }
                    windows.push(WindowEvidence { window_id: wid, procs });
                }
                Err(e) => { complete = false; errors.push(format!("window {wid}: {e}")); }
            }
        }
        Ok(ProcessEvidence { windows, complete, errors })
    }

    /// Run a launch in the foreground (bare-terminal mode).
    pub fn run_in_foreground(&self, req: &LaunchRequest) -> Result<()> {
        self.foreground.run(req)
    }

    /// Open a launch request in a new tmux window of the current session. The
    /// launch is serialized to a POSIX sh fragment once, then POSIX sh itself is
    /// invoked explicitly through tmux's multi-argument command interface so the
    /// user's default shell never interprets it.
    pub fn open_in_tmux(&self, label: &str, req: &LaunchRequest) -> Result<String> {
        validate_launch(req)?;
        let cmd = serialize_launch(req)?;
        let session = self.tmux.current_session()?;
        let argv: Vec<String> = vec!["sh".into(), "-c".into(), cmd];
        self.tmux.new_window(&session, label, &argv)
    }
}

// ---- POSIX sh serialization -------------------------------------------------

/// Quote a single word for POSIX sh. Always quotes, including empty strings, so
/// no embedded token can be interpreted by a shell.
fn sh_quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''"))
}

fn validate_env(env: &[(String, String)]) -> Result<()> {
    for (k, v) in env {
        if k.contains('\0') || v.contains('\0') {
            return Err(anyhow!("environment override contains NUL"));
        }
        let mut it = k.chars();
        if !matches!(it.next(), Some(c) if c.is_ascii_alphabetic() || c == '_')
            || !it.all(|c| c.is_ascii_alphanumeric() || c == '_') {
            return Err(anyhow!("invalid environment name {k:?}"));
        }
    }
    Ok(())
}

/// Shared request validation for BOTH foreground and tmux execution: no NUL in
/// program/args/cwd/env values, and valid env names.
pub fn validate_launch(req: &LaunchRequest) -> Result<()> {
    for s in std::iter::once(&req.program).chain(req.args.iter()).chain(req.cwd.iter()) {
        if s.contains('\0') {
            return Err(anyhow!("launch field contains NUL"));
        }
    }
    validate_env(&req.env)
}

/// Serialize a launch request to a POSIX sh command: `exec` with every program
/// and argument single-quoted (including empties), optional `cd` for cwd, and
/// `NAME=value` env overrides directly on the `exec` (so a `cd` builtin never
/// scopes the assignments away). `exec` so process inspection sees the real
/// child. Launch values are UTF-8 Rust strings, so no non-UTF-8 value can be
/// silently altered here.
pub fn serialize_launch(req: &LaunchRequest) -> Result<String> {
    validate_launch(req)?;
    let mut parts: Vec<String> = Vec::new();
    if let Some(cwd) = &req.cwd {
        parts.push(format!("cd {} &&", sh_quote(cwd)));
    }
    for (k, v) in &req.env {
        parts.push(format!("{}={}", k, sh_quote(v)));
    }
    parts.push("exec".into());
    parts.push(sh_quote(&req.program));
    for a in &req.args { parts.push(sh_quote(a)); }
    Ok(parts.join(" "))
}

/// Run a launch in the foreground and ALWAYS call `restore` afterwards — on a
/// normal child return AND on a spawn failure — so terminal state is repaired
/// even when the child never started. The error is propagated after restore.
pub fn run_guarded(l: &Launcher, req: &LaunchRequest, restore: impl FnOnce()) -> anyhow::Result<()> {
    let r = l.run_in_foreground(req);
    restore();
    r
}

// ---- core adoption policy ---------------------------------------------------

/// What the app should do to open a session given its evidence.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OpenAction {
    Select { window_id: String },
    Adopt { window_id: String },
    Spawn,
    RefuseUncertain,
    RefuseIncomplete,
    RefuseActive,
}

/// Rank for deduplication: Confirmed > Heuristic > Ambiguous.
fn confidence_rank(c: MatchConfidence) -> u8 {
    match c {
        MatchConfidence::Confirmed => 2,
        MatchConfidence::Heuristic => 1,
        MatchConfidence::Ambiguous => 0,
    }
}

/// Deduplicate candidate window ids, keeping the strongest confidence per id.
fn dedup_matches(matches: &[WindowMatch]) -> Vec<WindowMatch> {
    let mut out: Vec<WindowMatch> = Vec::new();
    for m in matches {
        match out.iter_mut().find(|e| e.window_id == m.window_id) {
            Some(existing) => {
                if confidence_rank(m.confidence) > confidence_rank(existing.confidence) {
                    existing.confidence = m.confidence;
                }
            }
            None => out.push(m.clone()),
        }
    }
    out
}

/// The explicit adoption policy (PA-01 Stage 2). A tracked window is selected
/// ONLY when it is alive AND positively identified by Confirmed evidence;
/// liveness alone is not proof of identity. `tracked` is (window_id, alive).
pub fn decide_open(
    matches: &[WindowMatch],
    tracked: Option<(String, bool)>,
    active: bool,
    force: bool,
    complete: bool,
) -> OpenAction {
    let dedup = dedup_matches(matches);
    // 1. A tracked window that is alive AND positively identified wins.
    if let Some((win, true)) = &tracked {
        if dedup.iter().any(|m| &m.window_id == win && m.confidence == MatchConfidence::Confirmed) {
            return OpenAction::Select { window_id: win.clone() };
        }
    }
    let confirmed: Vec<&WindowMatch> =
        dedup.iter().filter(|m| m.confidence == MatchConfidence::Confirmed).collect();
    let uncertain: Vec<&WindowMatch> =
        dedup.iter().filter(|m| m.confidence != MatchConfidence::Confirmed).collect();
    match confirmed.len() {
        0 => {
            if !uncertain.is_empty() {
                // 3. heuristic/ambiguous identity: explain and refuse unless forced.
                if force { OpenAction::Spawn } else { OpenAction::RefuseUncertain }
            } else if !complete {
                // 5. incomplete inspection, no confirmed candidate: unavailable.
                if force { OpenAction::Spawn } else { OpenAction::RefuseIncomplete }
            } else if active && !force {
                // 4. complete, no candidates: allow launch unless active refusal.
                OpenAction::RefuseActive
            } else {
                OpenAction::Spawn
            }
        }
        // 2. exactly one confirmed candidate -> adopt it.
        1 => OpenAction::Adopt { window_id: confirmed[0].window_id.clone() },
        // 3. multiple confirmed candidates are uncertain too.
        _ => {
            if force { OpenAction::Spawn } else { OpenAction::RefuseUncertain }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::MatchConfidence;
    use std::fs;
    use std::sync::Arc;

    /// A foreground runner that always fails or always succeeds to spawn.
    struct FakeForeground(bool);
    impl Foreground for FakeForeground {
        fn run(&self, _req: &LaunchRequest) -> Result<()> {
            if self.0 { Err(anyhow!("spawn failed")) } else { Ok(()) }
        }
    }

    fn launch() -> LaunchRequest {
        LaunchRequest { program: "true".into(), args: vec![], cwd: None, env: vec![] }
    }

    #[test]
    fn restoration_runs_on_both_success_and_spawn_failure() {
        let l = Launcher::with_seams(Box::new(ProcFs), Box::new(TmuxCli),
                                     Box::new(FakeForeground(true)));
        let mut restored = false;
        let r = run_guarded(&l, &launch(), || restored = true);
        assert!(r.is_err());
        assert!(restored, "restore must run after a spawn failure");

        let l2 = Launcher::with_seams(Box::new(ProcFs), Box::new(TmuxCli),
                                      Box::new(FakeForeground(false)));
        let mut restored2 = false;
        let r2 = run_guarded(&l2, &launch(), || restored2 = true);
        assert!(r2.is_ok());
        assert!(restored2);
    }

    /// A fake tmux that records the new-window command argv.
    #[allow(clippy::type_complexity)]
    struct FakeTmux { created: Arc<std::sync::Mutex<Vec<(String, Vec<String>)>>> }
    impl FakeTmux {
        fn new() -> Self { Self { created: Arc::new(std::sync::Mutex::new(Vec::new())) } }
    }
    impl Tmux for FakeTmux {
        fn in_tmux(&self) -> bool { true }
        fn current_session(&self) -> Result<String> { Ok("main".into()) }
        fn new_window(&self, session: &str, label: &str, command: &[String]) -> Result<String> {
            self.created.lock().unwrap().push((label.into(), command.to_vec()));
            let _ = session;
            Ok("@7".into())
        }
        fn select_window(&self, _win: &str) -> Result<()> { Ok(()) }
        fn window_alive(&self, _win: &str) -> Result<bool> { Ok(true) }
        fn mouse_on(&self) -> Result<bool> { Ok(true) }
        fn list_window_ids(&self, _all: bool) -> Result<Vec<String>> { Ok(vec![]) }
        fn pane_root_pids(&self, _win: &str) -> Result<Vec<u64>> { Ok(vec![]) }
    }

    #[test]
    fn open_in_tmux_invokes_posix_sh_explicitly() {
        let tmux = FakeTmux::new();
        let probe = Arc::clone(&tmux.created);
        let l = Launcher::with_seams(Box::new(ProcFs), Box::new(tmux), Box::new(FakeForeground(false)));
        let req = LaunchRequest { program: "codex".into(), args: vec!["resume".into(), "my title".into()],
                                  cwd: Some("/tmp".into()), env: vec![] };
        let win = l.open_in_tmux("label", &req).unwrap();
        assert_eq!(win, "@7");
        let (label, argv) = probe.lock().unwrap().last().unwrap().clone();
        assert_eq!(label, "label");
        // tmux must be asked to run POSIX sh explicitly, never a default shell.
        assert_eq!(argv[0], "sh");
        assert_eq!(argv[1], "-c");
        assert!(argv[2].contains("exec 'codex' 'resume' 'my title'"));
    }

    #[test]
    fn serialization_preserves_shell_hostile_args_and_env_and_cwd() {
        let tmp = std::env::temp_dir().join(format!("pinga-serialize-{}", std::process::id()));
        fs::create_dir_all(&tmp).expect("tmp");
        let script = tmp.join("record.sh");
        let record = tmp.join("record.txt");
        fs::write(&script, concat!(
            "#!/bin/sh\n",
            ": > \"$RECORD\"\n",
            "for a in \"$@\"; do printf '<%s>\\n' \"$a\" >> \"$RECORD\"; done\n",
            "printf 'PWD=%s\\n' \"$PWD\" >> \"$RECORD\"\n",
            "printf 'MYVAR=%s\\n' \"$MYVAR\" >> \"$RECORD\"\n",
        )).expect("script");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&script, fs::Permissions::from_mode(0o755)).expect("chmod");
        }

        let tricky = vec![
            "plain".to_string(),
            "with spaces".into(),
            "it's".into(),
            String::new(), // empty arg must survive
            "unicode π".into(),
            "$(subshell)".into(),
            "`backtick`".into(),
            "a;b".into(),
        ];
        let req = LaunchRequest {
            program: script.to_string_lossy().into_owned(),
            args: tricky.clone(),
            cwd: Some(tmp.to_string_lossy().into_owned()),
            env: vec![("MYVAR".into(), "va l'ue".into()), ("RECORD".into(), record.to_string_lossy().into_owned())],
        };
        let cmd = serialize_launch(&req).unwrap();
        let status = Command::new("sh").arg("-c").arg(&cmd).status().expect("run sh");
        assert!(status.success());

        let lines: Vec<String> = fs::read_to_string(&record).expect("record")
            .lines().map(|l| l.to_string()).collect();
        for (i, expect) in tricky.iter().enumerate() {
            assert_eq!(lines[i], format!("<{expect}>"), "argv[{i}] preserved");
        }
        assert!(lines.contains(&format!("PWD={}", tmp.to_string_lossy())));
        assert!(lines.contains(&"MYVAR=va l'ue".to_string()));
        fs::remove_dir_all(&tmp).ok();
    }

    #[test]
    fn serialization_rejects_nul_anywhere_and_invalid_env_names() {
        // NUL in program, an arg, or cwd is rejected, not only env values.
        assert!(serialize_launch(&LaunchRequest { program: "x\0y".into(), args: vec![], cwd: None,
            env: vec![] }).is_err());
        assert!(serialize_launch(&LaunchRequest { program: "x".into(), args: vec!["a\0b".into()],
            cwd: None, env: vec![] }).is_err());
        assert!(serialize_launch(&LaunchRequest { program: "x".into(), args: vec![], cwd: Some("a\0b".into()),
            env: vec![] }).is_err());
        assert!(serialize_launch(&LaunchRequest { program: "x".into(), args: vec![], cwd: None,
            env: vec![("1BAD".into(), "v".into())] }).is_err());
        assert!(serialize_launch(&LaunchRequest { program: "x".into(), args: vec![], cwd: None,
            env: vec![("GOOD".into(), "va\0l".into())] }).is_err());
        assert!(serialize_launch(&LaunchRequest { program: "x".into(), args: vec![], cwd: None,
            env: vec![("MY_VAR2".into(), "ok".into())] }).is_ok());
    }

    fn m(win: &str, c: MatchConfidence) -> WindowMatch {
        WindowMatch { window_id: win.into(), confidence: c }
    }

    #[test]
    fn adoption_policy_requires_confirmed_evidence_for_tracked_window() {
        let confirmed_elsewhere = vec![m("@1", MatchConfidence::Confirmed)];
        // A live tracked window @0 that is NOT positively identified must NOT be
        // selected; the confirmed candidate elsewhere is adopted instead.
        assert_eq!(decide_open(&confirmed_elsewhere, Some(("@0".into(), true)), false, false, true),
                   OpenAction::Adopt { window_id: "@1".into() });
        // A tracked window that IS confirmed is selected.
        let tracked_confirmed = vec![m("@0", MatchConfidence::Confirmed)];
        assert_eq!(decide_open(&tracked_confirmed, Some(("@0".into(), true)), false, false, true),
                   OpenAction::Select { window_id: "@0".into() });
        // Ambiguous tracked identity -> refuse unless forced.
        let amb = vec![m("@0", MatchConfidence::Ambiguous)];
        assert_eq!(decide_open(&amb, Some(("@0".into(), true)), false, false, true),
                   OpenAction::RefuseUncertain);
        assert_eq!(decide_open(&amb, Some(("@0".into(), true)), false, true, true),
                   OpenAction::Spawn);
        // Incomplete evidence, no candidates -> refuse unless forced.
        assert_eq!(decide_open(&[], Some(("@0".into(), true)), false, false, false),
                   OpenAction::RefuseIncomplete);
    }

    #[test]
    fn adoption_policy_covers_remaining_cases_and_dedups() {
        // 2. exactly one confirmed -> adopt
        let one = vec![m("@1", MatchConfidence::Confirmed)];
        assert_eq!(decide_open(&one, None, false, false, true),
                   OpenAction::Adopt { window_id: "@1".into() });
        // dedup: same window twice -> single confirmed adopt
        let dup = vec![m("@1", MatchConfidence::Confirmed), m("@1", MatchConfidence::Ambiguous)];
        assert_eq!(decide_open(&dup, None, false, false, true),
                   OpenAction::Adopt { window_id: "@1".into() });
        // multiple distinct confirmed -> uncertain
        let two = vec![m("@1", MatchConfidence::Confirmed), m("@2", MatchConfidence::Confirmed)];
        assert_eq!(decide_open(&two, None, false, false, true), OpenAction::RefuseUncertain);
        // ambiguous -> refuse unless forced
        let amb = vec![m("@1", MatchConfidence::Ambiguous)];
        assert_eq!(decide_open(&amb, None, false, false, true), OpenAction::RefuseUncertain);
        assert_eq!(decide_open(&amb, None, false, true, true), OpenAction::Spawn);
        // 4. no candidates + complete -> spawn (respect active)
        assert_eq!(decide_open(&[], None, false, false, true), OpenAction::Spawn);
        assert_eq!(decide_open(&[], None, true, false, true), OpenAction::RefuseActive);
        assert_eq!(decide_open(&[], None, true, true, true), OpenAction::Spawn);
        // 5. incomplete + no confirmed -> refuse unless forced
        assert_eq!(decide_open(&[], None, false, false, false), OpenAction::RefuseIncomplete);
        assert_eq!(decide_open(&[], None, false, true, false), OpenAction::Spawn);
    }

    #[test]
    fn parse_cmdline_preserves_empty_args_and_rejects_truncated_or_non_utf8() {
        // trailing terminator NUL is dropped; args preserved
        assert_eq!(parse_cmdline(b"codex\0resume\0my title\0"),
                   Some(vec!["codex".into(), "resume".into(), "my title".into()]));
        // an empty argument between NULs is preserved
        assert_eq!(parse_cmdline(b"a\0\0b\0"), Some(vec!["a".into(), "".into(), "b".into()]));
        // truncated (no trailing NUL) -> unknown
        assert_eq!(parse_cmdline(b"no-nul"), None);
        // non-UTF-8 token -> unknown
        assert_eq!(parse_cmdline(&[b'a', 0xFF, b'\0']), None);
    }

    #[test]
    fn collect_evidence_aggregates_panes_and_marks_incomplete() {
        use std::collections::HashMap;

        struct P(HashMap<u64, ProcTree>);
        impl ProcReader for P {
            fn tree(&self, root: u64, _max: u32) -> ProcTree {
                self.0.get(&root).cloned().unwrap_or(ProcTree { procs: vec![], complete: true })
            }
        }
        struct T { ids: Vec<String>, panes: HashMap<String, Vec<u64>>, pane_err: Option<String> }
        impl Tmux for T {
            fn in_tmux(&self) -> bool { true }
            fn current_session(&self) -> Result<String> { Ok("main".into()) }
            fn new_window(&self, _s: &str, _l: &str, _c: &[String]) -> Result<String> { Ok("@9".into()) }
            fn select_window(&self, _w: &str) -> Result<()> { Ok(()) }
            fn window_alive(&self, _w: &str) -> Result<bool> { Ok(true) }
            fn mouse_on(&self) -> Result<bool> { Ok(true) }
            fn list_window_ids(&self, _all: bool) -> Result<Vec<String>> { Ok(self.ids.clone()) }
            fn pane_root_pids(&self, win: &str) -> Result<Vec<u64>> {
                if self.pane_err.as_deref() == Some(win) { Err(anyhow!("read failed")) }
                else { Ok(self.panes.get(win).cloned().unwrap_or_default()) }
            }
        }

        // All panes aggregated; a truncated tree makes the whole snapshot incomplete.
        let proc = P(HashMap::from([
            (100u64, ProcTree { procs: vec![ProcEvidence { pid: 100, argv: vec!["codex".into()], env: vec![], }], complete: true }),
            (200u64, ProcTree { procs: vec![ProcEvidence { pid: 200, argv: vec!["sh".into()], env: vec![], }], complete: false }),  // truncated/unreadable
            (300u64, ProcTree { procs: vec![], complete: true }),
        ]));
        let tmux = T { ids: vec!["@1".into(), "@2".into()],
                       panes: HashMap::from([("@1".into(), vec![100, 200]), ("@2".into(), vec![300])]),
                       pane_err: None };
        let l = Launcher::with_seams(Box::new(proc), Box::new(tmux), Box::new(FakeForeground(false)));
        let ev = l.collect_evidence(&[]).unwrap();
        assert_eq!(ev.windows.len(), 2);
        assert_eq!(ev.windows[0].procs.len(), 2, "both panes of @1 are aggregated");
        assert!(!ev.complete, "a truncated pane marks the snapshot incomplete");

        // An unreadable pane is reported as an error and marks incomplete.
        let tmux2 = T { ids: vec!["@3".into()], panes: HashMap::new(), pane_err: Some("@3".into()) };
        let l2 = Launcher::with_seams(Box::new(P(HashMap::new())), Box::new(tmux2), Box::new(FakeForeground(false)));
        let ev2 = l2.collect_evidence(&[]).unwrap();
        assert!(!ev2.complete);
        assert!(!ev2.errors.is_empty());
    }
}
```

### 11.8b External project browser (`core::browse`)

PB-01: `b` opens a Browse project directory form (advertised in help). Launching
Yazi rooted there reuses the structured `LaunchRequest`/execution seams — a new
tmux window in tmux, a suspend/foreground/restore run otherwise — and browser
windows NEVER enter session tracking, pending-creation reconciliation, or
provider operations. The private profile is isolated for ALL three tools: Yazi
via `YAZI_CONFIG_HOME`, Glow via `GLOW_CONFIG_HOME` (glow sources config only
from there and writes its own `glow.yml` into it), and bat via `BAT_CONFIG_PATH`
plus pinned paging (`BAT_PAGER`/`PAGER`). The Yazi `[open]` rules are fully
overridden (not appended), so Yazi's defaults (external editors, `xdg-open`,
archive extractors) never precede our viewers: Markdown → Glow, text/code →
bat, unsupported → a clear refusal. Openers use `--` end-of-options and the
`%s` placeholder (Yazi 26.9.1 shell-quotes substitutions — the shipped default
config relies on this); Pinga never puts user paths into shell text. Errors are
rendered alongside the still-editable form in both modal and inline modes.

``` {.rust #core-browse path="src/browse.rs"}
use anyhow::{anyhow, bail, Result};
use std::path::{Path, PathBuf};

use crate::model::LaunchRequest;

/// The external viewers the browser relies on, checked before any launch so a
/// missing dependency fails fast with actionable names. `less` is checked too:
/// it is the pinned pager for both Glow and bat.
pub const BROWSER_TOOLS: [&str; 4] = ["yazi", "glow", "bat", "less"];

/// pinga's runtime state directory. Overridable for tests via `PINGA_STATE_DIR`;
/// otherwise the platform state dir. Resolved at runtime so the feature works
/// from an installed binary, never a repo-relative or checkout path.
pub fn pinga_state_dir() -> PathBuf {
    if let Some(dir) = std::env::var_os("PINGA_STATE_DIR") {
        return PathBuf::from(dir);
    }
    dirs::state_dir()
        .unwrap_or_else(|| dirs::home_dir().unwrap_or_default().join(".local/state"))
        .join("pinga")
}

/// The private, Pinga-owned Yazi profile directory. Persistent (never deleted)
/// so a tmux window that outlives pinga never references a removed path.
pub fn profile_dir(state_dir: &Path) -> PathBuf {
    state_dir.join("browse").join("yazi-profile")
}

/// Minimal, Pinga-owned bat config: `BAT_CONFIG_PATH` replaces the user config
/// path, so no ambient user bat config can replace the intended viewer.
pub const BAT_CONF: &str = "# Pinga browse: minimal bat config (see browse_launch)\n";

/// Minimal, pinned Glow config. Glow's `main.go` PREPENDS `GLOW_CONFIG_HOME`
/// to the searched config dirs (it does not replace them), so an EMPTY private
/// dir would still fall through to the user's personal glow.yml. Publishing a
/// valid glow.yml here makes viper find THIS file first; ambient GLOW_* env is
/// additionally pinned in `browse_launch`.
pub const GLOW_YML: &str = concat!(
    "# Pinga browse: pinned minimal glow config\n",
    "style: dark\n",
    "pager: true\n",
    "tui: false\n",
    "mouse: false\n",
    "width: 100\n",
);

/// Private browser colors: pale green on dark purple and pale purple on dark
/// green. Keep the override under `[mode]` to preserve the indicator layout;
/// the earlier `[status]` override failed the user's visual check.
pub const THEME_TOML: &str = concat!(
    "# Pinga browse theme override (Yazi 26.9.1)\n",
    "# Preserve the default status layout; customize mode colors only.\n",
    "[mode]\n",
    "normal_main = { fg = \"#a5e5aa\", bg = \"#352044\", bold = true }\n",
    "normal_alt = { fg = \"#d3a4ef\", bg = \"#173d2a\" }\n",
);

/// The isolated Yazi profile. The `[open]` rules are FULLY overridden (never
/// appended), so Yazi's defaults — external editors, `xdg-open`, archive
/// extractors — never precede our viewers: Markdown → Glow, text/code → bat,
/// unsupported → a clear refusal. Openers use `--` end-of-options and the
/// `%s` placeholder (Yazi 26.9.1 shell-quotes substitutions; the shipped
/// default config relies on this), so hostile file names are never split or
/// parsed as flags.
pub const YAZI_PROFILE: &str = r#"# Pinga browse profile (Yazi 26.9.1, YAZI_CONFIG_HOME)
[opener]
markdown = [{ name = "markdown", run = 'glow -p -- %s1', block = true, desc = "Render the first selected markdown file in a pager" }]
text = [{ name = "text", run = 'bat --paging=always -- %s1', block = true, desc = "Page the first selected text/code file" }]
refuse = [{ name = "refuse", run = 'printf "No viewer configured for this file type (Pinga browse).\n"; sleep 1', block = true, desc = "Refuse unsupported file type" }]

[open]
rules = [
  { mime = "text/markdown", use = "markdown" },
  { url = "*.md", use = "markdown" },
  { url = "*.markdown", use = "markdown" },
  { mime = "text/*", use = "text" },
  { mime = "application/json", use = "text" },
  { mime = "inode/empty", use = "text" },
  { url = "*.{txt,log,cfg,conf,ini,toml,yaml,yml,json,xml,rs,py,sh,bash,zsh,go,js,jsx,ts,tsx,html,css,c,cpp,h,hpp,java,rb,php,lua,pl,r,swift,kt}", use = "text" },
  { url = "*", use = "refuse" },
]
"#;

/// Atomically publish a file with a UNIQUE temp name so concurrent Pinga
/// instances never share a temp path; `rename` is atomic on POSIX, so the last
/// writer wins whole and no reader ever observes a torn file.
fn publish(path: &Path, contents: &str) -> Result<()> {
    let nanos = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default().as_nanos();
    let name = path.file_name().map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| "file".into());
    let tmp = path.with_file_name(format!(".{name}.tmp.{}.{nanos}", std::process::id()));
    std::fs::write(&tmp, contents)?;
    std::fs::rename(&tmp, path)?;
    Ok(())
}

/// (Re)publish the private profile: the Yazi config, a private theme override,
/// a minimal bat config, a minimal pinned Glow config (published, not empty —
/// see GLOW_YML), and the private Glow home. Returns the canonical (absolute)
/// profile dir.
pub fn ensure_profile(state_dir: &Path) -> Result<PathBuf> {
    let dir = profile_dir(state_dir);
    std::fs::create_dir_all(&dir)?;
    publish(&dir.join("yazi.toml"), YAZI_PROFILE)?;
    publish(&dir.join("theme.toml"), THEME_TOML)?;
    publish(&dir.join("bat.conf"), BAT_CONF)?;
    let glow_home = dir.join("glow");
    std::fs::create_dir_all(&glow_home)?;
    publish(&glow_home.join("glow.yml"), GLOW_YML)?;
    Ok(std::fs::canonicalize(&dir)?)
}

#[cfg(unix)]
fn is_executable(p: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    p.metadata().map(|m| m.permissions().mode() & 0o111 != 0).unwrap_or(false)
}

#[cfg(not(unix))]
fn is_executable(_p: &Path) -> bool {
    true
}

fn on_path(dir: &Path, program: &str) -> bool {
    let full = dir.join(program);
    full.is_file() && is_executable(&full)
}

/// Check the external viewers against the given search directories (a PATH
/// split). Returns an actionable error listing which tools are missing.
pub fn check_tools(search: &[PathBuf]) -> Result<()> {
    let missing: Vec<&str> = BROWSER_TOOLS.iter().copied()
        .filter(|t| !search.iter().any(|d| on_path(d, t)))
        .collect();
    if missing.is_empty() {
        return Ok(());
    }
    bail!(
        "missing browser viewers on PATH: {} — install yazi, glow and bat \
         (see docs/handoffs/PB-01-report.md for instructions)",
        missing.join(", "))
}

/// Check the external viewers against the current process PATH.
pub fn check_tools_env() -> Result<()> {
    let search: Vec<PathBuf> = match std::env::var_os("PATH") {
        Some(p) => std::env::split_paths(&p).collect(),
        None => Vec::new(),
    };
    check_tools(&search)
}

/// Resolve the user's directory input against Pinga's cwd. Relative input
/// resolves against `cwd`; input is taken literally — no shell, no variable or
/// `~` expansion, and NO trimming of real path whitespace (leading/trailing
/// spaces are part of the path). Returns the validated absolute directory or
/// an explanation.
pub fn resolve_directory(input: &str, cwd: &Path) -> Result<PathBuf> {
    if input.is_empty() {
        bail!("enter a directory to browse");
    }
    let raw = Path::new(input);
    let candidate = if raw.is_absolute() {
        raw.to_path_buf()
    } else {
        cwd.join(raw)
    };
    let canonical = std::fs::canonicalize(&candidate)
        .map_err(|e| anyhow!("cannot resolve {:?}: {e}", candidate))?;
    if !canonical.is_dir() {
        bail!("{:?} is not a directory", canonical);
    }
    Ok(canonical)
}

/// Build the Yazi launch rooted at `dir` with the private profile. Literal
/// argv (no shell); file-argument boundaries are preserved by the launch
/// request serialization. Pins ALL viewer configs/pagers via environment: Yazi
/// `YAZI_CONFIG_HOME`, Glow `GLOW_CONFIG_HOME` + `GLOW_TUI=false` (neutralizes
/// ambient GLOW_TUI=true), bat `BAT_CONFIG_PATH`, color-preserving pager
/// `less -R` for both (`BAT_PAGER`/`PAGER`), and `LESS=""` so ambient `LESS`
/// flags (e.g. `-F` quit-if-one-screen) cannot cause an immediate viewer exit.
/// Rejects non-UTF-8 paths instead of substituting replacement characters.
pub fn browse_launch(dir: &Path, profile: &Path) -> Result<LaunchRequest> {
    let dir_s = dir.to_str().ok_or_else(|| anyhow!("browse directory is not valid UTF-8"))?;
    let profile_s = profile.to_str().ok_or_else(|| anyhow!("browse profile is not valid UTF-8"))?;
    Ok(LaunchRequest {
        program: "yazi".into(),
        args: vec![dir_s.to_string()],
        cwd: Some(dir_s.to_string()),
        env: vec![
            ("YAZI_CONFIG_HOME".into(), profile_s.to_string()),
            ("GLOW_CONFIG_HOME".into(), format!("{profile_s}/glow")),
            ("GLOW_TUI".into(), "false".into()),
            ("BAT_CONFIG_PATH".into(), format!("{profile_s}/bat.conf")),
            ("BAT_PAGER".into(), "less -R".into()),
            ("PAGER".into(), "less -R".into()),
            ("LESS".into(), String::new()),
        ],
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    struct TempDir(PathBuf);
    impl TempDir {
        fn new() -> Self {
            let nanos = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default().as_nanos();
            let p = std::env::temp_dir().join(format!("pinga-browse-{}-{}", std::process::id(), nanos));
            fs::create_dir_all(&p).unwrap();
            TempDir(p)
        }
        fn path(&self) -> &Path { &self.0 }
    }
    impl Drop for TempDir {
        fn drop(&mut self) { let _ = fs::remove_dir_all(&self.0); }
    }

    #[cfg(unix)]
    fn stub_bin(dir: &Path, name: &str) {
        use std::os::unix::fs::PermissionsExt;
        let p = dir.join(name);
        fs::write(&p, "#!/bin/sh\nexit 0\n").unwrap();
        fs::set_permissions(&p, fs::Permissions::from_mode(0o755)).unwrap();
    }
    #[cfg(not(unix))]
    fn stub_bin(dir: &Path, name: &str) {
        fs::write(dir.join(name), "exit 0\n").unwrap();
    }

    #[test]
    fn resolve_directory_accepts_absolute_and_resolves_relative() {
        let base = TempDir::new();
        let sub = base.path().join("sub dir with spaces");
        fs::create_dir_all(&sub).unwrap();
        let abs = resolve_directory(&sub.to_string_lossy(), base.path()).unwrap();
        assert_eq!(abs, fs::canonicalize(&sub).unwrap());
        let rel = resolve_directory("sub dir with spaces", base.path()).unwrap();
        assert_eq!(rel, abs);
        let file = sub.join("a file.txt");
        fs::write(&file, "x").unwrap();
        assert!(resolve_directory(&file.to_string_lossy(), base.path()).is_err());
    }

    #[test]
    fn resolve_directory_rejects_invalid_input() {
        let base = TempDir::new();
        assert!(resolve_directory("", base.path()).is_err());
        assert!(resolve_directory("   ", base.path()).is_err());
        assert!(resolve_directory("/nonexistent-pb01-xyz", base.path()).is_err());
    }

    #[test]
    fn resolve_directory_handles_hostile_names_literally() {
        let base = TempDir::new();
        let sub = base.path().join("$HOME; touch /tmp/pwned; ' quote");
        fs::create_dir_all(&sub).unwrap();
        let dir = resolve_directory(&sub.to_string_lossy(), base.path()).unwrap();
        assert_eq!(dir, fs::canonicalize(&sub).unwrap());
        assert!(!Path::new("/tmp/pwned").exists(), "nothing was executed");
    }

    #[test]
    fn check_tools_reports_missing_then_accepts_all() {
        let base = TempDir::new();
        let bindir = base.path().join("bin");
        fs::create_dir_all(&bindir).unwrap();
        let err = check_tools(std::slice::from_ref(&bindir)).unwrap_err();
        assert!(err.to_string().contains("missing browser viewers"));
        for tool in BROWSER_TOOLS {
            stub_bin(&bindir, tool);
        }
        assert!(check_tools(&[bindir]).is_ok());
    }

    #[test]
    fn profile_is_written_atomically_and_hermetic() {
        let base = TempDir::new();
        let dir = ensure_profile(base.path()).unwrap();
        assert_eq!(dir, std::fs::canonicalize(profile_dir(base.path())).unwrap());
        let cfg = fs::read_to_string(dir.join("yazi.toml")).unwrap();
        assert!(cfg.contains("[opener]"));
        assert!(cfg.contains("glow -p -- %s"));
        assert!(cfg.contains("bat --paging=always -- %s"));
        assert!(cfg.contains("block = true"));
        assert!(fs::read_to_string(dir.join("bat.conf")).unwrap().contains("minimal bat config"));
        assert!(fs::read_to_string(dir.join("theme.toml")).unwrap().contains("[mode]"),
            "the private Yazi theme override must be published");
        assert!(fs::read_to_string(dir.join("glow").join("glow.yml")).unwrap().contains("pager: true"),
            "a valid glow.yml must be published so viper finds it before personal config");
        assert!(dir.join("glow").is_dir());
        // Idempotent re-publication never deletes the profile.
        ensure_profile(base.path()).unwrap();
        assert_eq!(fs::read_to_string(dir.join("yazi.toml")).unwrap(), cfg);
    }

    #[test]
    fn profile_publication_is_safe_under_concurrent_writers() {
        let base = TempDir::new();
        let dir = base.path().to_path_buf();
        let mut handles = Vec::new();
        for _ in 0..8 {
            let d = dir.clone();
            handles.push(std::thread::spawn(move || ensure_profile(&d).unwrap()));
        }
        for h in handles {
            h.join().unwrap();
        }
        let cfg = fs::read_to_string(dir.join("browse").join("yazi-profile").join("yazi.toml")).unwrap();
        assert_eq!(cfg, YAZI_PROFILE, "no torn/corrupted profile after concurrent writers");
        assert_eq!(fs::read_to_string(dir.join("browse").join("yazi-profile").join("bat.conf")).unwrap(), BAT_CONF);
    }

    #[test]
    fn browse_launch_roots_yazi_with_private_profile() {
        let base = TempDir::new();
        let dir = base.path().join("dir with 'quotes' and $dollar");
        fs::create_dir_all(&dir).unwrap();
        let profile = base.path().join("profile");
        let launch = browse_launch(&dir, &profile).unwrap();
        assert_eq!(launch.program, "yazi");
        assert_eq!(launch.args, vec![dir.to_string_lossy().into_owned()]);
        assert_eq!(launch.cwd.as_deref(), Some(dir.to_string_lossy().as_ref()));
        let ps = profile.to_string_lossy().into_owned();
        assert!(launch.env.iter().any(|(k, v)| k == "YAZI_CONFIG_HOME" && v == &ps));
        assert!(launch.env.iter().any(|(k, v)| k == "GLOW_CONFIG_HOME" && v == &format!("{ps}/glow")));
        assert!(launch.env.iter().any(|(k, v)| k == "BAT_CONFIG_PATH" && v == &format!("{ps}/bat.conf")));
        assert!(launch.env.iter().any(|(k, v)| k == "BAT_PAGER" && v == "less -R"));
        assert!(launch.env.iter().any(|(k, v)| k == "PAGER" && v == "less -R"));
        assert!(launch.env.iter().any(|(k, v)| k == "GLOW_TUI" && v == "false"));
        assert!(launch.env.iter().any(|(k, v)| k == "LESS" && v.is_empty()),
            "ambient LESS flags (e.g. -F immediate exit) must be neutralized");
    }

    #[cfg(unix)]
    #[test]
    fn browse_launch_rejects_non_utf8_paths() {
        use std::os::unix::ffi::OsStrExt;
        let base = TempDir::new();
        let dir = base.path().join(std::ffi::OsStr::from_bytes(b"\xFF\xFE"));
        fs::create_dir_all(&dir).unwrap();
        let canonical = fs::canonicalize(&dir).unwrap();
        let profile = base.path().join("profile");
        assert!(browse_launch(&canonical, &profile).is_err(),
            "non-UTF-8 roots must be rejected, never lossily substituted");
    }

    #[test]
    fn resolve_directory_preserves_leading_trailing_spaces_literally() {
        let base = TempDir::new();
        let sub = base.path().join("  padded dir  ");
        fs::create_dir_all(&sub).unwrap();
        let dir = resolve_directory("  padded dir  ", base.path()).unwrap();
        assert_eq!(dir, fs::canonicalize(&sub).unwrap());
        // A near-miss with one trailing space is a DIFFERENT literal path.
        assert!(resolve_directory("  padded dir ", base.path()).is_err());
    }

    #[test]
    fn opener_templates_use_single_file_policy_and_full_rules_override() {
        assert_eq!(opener_run_template("markdown"), "glow -p -- %s1",
            "glow declares cobra.MaximumNArgs(1): exactly one file");
        assert_eq!(opener_run_template("text"), "bat --paging=always -- %s1",
            "single-file policy pinned for the bat viewer too");
        assert!(!YAZI_PROFILE.contains("append_rules"), "defaults must not precede our openers");
        assert!(!YAZI_PROFILE.contains("prepend_rules"));
        assert!(YAZI_PROFILE.contains("[open]\nrules = ["));
        assert!(YAZI_PROFILE.contains("{ url = \"*\", use = \"refuse\" }"), "unsupported -> clear refusal");
        assert!(YAZI_PROFILE.contains("use = \"markdown\""));
        assert!(YAZI_PROFILE.contains("use = \"text\""));
        // The refusal opener never interpolates a user path.
        let refuse = YAZI_PROFILE.lines().find(|l| l.contains("use = \"refuse\"")
            || l.contains("name = \"refuse\"")).unwrap_or("");
        assert!(!refuse.contains("%s"), "refusal must not execute the file");
    }

    fn opener_run_template(name: &str) -> String {
        for line in YAZI_PROFILE.lines() {
            let line = line.trim_start();
            if let Some(rest) = line.strip_prefix(&format!("{name} = ")) {
                let marker = "run = '";
                let start = rest.find(marker).expect("run template") + marker.len();
                let end = rest[start..].find('\'').expect("closing quote") + start;
                return rest[start..end].to_string();
            }
        }
        panic!("opener {name} not found in profile");
    }

    #[test]
    fn browse_theme_override_targets_low_contrast_status_widgets() {
        // Verified against the installed Yazi 26.9.1 in a PTY: a `[mode]`
        // override fixes the blue/white mode block and PRESERVES the status
        // bar layout (the right-hand tab indicator stays). A `[status]`
        // override (even `overall` alone) makes the right-hand tab indicator
        // disappear, so the override must NOT touch `[status]`.
        assert!(THEME_TOML.contains("[mode]"));
        assert!(THEME_TOML.contains("normal_main = { fg = \"#a5e5aa\", bg = \"#352044\", bold = true }"));
        assert!(!THEME_TOML.lines().any(|l| l.trim_start().starts_with("[status]")),
            "a [status] table hides the right tab indicator in Yazi 26.9.1");
        assert!(!THEME_TOML.contains("bg = \"blue\""),
            "the bare blue background of the shipped mode block must be replaced");
        for untouched in ["[which]", "[input]", "[manager]", "[confirm]"] {
            assert!(!THEME_TOML.contains(untouched),
                "override must not restyle unrelated widgets ({untouched})");
        }
    }

    #[cfg(unix)]
    #[test]
    fn opener_templates_survive_posix_quoting_for_single_hostile_file() {
        // Precisely scoped: this substitutes a RECORDER for the viewer and
        // emulates Yazi's single-quote `%s1` substitution to prove OUR opener
        // template survives a real POSIX shell for one hostile file at a time
        // (glow's cobra.MaximumNArgs(1) forbids multi-file). Real Yazi/Glow
        // runtime validation remains PENDING (tools not installed).
        use std::os::unix::fs::PermissionsExt;
        use std::process::Command;
        let base = TempDir::new();
        let script = base.path().join("record.sh");
        let record = base.path().join("record.txt");
        fs::write(&script, concat!(
            "#!/bin/sh\n",
            ": > \"$RECORD\"\n",
            "for a in \"$@\"; do printf '<%s>\\n' \"$a\" >> \"$RECORD\"; done\n",
        )).unwrap();
        fs::set_permissions(&script, fs::Permissions::from_mode(0o755)).unwrap();
        let hostile = [
            "-leading-dash",
            "with spaces",
            "it's quoted",
            "unicode π",
            "a;b",
            "$HOME; touch /tmp/x",
        ];
        for opener in ["markdown", "text"] {
            let run = opener_run_template(opener); // e.g. "glow -p -- %s1"
            let prog = script.to_string_lossy().into_owned();
            let rest = run.split_once(' ').map(|(_, r)| r).unwrap_or_default();
            for path in hostile {
                let quoted = format!("'{}'", path.replace('\'', "'\\''"));
                let cmd = format!("{prog} {}", rest.replace("%s1", &quoted));
                let status = Command::new("sh").arg("-c").arg(&cmd)
                    .env("RECORD", &record)
                    .env_remove("PAGER").env_remove("BAT_PAGER")
                    .status().expect("run recorder");
                assert!(status.success(), "opener template must run: {cmd}");
                let lines: Vec<String> = fs::read_to_string(&record).unwrap()
                    .lines().map(str::to_string).collect();
                assert_eq!(lines.len(), 3,
                    "flags + -- + EXACTLY ONE file for {opener} with {path:?}: {lines:?}");
                assert_eq!(lines[1], "<-->", "end-of-options present: {lines:?}");
                assert_eq!(lines[2], format!("<{path}>"),
                    "{opener} lost path {path:?}: {lines:?}");
            }
        }
    }
}
```

### 11.9 Tracking store (`core::tracking`)

Versioned, fallible tracking persisted at
`~/.local/state/pinga/tracking-v2.json` (+ `tracking-v2.lock`). The pinned JSON
envelope is `version: 2`, a monotonically allocated `next_id`, and tagged
records (`known`/`pending`/`opaque`). All writes lock, reread, mutate, and
atomically replace under the lock (same-directory temp file, flush/sync, then
rename); lock/read/parse/write/rename failures are errors and corruption is
never treated as an empty registry. A failed read preserves the last good
in-memory view. Legacy migration takes one `opened.json` snapshot under both
locks, saves its exact original bytes to `opened-v1-migration-backup.json`
(never overwriting an existing backup), and maps tuple `0`→`opencode`, `1`→`codex`
irrespective of current config; known indices with empty native IDs become
unresolved `pending` records and unknown indices become `opaque`. Once v2
exists, legacy is never rewritten or reimported.

``` {.rust #core-tracking path="src/tracking.rs"}
use anyhow::{anyhow, Context, Result};
use serde::{Deserialize, Serialize};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use crate::model::{ProviderId, SessionKey};

pub const SCHEMA_VERSION: u32 = 2;

/// Lifecycle state of a known tracked session. Interruption, once established,
/// is retained across refreshes/restarts until successfully resumed or the
/// known session disappears from a successful authoritative listing.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TrackedState {
    #[default]
    Open,
    Interrupted,
}

/// A tagged tracking record. `id` is the stable unique record id allocated
/// under the shared lock; newly added records carry 0 and are assigned on
/// commit (overflow is an error).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum TrackedRecord {
    Known { id: u64, provider: ProviderId, session: String, window: String, state: TrackedState },
    Pending { id: u64, provider: ProviderId, window: String, label: String },
    Opaque { id: u64, provider_index: usize, session: String, window: String },
}

impl TrackedRecord {
    pub fn record_id(&self) -> u64 {
        match self {
            TrackedRecord::Known { id, .. }
            | TrackedRecord::Pending { id, .. }
            | TrackedRecord::Opaque { id, .. } => *id,
        }
    }
    pub fn window(&self) -> &str {
        match self {
            TrackedRecord::Known { window, .. }
            | TrackedRecord::Pending { window, .. }
            | TrackedRecord::Opaque { window, .. } => window,
        }
    }
    pub fn provider_id(&self) -> Option<&ProviderId> {
        match self {
            TrackedRecord::Known { provider, .. } | TrackedRecord::Pending { provider, .. } => Some(provider),
            TrackedRecord::Opaque { .. } => None,
        }
    }
    /// The validated SessionKey of a Known record.
    pub fn known_key(&self) -> Option<Result<SessionKey>> {
        match self {
            TrackedRecord::Known { provider, session, .. } => {
                Some(SessionKey::new(provider.clone(), session.clone()))
            }
            _ => None,
        }
    }
}

fn id_mut(r: &mut TrackedRecord) -> &mut u64 {
    match r {
        TrackedRecord::Known { id, .. }
        | TrackedRecord::Pending { id, .. }
        | TrackedRecord::Opaque { id, .. } => id,
    }
}

/// The pinned serialized envelope (Stage 3).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Envelope {
    pub version: u32,
    pub next_id: u64,
    pub records: Vec<TrackedRecord>,
}

/// Fallible versioned tracking. `read` preserves the last good in-memory view
/// when the file is unreadable; `update` is an atomic locked read-modify-write.
pub trait TrackingStore: Send {
    fn read(&self) -> Result<Vec<TrackedRecord>>;
    fn update(&self, f: &mut dyn FnMut(&mut Vec<TrackedRecord>) -> bool) -> Result<Vec<TrackedRecord>>;
}

/// The real file-backed store with an injectable directory and a last-good
/// in-memory cache.
pub struct FileTrackingStore {
    dir: PathBuf,
    cache: Mutex<Option<Vec<TrackedRecord>>>,
}

impl FileTrackingStore {
    pub fn new(dir: PathBuf) -> Self { Self { dir, cache: Mutex::new(None) } }

    fn json_path(&self) -> PathBuf { self.dir.join("tracking-v2.json") }
    fn lock_path(&self) -> PathBuf { self.dir.join("tracking-v2.lock") }
    fn legacy_json_path(&self) -> PathBuf { self.dir.join("opened.json") }
    fn legacy_lock_path(&self) -> PathBuf { self.dir.join("opened.lock") }
    fn backup_path(&self) -> PathBuf { self.dir.join("opened-v1-migration-backup.json") }

    /// Ensure v2 exists; migrate from legacy once under both locks. Missing
    /// legacy => empty initial v2; malformed legacy aborts without replacing
    /// either data file. The legacy bytes are read ONCE under both locks and
    /// are both backed up and parsed from that single snapshot.
    fn ensure_initialized(&self) -> Result<()> {
        if self.json_path().exists() { return Ok(()); }
        let _lock = LockGuard::acquire(&self.lock_path())?;
        if self.json_path().exists() { return Ok(()); }
        let legacy: Option<(Vec<u8>, Vec<LegacyTuple>)> = {
            let _l = LockGuard::acquire(&self.legacy_lock_path())?;
            match read_legacy_bytes(&self.legacy_json_path())? {
                Some(raw) => {
                    let tuples: Vec<LegacyTuple> = serde_json::from_slice(&raw)
                        .with_context(|| format!("malformed legacy {}", self.legacy_json_path().display()))?;
                    Some((raw, tuples))
                }
                None => None,
            }
        };
        let mut env = Envelope { version: SCHEMA_VERSION, next_id: 1, records: Vec::new() };
        if let Some((raw, tuples)) = legacy {
            // Publish the EXACT original bytes as a durable backup BEFORE any v2
            // write; a conflicting/truncated existing backup aborts.
            publish_backup(&self.backup_path(), &raw)?;
            env.records = migrate(tuples, &mut env.next_id);
        }
        validate_envelope(&env)?;
        write_atomic(&self.json_path(), &env)?;
        Ok(())
    }
}

impl TrackingStore for FileTrackingStore {
    fn read(&self) -> Result<Vec<TrackedRecord>> {
        self.ensure_initialized()?;
        let env = read_v2(&self.json_path())?;
        let records = env.records.clone();
        *self.cache.lock().unwrap() = Some(records.clone());
        Ok(records)
    }

    fn update(&self, f: &mut dyn FnMut(&mut Vec<TrackedRecord>) -> bool) -> Result<Vec<TrackedRecord>> {
        self.ensure_initialized()?;
        let _lock = LockGuard::acquire(&self.lock_path())?;
        // Reread the CURRENT file under the lock; corruption is an error.
        let mut env = read_v2(&self.json_path())
            .with_context(|| format!("reread {}", self.json_path().display()))?;
        let changed = f(&mut env.records);
        if changed {
            for r in env.records.iter_mut() {
                if r.record_id() == 0 {
                    if env.next_id == u64::MAX { return Err(anyhow!("tracking record id overflow")); }
                    *id_mut(r) = env.next_id;
                    env.next_id += 1;
                }
            }
            // Constructor invariants must also hold after mutation.
            validate_envelope(&env)?;
            write_atomic(&self.json_path(), &env)?;
        }
        let records = env.records.clone();
        *self.cache.lock().unwrap() = Some(records.clone());
        Ok(records)
    }
}

/// An exclusive advisory lock held for the lifetime of the guard.
struct LockGuard { _file: fs::File }

impl LockGuard {
    fn acquire(path: &Path) -> Result<Self> {
        if let Some(parent) = path.parent() { fs::create_dir_all(parent)?; }
        let file = fs::OpenOptions::new()
            .create(true).read(true).write(true).truncate(false)
            .open(path).with_context(|| format!("open lock {}", path.display()))?;
        fs2::FileExt::lock_exclusive(&file)
            .with_context(|| format!("lock {}", path.display()))?;
        Ok(Self { _file: file })
    }
}

fn read_v2(path: &Path) -> Result<Envelope> {
    let raw = fs::read_to_string(path).with_context(|| format!("read {}", path.display()))?;
    let env: Envelope = serde_json::from_str(&raw)
        .with_context(|| format!("parse {}", path.display()))?;
    // Constructor invariants must also hold after deserialization.
    validate_envelope(&env)?;
    Ok(env)
}

fn read_legacy_bytes(path: &Path) -> Result<Option<Vec<u8>>> {
    match fs::read(path) {
        Ok(raw) => Ok(Some(raw)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(anyhow!("read legacy {}: {e}", path.display())),
    }
}

type LegacyTuple = (usize, String, String);

/// Map legacy tuples. Historical 0 => opencode, 1 => codex regardless of current
/// config/order; empty native IDs become unresolved pending records; unknown
/// indices remain opaque (including empty IDs).
fn migrate(tuples: Vec<(usize, String, String)>, next_id: &mut u64) -> Vec<TrackedRecord> {
    let mut out = Vec::new();
    for (p, sid, win) in tuples {
        let id = *next_id;
        *next_id += 1;
        match p {
            0 | 1 => {
                let provider = ProviderId::new(if p == 0 { "opencode" } else { "codex" })
                    .expect("builtin ids valid");
                if sid.is_empty() {
                    out.push(TrackedRecord::Pending { id, provider, window: win, label: "(unresolved legacy)".into() });
                } else {
                    out.push(TrackedRecord::Known { id, provider, session: sid, window: win, state: TrackedState::Open });
                }
            }
            _ => out.push(TrackedRecord::Opaque { id, provider_index: p, session: sid, window: win }),
        }
    }
    out
}

/// Same-directory temp + flush/sync + atomic rename; durability errors are
/// surfaced honestly. Directory metadata is synced after publication.
fn write_atomic(path: &Path, env: &Envelope) -> Result<()> {
    let json = serde_json::to_string_pretty(env).with_context(|| "serialize tracking")?;
    let tmp = path.with_extension("json.tmp");
    let mut f = fs::File::create(&tmp).with_context(|| format!("create {}", tmp.display()))?;
    f.write_all(json.as_bytes())?;
    f.flush()?;
    f.sync_all()?;
    fs::rename(&tmp, path).with_context(|| format!("rename to {}", path.display()))?;
    if let Some(parent) = path.parent() {
        fs::File::open(parent).with_context(|| format!("open directory {}", parent.display()))?
            .sync_all().with_context(|| format!("sync directory {}", parent.display()))?;
    }
    Ok(())
}

/// Durable, recoverable backup publication. An existing backup is accepted only
/// if byte-identical (a crash/retry with the same legacy); a conflicting or
/// truncated backup aborts before any v2 write. Published via temp + sync +
/// atomic rename + directory sync.
fn publish_backup(path: &Path, bytes: &[u8]) -> Result<()> {
    if let Some(parent) = path.parent() { fs::create_dir_all(parent)?; }
    if path.exists() {
        let existing = fs::read(path).with_context(|| format!("read backup {}", path.display()))?;
        if existing != bytes {
            return Err(anyhow!("backup {} conflicts with a previous migration; refusing to overwrite",
                               path.display()));
        }
        return Ok(()); // identical bytes: safe retry
    }
    let tmp = path.with_extension("json.bak.tmp");
    let mut f = fs::File::create(&tmp).with_context(|| format!("create {}", tmp.display()))?;
    f.write_all(bytes)?;
    f.flush()?;
    f.sync_all()?;
    fs::rename(&tmp, path).with_context(|| format!("publish backup {}", path.display()))?;
    if let Some(parent) = path.parent() {
        fs::File::open(parent).with_context(|| format!("open directory {}", parent.display()))?
            .sync_all().with_context(|| format!("sync directory {}", parent.display()))?;
    }
    Ok(())
}

/// Validate persisted envelope invariants: version, unique nonzero record ids,
/// `next_id` strictly greater than every committed id, valid provider ids, and
/// nonempty native ids on Known records. Invalid envelopes never rewrite the
/// file (callers must fail before committing).
pub fn validate_envelope(env: &Envelope) -> Result<()> {
    if env.version != SCHEMA_VERSION {
        return Err(anyhow!("unsupported tracking version {}", env.version));
    }
    if env.next_id == 0 {
        return Err(anyhow!("next_id must be nonzero"));
    }
    let mut seen = std::collections::HashSet::new();
    for r in &env.records {
        let id = r.record_id();
        if id == 0 { return Err(anyhow!("tracking record id must be nonzero")); }
        if !seen.insert(id) { return Err(anyhow!("duplicate tracking record id {id}")); }
        match r {
            TrackedRecord::Known { provider, session, .. } => {
                ProviderId::new(provider.as_str()).map_err(|_| anyhow!("invalid provider id in record"))?;
                if session.is_empty() { return Err(anyhow!("known record has an empty native id")); }
            }
            TrackedRecord::Pending { provider, .. } => {
                ProviderId::new(provider.as_str()).map_err(|_| anyhow!("invalid provider id in record"))?;
            }
            TrackedRecord::Opaque { .. } => {}
        }
    }
    if let Some(max) = seen.iter().max() {
        if env.next_id <= *max {
            return Err(anyhow!("next_id {} collides with a committed record id", env.next_id));
        }
    }
    Ok(())
}

/// An in-memory store for tests that mirrors the real store: it holds an
/// Envelope (retaining `next_id` across deletions), keeps the lock over the
/// read-modify-write, allocates monotonic ids, and validates the envelope.
pub struct MemStore { inner: std::sync::Arc<Mutex<Envelope>> }

impl MemStore {
    pub fn new(records: Vec<TrackedRecord>) -> Self {
        let next = records.iter().map(|r| r.record_id()).max().unwrap_or(0) + 1;
        Self { inner: std::sync::Arc::new(Mutex::new(
            Envelope { version: SCHEMA_VERSION, next_id: next.max(1), records })) }
    }
    pub fn shared(inner: std::sync::Arc<Mutex<Envelope>>) -> Self { Self { inner } }
    pub fn snapshot(&self) -> Vec<TrackedRecord> { self.inner.lock().unwrap().records.clone() }
    pub fn envelope(&self) -> Envelope { self.inner.lock().unwrap().clone() }
}

impl TrackingStore for MemStore {
    fn read(&self) -> Result<Vec<TrackedRecord>> {
        let env = self.inner.lock().unwrap().clone();
        validate_envelope(&env)?;
        Ok(env.records)
    }
    fn update(&self, f: &mut dyn FnMut(&mut Vec<TrackedRecord>) -> bool) -> Result<Vec<TrackedRecord>> {
        let mut env = self.inner.lock().unwrap().clone();
        let changed = f(&mut env.records);
        if changed {
            for r in env.records.iter_mut() {
                if r.record_id() == 0 {
                    if env.next_id == u64::MAX { return Err(anyhow!("tracking record id overflow")); }
                    *id_mut(r) = env.next_id;
                    env.next_id += 1;
                }
            }
            validate_envelope(&env)?;
            *self.inner.lock().unwrap() = env.clone();
        }
        Ok(env.records)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct TempDir(PathBuf);
    impl TempDir {
        fn new() -> Self {
            let nanos = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default().as_nanos();
            let p = std::env::temp_dir().join(format!("pinga-tracking-{}-{}", std::process::id(), nanos));
            std::fs::create_dir_all(&p).unwrap();
            TempDir(p)
        }
        fn path(&self) -> &Path { &self.0 }
    }
    impl Drop for TempDir { fn drop(&mut self) { let _ = std::fs::remove_dir_all(&self.0); } }

    fn known(id: u64, provider: &str, session: &str, win: &str) -> TrackedRecord {
        TrackedRecord::Known { id, provider: ProviderId::new(provider).unwrap(), session: session.into(),
                               window: win.into(), state: TrackedState::Open }
    }

    #[test]
    fn migrate_maps_known_pending_and_opaque() {
        let mut next = 1;
        let records = migrate(vec![
            (0, "ses_a".into(), "@1".into()),
            (1, "".into(), "@2".into()),
            (5, "x".into(), "@9".into()),
            (0, "".into(), "@3".into()),
        ], &mut next);
        assert_eq!(next, 5);
        assert_eq!(records[0], known(1, "opencode", "ses_a", "@1"));
        match &records[1] {
            TrackedRecord::Pending { id: 2, provider, window, .. } => {
                assert_eq!(provider.as_str(), "codex");
                assert_eq!(window, "@2");
            }
            _ => panic!("empty codex id -> pending"),
        }
        assert!(matches!(records[2], TrackedRecord::Opaque { provider_index: 5, .. }));
        assert!(matches!(records[3], TrackedRecord::Pending { .. }));
    }

    #[test]
    fn migration_backs_up_exact_bytes_and_is_idempotent() {
        let tmp = TempDir::new();
        let legacy = r#"[ [0,"ses_a","@1"], [1,"","@2"] ]"#;
        std::fs::write(tmp.path().join("opened.json"), legacy).unwrap();

        let store = FileTrackingStore::new(tmp.path().to_path_buf());
        let records = store.read().unwrap();
        assert_eq!(records.len(), 2);
        assert_eq!(std::fs::read_to_string(tmp.path().join("opened-v1-migration-backup.json")).unwrap(), legacy);

        // Idempotent restart: opening a second store does not reimport or overwrite.
        let store2 = FileTrackingStore::new(tmp.path().to_path_buf());
        let records2 = store2.read().unwrap();
        assert_eq!(records, records2);
        assert_eq!(std::fs::read_to_string(tmp.path().join("opened-v1-migration-backup.json")).unwrap(), legacy);
        assert_eq!(std::fs::read_to_string(tmp.path().join("opened.json")).unwrap(), legacy,
            "legacy never rewritten once v2 exists");
    }

    #[test]
    fn missing_legacy_is_empty_initial_v2() {
        let tmp = TempDir::new();
        let store = FileTrackingStore::new(tmp.path().to_path_buf());
        assert!(store.read().unwrap().is_empty());
    }

    #[test]
    fn malformed_legacy_aborts_without_replacing_data() {
        let tmp = TempDir::new();
        let legacy = "not-json";
        std::fs::write(tmp.path().join("opened.json"), legacy).unwrap();
        let store = FileTrackingStore::new(tmp.path().to_path_buf());
        assert!(store.read().is_err(), "malformed legacy aborts");
        assert!(!tmp.path().join("tracking-v2.json").exists(), "no v2 written");
        assert!(!tmp.path().join("opened-v1-migration-backup.json").exists(), "no backup on abort");
        assert_eq!(std::fs::read_to_string(tmp.path().join("opened.json")).unwrap(), legacy,
            "legacy untouched");
    }

    #[test]
    fn unsupported_version_fails_without_rewriting() {
        let tmp = TempDir::new();
        let bad = r#"{"version":99,"next_id":1,"records":[]}"#;
        std::fs::write(tmp.path().join("tracking-v2.json"), bad).unwrap();
        let store = FileTrackingStore::new(tmp.path().to_path_buf());
        assert!(store.read().is_err());
        assert!(store.update(&mut |_| true).is_err(), "unsupported version blocks writes");
        assert_eq!(std::fs::read_to_string(tmp.path().join("tracking-v2.json")).unwrap(), bad,
            "unsupported version not rewritten");
    }

    #[test]
    fn update_allocates_monotonic_ids_and_persists() {
        let tmp = TempDir::new();
        let store = FileTrackingStore::new(tmp.path().to_path_buf());
        store.update(&mut |recs| {
            recs.push(TrackedRecord::Pending { id: 0, provider: ProviderId::new("opencode").unwrap(),
                                               window: "@1".into(), label: "n".into() });
            true
        }).unwrap();
        let recs = store.read().unwrap();
        assert_eq!(recs[0].record_id(), 1);
        // A second writer sees the persisted state (cooperative).
        let store2 = FileTrackingStore::new(tmp.path().to_path_buf());
        let recs2 = store2.read().unwrap();
        assert_eq!(recs2.len(), 1);
        assert_eq!(recs2[0].record_id(), 1);
    }

    #[test]
    fn two_stores_interleave_concurrent_updates_without_overwrite() {
        let tmp = TempDir::new();
        let a = std::sync::Arc::new(FileTrackingStore::new(tmp.path().to_path_buf()));
        let b = std::sync::Arc::new(FileTrackingStore::new(tmp.path().to_path_buf()));
        let ha = {
            let s = std::sync::Arc::clone(&a);
            std::thread::spawn(move || {
                for i in 0..10 {
                    s.update(&mut |r| { r.push(TrackedRecord::Pending {
                        id: 0, provider: ProviderId::new("opencode").unwrap(),
                        window: format!("@a{i}"), label: "a".into() }); true }).unwrap();
                }
            })
        };
        let hb = {
            let s = std::sync::Arc::clone(&b);
            std::thread::spawn(move || {
                for i in 0..10 {
                    s.update(&mut |r| { r.push(TrackedRecord::Pending {
                        id: 0, provider: ProviderId::new("codex").unwrap(),
                        window: format!("@b{i}"), label: "b".into() }); true }).unwrap();
                }
            })
        };
        ha.join().unwrap(); hb.join().unwrap();
        let final_recs = a.read().unwrap();
        assert_eq!(final_recs.len(), 20, "no overwrite under the shared lock");
        let ids: Vec<u64> = final_recs.iter().map(|r| r.record_id()).collect();
        let mut sorted = ids.clone(); sorted.sort_unstable(); sorted.dedup();
        assert_eq!(sorted.len(), 20, "record ids are unique");
    }

    #[test]
    fn stale_update_preserves_records_added_since_inspection() {
        let tmp = TempDir::new();
        let a = FileTrackingStore::new(tmp.path().to_path_buf());
        a.update(&mut |r| { r.push(known(0, "opencode", "ses_1", "@1")); true }).unwrap();
        let before = a.read().unwrap();
        // Another instance adds a record after `a` inspected.
        let b = FileTrackingStore::new(tmp.path().to_path_buf());
        b.update(&mut |r| { r.push(TrackedRecord::Pending { id: 0,
            provider: ProviderId::new("codex").unwrap(), window: "@2".into(), label: "n".into() }); true }).unwrap();
        // `a` applies a conditional change by record id; the concurrent record
        // must survive the stale result.
        a.update(&mut |r| {
            for rec in r.iter_mut() {
                if rec.record_id() == before[0].record_id() {
                    *rec = TrackedRecord::Known { id: before[0].record_id(),
                        provider: ProviderId::new("opencode").unwrap(), session: "ses_1".into(),
                        window: "@1".into(), state: TrackedState::Interrupted };
                }
            }
            true
        }).unwrap();
        let after = a.read().unwrap();
        assert_eq!(after.len(), 2, "records added since inspection survive stale results");
        assert_eq!(after[0].record_id(), 1);
    }

    #[test]
    fn read_failure_is_surfaced_not_hidden_behind_cache() {
        let tmp = TempDir::new();
        let store = FileTrackingStore::new(tmp.path().to_path_buf());
        store.update(&mut |r| { r.push(known(0, "opencode", "ses_1", "@1")); true }).unwrap();
        assert_eq!(store.read().unwrap().len(), 1);
        // Corrupt the file: read now ERRORS (surfaced), never silently empty.
        std::fs::write(tmp.path().join("tracking-v2.json"), "garbage").unwrap();
        assert!(store.read().is_err(), "read failure must be surfaced");
        assert!(store.update(&mut |_| true).is_err(), "write blocked on corrupt read");
        assert_eq!(std::fs::read_to_string(tmp.path().join("tracking-v2.json")).unwrap(), "garbage",
            "invalid envelope not rewritten");
    }

    #[test]
    fn mem_store_is_isolated() {
        let a = MemStore::new(vec![]);
        a.update(&mut |r| { r.push(known(0, "opencode", "ses_1", "@1")); true }).unwrap();
        let b = MemStore::new(vec![]);
        assert!(b.read().unwrap().is_empty(), "isolated instances");
        assert_eq!(a.snapshot().len(), 1);
    }

    #[test]
    fn mem_store_allocates_ids_and_validates_like_the_real_store() {
        let a = MemStore::new(vec![]);
        a.update(&mut |r| { r.push(known(0, "opencode", "s1", "@1")); true }).unwrap();
        assert_eq!(a.read().unwrap()[0].record_id(), 1);
        // A record with a duplicate/zero id is rejected by the shared validator.
        let bad = MemStore::new(vec![known(0, "opencode", "s1", "@1"), known(0, "opencode", "s2", "@2")]);
        assert!(bad.read().is_err(), "duplicate id 0 rejected on decode");
    }

    #[test]
    fn conflicting_backup_aborts_without_committing_v2() {
        let tmp = TempDir::new();
        let legacy = r#"[ [0,"ses_a","@1"] ]"#;
        std::fs::write(tmp.path().join("opened.json"), legacy).unwrap();
        // A conflicting backup already exists: migration must abort, never
        // overwrite it, and never write v2.
        std::fs::write(tmp.path().join("opened-v1-migration-backup.json"), "conflicting").unwrap();
        let store = FileTrackingStore::new(tmp.path().to_path_buf());
        assert!(store.read().is_err(), "conflicting backup aborts");
        assert!(!tmp.path().join("tracking-v2.json").exists(), "no v2 on conflict");
        assert_eq!(std::fs::read_to_string(tmp.path().join("opened-v1-migration-backup.json")).unwrap(), "conflicting",
            "conflicting backup never overwritten");
        assert_eq!(std::fs::read_to_string(tmp.path().join("opened.json")).unwrap(), legacy, "legacy untouched");
    }

    #[test]
    fn identical_backup_permits_safe_retry() {
        let tmp = TempDir::new();
        let legacy = r#"[ [0,"ses_a","@1"] ]"#;
        std::fs::write(tmp.path().join("opened.json"), legacy).unwrap();
        // An identical backup from a prior (crashed) attempt is a safe retry.
        std::fs::write(tmp.path().join("opened-v1-migration-backup.json"), legacy).unwrap();
        let store = FileTrackingStore::new(tmp.path().to_path_buf());
        let recs = store.read().unwrap();
        assert_eq!(recs.len(), 1);
        assert!(tmp.path().join("tracking-v2.json").exists());
    }

    #[test]
    fn backup_write_failure_aborts_without_v2() {
        let tmp = TempDir::new();
        let legacy = r#"[ [0,"ses_a","@1"] ]"#;
        std::fs::write(tmp.path().join("opened.json"), legacy).unwrap();
        // Make the backup path an unwritable directory so publication fails.
        std::fs::create_dir_all(tmp.path().join("opened-v1-migration-backup.json")).unwrap();
        let store = FileTrackingStore::new(tmp.path().to_path_buf());
        assert!(store.read().is_err(), "backup write failure aborts migration");
        assert!(!tmp.path().join("tracking-v2.json").exists(), "no v2 after backup failure");
        assert_eq!(std::fs::read_to_string(tmp.path().join("opened.json")).unwrap(), legacy);
    }

    #[test]
    fn invalid_envelope_invariants_are_rejected() {
        let cases: Vec<&str> = vec![
            // duplicate record id
            r#"{"version":2,"next_id":3,"records":[
                {"kind":"known","id":1,"provider":"opencode","session":"s1","window":"@1","state":"open"},
                {"kind":"known","id":1,"provider":"codex","session":"s2","window":"@2","state":"open"}]}"#,
            // zero record id
            r#"{"version":2,"next_id":2,"records":[{"kind":"known","id":0,"provider":"opencode","session":"s1","window":"@1","state":"open"}]}"#,
            // empty known native id
            r#"{"version":2,"next_id":2,"records":[{"kind":"known","id":1,"provider":"opencode","session":"","window":"@1","state":"open"}]}"#,
            // invalid provider id
            r#"{"version":2,"next_id":2,"records":[{"kind":"known","id":1,"provider":"BAD ID","session":"s1","window":"@1","state":"open"}]}"#,
            // next_id collides with a committed id
            r#"{"version":2,"next_id":1,"records":[{"kind":"known","id":1,"provider":"opencode","session":"s1","window":"@1","state":"open"}]}"#,
            // pending with invalid provider id
            r#"{"version":2,"next_id":2,"records":[{"kind":"pending","id":1,"provider":"bad id","window":"@1","label":"x"}]}"#,
        ];
        for (i, bad) in cases.iter().enumerate() {
            let d = TempDir::new();
            std::fs::write(d.path().join("tracking-v2.json"), bad).unwrap();
            let store = FileTrackingStore::new(d.path().to_path_buf());
            assert!(store.read().is_err(), "invariant case {i} rejected");
            assert_eq!(std::fs::read_to_string(d.path().join("tracking-v2.json")).unwrap(), *bad,
                "invalid envelope {i} never rewritten");
        }
        // A valid envelope still loads (opaque legacy preserved untouched).
        let d = TempDir::new();
        let good = r#"{"version":2,"next_id":3,"records":[
            {"kind":"opaque","id":1,"provider_index":5,"session":"x","window":"@9"}]}"#;
        std::fs::write(d.path().join("tracking-v2.json"), good).unwrap();
        let store = FileTrackingStore::new(d.path().to_path_buf());
        assert_eq!(store.read().unwrap().len(), 1);
    }
}
```

### 11.10 TUI module & theme (`tui::mod`, `tui::theme`)

`main.rs` declares `mod tui`, and the console lives across two files, so `tui`
is a directory with a module file joining `app` and `theme`.

``` {.rust #tui-mod path="src/tui/mod.rs"}
pub mod app;
pub mod theme;
```

The palette (purple/green). Two accent families double as the column
identities: **purple = opencode**, **green = codex**. Neutrals on a deep plum
background keep text readable; the strong accents are used for borders and
highlights, not body text.

``` {.rust #tui-theme path="src/tui/theme.rs"}
use ratatui::style::{Color, Modifier, Style};

// Neutral base (deep plum)
pub const BG: Color = Color::Rgb(0x24, 0x1f, 0x35);
pub const SURFACE: Color = Color::Rgb(0x30, 0x2a, 0x47);
pub const FG: Color = Color::Rgb(0xe0, 0xd4, 0xf5);   // lavender text
pub const DIM: Color = Color::Rgb(0x9d, 0x93, 0xb8);  // muted metadata

// Borders / accents
pub const BORDER: Color = Color::Rgb(0x4e, 0x44, 0x70); // idle border
pub const FOCUS: Color = Color::Rgb(0xa0, 0x6c, 0xd5);  // focused border (opencode purple)
pub const SELECTED_BG: Color = Color::Rgb(0x57, 0x4a, 0x78);
pub const MINT: Color = Color::Rgb(0x66, 0xd9, 0x9b);   // codex green accent
pub const GREEN_DIM: Color = Color::Rgb(0x3f, 0x8f, 0x63);
pub const WARN: Color = Color::Rgb(0xe8, 0xb4, 0x6b);   // amber for warnings only

pub fn focus_style() -> Style  { Style::default().fg(FOCUS).add_modifier(Modifier::BOLD) }
pub fn idle_style() -> Style   { Style::default().fg(BORDER) }
pub fn text_style() -> Style   { Style::default().fg(FG) }
pub fn dim_style() -> Style    { Style::default().fg(DIM) }
pub fn surface_style() -> Style { Style::default().bg(SURFACE) }
pub fn selected_style() -> Style { Style::default().bg(SELECTED_BG).fg(FG).add_modifier(Modifier::BOLD) }
pub fn codex_accent() -> Style { Style::default().fg(MINT) }
pub fn warn_style() -> Style    { Style::default().fg(WARN).add_modifier(Modifier::BOLD) }
```

### 11.11 The console (`tui::app`)

The heart. Two scrolling columns, arrow keys, full mouse support, inline rename
with a prefilled suggestion, and the handoff loop that honors R9 (tmux window)
or R10 (take the terminal, come back).

``` {.rust #tui-app path="src/tui/app.rs"}
use std::io::Stdout;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use anyhow::anyhow;
use crossterm::event::{self, Event, KeyCode, KeyEventKind, MouseButton, MouseEventKind};
use ratatui::backend::CrosstermBackend;
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::Style;
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, List, ListItem, Paragraph};
use ratatui::{Frame, Terminal};

use crate::browse;
use crate::config::Config;
use crate::launcher::{self, Launcher, OpenAction};
use crate::model::{now_ms, CreateOutcome, LaunchRequest, MatchConfidence, ProviderId, Session, SessionKey};
use crate::naming::NameEngine;
use crate::provider::{self, Provider};
use crate::tracking::{self, TrackedRecord, TrackedState, TrackingStore};

use super::theme;

const HELP: &str = "↑↓ select · ←→/Tab column · click select · dbl-click/Enter open · Enter on '+' new · r rename · s suggest · i info · g refresh · p retry pending · d detail · m mouse · o auto · b browse · f force · q quit";
pub const QUIT_MSG: &str = "quit";

/// D8: two clicks on the same cell within this window count as one open.
const DOUBLE_MS: Duration = Duration::from_millis(500);
/// After a tmux window switch, swallow mouse downs for this long so a stray
/// press can't be read as a new selection once pinga gets focus back.
const SWITCH_COOLDOWN: Duration = Duration::from_millis(250);
/// Show at most two equal columns when the body is at least this wide.
const TWO_COL_MIN_WIDTH: u16 = 80;

/// A mouse-initiated open deferred until the button is released. Each variant
/// carries its OWN provider identity and launch data, so executing it never
/// depends on whichever column is focused later.
enum Plan {
    Select { provider: ProviderId, win: String },
    Adopt { provider: ProviderId, win: String, key: SessionKey },
    SpawnKnown { provider: ProviderId, label: String, launch: LaunchRequest, key: SessionKey },
    SpawnPending { provider: ProviderId, label: String, launch: LaunchRequest },
}

/// Outcome of trying to open a session, so the creation context can distinguish
/// a real open from a control return that merely left the session unopened.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum OpenResult {
    Opened,
    Refused,
    Failed,
}

/// A window that WAS launched but could not yet be recorded (tracking write
/// failed). Retained in memory so a retry records the existing window instead of
/// spawning another; removed only after successful recording or confirmed death.
#[derive(Clone)]
struct UnrecordedLaunch {
    token: u64,
    provider: ProviderId,
    known: Option<SessionKey>,
    label: String,
    cwd: Option<String>,
    window: String,
}

/// One row of a column's visual list, in display order: the fixed "+ new
/// session" row, then any interrupted (orphaned) sessions, then the rest.
#[derive(Debug, Clone, Copy)]
enum VRow { New, Int(usize), Sess(usize), Header(&'static str) }

/// The shared column layout: the visible window of visual rows plus where the
/// selection sits in it (visual index and selectable index relative to start).
#[derive(Debug, Clone, Copy)]
struct ListLayout {
    start: usize,        // visual index of the first visible row
    end: usize,          // one past the last visible visual row
    sel_visual: usize,   // visual index of the selected row
    sel_relative: usize, // selectable index of the selection relative to start
}

/// One past the last visual row whose cumulative line heights fit `height`
/// starting at `start`. Always includes at least the row at `start`.
fn window_end(rows: &[VRow], heights: &[u16], start: usize, height: usize) -> usize {
    let mut lines = 0usize;
    let mut i = start;
    while i < rows.len() {
        let h = usize::from(heights[i]);
        if lines + h > height && lines > 0 { break; }
        lines += h;
        i += 1;
    }
    i
}

/// The bottom-line editor modes.
enum EditState {
    Rename(TextEdit),
    NewSession { name: TextEdit, cwd: TextEdit, field: u8 },
    Browse(TextEdit),
}

/// Per-provider view state (Stage 3). Positions only address visible lists;
/// identity and tracking use the stable ProviderId/SessionKey.
#[derive(Clone)]
struct ProviderView {
    id: ProviderId,
    type_key: &'static str,
    label: String,
    snapshot: Vec<Session>,
    ok: bool,
    error: Option<String>,
    sel: usize,
    scroll: usize,
    interrupted: Vec<String>,
    running: Vec<String>,
}

pub struct App {
    cfg: Config,
    launcher: Launcher,
    store: Box<dyn TrackingStore>,
    terminal: Box<dyn launcher::Terminal>,
    providers: provider::ProviderRegistry,
    views: Vec<ProviderView>,
    focus: usize,          // index into `views`
    viewport_start: usize, // first visible view index
    naming: NameEngine,
    edited: Option<EditState>,
    mouse_on: bool,
    last_poll: Instant,
    error: Option<String>,
    records: Vec<TrackedRecord>,
    detail: bool,
    last_click: Option<(Instant, usize, usize)>,
    force_open: bool,
    pending: Option<Plan>,
    mouse_ignore_until: Option<Instant>,
    needs_clear: bool,
    last_width: u16,
    last_height: u16,
    locally_created: Vec<Session>,
    startup_eligible: Vec<u64>,  // stable record ids unresolved at startup
    startup_eligible_initialized: bool,
    unrecorded_launches: Vec<UnrecordedLaunch>,
    next_launch_token: u64,
    info: Option<Session>,
    state_dir: PathBuf,
    tools_check: Box<dyn Fn() -> anyhow::Result<()>>,
}

#[derive(Debug, Clone, Copy)]
struct Rects { left: Rect, right: Option<Rect> }

/// Tiny line editor for the rename input: char buffer + cursor index.
struct TextEdit {
    chars: Vec<char>,
    cursor: usize,
}

impl TextEdit {
    fn new(initial: &str) -> Self {
        let chars: Vec<char> = initial.chars().collect();
        let cursor = chars.len();
        Self { chars, cursor }
    }
    fn insert(&mut self, c: char) {
        self.chars.insert(self.cursor, c);
        self.cursor += 1;
    }
    fn backspace(&mut self) {
        if self.cursor > 0 {
            self.cursor -= 1;
            self.chars.remove(self.cursor);
        }
    }
    fn delete(&mut self) {
        if self.cursor < self.chars.len() {
            self.chars.remove(self.cursor);
        }
    }
    fn cursor_left(&mut self) { self.cursor = self.cursor.saturating_sub(1); }
    fn cursor_right(&mut self) { self.cursor = (self.cursor + 1).min(self.chars.len()); }
    fn home(&mut self) { self.cursor = 0; }
    fn end(&mut self) { self.cursor = self.chars.len(); }
    fn cursor(&self) -> usize { self.cursor }
    fn text(&self) -> String { self.chars.iter().collect() }
}

impl App {
    /// Production construction: build providers from config, real launcher,
    /// versioned tracking store in the state dir, real terminal. Migration and
    /// any read/migration errors surface here (never silently empty).
    pub fn new(cfg: Config) -> anyhow::Result<Self> {
        let providers = provider::build_registry(&cfg)?;
        Self::from_parts(cfg, providers)
    }

    /// Build the app from config and an already-built provider registry. The
    /// registry should be built before raw/alternate-screen mode so config errors
    /// surface in a normal terminal; tracking read/migration errors also surface
    /// here rather than silently emptying the registry.
    pub fn from_parts(cfg: Config, providers: provider::ProviderRegistry) -> anyhow::Result<Self> {
        // Tracking lives in the platform state dir; the browser's own override
        // (PINGA_STATE_DIR) is scoped to browsing ONLY and must not relocate
        // provider tracking.
        let store_dir = dirs::state_dir()
            .unwrap_or_else(|| dirs::home_dir().unwrap_or_default().join(".local/state"))
            .join("pinga");
        let store: Box<dyn TrackingStore> = Box::new(tracking::FileTrackingStore::new(store_dir));
        let records = store.read()?;
        let browse_dir = browse::pinga_state_dir();
        Ok(Self::with_records(cfg, providers, Launcher::real(), store,
                              Box::new(launcher::RealTerminal), records, browse_dir))
    }

    /// Testable construction with injected registry, launcher, tracking store,
    /// and terminal seam.
    pub fn with(cfg: Config, providers: provider::ProviderRegistry, launcher: Launcher,
                store: Box<dyn TrackingStore>, terminal: Box<dyn launcher::Terminal>) -> Self {
        let records = store.read().expect("tracking read (test store)");
        Self::with_records(cfg, providers, launcher, store, terminal, records,
                           browse::pinga_state_dir())
    }

    fn with_records(cfg: Config, providers: provider::ProviderRegistry, launcher: Launcher,
                    store: Box<dyn TrackingStore>, terminal: Box<dyn launcher::Terminal>,
                    records: Vec<TrackedRecord>, state_dir: PathBuf) -> Self {
        let views: Vec<ProviderView> = providers.iter().map(|p| {
            let d = p.descriptor();
            ProviderView { id: d.id, type_key: d.type_key, label: d.display_name,
                           snapshot: Vec::new(), ok: false, error: None, sel: 0, scroll: 0,
                           interrupted: Vec::new(), running: Vec::new() }
        }).collect();
        let (base, key, model) = cfg.naming_endpoint()
            .map(|(b, k, m)| (Some(b), k, m))
            .unwrap_or((None, None, "fallback-heuristic".into()));
        let detail = cfg.list_detail.as_str() != "bottom";
        let mouse_on = default_mouse(&launcher);
        // Startup eligibility is seeded from construction-time initial records so
        // later additions never inherit it.
        let startup_eligible: Vec<u64> = records.iter().filter_map(|r| match r {
            TrackedRecord::Known { id, .. } => Some(*id),
            _ => None,
        }).collect();
        Self {
            cfg, launcher, store, terminal, providers, views,
            focus: 0, viewport_start: 0,
            naming: NameEngine::new(base, key, model),
            edited: None, mouse_on, last_poll: Instant::now(), error: None,
            records, detail, last_click: None, force_open: false, pending: None,
            mouse_ignore_until: None, needs_clear: false, last_width: 120, last_height: 30,
            locally_created: Vec::new(), startup_eligible,
            startup_eligible_initialized: true, unrecorded_launches: Vec::new(),
            next_launch_token: 1, info: None,
            state_dir, tools_check: Box::new(browse::check_tools_env),
        }
    }

    fn view(&self, i: usize) -> &ProviderView { &self.views[i] }
    fn view_mut(&mut self, i: usize) -> &mut ProviderView { &mut self.views[i] }
    fn view_index(&self, id: &ProviderId) -> Option<usize> {
        self.views.iter().position(|v| v.id == *id)
    }
    fn provider(&self, id: &ProviderId) -> Option<&dyn Provider> { self.providers.get(id) }

    fn refresh(&mut self) {
        if let Some(plan) = self.pending.take() {
            if let Err(e) = self.execute(plan) { self.error = Some(e.to_string()); }
        }
        // Capture the tracking snapshot BEFORE listing providers so a second
        // instance's records added during/after listing are never reconciled
        // against an older list (they fall outside the observed generation and
        // are preserved by the conditional commit).
        let observed = match self.store.read() {
            Ok(r) => r,
            Err(e) => { self.error = Some(format!("tracking: {e}")); return; }
        };
        self.records = observed.clone();
        let n = self.views.len();
        for i in 0..n {
            let id = self.views[i].id.clone();
            let listed = match self.provider(&id) { Some(p) => p.list(), None => Ok(Vec::new()) };
            match listed {
                Ok(list) => {
                    // Validate identities and nonempty native IDs before accepting.
                    let bad = list.iter().filter(|s| s.provider_id != id || s.id.is_empty()).count();
                    if bad > 0 {
                        let v = self.view_mut(i);
                        v.ok = false;
                        v.error = Some(format!("{bad} malformed session(s) from {}", v.label));
                        continue;
                    }
                    let mut snap = list;
                    let mut kept = Vec::new();
                    for s in std::mem::take(&mut self.locally_created) {
                        if s.provider_id != id { kept.push(s); }
                        else if snap.iter().any(|e| e.id == s.id) { /* observed */ }
                        else { snap.push(s.clone()); kept.push(s); }
                    }
                    self.locally_created = kept;
                    // Preserve the selected SessionKey across reorder/group
                    // transitions; bounded fallback when the row disappears.
                    let selected = if self.view(i).sel == 0 { None } else {
                        self.view(i).snapshot.get(self.selected_index(i))
                            .map(|s| (s.provider_id.clone(), s.id.clone()))
                    };
                    self.view_mut(i).snapshot = snap;
                    let restored = selected.as_ref().and_then(|(pid, sid)| {
                        self.selectable_sessions(i).iter()
                            .position(|&idx| self.view(i).snapshot.get(idx)
                                .map(|s| s.provider_id == *pid && s.id == *sid).unwrap_or(false))
                            .map(|p| p + 1) // selectable 0 is the "+ new" row
                    });
                    let v = self.view_mut(i);
                    v.ok = true;
                    v.error = None;
                    v.sel = restored.unwrap_or_else(|| v.sel.min(v.snapshot.len()));
                    v.scroll = v.scroll.min(v.snapshot.len().saturating_sub(1));
                }
                Err(e) => {
                    let v = self.view_mut(i);
                    v.ok = false;
                    v.error = Some(e.to_string());
                    self.error = Some(format!("{}: {e}", v.label));
                }
            }
        }
        self.reconcile(observed);
        self.compute_running();
        self.ensure_focus_visible();
        self.last_poll = Instant::now();
    }

    /// The window ids pinga tracks (known + pending), so evidence collection
    /// also inspects tracked windows outside the current tmux session.
    fn tracked_windows(&self) -> Vec<String> {
        let mut v: Vec<String> = self.records.iter().map(|r| r.window().to_string()).collect();
        v.sort(); v.dedup();
        v
    }

    /// Reconcile persisted records against evidence, retaining interruption and
    /// resolving/dropping pendings. Unknown/incomplete evidence never closes.
    /// `observed` was captured BEFORE listing/evidence was collected, so records
    /// added concurrently by another instance are outside this generation and are
    /// preserved by the conditional commit (never deleted against an older list).
    fn reconcile(&mut self, observed: Vec<TrackedRecord>) {
        self.reconcile_unrecorded();
        self.records = observed.clone();
        let evidence = if self.launcher.in_tmux() {
            self.launcher.collect_evidence(&self.tracked_windows()).ok()
        } else { None };
        let views = self.views.clone();
        let providers = &self.providers;
        let launcher = &self.launcher;

        // Compute ALL proposed changes OUTSIDE the lock. A plan records whether
        // its record was startup-eligible and whether that eligibility must be
        // preserved on a successful application.
        struct Plan { observed: TrackedRecord, eligible: bool, preserve: bool, kind: PlanKind }
        enum PlanKind { Keep, Replace(TrackedRecord), Remove }
        let mut plans: Vec<Plan> = Vec::new();
        for r in &observed {
            match r {
                TrackedRecord::Opaque { .. } => plans.push(Plan {
                    observed: r.clone(), eligible: false, preserve: false, kind: PlanKind::Keep }),
                TrackedRecord::Pending { id, provider, window, label: _ } => {
                    let view_i = view_index_for(provider, &views);
                    let prov_ok = view_i.map(|i| views[i].ok).unwrap_or(false);
                    if view_i.is_none() || !prov_ok {
                        // Preserve untouched until that provider has a successful snapshot.
                        plans.push(Plan { observed: r.clone(), eligible: false, preserve: true, kind: PlanKind::Keep });
                        continue;
                    }
                    match launcher.window_alive(window).ok() {
                        Some(false) => plans.push(Plan { observed: r.clone(), eligible: false, preserve: false, kind: PlanKind::Remove }),
                        _ => {
                            let complete = evidence.as_ref().map(|e| e.complete).unwrap_or(false);
                            if complete {
                                let key = resolve_pending(providers, &views, provider, window, evidence.as_ref());
                                match key {
                                    Some(key) => plans.push(Plan {
                                        observed: r.clone(), eligible: false, preserve: false,
                                        kind: PlanKind::Replace(TrackedRecord::Known {
                                            id: *id, provider: provider.clone(),
                                            session: key.native_id().to_string(),
                                            window: window.clone(), state: TrackedState::Open }) }),
                                    None => plans.push(Plan { observed: r.clone(), eligible: false, preserve: true, kind: PlanKind::Keep }),
                                }
                            } else {
                                plans.push(Plan { observed: r.clone(), eligible: false, preserve: true, kind: PlanKind::Keep });
                            }
                        }
                    }
                }
                TrackedRecord::Known { id, provider, session, window, state } => {
                    let eligible = self.startup_eligible.contains(id);
                    let view_i = view_index_for(provider, &views);
                    let prov_ok = view_i.map(|i| views[i].ok).unwrap_or(false);
                    if view_i.is_none() || !prov_ok {
                        plans.push(Plan { observed: r.clone(), eligible, preserve: true, kind: PlanKind::Keep });
                        continue;
                    }
                    let in_list = views[view_i.unwrap()].snapshot.iter().any(|s| s.id == *session);
                    if !in_list {
                        // Authoritative disappearance from a successful list.
                        plans.push(Plan { observed: r.clone(), eligible, preserve: false, kind: PlanKind::Remove });
                        continue;
                    }
                    let (running_here, uncertain) = match &evidence {
                        Some(ev) => {
                            let s = views[view_i.unwrap()].snapshot.iter().find(|s| s.id == *session);
                            match s {
                                Some(s) => {
                                    let m = providers.get(provider).expect("provider")
                                        .match_session(s, &views[view_i.unwrap()].snapshot, ev);
                                    let mine: Vec<_> = m.iter().filter(|x| x.window_id == *window).collect();
                                    (mine.iter().any(|x| x.confidence == MatchConfidence::Confirmed),
                                     mine.iter().any(|x| x.confidence != MatchConfidence::Confirmed))
                                }
                                None => (false, true),
                            }
                        }
                        None => (false, true), // unknown evidence
                    };
                    match state {
                        TrackedState::Interrupted => {
                            if running_here {
                                plans.push(Plan { observed: r.clone(), eligible, preserve: false,
                                    kind: PlanKind::Replace(TrackedRecord::Known {
                                        id: *id, provider: provider.clone(), session: session.clone(),
                                        window: window.clone(), state: TrackedState::Open }) });
                            } else {
                                plans.push(Plan { observed: r.clone(), eligible, preserve: true, kind: PlanKind::Keep });
                            }
                        }
                        TrackedState::Open => {
                            match launcher.window_alive(window).ok() {
                                Some(false) => {
                                    if eligible {
                                        plans.push(Plan { observed: r.clone(), eligible, preserve: false,
                                            kind: PlanKind::Replace(TrackedRecord::Known {
                                                id: *id, provider: provider.clone(), session: session.clone(),
                                                window: window.clone(), state: TrackedState::Interrupted }) });
                                    } else {
                                        plans.push(Plan { observed: r.clone(), eligible, preserve: false, kind: PlanKind::Remove });
                                    }
                                }
                                Some(true) => {
                                    if running_here {
                                        plans.push(Plan { observed: r.clone(), eligible, preserve: false, kind: PlanKind::Keep });
                                    } else if uncertain || !evidence.as_ref().map(|e| e.complete).unwrap_or(false) {
                                        plans.push(Plan { observed: r.clone(), eligible, preserve: true, kind: PlanKind::Keep });
                                    } else {
                                        plans.push(Plan { observed: r.clone(), eligible, preserve: false, kind: PlanKind::Remove });
                                    }
                                }
                                None => {
                                    plans.push(Plan { observed: r.clone(), eligible, preserve: true, kind: PlanKind::Keep });
                                }
                            }
                        }
                    }
                }
            }
        }

        // Under the lock, apply a plan ONLY when the exact observed record id AND
        // its prior window/state/identity still match; concurrent additions and
        // same-id changes survive stale evidence. Eligibility/removal accounting
        // reflects what was actually applied (or preserved for a skipped
        // same-id record), not merely what was proposed.
        enum Applied { KeptEligible(u64), Removed }
        let mut applied: Vec<Applied> = Vec::new();
        let result = self.store.update(&mut |recs| {
            let mut changed = false;
            for plan in &plans {
                let pos = match recs.iter().position(|r| r.record_id() == plan.observed.record_id()) {
                    Some(p) => p, None => continue,
                };
                if recs[pos] != plan.observed {
                    // Concurrent change to this record: never act on stale state;
                    // preserve its startup eligibility by id.
                    if plan.eligible { applied.push(Applied::KeptEligible(plan.observed.record_id())); }
                    continue;
                }
                match &plan.kind {
                    PlanKind::Keep => {
                        if plan.preserve && plan.eligible { applied.push(Applied::KeptEligible(plan.observed.record_id())); }
                    }
                    PlanKind::Replace(new) => {
                        if *new != recs[pos] { recs[pos] = new.clone(); changed = true; }
                    }
                    PlanKind::Remove => { recs.remove(pos); changed = true; applied.push(Applied::Removed); }
                }
            }
            changed
        });
        match result {
            Ok(recs) => {
                self.records = recs;
                let mut still: Vec<u64> = Vec::new();
                let mut gone = 0usize;
                for a in applied {
                    match a {
                        Applied::KeptEligible(id) => still.push(id),
                        Applied::Removed => gone += 1,
                    }
                }
                self.startup_eligible = still;
                if gone > 0 {
                    self.error = Some(format!(
                        "{gone} tracked record(s) were removed (closed, ended, or no longer listed)"));
                }
            }
            Err(e) => {
                // Commit failed: eligibility/removal notices are NOT consumed and
                // the last good in-memory view is retained.
                self.error = Some(format!("tracking: {e}"));
            }
        }
        for v in &mut self.views {
            v.interrupted = self.records.iter().filter_map(|r| match r {
                TrackedRecord::Known { provider, session, state: TrackedState::Interrupted, .. }
                    if *provider == v.id => Some(session.clone()),
                _ => None,
            }).collect();
        }
    }

    /// Which sessions are currently running (per provider), using the same
    /// adapter evidence. Only a Confirmed match marks a session running.
    fn compute_running(&mut self) {
        for i in 0..self.views.len() {
            let v = &self.views[i];
            if !v.ok { continue; }
            let id = v.id.clone();
            let snapshot = v.snapshot.clone();
            let running = if self.launcher.in_tmux() {
                let running = if let Ok(ev) = self.launcher.collect_evidence(&self.tracked_windows()) {
                    let mut r = Vec::new();
                    if let Some(p) = self.provider(&id) {
                        for s in &snapshot {
                            if p.match_session(s, &snapshot, &ev)
                                .iter().any(|m| m.confidence == MatchConfidence::Confirmed) {
                                r.push(s.id.clone());
                            }
                        }
                    }
                    r
                } else { Vec::new() };
                running
            } else { Vec::new() };
            self.views[i].running = running;
        }
    }

    fn ensure_focus_visible(&mut self) {
        let visible = self.visible_count();
        if self.views.is_empty() { self.viewport_start = 0; return; }
        self.focus = self.focus.min(self.views.len() - 1);
        if self.focus < self.viewport_start { self.viewport_start = self.focus; }
        if self.focus >= self.viewport_start + visible {
            self.viewport_start = self.focus + 1 - visible;
        }
    }

    /// How many provider columns fit: two when the body is wide enough, else one.
    fn visible_count(&self) -> usize {
        if self.last_width >= TWO_COL_MIN_WIDTH && self.views.len() >= 2 { 2 } else { 1 }
    }

    /// The view indices currently visible.
    fn visible_indices(&self) -> Vec<usize> {
        let n = self.visible_count().min(self.views.len());
        let start = self.viewport_start.min(self.views.len().saturating_sub(n));
        (start..start + n).collect()
    }

    /// Terminal lines occupied by one visual row: headers and the "+ new" row
    /// take one line; a session item takes one line normally and two when
    /// two-line detail mode is on.
    fn row_lines(&self, row: VRow) -> u16 {
        match row {
            VRow::Header(_) | VRow::New => 1,
            VRow::Int(_) | VRow::Sess(_) => if self.detail { 2 } else { 1 },
        }
        .max(1)
    }

    /// Visual rows for a provider column.
    fn visual_rows(&self, idx: usize) -> Vec<VRow> {
        let v = self.view(idx);
        let mut ints = Vec::new(); let mut runs = Vec::new(); let mut closed = Vec::new();
        for (i, s) in v.snapshot.iter().enumerate() {
            if v.interrupted.iter().any(|id| id == &s.id) { ints.push(i); }
            else if v.running.iter().any(|id| id == &s.id) { runs.push(i); }
            else { closed.push(i); }
        }
        let mut rows = Vec::with_capacity(v.snapshot.len() + 4);
        rows.push(VRow::New);
        if !ints.is_empty() { rows.push(VRow::Header(" interrupted")); rows.extend(ints.into_iter().map(VRow::Int)); }
        if !runs.is_empty() { rows.push(VRow::Header(" running")); rows.extend(runs.into_iter().map(VRow::Sess)); }
        if !closed.is_empty() { rows.push(VRow::Header(" closed")); rows.extend(closed.into_iter().map(VRow::Sess)); }
        rows
    }

    fn list_len(&self, idx: usize) -> usize { self.view(idx).snapshot.len() + 1 }

    /// The actual inner height of a provider column, derived from the stored
    /// terminal size the same way render lays the screen out: one title line
    /// plus the column's two border lines come off the terminal height.
    fn column_inner_height(&self) -> usize {
        usize::from(self.last_height.saturating_sub(3)).max(1)
    }

    /// The one shared layout model for a column: given the visual rows, their
    /// line heights, the selected SELECTABLE index, a candidate scroll (visual
    /// row offset) and the ACTUAL inner height, return the visible window and
    /// where the selection falls within it. Drawing, highlighting, mouse
    /// hit-testing, and cursor movement all consume this, so they cannot
    /// disagree. The window always keeps the selected row visible.
    fn list_layout(&self, rows: &[VRow], heights: &[u16], sel: usize,
                   scroll: usize, height: usize) -> ListLayout {
        let mut sel_visual = 0usize;
        let mut count = 0usize;
        for (vi, r) in rows.iter().enumerate() {
            if matches!(r, VRow::Header(_)) { continue; }
            if count == sel { sel_visual = vi; break; }
            count += 1;
        }
        let total = rows.len();
        let mut start = scroll.min(total.saturating_sub(1));
        // Scroll up so the selected row is never above the window...
        if sel_visual < start { start = sel_visual; }
        // ...and advance the window until the selected row is inside it.
        loop {
            let end = window_end(rows, heights, start, height);
            if sel_visual < end || start >= total { break; }
            start += 1;
        }
        let end = window_end(rows, heights, start, height);
        let before = rows.iter().take(start).filter(|r| !matches!(r, VRow::Header(_))).count();
        ListLayout { start, end, sel_visual, sel_relative: sel.saturating_sub(before) }
    }

    fn selectable_sessions(&self, idx: usize) -> Vec<usize> {
        let v = self.view(idx);
        let mut order = Vec::new();
        for group in [&v.interrupted, &v.running] {
            for (i, s) in v.snapshot.iter().enumerate() {
                if group.iter().any(|id| id == &s.id) { order.push(i); }
            }
        }
        for (i, s) in v.snapshot.iter().enumerate() {
            if !v.interrupted.iter().any(|id| id == &s.id) && !v.running.iter().any(|id| id == &s.id) {
                order.push(i);
            }
        }
        order
    }

    /// Index into the snapshot of the currently selected session (None when
    /// the "+ new" row or nothing is selected).
    fn selected_index(&self, idx: usize) -> usize {
        let sel = self.view(idx).sel;
        if sel == 0 { return 0; }
        self.selectable_sessions(idx).get(sel - 1).copied().unwrap_or(0)
    }

    fn move_cursor(&mut self, delta: i32) {
        if self.views.is_empty() { return; }
        let idx = self.focus;
        let n = self.list_len(idx);
        if n == 0 { self.view_mut(idx).sel = 0; return; }
        let max = n - 1;
        let news = (self.view(idx).sel as i64 + delta as i64).clamp(0, max as i64) as usize;
        // Compute the selection against the SAME layout model render/hit-test
        // use: column inner height (not the full terminal), visual item indices
        // (headers are not selectable), and per-row line heights. The returned
        // scroll keeps the selected visual row inside the viewport.
        let rows = self.visual_rows(idx);
        let heights: Vec<u16> = rows.iter().map(|r| self.row_lines(*r)).collect();
        let height = self.column_inner_height();
        let layout = self.list_layout(&rows, &heights, news, self.view(idx).scroll, height);
        let v = self.view_mut(idx);
        v.sel = news;
        v.scroll = layout.start;
    }

    fn on_new_row(&self) -> bool { self.view(self.focus).sel == 0 }

    pub fn run(&mut self, term: &mut Terminal<CrosstermBackend<Stdout>>) -> anyhow::Result<()> {
        self.refresh();
        if self.mouse_on {
            crossterm::execute!(std::io::stdout(), crossterm::event::EnableMouseCapture)?;
        }
        loop {
            if let Ok((w, h)) = crossterm::terminal::size() { self.last_width = w; self.last_height = h; }
            let timeout = Duration::from_millis(self.cfg.refresh_secs.saturating_mul(1000) / 4);
            match event::poll(timeout)? {
                true => match event::read()? {
                    Event::Key(k) if k.kind == KeyEventKind::Press => self.handle_key(k.code)?,
                    Event::Mouse(m) => {
                        let (w, h) = crossterm::terminal::size()?;
                        self.handle_mouse(&m, Rect::new(0, 0, w, h))?;
                    }
                    _ => {}
                },
                false => self.refresh(),
            }
            if self.needs_clear {
                term.clear()?;
                self.needs_clear = false;
            }
            term.draw(|f| self.render(f))?;
        }
    }

    fn handle_key(&mut self, code: KeyCode) -> anyhow::Result<()> {
        use KeyCode::*;
        if let Some(plan) = self.pending.take() { self.execute(plan)?; }
        self.error = None;
        if self.info.is_some() {
            if matches!(code, Esc | Char('q')) { self.info = None; }
            return Ok(());
        }
        if self.edited.is_some() { return self.handle_edit_key(code); }
        match code {
            Char('q') | Esc => return Err(anyhow!(QUIT_MSG)),
            Enter => return self.open_selected(false),
            Char('m') => return self.toggle_mouse(),
            Char('s') => return self.suggest_current(false),
            Char('f') => return self.open_selected_force(),
            Char('p') => {
                if let Some(token) = self.unrecorded_launches.iter()
                    .find(|u| u.known.is_none()).map(|u| u.token) {
                    if let Err(e) = self.retry_unrecorded(token) { self.error = Some(e.to_string()); }
                }
                return Ok(());
            }
            Char('g') => { self.refresh(); return Ok(()); }
            Char('i') => { if let Some(s) = self.focused_session().cloned() { self.info = Some(s); } return Ok(()); }
            Char('r') => return self.start_rename(),
            Char('b') => return self.start_browse(),
            _ => {}
        }
        match code {
            Up => self.move_cursor(-1),
            Down => self.move_cursor(1),
            Left | Char('h') => self.focus_next(-1),
            Right | Char('l') | Tab => self.focus_next(1),
            Char('o') => self.cfg.auto_rename = !self.cfg.auto_rename,
            Char('d') => self.detail = !self.detail,
            _ => {}
        }
        Ok(())
    }

    /// Move focus across the full enabled provider sequence, wrapping at ends,
    /// scrolling the viewport to keep focus visible.
    fn focus_next(&mut self, delta: i32) {
        if self.views.is_empty() { return; }
        let n = self.views.len() as i64;
        self.focus = ((self.focus as i64 + delta as i64).rem_euclid(n)) as usize;
        self.ensure_focus_visible();
    }

    fn toggle_mouse(&mut self) -> anyhow::Result<()> {
        self.mouse_on = !self.mouse_on;
        if self.mouse_on {
            crossterm::execute!(std::io::stdout(), crossterm::event::EnableMouseCapture)?;
        } else {
            crossterm::execute!(std::io::stdout(), crossterm::event::DisableMouseCapture)?;
        }
        Ok(())
    }

    fn handle_edit_key(&mut self, code: KeyCode) -> anyhow::Result<()> {
        use KeyCode::*;
        match &mut self.edited {
            Some(EditState::Rename(e)) => match code {
                Enter => { let title = e.text(); self.edited = None; self.apply_rename_to_focused(&title)?; Ok(()) }
                Esc => { self.edited = None; Ok(()) }
                Backspace => { e.backspace(); Ok(()) }
                Delete => { e.delete(); Ok(()) }
                Left => { e.cursor_left(); Ok(()) }
                Right => { e.cursor_right(); Ok(()) }
                Home => { e.home(); Ok(()) }
                End => { e.end(); Ok(()) }
                Char(c) => { e.insert(c); Ok(()) }
                _ => Ok(()),
            },
            Some(EditState::NewSession { name, cwd, field }) => match code {
                Esc => { self.edited = None; Ok(()) }
                Tab => { *field = 1 - *field; Ok(()) }
                Enter => {
                    if *field == 0 { *field = 1; Ok(()) }
                    else {
                        let name = name.text(); let cwd = cwd.text();
                        self.edited = None;
                        self.create_new_session(&name, &cwd)
                    }
                }
                _ => {
                    let active = if *field == 0 { name } else { cwd };
                    match code {
                        Backspace => { active.backspace(); Ok(()) }
                        Delete => { active.delete(); Ok(()) }
                        Left => { active.cursor_left(); Ok(()) }
                        Right => { active.cursor_right(); Ok(()) }
                        Home => { active.home(); Ok(()) }
                        End => { active.end(); Ok(()) }
                        Char(c) => { active.insert(c); Ok(()) }
                        _ => Ok(()),
                    }
                }
            },
            Some(EditState::Browse(e)) => match code {
                Esc => { self.edited = None; Ok(()) }
                Enter => {
                    let dir = e.text();
                    match self.commit_browse(&dir) {
                        Ok(()) => { self.edited = None; Ok(()) }
                        Err(err) => { self.error = Some(err.to_string()); Ok(()) }
                    }
                }
                Backspace => { e.backspace(); Ok(()) }
                Delete => { e.delete(); Ok(()) }
                Left => { e.cursor_left(); Ok(()) }
                Right => { e.cursor_right(); Ok(()) }
                Home => { e.home(); Ok(()) }
                End => { e.end(); Ok(()) }
                Char(c) => { e.insert(c); Ok(()) }
                _ => Ok(()),
            },
            None => Ok(()),
        }
    }

    fn focused_session(&self) -> Option<&Session> {
        if self.views.is_empty() { return None; }
        let sel = self.view(self.focus).sel;
        if sel == 0 { return None; }
        self.selectable_sessions(self.focus)
            .get(sel - 1)
            .and_then(|&i| self.view(self.focus).snapshot.get(i))
    }

    fn sel_from_visual(&self, idx: usize, screen_row: usize) -> Option<usize> {
        // The screen shows only a scrolled window of the list; map a screen row
        // to a visual row via cumulative item heights from the shared layout's
        // window start, so headers and two-line items land on the same rows the
        // renderer draws and cursor movement keeps in range.
        let v = self.view(idx);
        let rows = self.visual_rows(idx);
        let heights: Vec<u16> = rows.iter().map(|r| self.row_lines(*r)).collect();
        let height = self.column_inner_height();
        let layout = self.list_layout(&rows, &heights, v.sel, v.scroll, height);
        let mut lines = 0usize;
        let mut i = layout.start;
        while i < layout.end {
            let h = usize::from(heights[i]);
            if screen_row < lines + h { break; }
            lines += h;
            i += 1;
        }
        let vrow = i;
        if vrow >= layout.end || matches!(rows[vrow], VRow::Header(_)) { return None; }
        let mut sel = 0usize;
        for (j, row) in rows.iter().enumerate() {
            if j == vrow { return Some(sel); }
            if !matches!(row, VRow::Header(_)) { sel += 1; }
        }
        None
    }

    fn open_selected(&mut self, from_mouse: bool) -> anyhow::Result<()> {
        if self.views.is_empty() { return Ok(()); }
        if self.on_new_row() {
            if !self.provider(&self.view(self.focus).id).map(|p| p.capabilities().new_session.supported).unwrap_or(false) {
                self.error = Some("new session is not supported by this provider".into());
                return Ok(());
            }
            let cwd = std::env::current_dir().ok()
                .and_then(|p| p.into_os_string().into_string().ok())
                .unwrap_or_default();
            self.edited = Some(EditState::NewSession { name: TextEdit::new(""), cwd: TextEdit::new(&cwd), field: 0 });
            return Ok(());
        }
        let Some(s) = self.focused_session().cloned() else { return Ok(()) };
        self.open_session(&s, from_mouse)?;
        Ok(())
    }

    fn open_selected_force(&mut self) -> anyhow::Result<()> {
        self.force_open = true;
        self.open_selected(false)
    }

    /// Open the Browse project directory form. Prefill with the focused
    /// session's local absolute directory when valid, otherwise Pinga's current
    /// directory. Directory selection only — never Git-root inference and never
    /// a provider call.
    fn start_browse(&mut self) -> anyhow::Result<()> {
        // Prefill only with an ABSOLUTE path that still EXISTS as a directory;
        // a missing/deleted/file-valued session directory falls back to cwd.
        let valid_dir = |d: &str| -> bool {
            Path::new(d).is_absolute()
                && std::fs::metadata(d).map(|m| m.is_dir()).unwrap_or(false)
        };
        let prefill = self.focused_session()
            .and_then(|s| s.directory.as_deref())
            .filter(|d| valid_dir(d))
            .map(str::to_owned)
            .or_else(|| std::env::current_dir().ok()
                .and_then(|p| p.into_os_string().into_string().ok()))
            .unwrap_or_default();
        self.edited = Some(EditState::Browse(TextEdit::new(&prefill)));
        Ok(())
    }

    /// Commit the browse form: validate the directory, verify the external
    /// viewers, write the isolated profile, then launch Yazi rooted there — a
    /// new tmux window in tmux, a suspend/foreground/restore run otherwise.
    /// Browser windows never enter session tracking or provider operations.
    fn commit_browse(&mut self, dir: &str) -> anyhow::Result<()> {
        let cwd = std::env::current_dir()?;
        let dir = browse::resolve_directory(dir, &cwd)?;
        (self.tools_check)()?;
        let profile = browse::ensure_profile(&self.state_dir)?;
        let launch = browse::browse_launch(&dir, &profile)?;
        if self.launcher.in_tmux() {
            self.launcher.open_in_tmux("browse", &launch)?;
        } else {
            self.suspend_for(&launch)?;
        }
        self.needs_clear = true;
        Ok(())
    }

    fn open_session(&mut self, s: &Session, from_mouse: bool) -> anyhow::Result<OpenResult> {
        let id = s.provider_id.clone();
        let provider = self.provider(&id).ok_or_else(|| anyhow!("unknown provider {}", id))?;
        provider::check_session_belongs(provider, s)?;
        if !provider.capabilities().resume {
            self.error = Some("this provider does not support resuming".into());
            return Ok(OpenResult::Refused);
        }
        let plan = provider.resume_plan(s)?;
        let label = s.display_title().chars().take(24).collect::<String>();
        if self.launcher.in_tmux() {
            self.open_in_tmux_guarded(id, s, &label, plan, from_mouse)
        } else {
            if s.active && !self.force_open {
                self.error = Some(format!("{} is already open elsewhere — f to force", s.display_title()));
                return Ok(OpenResult::Refused);
            }
            let r = self.suspend_for(&plan);
            self.refresh();
            self.force_open = false;
            if let Err(e) = r { self.error = Some(format!("launch failed: {e}")); return Ok(OpenResult::Failed); }
            Ok(OpenResult::Opened)
        }
    }

    fn open_in_tmux_guarded(&mut self, provider: ProviderId, s: &Session, label: &str,
                            launch: LaunchRequest, from_mouse: bool) -> anyhow::Result<OpenResult> {
        // Use the session directly (a freshly created known session may not yet
        // appear in the provider snapshot until the next refresh merges it).
        let key = SessionKey::new(s.provider_id.clone(), s.id.clone())?;
        // Recovery: if a window for this exact key was launched but not yet
        // recorded, retry persistence of that window WITHOUT evidence/adoption
        // refusal or a new spawn (never call create again).
        if self.unrecorded_launches.iter().any(|u| u.provider == provider
            && u.known.as_ref().map(|k| k.native_id()) == Some(s.id.as_str())) {
            self.spawn_launch(provider, &s.display_title().chars().take(24).collect::<String>(),
                               &launch, Some(key))?;
            return Ok(OpenResult::Opened);
        }
        let tracked = self.records.iter()
            .find(|r| matches!(r, TrackedRecord::Known { provider: p, session, .. }
                if p == &provider && session == &s.id))
            .map(|r| (r.window().to_string(), self.launcher.window_alive(r.window()).unwrap_or(false)));
        let evidence = self.launcher.collect_evidence(&self.tracked_windows())?;
        let snap = if let Some(i) = self.view_index(&provider) {
            if self.view(i).ok { self.view(i).snapshot.clone() } else { Vec::new() }
        } else { Vec::new() };
        let complete = self.view_index(&provider).map(|i| self.view(i).ok).unwrap_or(false) && evidence.complete;
        let matches = self.provider(&provider).expect("provider").match_session(s, &snap, &evidence);
        let action = launcher::decide_open(&matches, tracked, s.active, self.force_open, complete);
        match action {
            OpenAction::Select { window_id } => {
                self.commit_or_defer(Plan::Select { provider, win: window_id }, from_mouse)?;
                Ok(OpenResult::Opened)
            }
            OpenAction::Adopt { window_id } => {
                self.commit_or_defer(Plan::Adopt { provider, win: window_id, key }, from_mouse)?;
                Ok(OpenResult::Opened)
            }
            OpenAction::Spawn => {
                self.commit_or_defer(Plan::SpawnKnown { provider, label: label.to_string(), launch, key }, from_mouse)?;
                Ok(OpenResult::Opened)
            }
            OpenAction::RefuseUncertain => {
                self.error = Some(format!("{} — uncertain whether already open elsewhere; f to force a fresh launch", s.display_title()));
                Ok(OpenResult::Refused)
            }
            OpenAction::RefuseIncomplete => {
                self.error = Some(format!("{} — cannot inspect running windows right now; f to force", s.display_title()));
                Ok(OpenResult::Refused)
            }
            OpenAction::RefuseActive => {
                self.error = Some(format!("{} is already open elsewhere — f to force", s.display_title()));
                Ok(OpenResult::Refused)
            }
        }
    }

    fn create_new_session(&mut self, name: &str, cwd: &str) -> anyhow::Result<()> {
        if self.views.is_empty() { return Ok(()); }
        let name = name.trim();
        let dir = if cwd.trim().is_empty() {
            match std::env::current_dir() {
                Ok(p) => match p.into_os_string().into_string() {
                    Ok(s) => s,
                    Err(_) => { self.error = Some("current directory is not valid UTF-8".into()); return Ok(()); }
                },
                Err(e) => { self.error = Some(format!("cannot determine current directory: {e}")); return Ok(()); }
            }
        } else { cwd.trim().to_string() };
        let label = if name.is_empty() { None } else { Some(name.chars().take(24).collect::<String>()) };
        let id = self.view(self.focus).id.clone();
        let provider = self.provider(&id).ok_or_else(|| anyhow!("unknown provider {}", id))?;
        if !provider.capabilities().new_session.supported {
            self.error = Some("new session is not supported by this provider".into());
            return Ok(());
        }
        match provider.create(name, &dir)? {
            CreateOutcome::KnownSession(s) => {
                provider::check_session_belongs(provider, &s)?;
                let key = SessionKey::new(s.provider_id.clone(), s.id.clone())
                    .map_err(|_| anyhow!("created session has an empty native id"))?;
                self.locally_created.push(s.clone());
                match self.open_session(&s, false) {
                    Ok(OpenResult::Opened) => {}
                    Ok(OpenResult::Refused) => {
                        self.error = Some(format!("session created but not opened: {}", s.display_title()));
                    }
                    Ok(OpenResult::Failed) => {
                        let msg = self.error.clone().unwrap_or_default();
                        self.error = Some(format!("session created but could not be opened: {msg}"));
                    }
                    Err(e) => self.error = Some(format!("session created but could not be opened: {e}")),
                }
                let _ = key;
                Ok(())
            }
            CreateOutcome::LaunchToCreate(launch) => {
                let label = label.unwrap_or_else(|| "new session".to_string());
                self.commit_or_defer(Plan::SpawnPending { provider: id, label, launch }, false)
            }
        }
    }

    fn commit_or_defer(&mut self, plan: Plan, from_mouse: bool) -> anyhow::Result<()> {
        self.force_open = false;
        if from_mouse { self.pending = Some(plan); return Ok(()); }
        self.execute(plan)
    }

    /// Spawn a launch request in a fresh tmux window, persisting a Known or
    /// Pending record (stable provider identity); foreground mode refreshes.
    fn spawn_launch(&mut self, provider: ProviderId, label: &str, launch: &LaunchRequest,
                    known: Option<SessionKey>) -> anyhow::Result<()> {
        if self.launcher.in_tmux() {
            // KNOWN launches: reopening the retained session is itself the retry
            // action, so a launch carrying that SessionKey reuses the EXISTING
            // window (never a second spawn, never a second create). Pending
            // launches (known == None) are matched ONLY by explicit token in
            // `retry_unrecorded`; a fresh pending launch here always spawns a
            // new window because two intentional launches may legitimately share
            // provider/label/cwd.
            if let Some(key) = &known {
                let existing = self.unrecorded_launches.iter()
                    .find(|u| u.known.as_ref().map(|k| k.native_id()) == Some(key.native_id()))
                    .map(|u| u.window.clone());
                if let Some(win) = existing {
                    // Check liveness at retry time: a confirmed-dead window must
                    // not be recorded as a successful live launch; a failed
                    // inspection must RETAIN the recovery state.
                    match self.launcher.window_alive(&win).ok() {
                        Some(false) => {
                            self.unrecorded_launches.retain(|u| u.window != win);
                            return Err(anyhow!("launched window {win} died before it could be recorded"));
                        }
                        _ => return self.record_launch(provider, label, known, &win, true,
                                                       launch.cwd.clone(), 0),
                    }
                }
            }
            let win = self.launcher.open_in_tmux(label, launch)?;
            self.record_launch(provider, label, known, &win, false, launch.cwd.clone(), 0)
        } else {
            // Foreground launch-to-create must return failure honestly.
            let r = self.suspend_for(launch);
            self.refresh();
            r
        }
    }

    /// Record a launched window (fresh or retried). On success removes any
    /// matching unrecorded entry; on failure keeps it and reports the window so a
    /// retry can record it without spawning another.
    #[allow(clippy::too_many_arguments)]
    fn record_launch(&mut self, provider: ProviderId, label: &str, known: Option<SessionKey>,
                     win: &str, retry: bool, cwd: Option<String>, token: u64) -> anyhow::Result<()> {
        let store = &self.store;
        let p0 = provider.clone();
        let k0 = known.clone();
        let w0 = win.to_string();
        self.records = match store.update(&mut |recs| {
            match &k0 {
                Some(key) => {
                    recs.retain(|r| !matches!(r, TrackedRecord::Known { provider: q, session, .. }
                        if *q == p0 && session == key.native_id()));
                    recs.push(TrackedRecord::Known { id: 0, provider: p0.clone(),
                                                     session: key.native_id().to_string(),
                                                     window: w0.clone(), state: TrackedState::Open });
                }
                None => {
                    recs.push(TrackedRecord::Pending { id: 0, provider: p0.clone(),
                                                       window: w0.clone(), label: label.to_string() });
                }
            }
            true
        }) {
            Ok(r) => r,
            Err(e) => {
                // Keep the launched-but-unrecorded window so an EXPLICIT retry
                // (by token) records it without spawning another. A token is
                // assigned only for a genuinely fresh launch; a known-key retry
                // reuses the existing entry's token (token 0 = no new entry).
                if !retry && token == 0 {
                    let token = self.next_launch_token;
                    self.next_launch_token += 1;
                    self.unrecorded_launches.push(UnrecordedLaunch {
                        token, provider, known: known.clone(), label: label.to_string(),
                        cwd, window: win.to_string() });
                }
                return Err(anyhow!("launched window {win} but tracking failed: {e}"));
            }
        };
        // Clear the recovered entry: known by SessionKey, pending by token.
        self.unrecorded_launches.retain(|u| match (&u.known, &known) {
            (Some(a), Some(b)) => !(u.provider == provider && a.native_id() == b.native_id()),
            (None, None) => u.token != token,
            _ => true,
        });
        Ok(())
    }

    /// EXPLICIT pending retry: record the EXISTING unrecorded window for this
    /// token (never a new spawn). Ordinary new launches always mean new; this is
    /// the only path that reuses a pending window. Liveness is checked first: a
    /// confirmed-dead window is dropped and fails; a failed inspection RETAINS
    /// the recovery state and fails, so the user can retry again.
    fn retry_unrecorded(&mut self, token: u64) -> anyhow::Result<()> {
        let Some(entry) = self.unrecorded_launches.iter()
            .find(|u| u.known.is_none() && u.token == token)
            .cloned()
        else {
            return Err(anyhow!("no unrecorded pending launch for token {token}"));
        };
        match self.launcher.window_alive(&entry.window).ok() {
            Some(false) => {
                self.unrecorded_launches.retain(|u| u.token != token);
                return Err(anyhow!("launched window {} died before it could be recorded", entry.window));
            }
            None => {
                // Failed inspection: keep the recovery state, do not record a
                // successful open, and let the caller retry.
                return Err(anyhow!("cannot inspect launched window {} right now", entry.window));
            }
            _ => {}
        }
        self.record_launch(entry.provider.clone(), &entry.label, entry.known.clone(),
                           &entry.window, true, entry.cwd.clone(), token)
    }

    /// Drop an unrecorded launch only on confirmed window death; failed
    /// inspection retains it.
    fn reconcile_unrecorded(&mut self) {
        let launcher = &self.launcher;
        let mut kept = Vec::new();
        for u in std::mem::take(&mut self.unrecorded_launches) {
            match launcher.window_alive(&u.window).ok() {
                Some(true) | None => kept.push(u),
                Some(false) => { /* confirmed dead -> remove */ }
            }
        }
        self.unrecorded_launches = kept;
    }

    fn execute(&mut self, plan: Plan) -> anyhow::Result<()> {
        let result = match &plan {
            Plan::Select { provider, win } => {
                let _ = provider;
                self.launcher.select_window(win)
            }
            Plan::Adopt { provider, win, key } => {
                let p = provider.clone();
                let k = key.clone();
                let w = win.clone();
                self.records = self.store.update(&mut |recs| {
                    recs.retain(|r| !matches!(r, TrackedRecord::Known { provider: q, session, .. }
                        if *q == p && session == k.native_id()));
                    recs.push(TrackedRecord::Known { id: 0, provider: p.clone(),
                                                     session: k.native_id().to_string(),
                                                     window: w.clone(), state: TrackedState::Open });
                    true
                })?;
                self.launcher.select_window(win)
            }
            Plan::SpawnKnown { provider, label, launch, key } => {
                self.spawn_launch(provider.clone(), label, launch, Some(key.clone()))
            }
            Plan::SpawnPending { provider, label, launch } => {
                self.spawn_launch(provider.clone(), label, launch, None)
            }
        };
        self.mouse_ignore_until = Some(Instant::now() + SWITCH_COOLDOWN);
        result
    }

    fn suspend_for(&mut self, req: &LaunchRequest) -> anyhow::Result<()> {
        let mut errs: Vec<String> = Vec::new();
        let prep_ok = match self.terminal.suspend() {
            Ok(()) => true,
            Err(e) => { errs.push(format!("suspend: {e}")); false }
        };
        if prep_ok {
            if let Err(e) = self.launcher.run_in_foreground(req) { errs.push(format!("launch: {e}")); }
        }
        if let Err(e) = self.terminal.restore(self.mouse_on) { errs.push(format!("restore: {e}")); }
        self.needs_clear = true;
        if errs.is_empty() { Ok(()) } else { Err(anyhow!(errs.join("; "))) }
    }

    fn suggest_current(&mut self, commit: bool) -> anyhow::Result<()> {
        if self.views.is_empty() { return Ok(()); }
        let id = self.view(self.focus).id.clone();
        if !self.provider(&id).map(|p| p.capabilities().rename).unwrap_or(false) {
            self.error = Some("this provider does not support renaming".into());
            return Ok(());
        }
        let Some(s) = self.focused_session().cloned() else { return Ok(()) };
        let seed = self.seed_for(&s);
        let name = self.naming.suggest(&seed);
        if commit {
            self.provider(&id).expect("provider").rename(&s, &name)?;
            self.refresh();
        } else {
            self.edited = Some(EditState::Rename(TextEdit::new(&name)));
        }
        Ok(())
    }

    fn start_rename(&mut self) -> anyhow::Result<()> {
        if self.views.is_empty() { return Ok(()); }
        let id = self.view(self.focus).id.clone();
        if !self.provider(&id).map(|p| p.capabilities().rename).unwrap_or(false) {
            self.error = Some("this provider does not support renaming".into());
            return Ok(());
        }
        let pre = self.focused_session().map(|s| s.display_title().to_string()).unwrap_or_default();
        self.edited = Some(EditState::Rename(TextEdit::new(&pre)));
        Ok(())
    }

    fn new_row_enabled(&self) -> bool {
        self.views.is_empty()
            || self.provider(&self.view(self.focus).id).map(|p| p.capabilities().new_session.supported).unwrap_or(false)
    }

    fn pending_status_line(&self) -> Option<String> {
        if let Some(u) = self.unrecorded_launches.iter().find(|u| u.known.is_none()) {
            return Some(format!("window {} unrecorded · p retries launch #{}", u.window, u.token));
        }
        let n = self.records.iter().filter(|r| matches!(r, TrackedRecord::Pending { .. })).count();
        if n == 0 { None } else { Some(format!("{n} pending launch(es) resolving…")) }
    }

    fn apply_rename_to_focused(&mut self, title: &str) -> anyhow::Result<()> {
        if let Some(s) = self.focused_session().cloned() {
            let id = s.provider_id.clone();
            self.provider(&id).expect("provider").rename(&s, title)?;
            self.refresh();
        }
        Ok(())
    }

    fn seed_for(&self, s: &Session) -> String {
        match (&s.title, &s.slug) {
            (Some(t), _) if !t.is_empty() => t.clone(),
            (_, Some(slug)) => slug.clone(),
            _ => s.id.clone(),
        }
    }

    fn handle_mouse(&mut self, m: &crossterm::event::MouseEvent, area: Rect) -> anyhow::Result<()> {
        let body = body_rect(area);
        let visible = self.visible_indices();
        let Rects { left, right } = layout_rects(body, visible.len());
        let (col, row) = hit_rect(m.column, m.row, left, right);
        match m.kind {
            MouseEventKind::ScrollDown => self.move_cursor(1),
            MouseEventKind::ScrollUp => self.move_cursor(-1),
            MouseEventKind::Down(MouseButton::Left) => {
                if let Some(until) = self.mouse_ignore_until {
                    if Instant::now() < until { self.mouse_ignore_until = None; self.last_click = None; return Ok(()); }
                }
                self.error = None;
                if let (Some(c), Some(r)) = (col, row) {
                    let Some(idx) = visible.get(c).copied() else { return Ok(()) };
                    if let Some(new_sel) = self.sel_from_visual(idx, r) {
                        self.focus = idx;
                        self.view_mut(idx).sel = new_sel;
                        let is_double = self.last_click
                            .filter(|(t, pc, pr)| t.elapsed() < DOUBLE_MS && *pc == idx && *pr == new_sel)
                            .is_some();
                        self.last_click = Some((Instant::now(), idx, new_sel));
                        if is_double { return self.open_selected(true); }
                    }
                }
            }
            MouseEventKind::Up(_) => {
                if let Some(plan) = self.pending.take() { return self.execute(plan); }
            }
            _ => {}
        }
        Ok(())
    }

    fn render(&self, f: &mut Frame) {
        let area = f.area();
        let vert = Layout::default().direction(Direction::Vertical)
            .constraints([Constraint::Length(1), Constraint::Min(0)]).split(area);
        let header = Line::from(vec![
            Span::styled(" pinga ", theme::focus_style()),
            Span::styled(" · ", theme::dim_style()),
            Span::styled(Self::fit(HELP, usize::from(vert[0].width).saturating_sub(
                unicode_width::UnicodeWidthStr::width(" pinga  · "))), theme::dim_style()),
        ]);
        f.render_widget(Paragraph::new(header).style(theme::surface_style()), vert[0]);

        let visible = self.visible_indices();
        if visible.is_empty() {
            // Zero enabled providers: useful empty state; quit still works.
            let rect = Rect::new(area.x, vert[1].y, vert[1].width, vert[1].height);
            let msg = " no enabled providers — add a [[providers]] entry to your config (q quits)";
            f.render_widget(Paragraph::new(Line::from(Span::styled(msg, theme::dim_style()))), rect);
        } else {
            let Rects { left, right } = layout_rects(vert[1], visible.len());
            self.render_column(f, left, visible[0]);
            if let Some(r) = right { if visible.len() > 1 { self.render_column(f, r, visible[1]); } }
        }

        if self.cfg.forms == "modal" && self.edited.is_some() {
            self.render_edit_modal(f);
        } else if let Some(edit) = &self.edited {
            let line = match edit {
                EditState::Rename(e) => self.rename_line(e, area.width),
                EditState::NewSession { name, cwd, field } => self.new_session_line(name, cwd, *field, area.width),
                EditState::Browse(e) => self.browse_line(e, area.width),
            };
            let rect = Rect::new(area.x, area.bottom().saturating_sub(1), area.width, 1);
            f.render_widget(Paragraph::new(line).style(theme::surface_style()), rect);
            if let Some(e) = &self.error {
                let err_rect = Rect::new(area.x, area.bottom().saturating_sub(2), area.width, 1);
                f.render_widget(Paragraph::new(Self::fit(&format!(" ✗ {e}"), usize::from(area.width)))
                    .style(theme::warn_style()), err_rect);
            }
        } else if let Some(e) = &self.error {
            let line = Rect::new(area.x, area.bottom().saturating_sub(1), area.width, 1);
            f.render_widget(Paragraph::new(Self::fit(e, usize::from(area.width))).style(theme::warn_style()), line);
        } else if let Some(status) = self.pending_status_line() {
            let line = Rect::new(area.x, area.bottom().saturating_sub(1), area.width, 1);
            f.render_widget(Paragraph::new(Self::fit(&status, usize::from(area.width))).style(theme::warn_style()), line);
        } else if !self.detail {
            if let Some(s) = self.focused_session() {
                let line = Rect::new(area.x, area.bottom().saturating_sub(1), area.width, 1);
                let text = format!(" {} · {}", s.display_title(), s.id);
                f.render_widget(Paragraph::new(Self::fit(&text, usize::from(area.width))).style(theme::surface_style()), line);
            }
        }
        if let Some(s) = &self.info { self.render_info_modal(f, s); }
    }

    fn modal_box(&self, f: &mut Frame, title: &str, lines: Vec<Line>) {
        let area = f.area();
        let width = area.width.saturating_sub(8).min(64);
        let height = (lines.len() as u16 + 2).min(area.height.saturating_sub(2));
        let x = area.x + area.width.saturating_sub(width) / 2;
        let y = area.y + area.height.saturating_sub(height) / 2;
        let rect = Rect::new(x, y, width, height);
        f.render_widget(ratatui::widgets::Clear, rect);
        let block = Block::default().borders(Borders::ALL)
            .title(Span::styled(title, theme::focus_style()))
            .border_style(theme::focus_style());
        f.render_widget(&block, rect);
        f.render_widget(Paragraph::new(lines).style(theme::surface_style()), block.inner(rect));
    }

    fn render_edit_modal(&self, f: &mut Frame) {
        let cursor_style = Style::default().bg(theme::FG).fg(theme::BG);
        let field_line = |e: &TextEdit, prefix: String| -> Line {
            let text = e.text();
            let cursor = e.cursor();
            let before: String = text.chars().take(cursor).collect();
            let full_after: String = text.chars().skip(cursor).collect();
            let after = Self::fit(&full_after, 40);
            Line::from(vec![
                Span::styled(prefix, theme::codex_accent()),
                Span::styled(before, theme::text_style()),
                Span::styled("▌", cursor_style),
                Span::styled(after, theme::dim_style()),
            ])
        };
        let (title, mut lines): (&str, Vec<Line>) = match &self.edited {
            Some(EditState::Rename(e)) => (" rename ", vec![
                field_line(e, " name: ".to_string()),
                Line::from(Span::styled(" [Enter apply · Esc cancel]", theme::dim_style())),
            ]),
            Some(EditState::NewSession { name, cwd, field }) => {
                let name_mark = if *field == 0 { "▸" } else { " " };
                let cwd_mark = if *field == 1 { "▸" } else { " " };
                let Some(caps) = self.provider(&self.view(self.focus).id)
                    .map(|p| p.capabilities().new_session) else { return; };
                let title_note = if caps.applies_title { "native title: applied" } else { "native title: window label only" };
                let cwd_note = if caps.applies_cwd { "cwd: applied" } else { "cwd: not honoured" };
                (" new session ", vec![
                    field_line(name, format!("{name_mark} name: ")),
                    field_line(cwd, format!("{cwd_mark} cwd: ")),
                    Line::from(Span::styled(format!(" {title_note} · {cwd_note}"), theme::dim_style())),
                    Line::from(Span::styled(" [Tab field · Enter next/create · Esc cancel]", theme::dim_style())),
                ])
            }
            Some(EditState::Browse(e)) => (" browse project directory ", vec![
                field_line(e, " dir: ".to_string()),
                Line::from(Span::styled(
                    " [Enter open · Esc cancel] — directory selection only",
                    theme::dim_style())),
            ]),
            None => return,
        };
        // Errors stay visible alongside the still-editable form.
        if let Some(e) = &self.error {
            lines.push(Line::from(Span::styled(format!(" ✗ {e}"), theme::warn_style())));
        }
        self.modal_box(f, title, lines);
    }

    fn render_info_modal(&self, f: &mut Frame, s: &Session) {
        let rows: Vec<(&str, Option<&str>)> = vec![
            ("id", Some(&s.id)),
            ("session id", s.session_id.as_deref()),
            ("thread", s.title.as_deref()),
            ("slug", s.slug.as_deref()),
            ("directory", s.directory.as_deref()),
            ("model", s.model.as_deref()),
            ("agent", s.agent.as_deref()),
        ];
        let mut lines: Vec<Line> = Vec::new();
        lines.push(Line::from(vec![
            Span::styled(s.display_title().to_string(), theme::focus_style()),
            Span::styled(format!("  {}", s.age(now_ms())), theme::dim_style()),
        ]));
        for (k, v) in rows {
            let val = v.unwrap_or("—");
            lines.push(Line::from(vec![
                Span::styled(format!(" {k}: "), theme::dim_style()),
                Span::styled(Self::fit(val, 52), theme::text_style()),
            ]));
        }
        lines.push(Line::from(Span::styled(" [Esc close]", theme::dim_style())));
        self.modal_box(f, " info ", lines);
    }

    fn rename_line(&self, e: &TextEdit, width: u16) -> Line<'_> {
        let text = e.text();
        let cursor = e.cursor();
        let before: String = text.chars().take(cursor).collect();
        let full_after: String = text.chars().skip(cursor).collect();
        let hint = "  [Enter apply · Esc cancel]";
        let cursor_style = Style::default().bg(theme::FG).fg(theme::BG);
        let budget = usize::from(width).saturating_sub(9 + unicode_width::UnicodeWidthStr::width(before.as_str()) + 1 + hint.chars().count());
        let after = Self::fit(&full_after, budget);
        Line::from(vec![
            Span::styled(" rename: ", theme::codex_accent()),
            Span::styled(before, theme::text_style()),
            Span::styled("▌", cursor_style),
            Span::styled(after, theme::dim_style()),
            Span::styled(hint, theme::dim_style()),
        ])
    }

    fn browse_line(&self, e: &TextEdit, width: u16) -> Line<'_> {
        let text = e.text();
        let cursor = e.cursor();
        let before: String = text.chars().take(cursor).collect();
        let full_after: String = text.chars().skip(cursor).collect();
        let hint = "  [Enter open · Esc cancel]";
        let cursor_style = Style::default().bg(theme::FG).fg(theme::BG);
        let prefix = unicode_width::UnicodeWidthStr::width(" browse dir:");
        let budget = usize::from(width).saturating_sub(prefix
            + unicode_width::UnicodeWidthStr::width(before.as_str()) + 1 + hint.chars().count());
        let after = Self::fit(&full_after, budget);
        Line::from(vec![
            Span::styled(" browse dir:", theme::codex_accent()),
            Span::styled(" ", theme::dim_style()),
            Span::styled(before, theme::text_style()),
            Span::styled("▌", cursor_style),
            Span::styled(after, theme::dim_style()),
            Span::styled(hint, theme::dim_style()),
        ])
    }

    fn new_session_line(&self, name: &TextEdit, cwd: &TextEdit, field: u8, width: u16) -> Line<'_> {
        let (label, e, hint) = if field == 0 {
            (" name: ", name, "  [Tab cwd · Enter next · Esc cancel]")
        } else {
            (" cwd: ", cwd, "  [Tab name · Enter create · Esc cancel]")
        };
        let text = e.text();
        let cursor = e.cursor();
        let before: String = text.chars().take(cursor).collect();
        let full_after: String = text.chars().skip(cursor).collect();
        let cursor_style = Style::default().bg(theme::FG).fg(theme::BG);
        let prefix = unicode_width::UnicodeWidthStr::width(" new session") + unicode_width::UnicodeWidthStr::width(label);
        let budget = usize::from(width).saturating_sub(prefix + unicode_width::UnicodeWidthStr::width(before.as_str()) + 1 + hint.chars().count());
        let after = Self::fit(&full_after, budget);
        Line::from(vec![
            Span::styled(" new session", theme::codex_accent()),
            Span::styled(label, theme::dim_style()),
            Span::styled(before, theme::text_style()),
            Span::styled("▌", cursor_style),
            Span::styled(after, theme::dim_style()),
            Span::styled(hint, theme::dim_style()),
        ])
    }

    fn fit(text: &str, max: usize) -> String {
        use unicode_width::UnicodeWidthChar;
        let mut s = String::new();
        let mut w = 0usize;
        for c in text.chars() {
            if w + c.width().unwrap_or(0) > max { break; }
            w += c.width().unwrap_or(0);
            s.push(c);
        }
        s
    }

    fn render_column(&self, f: &mut Frame, area: Rect, idx: usize) {
        let v = self.view(idx);
        let pos = self.views.iter().position(|x| x.id == v.id).map(|p| p + 1).unwrap_or(0);
        let title = format!(" {} ({}) {} of {}", v.label, v.snapshot.len(), pos, self.views.len());
        let border = if idx == self.focus { theme::focus_style() } else { theme::idle_style() };
        let brand = if idx % 2 == 1 { theme::codex_accent() } else { theme::focus_style() };
        let block = Block::default().title(Span::styled(title, brand)).borders(Borders::ALL).border_style(border);
        let inner = block.inner(area);
        f.render_widget(&block, area);

        let mut items: Vec<ListItem> = Vec::new();
        let mut sel_row = 0usize;
        let mut sel_item_index: Option<usize> = None;
        // Render the scrolled window of the list using the ACTUAL inner height
        // and per-item line heights (headers, two-line rows), so drawing,
        // selection highlight, and mouse hit-testing share one mapping.
        let rows = self.visual_rows(idx);
        let heights: Vec<u16> = rows.iter().map(|r| self.row_lines(*r)).collect();
        let height = usize::from(inner.height).max(1);
        let layout = self.list_layout(&rows, &heights, v.sel, v.scroll, height);
        let start = layout.start;
        let end = layout.end;
        let relative_sel = layout.sel_relative;
        for row in rows.iter().take(end).skip(start) {
            match row {
                VRow::Header(label) => items.push(ListItem::new(Line::from(Span::styled(
                    format!(" {} ", label), theme::dim_style())))),
                VRow::New => {
                    let selected = sel_row == relative_sel;
                    let enabled = self.provider(&v.id)
                        .map(|p| p.capabilities().new_session.supported).unwrap_or(false);
                    let style = if selected { theme::selected_style() }
                        else if enabled { theme::codex_accent() } else { theme::dim_style() };
                    items.push(ListItem::new(Line::from(Span::styled(" + new session", style))));
                    if selected { sel_item_index = Some(items.len() - 1); }
                    sel_row += 1;
                }
                VRow::Int(i) => {
                    let selected = sel_row == relative_sel;
                    items.push(self.session_item(&v.snapshot[*i], true, selected));
                    if selected { sel_item_index = Some(items.len() - 1); }
                    sel_row += 1;
                }
                VRow::Sess(i) => {
                    let selected = sel_row == relative_sel;
                    items.push(self.session_item(&v.snapshot[*i], false, selected));
                    if selected { sel_item_index = Some(items.len() - 1); }
                    sel_row += 1;
                }
            }
        }
        let mut state = ratatui::widgets::ListState::default();
        if let Some(si) = sel_item_index { state.select(Some(si)); }
        f.render_stateful_widget(List::new(items), inner, &mut state);
    }

    fn session_item<'a>(&self, s: &'a Session, interrupted: bool, selected: bool) -> ListItem<'a> {
        let marker = if interrupted { "⚠ " } else { "· " };
        let title_fg = if interrupted { theme::WARN } else { theme::FG };
        let mut lines = vec![Line::from(vec![
            Span::styled(format!(" {marker}"), Style::default().fg(theme::DIM)),
            Span::styled(s.display_title(), Style::default().fg(title_fg)),
            Span::styled(format!(" {}", s.age(now_ms())), Style::default().fg(theme::DIM)),
        ])];
        if self.detail {
            lines.push(Line::from(Span::styled(format!("   {}", s.id), Style::default().fg(theme::DIM))));
        }
        let mut item = ListItem::new(lines);
        if selected { item = item.style(theme::selected_style()); }
        item
    }
}

/// Resolve a pending launch only when a successful listing + adapter evidence
/// UNIQUELY proves one SessionKey in the exact pending window.
fn resolve_pending(providers: &provider::ProviderRegistry, views: &[ProviderView],
                   provider: &ProviderId, window: &str, evidence: Option<&crate::model::ProcessEvidence>)
    -> Option<SessionKey> {
    let view_i = view_index_for(provider, views)?;
    let v = &views[view_i];
    if !v.ok { return None; }
    let ev = evidence?;
    let p = providers.get(provider)?;
    let mut matches: Vec<SessionKey> = Vec::new();
    for s in &v.snapshot {
        let m = p.match_session(s, &v.snapshot, ev);
        if m.iter().any(|x| x.window_id == window && x.confidence == MatchConfidence::Confirmed) {
            matches.push(SessionKey::new(s.provider_id.clone(), s.id.clone()).ok()?);
        }
    }
    if matches.len() == 1 { matches.pop() } else { None }
}

fn view_index_for(id: &ProviderId, views: &[ProviderView]) -> Option<usize> {
    views.iter().position(|v| v.id == *id)
}

/// Default for mouse capture at startup: enable it when a mouse looks usable
/// (in tmux only if tmux forwards mouse events), otherwise on for standalone
/// terminals.
fn default_mouse(l: &Launcher) -> bool {
    if l.in_tmux() { l.mouse_on().unwrap_or(true) } else { true }
}

/// The area below the one-line header.
fn body_rect(area: Rect) -> Rect {
    let vert = Layout::default().direction(Direction::Vertical)
        .constraints([Constraint::Length(1), Constraint::Min(0)]).split(area);
    vert[1]
}

/// Split the body into up to two equal columns (n == 1 -> one full column).
fn layout_rects(body: Rect, n: usize) -> Rects {
    if n <= 1 {
        return Rects { left: body, right: None };
    }
    let cols = Layout::default().direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(50), Constraint::Percentage(50)]).split(body);
    Rects { left: cols[0], right: Some(cols[1]) }
}

/// Map terminal coords to (column index, row index inside that column's list).
fn hit_rect(x: u16, y: u16, left: Rect, right: Option<Rect>) -> (Option<usize>, Option<usize>) {
    let mut rects: Vec<(usize, Rect)> = vec![(0usize, left)];
    if let Some(r) = right { rects.push((1, r)); }
    for (idx, r) in rects {
        if x >= r.x && x < r.right() {
            if y > r.y && y < r.bottom().saturating_sub(1) {
                return (Some(idx), Some((y - r.y - 1) as usize));
            }
            return (Some(idx), None);
        }
    }
    (None, None)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::launcher::{Foreground, ProcReader, ProcTree, Tmux};
    use crate::model::{ProcessEvidence, WindowMatch};
    use crate::provider::ProviderDescriptor;
    use crate::tracking::{self, TrackedRecord, TrackedState};
    use ratatui::backend::TestBackend;
    use std::collections::HashMap;
    use std::path::{Path, PathBuf};
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    use std::sync::{Arc, Mutex};

    // ---- fake provider -----------------------------------------------------

    #[derive(Clone, Copy, PartialEq, Eq)]
    enum CreateMode { Known, LaunchToCreate, Unsupported }

    #[derive(Default)]
    struct Rec { create_calls: AtomicUsize, resume_calls: AtomicUsize, rename_calls: AtomicUsize }

    struct FakeProvider {
        id: &'static str,
        type_key: &'static str,
        label: String,
        create_mode: CreateMode,
        resume_cap: bool,
        rename_cap: bool,
        resume_err: bool,
        new_supported: bool,
        list_out: Arc<Mutex<Vec<Session>>>,
        list_err: Arc<AtomicBool>,
        match_out: Vec<WindowMatch>,
        rec: Arc<Rec>,
    }

    impl FakeProvider {
        fn new(id: &'static str) -> Self {
            Self { id, type_key: "fake", label: id.into(), create_mode: CreateMode::Unsupported,
                   resume_cap: true, rename_cap: true, resume_err: false, new_supported: true,
                   list_out: Arc::new(Mutex::new(Vec::new())), list_err: Arc::new(AtomicBool::new(false)), match_out: Vec::new(),
                   rec: Arc::new(Rec::default()) }
        }
    }

    fn fake_session(id: &str, native: &str) -> Session {
        Session { provider_id: ProviderId::new(id).unwrap(), id: native.into(), title: Some("S".into()),
                  slug: None, directory: None, session_id: None, agent: None, model: None,
                  created_ms: None, updated_ms: None, active: false }
    }

    impl Provider for FakeProvider {
        fn descriptor(&self) -> ProviderDescriptor {
            ProviderDescriptor { id: ProviderId::new(self.id).unwrap(), type_key: self.type_key,
                                 display_name: self.label.clone() }
        }
        fn capabilities(&self) -> provider::ProviderCapabilities {
            provider::ProviderCapabilities {
                rename: self.rename_cap, resume: self.resume_cap,
                new_session: provider::NewSessionCapability { supported: self.new_supported,
                                                              applies_title: false, applies_cwd: false },
            }
        }
        fn list(&self) -> anyhow::Result<Vec<Session>> {
            if self.list_err.load(Ordering::SeqCst) { return Err(anyhow!("list failed")); }
            Ok(self.list_out.lock().unwrap().clone())
        }
        fn rename(&self, _s: &Session, _t: &str) -> anyhow::Result<()> {
            self.rec.rename_calls.fetch_add(1, Ordering::SeqCst);
            if self.rename_cap { Ok(()) } else { Err(provider::unsupported("rename")) }
        }
        fn resume_plan(&self, _s: &Session) -> anyhow::Result<LaunchRequest> {
            self.rec.resume_calls.fetch_add(1, Ordering::SeqCst);
            if self.resume_err { Err(anyhow!("resume failed")) }
            else { Ok(LaunchRequest { program: self.id.into(), args: vec!["resume".into()], cwd: None, env: vec![] }) }
        }
        fn create(&self, _n: &str, _d: &str) -> anyhow::Result<CreateOutcome> {
            self.rec.create_calls.fetch_add(1, Ordering::SeqCst);
            match self.create_mode {
                CreateMode::Known => Ok(CreateOutcome::KnownSession(fake_session(self.id, &format!("s-{}", self.rec.create_calls.load(Ordering::SeqCst))))),
                CreateMode::LaunchToCreate => Ok(CreateOutcome::LaunchToCreate(LaunchRequest {
                    program: self.id.into(), args: vec![], cwd: Some("/tmp".into()), env: vec![] })),
                CreateMode::Unsupported => Err(provider::unsupported("new session")),
            }
        }
        fn match_session(&self, _s: &Session, _snap: &[Session], _ev: &ProcessEvidence) -> Vec<WindowMatch> {
            self.match_out.clone()
        }
    }

    // ---- fake launcher/terminal --------------------------------------------

    struct FakeProc { trees: HashMap<u64, ProcTree> }
    impl ProcReader for FakeProc {
        fn tree(&self, root: u64, _m: u32) -> ProcTree {
            self.trees.get(&root).cloned().unwrap_or(ProcTree { procs: vec![], complete: true })
        }
    }

    #[allow(clippy::type_complexity)]
    struct FakeTmux {
        in_tmux: bool,
        list_ids: Vec<String>,
        panes: HashMap<String, Vec<u64>>,
        alive: Arc<Mutex<HashMap<String, bool>>>,
        alive_err: Arc<AtomicBool>,
        list_ids_err: bool,
        new_win_err: bool,
        created: Arc<Mutex<Vec<(String, Vec<String>)>>>,
        selected: Arc<Mutex<Vec<String>>>,
        next_win: AtomicUsize,
    }
    impl FakeTmux {
        fn new(in_tmux: bool) -> Self {
            Self { in_tmux, list_ids: vec![], panes: HashMap::new(),
                   alive: Arc::new(Mutex::new(HashMap::new())),
                   alive_err: Arc::new(AtomicBool::new(false)),
                   list_ids_err: false, new_win_err: false,
                   created: Arc::new(Mutex::new(Vec::new())), selected: Arc::new(Mutex::new(Vec::new())),
                   next_win: AtomicUsize::new(10) }
        }
        fn set_alive(&mut self, win: &str, alive: bool) {
            self.alive.lock().unwrap().insert(win.to_string(), alive);
        }
    }
    impl Tmux for FakeTmux {
        fn in_tmux(&self) -> bool { self.in_tmux }
        fn current_session(&self) -> anyhow::Result<String> { Ok("main".into()) }
        fn new_window(&self, _s: &str, label: &str, command: &[String]) -> anyhow::Result<String> {
            if self.new_win_err { return Err(anyhow!("tmux new-window failed")); }
            self.created.lock().unwrap().push((label.into(), command.to_vec()));
            let n = self.next_win.fetch_add(1, Ordering::SeqCst);
            Ok(format!("@{n}"))
        }
        fn select_window(&self, win: &str) -> anyhow::Result<()> {
            self.selected.lock().unwrap().push(win.into()); Ok(())
        }
        fn window_alive(&self, win: &str) -> anyhow::Result<bool> {
            if self.alive_err.load(Ordering::SeqCst) { return Err(anyhow!("tmux failed")); }
            Ok(*self.alive.lock().unwrap().get(win).unwrap_or(&false))
        }
        fn mouse_on(&self) -> anyhow::Result<bool> { Ok(true) }
        fn list_window_ids(&self, _a: bool) -> anyhow::Result<Vec<String>> {
            if self.list_ids_err { return Err(anyhow!("list failed")); }
            Ok(self.list_ids.clone())
        }
        fn pane_root_pids(&self, win: &str) -> anyhow::Result<Vec<u64>> {
            Ok(self.panes.get(win).cloned().unwrap_or_default())
        }
    }

    struct FakeForeground { err: bool, runs: Arc<AtomicUsize> }
    impl FakeForeground {
        fn new(err: bool) -> Self { Self { err, runs: Arc::new(AtomicUsize::new(0)) } }
    }
    impl Foreground for FakeForeground {
        fn run(&self, _r: &LaunchRequest) -> anyhow::Result<()> {
            self.runs.fetch_add(1, Ordering::SeqCst);
            if self.err { Err(anyhow!("spawn failed")) } else { Ok(()) }
        }
    }

    #[derive(Default)]
    struct TermCalls { suspended: AtomicUsize, restored: AtomicUsize }
    struct FakeTerminal { suspend_err: bool, restore_err: bool, calls: Arc<TermCalls> }
    impl FakeTerminal {
        fn new(s: bool, r: bool) -> Self { Self { suspend_err: s, restore_err: r, calls: Arc::new(TermCalls::default()) } }
    }
    impl launcher::Terminal for FakeTerminal {
        fn suspend(&self) -> anyhow::Result<()> {
            self.calls.suspended.fetch_add(1, Ordering::SeqCst);
            if self.suspend_err { Err(anyhow!("suspend failed")) } else { Ok(()) }
        }
        fn restore(&self, _m: bool) -> anyhow::Result<()> {
            self.calls.restored.fetch_add(1, Ordering::SeqCst);
            if self.restore_err { Err(anyhow!("restore failed")) } else { Ok(()) }
        }
    }

    // ---- harness -----------------------------------------------------------

    fn make_registry(fakes: Vec<FakeProvider>) -> provider::ProviderRegistry {
        let mut reg = provider::ProviderRegistry::new();
        for f in fakes { reg.register(Box::new(f)).unwrap(); }
        reg
    }

    fn make_app(reg: provider::ProviderRegistry, tmux: FakeTmux, proc: FakeProc,
                store: Box<dyn TrackingStore>) -> App {
        App::with(Config::default(), reg, Launcher::with_seams(Box::new(proc), Box::new(tmux),
                                                               Box::new(FakeForeground::new(false))),
                  store, Box::new(FakeTerminal::new(false, false)))
    }

    /// Two-slot harness with a configurable foreground runner and terminal.
    fn make_app_with(fake: FakeProvider, tmux: FakeTmux, proc: FakeProc, initial: Vec<TrackedRecord>,
                     foreground: Box<dyn launcher::Foreground>, terminal: Box<dyn launcher::Terminal>) -> App {
        let mut reg = provider::ProviderRegistry::new();
        reg.register(Box::new(fake)).unwrap();
        reg.register(Box::new(FakeProvider::new("two"))).unwrap();
        App::with(Config::default(), reg, Launcher::with_seams(Box::new(proc), Box::new(tmux), foreground),
                  Box::new(tracking::MemStore::new(initial)), terminal)
    }

    struct TempDir(PathBuf);
    impl TempDir {
        fn new() -> Self {
            let nanos = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default().as_nanos();
            let p = std::env::temp_dir().join(format!("pinga-app-{}-{}", std::process::id(), nanos));
            std::fs::create_dir_all(&p).unwrap();
            TempDir(p)
        }
        fn path(&self) -> &Path { &self.0 }
    }
    impl Drop for TempDir { fn drop(&mut self) { let _ = std::fs::remove_dir_all(&self.0); } }

    fn known_rec(provider: &str, session: &str, win: &str, state: TrackedState) -> TrackedRecord {
        TrackedRecord::Known { id: 1, provider: ProviderId::new(provider).unwrap(), session: session.into(),
                               window: win.into(), state }
    }

    #[test]
    fn new_session_modal_uses_arbitrary_provider_capabilities() {
        let reg = make_registry(vec![FakeProvider::new("third")]);
        let mut app = make_app(reg, FakeTmux::new(false), FakeProc { trees: HashMap::new() },
                               Box::new(tracking::MemStore::new(vec![])));
        app.edited = Some(EditState::NewSession {
            name: TextEdit::new(""), cwd: TextEdit::new("/tmp"), field: 0,
        });
        let mut term = Terminal::new(TestBackend::new(120, 30)).unwrap();
        term.draw(|f| app.render(f)).unwrap();
        let rendered: String = term.backend().buffer().content.iter()
            .map(|cell| cell.symbol()).collect();
        assert!(rendered.contains("native title: window label only"));
        assert!(rendered.contains("cwd: not honoured"));
        assert!(!rendered.contains("native title: applied"));
    }

    #[test]
    fn browse_form_prefills_session_dir_and_launches_yazi_in_tmux_without_tracking() {
        let f1 = FakeProvider::new("one");
        let mut sess = fake_session("one", "s0");
        sess.directory = Some("/tmp".to_string());
        *f1.list_out.lock().unwrap() = vec![sess];
        let reg = make_registry(vec![f1]);
        let tmux = FakeTmux::new(true);
        let created = Arc::clone(&tmux.created);
        let mut app = make_app(reg, tmux, FakeProc { trees: HashMap::new() },
                               Box::new(tracking::MemStore::new(vec![])));
        let td = TempDir::new();
        app.state_dir = td.path().to_path_buf();
        app.tools_check = Box::new(|| Ok(()));
        app.refresh();
        app.view_mut(0).sel = 1; // first session (after the "+ new" row)
        app.handle_key(KeyCode::Char('b')).unwrap();
        let Some(EditState::Browse(e)) = &app.edited else {
            panic!("b must open the browse form")
        };
        assert_eq!(e.text(), "/tmp", "prefill uses the selected session directory");
        app.handle_key(KeyCode::Enter).unwrap();
        assert!(app.edited.is_none(), "successful commit closes the form");
        let created = created.lock().unwrap().clone();
        let (label, argv) = created.last().unwrap().clone();
        assert_eq!(label, "browse");
        assert_eq!(argv[0], "sh");
        assert!(argv[2].contains("exec 'yazi' '/tmp'"), "yazi rooted at the dir: {argv:?}");
        assert!(argv[2].contains("YAZI_CONFIG_HOME="), "private profile is set: {argv:?}");
        assert!(app.records.is_empty(), "browser windows never enter session tracking");
        assert_eq!(app.views[0].snapshot.len(), 1, "no provider side effects");
    }

    #[test]
    fn browse_foreground_suspends_runs_and_restores() {
        let fg = FakeForeground::new(false);
        let runs = Arc::clone(&fg.runs);
        let term = FakeTerminal::new(false, false);
        let calls = Arc::clone(&term.calls);
        let mut app = make_app_with(FakeProvider::new("one"), FakeTmux::new(false),
                                    FakeProc { trees: HashMap::new() }, vec![],
                                    Box::new(fg), Box::new(term));
        let td = TempDir::new();
        app.state_dir = td.path().to_path_buf();
        app.tools_check = Box::new(|| Ok(()));
        app.handle_key(KeyCode::Char('b')).unwrap();
        if let Some(EditState::Browse(e)) = &mut app.edited {
            *e = TextEdit::new("/tmp");
        }
        app.handle_key(KeyCode::Enter).unwrap();
        assert_eq!(runs.load(Ordering::SeqCst), 1, "yazi ran in the foreground");
        assert_eq!(calls.suspended.load(Ordering::SeqCst), 1);
        assert_eq!(calls.restored.load(Ordering::SeqCst), 1);
        assert!(app.records.is_empty());
    }

    #[test]
    fn browse_form_esc_cancels_without_launch() {
        let mut app = make_app(make_registry(vec![FakeProvider::new("one")]),
                               FakeTmux::new(true), FakeProc { trees: HashMap::new() },
                               Box::new(tracking::MemStore::new(vec![])));
        app.state_dir = TempDir::new().path().to_path_buf();
        app.handle_key(KeyCode::Char('b')).unwrap();
        assert!(matches!(app.edited, Some(EditState::Browse(_))));
        app.handle_key(KeyCode::Esc).unwrap();
        assert!(app.edited.is_none());
        assert!(app.records.is_empty());
    }

    #[test]
    fn browse_form_reports_invalid_directory_and_keeps_edits() {
        let mut app = make_app(make_registry(vec![FakeProvider::new("one")]),
                               FakeTmux::new(true), FakeProc { trees: HashMap::new() },
                               Box::new(tracking::MemStore::new(vec![])));
        app.tools_check = Box::new(|| Ok(()));
        app.handle_key(KeyCode::Char('b')).unwrap();
        if let Some(EditState::Browse(e)) = &mut app.edited {
            *e = TextEdit::new("/nonexistent-pb01-xyz");
        }
        app.handle_key(KeyCode::Enter).unwrap();
        assert!(app.edited.is_some(), "invalid input must keep the form open");
        assert!(app.error.as_deref().unwrap_or("").contains("cannot resolve"));
        assert!(app.records.is_empty());
    }

    #[test]
    fn browse_missing_tools_fail_actionably_without_launch() {
        let tmux = FakeTmux::new(true);
        let created = Arc::clone(&tmux.created);
        let fg = FakeForeground::new(false);
        let runs = Arc::clone(&fg.runs);
        let mut app = make_app_with(FakeProvider::new("one"), tmux,
                                    FakeProc { trees: HashMap::new() }, vec![],
                                    Box::new(fg), Box::new(FakeTerminal::new(false, false)));
        let td = TempDir::new();
        app.state_dir = td.path().to_path_buf();
        app.tools_check = Box::new(|| Err(anyhow!("missing browser viewers on PATH: yazi, glow, bat")));
        app.handle_key(KeyCode::Char('b')).unwrap();
        if let Some(EditState::Browse(e)) = &mut app.edited {
            *e = TextEdit::new("/tmp");
        }
        app.handle_key(KeyCode::Enter).unwrap();
        assert!(app.edited.is_some(), "missing tools keep the form open");
        assert!(app.error.as_deref().unwrap_or("").contains("missing browser viewers"));
        assert!(created.lock().unwrap().is_empty(), "no tmux window was created");
        assert_eq!(runs.load(Ordering::SeqCst), 0, "no foreground launch happened");
        assert!(app.records.is_empty());
    }

    #[test]
    fn browse_errors_render_alongside_the_still_editable_form() {
        for forms in ["modal", "inline"] {
            let mut app = make_app(make_registry(vec![FakeProvider::new("one")]),
                                   FakeTmux::new(true), FakeProc { trees: HashMap::new() },
                                   Box::new(tracking::MemStore::new(vec![])));
            app.cfg.forms = forms.to_string();
            app.state_dir = TempDir::new().path().to_path_buf();
            app.tools_check = Box::new(|| Ok(()));
            app.handle_key(KeyCode::Char('b')).unwrap();
            if let Some(EditState::Browse(e)) = &mut app.edited {
                *e = TextEdit::new("/nonexistent-pb01-xyz");
            }
            app.handle_key(KeyCode::Enter).unwrap();
            assert!(app.edited.is_some(), "form stays open after failure in {forms}");
            let mut term = Terminal::new(TestBackend::new(120, 30)).unwrap();
            term.draw(|f| app.render(f)).unwrap();
            let rendered: String = term.backend().buffer().content.iter()
                .map(|cell| cell.symbol()).collect();
            assert!(rendered.contains("✗"), "error marker visible in {forms}: {rendered}");
            assert!(rendered.contains("cannot resolve"),
                "error text rendered in {forms}: {rendered}");
            assert!(rendered.contains("/nonexistent-pb01-xyz"),
                "edits stay visible in {forms}: {rendered}");
        }
    }

    #[test]
    fn browse_tmux_new_window_failure_surfaces_error_and_keeps_form() {
        let mut tmux = FakeTmux::new(true);
        tmux.new_win_err = true;
        let created = Arc::clone(&tmux.created);
        let mut app = make_app(make_registry(vec![FakeProvider::new("one")]), tmux,
                               FakeProc { trees: HashMap::new() },
                               Box::new(tracking::MemStore::new(vec![])));
        app.state_dir = TempDir::new().path().to_path_buf();
        app.tools_check = Box::new(|| Ok(()));
        app.handle_key(KeyCode::Char('b')).unwrap();
        if let Some(EditState::Browse(e)) = &mut app.edited {
            *e = TextEdit::new("/tmp");
        }
        app.handle_key(KeyCode::Enter).unwrap();
        assert!(app.edited.is_some(), "form stays open after a launch failure");
        assert!(app.error.as_deref().unwrap_or("").contains("tmux new-window failed"));
        assert!(created.lock().unwrap().is_empty(), "no window was created");
        assert!(app.records.is_empty());
    }

    #[test]
    fn browse_foreground_spawn_failure_restores_and_surfaces_error() {
        let fg = FakeForeground::new(true);
        let runs = Arc::clone(&fg.runs);
        let term = FakeTerminal::new(false, false);
        let calls = Arc::clone(&term.calls);
        let mut app = make_app_with(FakeProvider::new("one"), FakeTmux::new(false),
                                    FakeProc { trees: HashMap::new() }, vec![],
                                    Box::new(fg), Box::new(term));
        app.state_dir = TempDir::new().path().to_path_buf();
        app.tools_check = Box::new(|| Ok(()));
        app.handle_key(KeyCode::Char('b')).unwrap();
        if let Some(EditState::Browse(e)) = &mut app.edited {
            *e = TextEdit::new("/tmp");
        }
        app.handle_key(KeyCode::Enter).unwrap();
        assert_eq!(runs.load(Ordering::SeqCst), 1, "spawn was attempted");
        assert_eq!(calls.suspended.load(Ordering::SeqCst), 1);
        assert_eq!(calls.restored.load(Ordering::SeqCst), 1, "restore always runs");
        assert!(app.edited.is_some());
        assert!(app.error.as_deref().unwrap_or("").contains("spawn failed"));
        assert!(app.records.is_empty());
    }

    #[test]
    fn browse_partial_suspend_failure_never_launches() {
        let fg = FakeForeground::new(false);
        let runs = Arc::clone(&fg.runs);
        let term = FakeTerminal::new(true, false); // suspend fails
        let calls = Arc::clone(&term.calls);
        let mut app = make_app_with(FakeProvider::new("one"), FakeTmux::new(false),
                                    FakeProc { trees: HashMap::new() }, vec![],
                                    Box::new(fg), Box::new(term));
        app.state_dir = TempDir::new().path().to_path_buf();
        app.tools_check = Box::new(|| Ok(()));
        app.handle_key(KeyCode::Char('b')).unwrap();
        if let Some(EditState::Browse(e)) = &mut app.edited {
            *e = TextEdit::new("/tmp");
        }
        app.handle_key(KeyCode::Enter).unwrap();
        assert_eq!(runs.load(Ordering::SeqCst), 0,
            "failed terminal preparation must never launch");
        assert_eq!(calls.restored.load(Ordering::SeqCst), 1, "restore always runs");
        assert!(app.error.as_deref().unwrap_or("").contains("suspend"));
        assert!(app.records.is_empty());
    }

    #[test]
    fn browse_zero_providers_opens_form_via_key_handler() {
        let reg = make_registry(vec![]);
        let mut app = make_app(reg, FakeTmux::new(true), FakeProc { trees: HashMap::new() },
                               Box::new(tracking::MemStore::new(vec![])));
        app.handle_key(KeyCode::Char('b')).unwrap();
        let Some(EditState::Browse(e)) = &app.edited else {
            panic!("b must open the browse form with zero providers")
        };
        assert!(!e.text().is_empty(), "prefill falls back to Pinga's cwd");
        app.handle_key(KeyCode::Esc).unwrap();
        assert!(app.edited.is_none());
    }

    #[test]
    fn browse_falls_back_to_cwd_when_session_dir_missing_or_file() {
        let td = TempDir::new();
        let file = td.path().join("afile");
        std::fs::write(&file, "x").unwrap();
        let missing = td.path().join("missing-dir");
        for dir in [missing.to_string_lossy().into_owned(), file.to_string_lossy().into_owned()] {
            let f1 = FakeProvider::new("one");
            let mut sess = fake_session("one", "s0");
            sess.directory = Some(dir.clone());
            *f1.list_out.lock().unwrap() = vec![sess];
            let reg = make_registry(vec![f1]);
            let mut app = make_app(reg, FakeTmux::new(true), FakeProc { trees: HashMap::new() },
                                   Box::new(tracking::MemStore::new(vec![])));
            app.refresh();
            app.view_mut(0).sel = 1;
            app.handle_key(KeyCode::Char('b')).unwrap();
            let Some(EditState::Browse(e)) = &app.edited else { panic!("b must open browse") };
            let cwd = std::env::current_dir().unwrap().to_string_lossy().into_owned();
            assert_eq!(e.text(), cwd,
                "a missing/file-valued session dir must fall back to cwd (had {dir:?})");
        }
    }

    /// Long-list scrolling and mouse hit-testing share ONE layout: moving
    /// below the viewport must keep the selected row visible on screen (with
    /// headers and two-line items), and clicking the visible selected row must
    /// dispatch the correct SessionKey. Exercised at both short and tall sizes
    /// through the real renderer (TestBackend), asserting RENDERED text and the
    /// DISPATCHED key, not just stored offsets.
    #[test]
    fn long_list_scrolls_to_selection_and_click_dispatches_sessionkey() {
        use crossterm::event::{MouseButton, MouseEvent, MouseEventKind};

        let mut sessions = Vec::new();
        for i in 0..30 {
            let mut s = fake_session("one", &format!("s{i}"));
            s.title = Some(format!("S {i}"));
            sessions.push(s);
        }
        let f1 = FakeProvider::new("one");
        *f1.list_out.lock().unwrap() = sessions;
        let reg = make_registry(vec![f1]);
        let mut tmux = FakeTmux::new(true);
        tmux.list_ids = vec![]; // no confirmed running windows
        let mut app = make_app(reg, tmux, FakeProc { trees: HashMap::new() },
                               Box::new(tracking::MemStore::new(vec![])));
        app.last_width = 120;
        app.refresh();
        assert_eq!(app.view(0).snapshot.len(), 30);
        app.detail = true; // two-line session items

        for (term_h, sel_target) in [(40usize, 25usize), (9usize, 25usize)] {
            app.last_height = term_h as u16;
            app.view_mut(0).sel = 0;
            app.view_mut(0).scroll = 0;
            for _ in 0..sel_target { app.move_cursor(1); }
            assert_eq!(app.view(0).sel, sel_target, "selection advanced to target");
            // Selectable index 0 is the "+ new" row, so sel_target selects the
            // (sel_target - 1)-th session.
            let session_idx = sel_target - 1;
            let expected = format!("S {session_idx}");
            // RENDER: the selected row must be inside the viewport and visible.
            let mut term = Terminal::new(TestBackend::new(120, term_h as u16)).unwrap();
            term.draw(|f| app.render(f)).unwrap();
            let rendered: String = term.backend().buffer().content.iter()
                .map(|cell| cell.symbol()).collect();
            assert!(rendered.contains(&expected),
                "selected row {expected} must be rendered at height {term_h}: {rendered}");
            // CLICK the visible selected row: map it through the same layout the
            // renderer uses, then dispatch a mouse Down; the resulting selection
            // must carry the SessionKey of the clicked session.
            let v = app.view(0);
            let rows = app.visual_rows(0);
            let heights: Vec<u16> = rows.iter().map(|r| app.row_lines(*r)).collect();
            let layout = app.list_layout(&rows, &heights, v.sel, v.scroll, app.column_inner_height());
            // Inner row of the selected item: cumulative lines from
            // layout.start to the selected visual row (same walk the renderer
            // uses), so the click lands on its first line.
            let inner: usize = heights.iter().take(layout.sel_visual)
                .map(|h| usize::from(*h)).sum();
            // Terminal row = title line (1) + column border (1) + inner row.
            let y = (inner + 2) as u16;
            let m = MouseEvent {
                kind: MouseEventKind::Down(MouseButton::Left),
                column: 2,
                row: y,
                modifiers: crossterm::event::KeyModifiers::NONE,
            };
            app.last_click = None;
            app.handle_mouse(&m, Rect::new(0, 0, 120, term_h as u16)).unwrap();
            let focused = app.focused_session().map(|s| s.id.clone());
            let want = format!("s{session_idx}");
            assert_eq!(focused.as_deref().map(str::to_string).as_deref(), Some(want.as_str()),
                "click dispatched the SessionKey of the visible selected row at height {term_h}");
        }
    }

    #[test]
    fn zero_providers_renders_empty_state_and_noops() {
        let reg = provider::ProviderRegistry::new();
        let mut app = make_app(reg, FakeTmux::new(true), FakeProc { trees: HashMap::new() },
                               Box::new(tracking::MemStore::new(vec![])));
        app.last_width = 120;
        app.refresh();
        assert!(app.visible_indices().is_empty());
        app.handle_key(KeyCode::Down).unwrap();
        app.handle_key(KeyCode::Up).unwrap();
        app.focus_next(1);
        assert!(app.open_selected(false).is_ok());
        let mut term = Terminal::new(TestBackend::new(120, 30)).unwrap();
        term.draw(|f| app.render(f)).unwrap(); // no panic, useful empty state
        // quit still works
        assert!(app.handle_key(KeyCode::Char('q')).is_err());
    }

    #[test]
    fn one_two_three_provider_refresh_focus_and_viewport() {
        let f1 = FakeProvider::new("one");
        *f1.list_out.lock().unwrap() = vec![fake_session("one", "s1")];
        let f2 = FakeProvider::new("two");
        *f2.list_out.lock().unwrap() = vec![fake_session("two", "s2")];
        let f3 = FakeProvider::new("three");
        *f3.list_out.lock().unwrap() = vec![fake_session("three", "s3")];
        let reg = make_registry(vec![f1, f2, f3]);
        let mut app = make_app(reg, FakeTmux::new(true), FakeProc { trees: HashMap::new() },
                               Box::new(tracking::MemStore::new(vec![])));
        app.last_width = 120;
        app.refresh();
        assert_eq!(app.views.len(), 3);
        assert_eq!(app.view(0).snapshot.len(), 1);
        assert_eq!(app.view(2).snapshot.len(), 1);
        assert!(app.view(0).ok);
        // viewport shows at most two, focus wraps across all three.
        assert_eq!(app.visible_indices().len(), 2);
        app.focus = 0;
        app.focus_next(1); assert_eq!(app.focus, 1);
        app.focus_next(1); assert_eq!(app.focus, 2);
        app.focus_next(1); assert_eq!(app.focus, 0, "wraps at end");
        app.focus = 2;
        app.focus_next(-1); assert_eq!(app.focus, 1);
        // narrow terminal: one column
        app.last_width = 70;
        assert_eq!(app.visible_indices().len(), 1);
        // render with two columns via TestBackend
        app.last_width = 120;
        app.focus = 2;
        app.ensure_focus_visible();
        let mut term = Terminal::new(TestBackend::new(120, 30)).unwrap();
        term.draw(|f| app.render(f)).unwrap();
    }

    #[test]
    fn per_provider_failure_is_local_and_selection_survives_reorder() {
        // A failing provider keeps its last good snapshot (ok=false) while the
        // other provider refreshes independently; the selected SessionKey is
        // restored after a reorder.
        let ok1 = FakeProvider::new("ok");
        *ok1.list_out.lock().unwrap() = vec![fake_session("ok", "a"), fake_session("ok", "b")];
        let ok_list = Arc::clone(&ok1.list_out);
        let bad = FakeProvider::new("bad");
        *bad.list_out.lock().unwrap() = vec![fake_session("bad", "x")];
        let bad_err = Arc::clone(&bad.list_err);
        let reg = make_registry(vec![ok1, bad]);
        let mut app = make_app(reg, FakeTmux::new(true), FakeProc { trees: HashMap::new() },
                               Box::new(tracking::MemStore::new(vec![])));
        app.last_width = 120;
        app.refresh(); // both succeed initially
        assert!(app.view(1).ok);
        // The bad provider's listing now fails; its last good snapshot is kept.
        bad_err.store(true, Ordering::SeqCst);
        app.refresh();
        assert!(app.view(0).ok, "provider 0 refreshed");
        assert_eq!(app.view(0).snapshot.len(), 2);
        assert!(!app.view(1).ok, "provider 1 failed");
        assert_eq!(app.view(1).snapshot.len(), 1, "last good snapshot retained on failure");

        // Select session "a", then reorder the list and refresh: selection must
        // follow "a" by SessionKey.
        app.focus = 0;
        app.view_mut(0).sel = 1; // selectable 1 -> first session ("a")
        *ok_list.lock().unwrap() = vec![fake_session("ok", "b"), fake_session("ok", "a")];
        app.refresh();
        let focused = app.focused_session().map(|s| s.id.clone());
        assert_eq!(focused.as_deref(), Some("a"), "selection follows the SessionKey across a reorder");
    }

    #[test]
    fn selection_is_preserved_by_sessionkey_on_reorder() {
        let f1 = FakeProvider::new("one");
        *f1.list_out.lock().unwrap() = vec![fake_session("one", "a"), fake_session("one", "b"), fake_session("one", "c")];
        let list = Arc::clone(&f1.list_out);
        let reg = make_registry(vec![f1]);
        let mut app = make_app(reg, FakeTmux::new(true), FakeProc { trees: HashMap::new() },
                               Box::new(tracking::MemStore::new(vec![])));
        app.last_width = 120;
        app.refresh();
        app.focus = 0;
        app.refresh();
        assert_eq!(app.view(0).sel, 0, "refresh must preserve the new-session row");
        app.view_mut(0).sel = 2; // selects "b" (selectable 2 -> second session)
        // Reorder: "b" moves to the end.
        *list.lock().unwrap() = vec![fake_session("one", "c"), fake_session("one", "a"), fake_session("one", "b")];
        app.refresh();
        let focused = app.focused_session().map(|s| s.id.clone());
        assert_eq!(focused.as_deref(), Some("b"),
            "selection restored by SessionKey after a reorder");
    }

    #[test]
    fn pending_is_persisted_and_resolved_after_restart_with_unique_evidence() {
        let tmp = TempDir::new();
        let store = Box::new(tracking::FileTrackingStore::new(tmp.path().to_path_buf()));
        let mut f = FakeProvider::new("third");
        f.create_mode = CreateMode::LaunchToCreate;
        let reg = make_registry(vec![f]);
        let mut app = make_app(reg, FakeTmux::new(true), FakeProc { trees: HashMap::new() }, store);
        app.last_width = 120;
        app.focus = 0;
        app.create_new_session("proj", "/tmp").unwrap();
        assert!(app.records.iter().any(|r| matches!(r, TrackedRecord::Pending { .. })),
            "pending persisted after successful window creation");

        // "Restart": a fresh store on the same directory sees the pending record.
        let store2 = Box::new(tracking::FileTrackingStore::new(tmp.path().to_path_buf()));
        let mut f2 = FakeProvider::new("third");
        // Listing now returns the session; unique confirmed evidence resolves it.
        *f2.list_out.lock().unwrap() = vec![fake_session("third", "created-ses")];
        f2.match_out = vec![WindowMatch { window_id: "@10".into(), confidence: MatchConfidence::Confirmed }];
        let reg2 = make_registry(vec![f2]);
        let mut tmux = FakeTmux::new(true);
        tmux.list_ids = vec!["@10".into()];
        tmux.set_alive("@10", true);
        let mut app2 = make_app(reg2, tmux, FakeProc { trees: HashMap::new() }, store2);
        app2.last_width = 120;
        // Load persisted records then reconcile.
        app2.records = app2.store.read().unwrap();
        app2.refresh();
        assert!(app2.records.iter().any(|r| matches!(r, TrackedRecord::Known { session, .. } if session == "created-ses")),
            "pending resolved to a known session on unique confirmed evidence");
        assert!(!app2.records.iter().any(|r| matches!(r, TrackedRecord::Pending { .. })),
            "no longer pending after unique resolution");
    }

    #[test]
    fn interrupted_state_is_stable_across_polls_and_later_opens_are_not_eligible() {
        // A Known record marked Interrupted stays interrupted across several
        // polls (retained, not dropped on a second dead-window poll).
        let store = Box::new(tracking::MemStore::new(vec![known_rec("one", "s1", "@1", TrackedState::Interrupted)]));
        let f = FakeProvider::new("one");
        *f.list_out.lock().unwrap() = vec![fake_session("one", "s1")];
        let mut tmux = FakeTmux::new(true);
        tmux.list_ids = vec!["@1".into()];
        tmux.set_alive("@1", false); // dead window
        let reg = make_registry(vec![f]);
        let mut app = make_app(reg, tmux, FakeProc { trees: HashMap::new() }, store);
        app.last_width = 120;
        app.records = app.store.read().unwrap();
        for _ in 0..3 { app.refresh(); }
        assert!(app.records.iter().any(|r| matches!(r, TrackedRecord::Known { state: TrackedState::Interrupted, .. })),
            "interruption retained across polls");
        assert!(app.view(0).interrupted.contains(&"s1".to_string()));

        // A record opened LATER (not startup-eligible) that dies is an intentional
        // close, never interrupted.
        let store2 = Box::new(tracking::MemStore::new(vec![]));
        let f2 = FakeProvider::new("one");
        *f2.list_out.lock().unwrap() = vec![fake_session("one", "s2")];
        let mut tmux2 = FakeTmux::new(true);
        tmux2.list_ids = vec!["@9".into()];
        tmux2.set_alive("@9", false);
        let reg2 = make_registry(vec![f2]);
        let mut app2 = make_app(reg2, tmux2, FakeProc { trees: HashMap::new() }, store2);
        app2.last_width = 120;
        // Seed a Known record AFTER startup (not eligible); the store allocates its id.
        let pending_open = TrackedRecord::Known { id: 0, provider: ProviderId::new("one").unwrap(),
                                                  session: "s2".into(), window: "@9".into(),
                                                  state: TrackedState::Open };
        app2.store.update(&mut |r| { r.push(pending_open.clone()); true }).unwrap();
        app2.records = app2.store.read().unwrap();
        app2.startup_eligible_initialized = true;
        app2.startup_eligible = vec![];
        app2.refresh();
        assert!(!app2.view(0).interrupted.contains(&"s2".to_string()),
            "later open is not flagged interrupted");
        assert!(!app2.records.iter().any(|r| matches!(r, TrackedRecord::Known { state: TrackedState::Interrupted, .. })),
            "later intentional close drops, not interrupt");
    }

    #[test]
    fn third_fake_provider_completes_list_create_resume_rename_tracking() {
        let tmp = TempDir::new();
        let store = Box::new(tracking::FileTrackingStore::new(tmp.path().to_path_buf()));
        let mut f = FakeProvider::new("third");
        f.type_key = "third";
        f.create_mode = CreateMode::Known;
        *f.list_out.lock().unwrap() = vec![fake_session("third", "s-a")];
        let reg = make_registry(vec![f]);
        let mut tmux = FakeTmux::new(true);
        tmux.list_ids = vec!["@10".into()];
        tmux.set_alive("@10", true);
        let mut app = make_app(reg, tmux, FakeProc { trees: HashMap::new() }, store);
        app.last_width = 120;
        app.focus = 0;
        // list
        app.refresh();
        assert_eq!(app.view(0).snapshot.len(), 1);
        // rename via generic path
        app.view_mut(0).sel = 1;
        app.apply_rename_to_focused("Renamed").unwrap();
        // resume plan via generic path (resume cap true)
        let s = fake_session("third", "s-a");
        let r = app.open_session(&s, false).unwrap();
        assert!(matches!(r, OpenResult::Opened | OpenResult::Refused), "generic resume path");
        // create -> known -> tracking record (tmux spawn OK)
        app.view_mut(0).sel = 0;
        app.create_new_session("proj", "/tmp").unwrap();
        assert!(app.records.iter().any(|r| matches!(r, TrackedRecord::Known { .. })),
            "third provider tracked through the generic core path");
        assert_eq!(app.views.len(), 1, "no extra production column");
    }

    #[test]
    fn deferred_plan_keeps_its_provider_after_focus_change() {
        let f1 = FakeProvider::new("one");
        let f2 = FakeProvider::new("two");
        let reg = make_registry(vec![f1, f2]);
        let tmux = FakeTmux::new(true);
        let selected = Arc::clone(&tmux.selected);
        let mut app = make_app(reg, tmux, FakeProc { trees: HashMap::new() },
                               Box::new(tracking::MemStore::new(vec![])));
        app.last_width = 120;
        app.commit_or_defer(Plan::Select { provider: ProviderId::new("one").unwrap(), win: "@9".into() }, true).unwrap();
        assert!(app.pending.is_some());
        app.focus = 1; // focus moves before execution
        let plan = app.pending.take().unwrap();
        app.execute(plan).unwrap();
        assert_eq!(selected.lock().unwrap().clone(), vec!["@9".to_string()],
            "deferred action kept its original provider");
    }

    #[test]
    fn identical_native_ids_across_providers_do_not_cross_track() {
        let f1 = FakeProvider::new("one");
        *f1.list_out.lock().unwrap() = vec![fake_session("one", "same-native")];
        let f2 = FakeProvider::new("two");
        *f2.list_out.lock().unwrap() = vec![fake_session("two", "same-native")];
        let reg = make_registry(vec![f1, f2]);
        let mut app = make_app(reg, FakeTmux::new(true), FakeProc { trees: HashMap::new() },
                               Box::new(tracking::MemStore::new(vec![])));
        app.last_width = 120;
        app.refresh();
        assert_eq!(app.view(0).snapshot[0].provider_id, ProviderId::new("one").unwrap());
        assert_eq!(app.view(1).snapshot[0].provider_id, ProviderId::new("two").unwrap());
        // Opening provider 0's session tracks only provider 0.
        let s = app.view(0).snapshot[0].clone();
        app.open_session(&s, false).unwrap();
        assert!(app.records.iter().any(|r| matches!(r, TrackedRecord::Known { provider, .. } if provider.as_str() == "one")));
        assert!(!app.records.iter().any(|r| matches!(r, TrackedRecord::Known { provider, .. } if provider.as_str() == "two")),
            "no cross-provider tracking update");
    }

    #[test]
    fn reconcile_preserves_records_replaced_by_another_store() {
        // Two handles share one backing store. The app reconciles from a
        // snapshot; a concurrent handle replaces the record; the app's
        // record-id compare-and-apply must not delete the replacement.
        let inner = Arc::new(Mutex::new(tracking::Envelope {
            version: tracking::SCHEMA_VERSION, next_id: 2,
            records: vec![known_rec("one", "s1", "@1", TrackedState::Open)] }));
        let store1 = Box::new(tracking::MemStore::shared(inner.clone()));
        let store2 = tracking::MemStore::shared(inner);
        let f = FakeProvider::new("one");
        *f.list_out.lock().unwrap() = vec![fake_session("one", "s1")];
        let mut tmux = FakeTmux::new(true);
        tmux.list_ids = vec!["@1".into()];
        tmux.set_alive("@1", true);
        tmux.set_alive("@2", true);
        tmux.set_alive("@9", true);
        tmux.list_ids_err = true; // evidence collection fails -> unknown/retain
        let reg = make_registry(vec![f]);
        let mut app = make_app(reg, tmux, FakeProc { trees: HashMap::new() }, store1);
        app.last_width = 120;
        app.refresh(); // snapshot + reconcile from the seed
        assert_eq!(app.records.len(), 1);
        // Another writer REPLACES the record (same provider/session/window, new
        // record id) and adds a pending; stale evidence must preserve both.
        store2.update(&mut |r| {
            r.clear();
            r.push(TrackedRecord::Known { id: 0, provider: ProviderId::new("one").unwrap(),
                                          session: "s1".into(), window: "@1".into(),
                                          state: TrackedState::Open });
            r.push(TrackedRecord::Pending { id: 0, provider: ProviderId::new("one").unwrap(),
                                            window: "@9".into(), label: "n".into() });
            true
        }).unwrap();
        app.refresh(); // stale evidence must preserve the concurrent records
        assert!(app.records.iter().any(|r| matches!(r, TrackedRecord::Known { id: 2, .. })),
            "replacement record (allocated new id) survives stale evidence");
        assert!(app.records.iter().any(|r| matches!(r, TrackedRecord::Pending { .. })),
            "concurrent addition survives stale evidence");
    }

    /// A REAL file-store interleaving seam: on the FIRST update, a second
    /// FileTrackingStore handle (same directory) deterministically commits a
    /// concurrent replacement BEFORE this store's own read-modify-write
    /// proceeds. This exercises the exact conflicting timing a racing instance
    /// creates between the app's snapshot read and its commit — not just edits
    /// between two complete refreshes. The app's conditional commit must not
    /// erase the replacement or the concurrent addition.
    struct RacingStore {
        inner: tracking::FileTrackingStore,
        other: tracking::FileTrackingStore,
        raced: Arc<AtomicBool>,
    }
    impl RacingStore {
        fn new(dir: &Path) -> Self {
            Self { inner: tracking::FileTrackingStore::new(dir.to_path_buf()),
                   other: tracking::FileTrackingStore::new(dir.to_path_buf()),
                   raced: Arc::new(AtomicBool::new(false)) }
        }
    }
    impl TrackingStore for RacingStore {
        fn read(&self) -> anyhow::Result<Vec<TrackedRecord>> { self.inner.read() }
        fn update(&self, f: &mut dyn FnMut(&mut Vec<TrackedRecord>) -> bool) -> anyhow::Result<Vec<TrackedRecord>> {
            if !self.raced.swap(true, Ordering::SeqCst) {
                // The other instance commits between our read and our write:
                // replace the seeded known record and add a pending.
                self.other.update(&mut |r| {
                    r.clear();
                    r.push(TrackedRecord::Known { id: 0,
                        provider: ProviderId::new("one").unwrap(), session: "s1".into(),
                        window: "@1".into(), state: TrackedState::Open });
                    r.push(TrackedRecord::Pending { id: 0,
                        provider: ProviderId::new("one").unwrap(), window: "@9".into(), label: "n".into() });
                    true
                }).expect("racing writer commits");
            }
            self.inner.update(f)
        }
    }

    /// End-to-end app integration through the REAL antigravity adapter: a temp
    /// home with a seeded summary DB lists its session, resume produces the
    /// `agy --conversation <uuid>` launch with the pinned data dir, and the
    /// tracked record lands. No live agy, tmux server, or user data dir.
    #[test]
    fn real_antigravity_adapter_through_the_app_list_resume_track() {
        let tmp = TempDir::new();
        let home = tmp.path().join("home");
        std::fs::create_dir_all(&home).unwrap();
        let db = home.join("conversation_summaries.db");
        let conn = rusqlite::Connection::open(&db).unwrap();
        conn.execute_batch("CREATE TABLE conversation_summaries (
            conversation_id TEXT PRIMARY KEY, title TEXT NOT NULL DEFAULT '',
            preview TEXT NOT NULL DEFAULT '', step_count INTEGER NOT NULL DEFAULT 0,
            last_modified_time DATETIME NOT NULL, workspace_uris TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL DEFAULT '', source TEXT NOT NULL DEFAULT '',
            project_id TEXT NOT NULL DEFAULT '', agent_name TEXT NOT NULL DEFAULT '',
            parent_conversation_id TEXT NOT NULL DEFAULT '', nesting_depth INTEGER NOT NULL DEFAULT 0,
            battle_id TEXT NOT NULL DEFAULT '', winning_conversation_id TEXT NOT NULL DEFAULT '',
            not_fully_idle NUMERIC NOT NULL DEFAULT false, killed NUMERIC NOT NULL DEFAULT false,
            last_user_input_time DATETIME NOT NULL DEFAULT '', last_user_input_step_index INTEGER NOT NULL DEFAULT -1,
            app_data_dir TEXT NOT NULL DEFAULT '', group_id TEXT NOT NULL DEFAULT '')").unwrap();
        conn.execute("INSERT INTO conversation_summaries
            (conversation_id, title, preview, last_modified_time, workspace_uris, project_id, agent_name, not_fully_idle, killed)
            VALUES ('u-1', 'Conv One', '', '2026-09-23 01:00:05', '/home/u/w/a', 'p1', '', 0, 0)",
            []).unwrap();
        drop(conn);

        // Build an App with the REAL antigravity adapter configured against this home.
        let mut opts = std::collections::BTreeMap::new();
        opts.insert("home".to_string(), toml::Value::String(home.to_string_lossy().into_owned()));
        let mut reg = provider::ProviderRegistry::new();
        reg.register(provider::antigravity::AntigravityProvider::factory(
            ProviderId::new("agy").unwrap(), None, &opts).unwrap()).unwrap();
        let mut tmux = FakeTmux::new(true);
        tmux.list_ids = vec!["@10".into()];
        tmux.set_alive("@10", true);
        let spawned = Arc::clone(&tmux.created);
        let mut app = make_app(reg, tmux, FakeProc { trees: HashMap::new() },
                               Box::new(tracking::MemStore::new(vec![])));
        app.last_width = 120;
        app.refresh();
        // LIST: the real adapter enumerates the seeded conversation.
        assert_eq!(app.view(0).snapshot.len(), 1);
        assert_eq!(app.view(0).snapshot[0].id, "u-1");
        assert_eq!(app.view(0).snapshot[0].title.as_deref(), Some("Conv One"));
        assert_eq!(app.view(0).snapshot[0].provider_id.as_str(), "agy");
        // RESUME: real adapter launch with --conversation and the pinned env.
        app.view_mut(0).sel = 1;
        let r = app.open_session(&app.view(0).snapshot[0].clone(), false);
        assert!(matches!(r, Ok(OpenResult::Opened)), "real adapter resume through the app");
        let argv = spawned.lock().unwrap();
        let (label, cmd) = argv.last().unwrap();
        assert_eq!(label, "Conv One");
        let sh_line = cmd.join(" ");
        assert!(sh_line.contains("exec 'agy'"), "spawns the agy binary: {sh_line}");
        assert!(sh_line.contains("--conversation"), "resume uses --conversation");
        assert!(sh_line.contains("'u-1'"), "resume targets the exact uuid");
        assert!(sh_line.contains("ANTIGRAVITY_APP_DATA_DIR"),
            "launch pins the data dir: {sh_line}");
        // TRACK: the resumed window is recorded.
        assert!(app.records.iter().any(|r| matches!(r, TrackedRecord::Known { provider, session, window, .. }
            if provider.as_str() == "agy" && session == "u-1" && window == "@10")));
    }

    #[test]
    fn deterministic_file_store_interleave_preserves_concurrent_replacement() {
        let tmp = TempDir::new();
        let dir = tmp.path().to_path_buf();
        // Seed through a plain store so the app reads a real observed generation.
        tracking::FileTrackingStore::new(dir.clone()).update(&mut |r| {
            r.push(TrackedRecord::Known { id: 0,
                provider: ProviderId::new("one").unwrap(), session: "s1".into(),
                window: "@1".into(), state: TrackedState::Open });
            true
        }).unwrap();
        let store = Box::new(RacingStore::new(&dir));
        let f = FakeProvider::new("one");
        *f.list_out.lock().unwrap() = vec![fake_session("one", "s1")];
        let mut tmux = FakeTmux::new(true);
        tmux.list_ids = vec!["@1".into(), "@9".into()];
        tmux.set_alive("@1", true);
        tmux.set_alive("@9", true);
        tmux.list_ids_err = true; // evidence collection fails -> unknown/retain
        let reg = make_registry(vec![f]);
        let mut app = make_app(reg, tmux, FakeProc { trees: HashMap::new() }, store);
        app.last_width = 120;
        app.refresh(); // read + reconcile; the FIRST update races a replacement
        assert!(app.records.iter().any(|r| matches!(r, TrackedRecord::Known { session, .. } if session == "s1")),
            "concurrent replacement record survives the stale-generation commit");
        assert!(app.records.iter().any(|r| matches!(r, TrackedRecord::Pending { .. })),
            "concurrent pending survives the stale-generation commit");
    }

    /// A store that fails every update (to exercise the launched-window
    /// tracking-failure reporting path).
    struct FailingUpdateStore { inner: tracking::MemStore, fail: Arc<AtomicBool> }
    impl FailingUpdateStore {
        fn new(records: Vec<TrackedRecord>) -> Self {
            Self { inner: tracking::MemStore::new(records), fail: Arc::new(AtomicBool::new(false)) }
        }
    }
    impl TrackingStore for FailingUpdateStore {
        fn read(&self) -> anyhow::Result<Vec<TrackedRecord>> { self.inner.read() }
        fn update(&self, _f: &mut dyn FnMut(&mut Vec<TrackedRecord>) -> bool) -> anyhow::Result<Vec<TrackedRecord>> {
            if self.fail.load(Ordering::SeqCst) { return Err(anyhow!("tracking write failed")); }
            self.inner.update(_f)
        }
    }

    #[test]
    fn tracking_failure_reports_launched_window_and_no_blind_retry() {
        let store = FailingUpdateStore::new(vec![]);
        let fail_flag = Arc::clone(&store.fail);
        let mut f = FakeProvider::new("one");
        f.create_mode = CreateMode::Known;
        let reg = make_registry(vec![f]);
        let mut tmux = FakeTmux::new(true);
        tmux.list_ids = vec!["@10".into()];
        tmux.set_alive("@10", true);
        let mut app = make_app(reg, tmux, FakeProc { trees: HashMap::new() }, Box::new(store));
        app.last_width = 120;
        app.focus = 0;
        app.refresh(); // provider refresh succeeds; reconciliation commits fine
        fail_flag.store(true, Ordering::SeqCst); // tracking writes now fail
        let r = app.create_new_session("proj", "/tmp");
        // The window WAS launched (@10) but tracking failed; the error must name
        // the window and report that tracking failed, not imply no launch.
        assert!(r.is_ok(), "create_new_session surfaces tracking failure in self.error");
        let msg = app.error.as_ref().unwrap();
        assert!(msg.contains("@10"), "error names the launched window: {msg}");
        assert!(msg.contains("tracking failed"), "error reports tracking failure: {msg}");
        assert!(msg.contains("could not be opened"));
    }

    #[test]
    fn retry_after_tracking_failure_records_existing_window_without_respawn() {
        // The fake allocates a DISTINCT native id per create (like a real API),
        // so a create-based "retry" would silently mint a duplicate session.
        // Recovery must retry the retained SessionKey via open_session and never
        // call create again.
        let store = FailingUpdateStore::new(vec![]);
        let fail_flag = Arc::clone(&store.fail);
        let mut f = FakeProvider::new("one");
        f.create_mode = CreateMode::Known;
        let rec = Arc::clone(&f.rec);
        let reg = make_registry(vec![f]);
        let mut tmux = FakeTmux::new(true);
        tmux.list_ids = vec!["@10".into()];
        tmux.set_alive("@10", true);
        let spawned = Arc::clone(&tmux.created);
        let mut app = make_app(reg, tmux, FakeProc { trees: HashMap::new() }, Box::new(store));
        app.last_width = 120;
        app.focus = 0;
        app.refresh();
        fail_flag.store(true, Ordering::SeqCst);
        // First create: window created, tracking fails, unrecorded launch kept.
        let _ = app.create_new_session("proj", "/tmp");
        assert_eq!(rec.create_calls.load(Ordering::SeqCst), 1);
        assert_eq!(app.unrecorded_launches.len(), 1);
        assert_eq!(spawned.lock().unwrap().len(), 1, "one window spawned");
        // Retry by re-opening the RETAINED session while writes still fail:
        // reuses the window, never a second spawn, never a second create.
        let retained = app.unrecorded_launches[0].known.clone().unwrap();
        let sess = fake_session("one", retained.native_id());
        let _ = app.open_session(&sess, false);
        assert_eq!(rec.create_calls.load(Ordering::SeqCst), 1, "retry never calls create again");
        assert_eq!(spawned.lock().unwrap().len(), 1, "retry must not spawn a second window");
        assert_eq!(app.unrecorded_launches.len(), 1, "still unrecorded while writes fail");
        // Recovery: a further retry records the existing window and clears state.
        fail_flag.store(false, Ordering::SeqCst);
        let _ = app.open_session(&sess, false);
        assert_eq!(rec.create_calls.load(Ordering::SeqCst), 1, "recovery never calls create again");
        assert_eq!(spawned.lock().unwrap().len(), 1, "recovery still reuses the window");
        assert!(app.unrecorded_launches.is_empty());
        assert!(app.records.iter().any(|r| matches!(r, TrackedRecord::Known { window, .. } if window == "@10")));
    }

    /// Two intentional new launches sharing provider/label/cwd are DISTINCT:
    /// pending recovery is token-based, so a fresh new launch always spawns a
    /// new window, never silently reuses the other's unrecorded window.
    #[test]
    fn same_label_same_cwd_new_launches_are_distinct_until_explicit_token_retry() {
        let store = FailingUpdateStore::new(vec![]);
        let fail_flag = Arc::clone(&store.fail);
        let mut f = FakeProvider::new("one");
        f.create_mode = CreateMode::LaunchToCreate;
        let reg = make_registry(vec![f]);
        let mut tmux = FakeTmux::new(true);
        tmux.list_ids = vec![];
        // next_win starts at @10: the three intentional launches will be @10,
        // @11, @12. Mark them alive so explicit retry liveness passes.
        tmux.set_alive("@10", true);
        tmux.set_alive("@11", true);
        tmux.set_alive("@12", true);
        let spawned = Arc::clone(&tmux.created);
        let mut app = make_app(reg, tmux, FakeProc { trees: HashMap::new() }, Box::new(store));
        app.last_width = 120;
        app.focus = 0;
        app.refresh();
        fail_flag.store(true, Ordering::SeqCst);
        // Two intentional new launches with identical label+cwd.
        let _ = app.create_new_session("same", "/tmp");
        let _ = app.create_new_session("same", "/tmp");
        assert_eq!(spawned.lock().unwrap().len(), 2, "each intentional new launch spawns its own window");
        assert_eq!(app.unrecorded_launches.len(), 2, "both kept for explicit retry");
        // They carry distinct tokens.
        let tokens: Vec<u64> = app.unrecorded_launches.iter().map(|u| u.token).collect();
        assert_eq!(tokens.len(), 2);
        assert_ne!(tokens[0], tokens[1], "tokens must be unique");
        // Ordinary NEW is still new: a third launch spawns yet another window.
        let _ = app.create_new_session("same", "/tmp");
        assert_eq!(spawned.lock().unwrap().len(), 3);
        // Explicit retry of the FIRST token reuses that window only.
        let before = app.unrecorded_launches.iter().map(|u| u.window.clone()).collect::<Vec<_>>();
        let r = app.retry_unrecorded(tokens[0]);
        assert!(r.is_err(), "tracking still fails, so retry reports failure");
        assert_eq!(spawned.lock().unwrap().len(), 3, "explicit retry never spawns");
        assert!(app.unrecorded_launches.iter().any(|u| u.token == tokens[0] && u.window == before[0]),
            "retry state retained while writes fail");
        // Recovery: a further explicit retry records that exact window.
        fail_flag.store(false, Ordering::SeqCst);
        assert!(app.pending_status_line().unwrap().contains("p retries launch"));
        app.handle_key(KeyCode::Char('p')).unwrap();
        assert_eq!(spawned.lock().unwrap().len(), 3, "recovery still never spawns");
        assert!(!app.unrecorded_launches.iter().any(|u| u.token == tokens[0]),
            "first token cleared after successful recording");
        assert!(app.records.iter().any(|r| matches!(r, TrackedRecord::Pending { window, .. } if window == &before[0])),
            "the exact first window was recorded, not the second");
    }

    /// Failed liveness at retry time must NOT record a successful open: the
    /// confirmed-dead window is dropped and the retry fails, while a failed
    /// inspection retains the recovery state.
    #[test]
    fn pending_retry_liveness_error_retains_state_and_never_records() {
        let store = FailingUpdateStore::new(vec![]);
        let fail_flag = Arc::clone(&store.fail);
        let mut f = FakeProvider::new("one");
        f.create_mode = CreateMode::LaunchToCreate;
        let reg = make_registry(vec![f]);
        let mut tmux = FakeTmux::new(true);
        tmux.list_ids = vec![];
        tmux.set_alive("@10", true);
        let alive = Arc::clone(&tmux.alive);
        let alive_err = Arc::clone(&tmux.alive_err);
        let mut app = make_app(reg, tmux, FakeProc { trees: HashMap::new() }, Box::new(store));
        app.last_width = 120;
        app.focus = 0;
        app.refresh();
        fail_flag.store(true, Ordering::SeqCst);
        let _ = app.create_new_session("n", "/tmp"); // @10, tracking fails
        assert_eq!(app.unrecorded_launches.len(), 1);
        let token = app.unrecorded_launches[0].token;
        // Inspection fails -> retry fails, state RETAINED, nothing recorded.
        alive_err.store(true, Ordering::SeqCst);
        let r = app.retry_unrecorded(token);
        assert!(r.is_err(), "failed inspection is not a successful open");
        assert_eq!(app.unrecorded_launches.len(), 1, "failed inspection retains the recovery state");
        assert!(!app.records.iter().any(|r| matches!(r, TrackedRecord::Pending { .. })),
            "failed inspection must not record a successful open");
        // Confirmed death -> retry fails, state DROPPED.
        alive_err.store(false, Ordering::SeqCst);
        alive.lock().unwrap().insert("@10".into(), false);
        let r = app.retry_unrecorded(token);
        assert!(r.is_err());
        assert!(app.unrecorded_launches.is_empty(), "confirmed death drops the entry");
        // Recovery only after the window is genuinely alive again.
        fail_flag.store(false, Ordering::SeqCst);
        let _ = app.create_new_session("n", "/tmp"); // spawns @11, records fine
        assert!(app.records.iter().any(|r| matches!(r, TrackedRecord::Pending { .. })),
            "later alive launch records normally");
    }

    #[test]
    fn foreground_launch_to_create_returns_failure_honestly() {
        // Bare-terminal launch-to-create must return an error on launch failure,
        // not stash it and return Ok (which would let a retry re-run the client).
        let mut f = FakeProvider::new("one");
        f.create_mode = CreateMode::LaunchToCreate;
        let mut app = make_app_with(f, FakeTmux::new(false), FakeProc { trees: HashMap::new() },
                                    vec![], Box::new(FakeForeground::new(true)),
                                    Box::new(FakeTerminal::new(false, false)));
        app.last_width = 120;
        app.focus = 0;
        let r = app.create_new_session("proj", "/tmp");
        assert!(r.is_err(), "foreground launch-to-create failure must propagate");
    }

    #[test]
    fn combined_terminal_cleanup_failures_are_surfaced_and_cleanup_runs() {
        // Foreground resume with BOTH a failed launch and a failed restoration:
        // cleanup still runs and the error is surfaced (not swallowed as Ok).
        let fg = FakeForeground::new(true);
        let fg_runs = Arc::clone(&fg.runs);
        let term = FakeTerminal::new(false, true); // suspend ok, restore fails
        let term_calls = Arc::clone(&term.calls);
        let f = FakeProvider::new("one");
        let mut app = make_app_with(f, FakeTmux::new(false), FakeProc { trees: HashMap::new() },
                                    vec![], Box::new(fg), Box::new(term));
        app.last_width = 120;
        app.focus = 0;
        app.view_mut(0).snapshot.push(fake_session("one", "s1"));
        let s = app.view(0).snapshot[0].clone();
        let r = app.open_session(&s, false);
        assert!(r.is_ok(), "open_session surfaces the failure via self.error");
        assert!(app.error.as_ref().map(|e| e.contains("launch")).unwrap_or(false),
            "launch error surfaced: {:?}", app.error);
        assert!(app.error.as_ref().map(|e| e.contains("restore")).unwrap_or(false),
            "restore error surfaced: {:?}", app.error);
        assert_eq!(fg_runs.load(Ordering::SeqCst), 1, "a launch was attempted");
        assert_eq!(term_calls.restored.load(Ordering::SeqCst), 1, "restore attempted even after launch failure");
    }

    #[test]
    fn ambiguous_malformed_evidence_retains_record_and_eligibility() {
        // A provider whose matcher reports AMBIGUOUS (e.g. an unparseable
        // endpoint, as the real opencode adapter does) must not erase the
        // tracked record or its startup eligibility. The real adapter's
        // malformed-endpoint -> Ambiguous behavior is covered by the opencode
        // unit tests; here the app reconciliation path is exercised.
        let mut f = FakeProvider::new("one");
        *f.list_out.lock().unwrap() = vec![fake_session("one", "s1")];
        f.match_out = vec![WindowMatch { window_id: "@1".into(), confidence: MatchConfidence::Ambiguous }];
        let reg = make_registry(vec![f]);
        let mut tmux = FakeTmux::new(true);
        tmux.list_ids = vec!["@1".into()];
        tmux.set_alive("@1", true);
        let store = Box::new(tracking::MemStore::new(vec![known_rec("one", "s1", "@1", TrackedState::Open)]));
        let mut app = make_app(reg, tmux, FakeProc { trees: HashMap::new() }, store);
        app.last_width = 120;
        app.refresh();
        assert!(app.records.iter().any(|r| matches!(r, TrackedRecord::Known { session, .. } if session == "s1")),
            "ambiguous malformed evidence must not erase the tracked record");
        assert!(app.startup_eligible.contains(&1), "startup eligibility preserved");
    }
}
```

> **Note.** The chunk is self-contained: the helpers (`body_rect`,
> `layout_rects`, `hit_rect`) and the single-click-open policy are real code
> now, not stubs. The **auto-rename pass** (§12) is deliberately left out of
> `refresh()` in this scaffolding so the loop stays obvious; it lands in the
> same function when §12's trigger policy is finalized. Mouse is opt-in with
> `m` so plain terminals never get capture surprises.

### 11.12 Entrypoint (`core::main`)

Tiny on purpose: terminal in/out is here, the loop is in `tui::app`.

``` {.rust #core-main path="src/main.rs"}
// Scaffold stage: the provider contract (§11.4–11.7) and theme (§11.9) declare
// the full data model and palette up front; the first TUI pass only reads a
// subset. `make lint` stays green while the remaining fields get wired in.
#![allow(dead_code)]

mod browse;
mod config;
mod launcher;
mod model;
mod naming;
mod provider;
mod tracking;
mod tui;

use std::io;

use crossterm::terminal::{disable_raw_mode, enable_raw_mode,
                          EnterAlternateScreen, LeaveAlternateScreen};
use ratatui::backend::CrosstermBackend;
use ratatui::Terminal;

fn main() -> anyhow::Result<()> {
    let cfg = config::Config::load()?;
    // Validate/build the provider registry BEFORE entering raw/alternate-screen
    // mode so configuration errors surface in a normal terminal.
    let providers = provider::build_registry(&cfg)?;
    enable_raw_mode()?;
    crossterm::execute!(io::stdout(), EnterAlternateScreen)?;
    let result = run_console(cfg, providers);
    // Restore the terminal fully: leave the alt screen, show the cursor, and
    // disable mouse capture (otherwise the shell receives raw SGR mouse
    // sequences — numbers bound with semicolons). "quit" exits cleanly, not as Err.
    let _ = crossterm::execute!(io::stdout(),
        LeaveAlternateScreen,
        crossterm::cursor::Show,
        crossterm::event::DisableMouseCapture);
    let _ = disable_raw_mode();
    result
}

fn run_console(cfg: config::Config, providers: provider::ProviderRegistry) -> anyhow::Result<()> {
    let backend = CrosstermBackend::new(io::stdout());
    let mut term = Terminal::new(backend)?;
    let mut app = tui::app::App::from_parts(cfg, providers)?;
    let res = app.run(&mut term);
    match &res {
        Err(e) if e.to_string() == tui::app::QUIT_MSG => Ok(()),
        Err(e) => {
            // Real failure: surface it above the fold before the alt screen drops.
            let msg = format!("exited with error: {e}");
            let _ = term.draw(|f| f.render_widget(ratatui::widgets::Paragraph::new(msg), f.area()));
            res
        }
        Ok(()) => res,
    }
}
```

## 11.13 External project browser (PB-01)

`b` opens a *Browse project directory* form, prefilled with the focused
session's existing local absolute directory when valid, otherwise Pinga's
current directory. It is directory selection only — never Git-root inference
and never a provider call. Enter launches; Esc cancels with no effects.
Relative input resolves against Pinga's cwd and is taken literally (no shell,
no `~`/variable expansion). Invalid or missing input explains the problem
without losing the user's edits. The feature works with zero providers, no
selection, an unavailable provider, or a missing session directory.

Launch roots external Yazi in the chosen directory: a new tmux window when
inside tmux, a suspend/foreground/restore run otherwise — reusing the existing
`LaunchRequest`/execution seams. Browser windows never enter session tracking,
pending-creation reconciliation, or provider operations. Failed terminal
preparation never launches, and restore/repaint always run after a foreground
return or error. Launch, tmux, spawn and suspend failures surface as a visible
error NEXT TO the still-editable form (modal and inline), and the user's edits
are kept.

Within Yazi, Markdown opens through **Glow** (`glow -p -- %s1`) and text/code
through **bat** (`bat --paging=always -- %s1`), both as `block`ing openers that
run in the SAME explorer window and block until the viewer exits back to Yazi —
no automatic new viewer windows. Viewers use a documented SINGLE-FILE policy
(`%s1` = first selected file): glow declares `cobra.MaximumNArgs(1)`, so
multi-select is never sent to a viewer. The `[open]` rules are fully
overridden so Yazi's defaults (external editors, `xdg-open`, archive
extractors) never precede our viewers; unsupported file types get a clear
refusal rather than executing the file or routing to an arbitrary app. The
profile is Pinga-owned and isolated for ALL THREE tools — Yazi via a private
`YAZI_CONFIG_HOME`, Glow via `GLOW_CONFIG_HOME` with a PUBLISHED minimal
`glow.yml` (an empty dir would fall through to the user's personal config) and
`GLOW_TUI=false` to neutralize ambient `GLOW_TUI=true`, bat via
`BAT_CONFIG_PATH` — plus a color-preserving pager pinned to `less -R` for both
viewers (`BAT_PAGER`/`PAGER`) with `LESS=""` so ambient `LESS` flags (e.g. `-F`
immediate exit) cannot dismiss the viewer. The profile lives under the runtime
state directory (`PINGA_STATE_DIR` for tests, scoped to browsing only; it never
relocates provider tracking). It works from an installed pinga binary, is never
repo-relative, and is never deleted while a tmux window could still reference
it. Profile files are published atomically under unique temp names, so
concurrent pinga instances never corrupt the profile. Pinga writes nothing to
the user's Yazi/Glow/bat config. A private `theme.toml` gives the directory
browser's normal-mode blocks pale green text on dark purple and pale purple
text on dark green. Only `[mode] normal_main/normal_alt` are overridden;
the default status layout is preserved.

Missing viewers (yazi, glow, bat, and the pinned pager `less`) are checked
before launch with actionable names. File-argument boundaries (spaces, quotes,
`$`, leading `-`, Unicode) are preserved: Pinga's outer
`LaunchRequest`/`serialize_launch` never uses a shell for user paths, and the
openers pass `--` before Yazi's `%s1` placeholder (which Yazi shell-quotes — the
shipped defaults rely on this). Directory input is taken literally, including
leading/trailing spaces, and non-UTF-8 canonical roots or profile paths are
rejected rather than lossily substituted. Yazi is a normal, writable file
manager — NOT a read-only sandbox — and the chosen directory is not a
filesystem confinement boundary.

### Verified tool contract (2026-09-24)

- **Yazi 26.9.1** (`https://yazi-rs.github.io/docs/configuration/yazi/` and
  `/configuration/overview`): `YAZI_CONFIG_HOME` selects the config directory;
  `[opener]` defines openers with `run` (placeholders `%s`, `%s1`, `%d`, `%%`),
  `block` (same-window blocking), `desc`, `orphan`, `for`; `[open]` rules use
  `url`/`mime` globs and `use`, with `prepend_rules`/`append_rules` mixing, and
  a full `rules = [...]` override. The shipped default rules route `text/*` to
  `$EDITOR`, images/media to `xdg-open`, and archives to extractors — our
  private profile overrides `rules` so those defaults never precede our
  viewers. The older `$@`-style syntax is NOT used. Shipped theme
  (`yazi-config/preset/theme-dark.toml`) puts the lower-right mode block on a
  bare `bg = "blue"` with the default white foreground; the private profile
  overrides `[mode] normal_main` only — verified in a PTY against the installed
  Yazi 26.9.1 that a `[status]` table hides the right-hand tab indicator, so
  `[status]` is not overridden. License: MIT
  (`https://github.com/sxyazi/yazi`).
- **Glow** (`https://github.com/charmbracelet/glow`, source-reviewed on current
  `main`, `main.go`): `-p` pager mode; pager is `$PAGER` or the default
  `less -r`; `cobra.MaximumNArgs(1)` — a single file only; config loading
  PREPENDS `GLOW_CONFIG_HOME` to the searched dirs (an empty dir does NOT
  isolate), `viper.AutomaticEnv` reads `GLOW_*` env (e.g. `GLOW_TUI`). License:
  MIT.
- **bat** (`https://github.com/sharkdp/bat`): `--paging=always` forces paging
  through its pager; `BAT_CONFIG_PATH`/`BAT_CONFIG_DIR` select a private config
  path; `BAT_PAGER` pins the pager. Whether bat refuses binary files is NOT
  claimed without an executable test. License: MIT OR Apache-2.0.
- **less** — the pinned pager (`less -R` preserves raw ANSI color for both
  viewers; ambient `LESS` flags are neutralized). License: GPL-2.0-or-later
  (less is a system utility; checked early, never installed by Pinga).

Only bat was present on PATH during architect inspection; a real Yazi/Glow/less
smoke test is explicitly NOT claimed without installing them — it is listed as
PENDING in the report. Install instructions for this Arch host plus named
release binaries are recorded in `docs/handoffs/PB-01-report.md`; no system
install or global config write is performed by this batch.

## 12. Event flow & refresh

- Snapshot-pull: every `refresh_secs/4` of input idle, or immediately after
  handoffs/renames. Both providers re-list; the two columns re-render. Sorting
  is by `updated_ms` desc, newest on top.
- Auto-rename (R5) is not implemented: `o` toggles the configuration flag,
  but no event-loop path acts on it. The former "3 min old + default title"
  description was a proposed policy, not current behavior.
- Manual rename (`r`) preloads the displayed title. `s` opens a rename editor
  prefilled with a suggestion seeded from the current title, slug, or ID;
  conversation text is not fetched. Applying either editor writes the rename
  and refreshes the lists. Recent-user-text suggestions (R4) remain incomplete.
- Handoff durability: after R10 returns, `refresh()` runs because the agent
  executed commands and the session lists changed underneath us.

## 13. Acceptance & test plan

The rows below are planned acceptance checks. PA-01 Stages 1–3 added automated
tests (identity, registry, capabilities, structured launches, provider-owned
evidence, adoption policy, serialization, terminal restoration, the real
evidence collector, application-level orchestration via injected
launcher/store/terminal seams, configurable instances/factories, and the
versioned tracking store + migration); the older provider/naming rows remain
planned, not yet automated — a passing `cargo test` alone does not establish
their coverage.

| Area | Test | Gate |
|------|------|------|
| Identity (model) | `ProviderId` accepts the documented syntax and rejects invalid IDs; distinct providers with the same native id yield different `SessionKey`s; empty native id is rejected; accessors reflect validation | `cargo test` |
| Config (core::config) | absent config uses defaults; explicit `providers = []` is authoritative-empty; two instances of one type with distinct options; duplicate IDs (incl. disabled) rejected; blank labels rejected; disabled entries still validated (unknown type/option/id are errors even when disabled); invalid TOML / missing explicit `$PINGA_CONFIG` are errors, not silent defaults | `cargo test` |
| Factories (prov::mod) | type-key→factory registry; unknown types/options rejected; explicit opencode `url` and absolute codex `home` required; `build_registry` with explicit providers builds in order, skips disabled, and `builtin_registry` preserves the legacy defaults | `cargo test` |
| Registry (prov::mod) | three fake providers register in order; duplicate ID fails without replacement/reordering; unknown lookup is absent | `cargo test` |
| Dispatch + unsupported | resume/create/rename/match reach the intended fake; unsupported is an identifiable category distinct from operational failure; capabilities agree | `cargo test` |
| Cross-provider identity | a session belonging to another instance is rejected before any side effect; a created session with an empty native key is refused at the boundary | `cargo test` |
| Composition (prov::mod) | `builtin_registry` preserves default IDs/order/types; a non-default OpenCode URL and a temporary Codex home fixture flow into the built-in adapters | `cargo test` |
| Adapter evidence (opencode/codex) | Stage 2 evidence + endpoint-validation tables and integrated adapter→reconciliation retention all retained | `cargo test` |
| Serialization | POSIX-sh serialization preserves hostile args/env/cwd; NUL rejected anywhere; invalid env names rejected | `cargo test` |
| tmux boundary | `open_in_tmux` invokes POSIX `sh` explicitly via tmux argv, never the default shell | `cargo test` |
| Terminal restoration | `App::suspend_for` behind an injectable terminal seam; refuses launch after failed suspension; always restores; surfaces combined errors | `cargo test` |
| Adoption policy | `decide_open` requires confirmed evidence for a tracked window, dedups, and covers all refusal/force cases | `cargo test` |
| Process collector | `parse_cmdline` preserves empty args, rejects truncated/non-UTF-8; `collect_evidence` aggregates panes and marks incomplete scans | `cargo test` |
| Tracking store (core::tracking) | **exact one-read legacy snapshot + durable conflict-checked backup (conflicting backup aborts, identical retry safe, write failure aborts without v2)**; persisted invariants validated on decode+commit (nonzero unique ids, next_id > max, valid provider ids, nonempty native ids); read failures surfaced not hidden; MemStore allocates ids and validates | migration maps legacy 0→opencode/1→codex, empty ids→pending, unknown→opaque; exact backup bytes; idempotent restart; legacy never rewritten once v2 exists; malformed legacy/unsupported version/read/lock failures abort without replacing data or the last-good view; monotonic record ids; two isolated file stores interleave concurrent updates without overwrite; stale results preserve records added since inspection | `cargo test` |
| App viewport (tui::app) | **selection preserved by SessionKey across reorder; per-view scroll used in render + mouse; tracking failure reports the launched window; foreground launch-to-create returns failure honestly** | zero providers render an empty state and quit works; 1/2/3 providers refresh into per-provider views; focus wraps across the sequence and the viewport keeps focus visible; at most two columns on wide terminals, one on narrow; per-provider failures stay local; identical native IDs across providers never cross-track; deferred plans keep their provider after focus change; TestBackend render assertions | `cargo test` |
| Lifecycle (tui::app) | **reconcile computes plans outside the lock and applies only to the exact observed record id/window/state (concurrent replacements survive); startup eligibility keyed by record id; pendings preserved while provider unavailable; codex launches carry CODEX_HOME and two real codex homes never cross-confirm** | pending launches persisted after successful window creation, visible after restart, and resolved to a known session only on unique confirmed evidence; interrupted state stable across several polls (not dropped on a second dead-window poll); later opens never inherit startup eligibility; local unobserved creations merge until first observed | `cargo test` |
| Third fake provider e2e | a `third` fake completes list/create/resume/rename/tracking through generic core paths with no application branch or extra column | `cargo test` |
| Provider (opencode/codex) | planned: parse a captured `GET /session` fixture; rename probes routes; codex join full rollout UUIDs, filter seeds, inherit ancestors, stable sort, legacy fallback | `cargo test` |
| Naming | planned: heuristic caps ≤ 40; remote path mocked (deny offline) | `cargo test` |
| Handoff (tmux) | manual on eris: double-click or Enter → new window in `main` holds the attach TUI; re-open selects the same window, never a duplicate; single click does not open | manual |
| Handoff (terminal) | manual: run pinga outside tmux, open a session, quit it, pinga redraws | manual |
| Living integration | `make tangle && cargo check && cargo test` must pass | CI gate |
| Readability | eyeball on eris terminal (truecolor); then dim-fg grid check §14 | manual |

## 14. Palette appendix (R11)

Swatch set (RGB on the deep plum `#241f35`):

| token | #rgb | role | contrast on BG |
|-------|------|------|----------------|
| `FG` | `#e0d4f5` | body text (lavender) | ≈ 12:1 ✓ |
| `DIM` | `#9d93b8` | metadata | ≈ 5.2:1 ✓ |
| `SURFACE` | `#302a47` | row/card fills | — |
| `BORDER` | `#4e4470` | idle borders | — |
| `FOCUS` | `#a06cd5` | focused border / opencode brand | ≈ 4.4:1 (accent) |
| `SELECTED_BG` | `#574a78` | selected row fill | with `FG` ≈ 8:1 ✓ |
| `MINT` | `#66d99b` | codex brand | ≈ 8:1 ✓ |
| `GREEN_DIM` | `#3f8f63` | codex metadata | ≈ 3.6:1 (non-tiny text) |
| `WARN` | `#e8b46b` | transient errors | ≈ 6.5:1 ✓ |

Rules: never put strong accents on large text bodies (use `FG`); use the
columns' brands only for borders, selection, and the column headers; reserve
`WARN` for the transient error line. Truecolor is required — fall back to the
nutty 256-color equivalents (`bg=236 surface, 60 border, 141 focus, 114 mint`)
only for `TERM` without color support.

## 15. Open questions / to-pin

1. **opencode rename route.** Which exact compat verb/path it is
   (`POST|PATCH|PUT /session/<id>(/rename)`) — still unpinned; investigate by
   sending one distinct title per candidate and re-reading `GET /session`
   (§5.1 already has the harness). Wrap the heuristic (try-all, verify) so a
   future opencode release that adds a real `/api/…/rename` slot maps to it.
2. **Codex storage migration implemented; fallback and resume remain open.**
   Listing and primary renaming use SQLite (§5.2). Decide how to report a
   failed SQLite rename instead of accepting a legacy append that listing
   ignores. Review title-based resume when several threads inherit one label.
3. **Auto-rename trigger implementation.** The setting currently has no effect.
   "3 min old + default title" remains a proposed policy; a configurable
   `auto_rename_min_age` does not yet exist.
4. **RESOLVED: select-on-click / open-on-double.** A single click selects
   only (leaving the mouse free for rename, column focus, etc.); a
   double-click (same cell, ≤ 500 ms) or `Enter` opens — the pattern lazygit
   uses, and it lets you tap rows without spawning windows. Wheel scroll is
   unchanged. D8 keeps it one window per session.
5. **pid-based session liveness.** `active` is best-effort; true liveness per
   session may need opencode's SSE event stream or `codex app-server` control —
   defer until the console proves annoying without it. Empirically this opencode
   build returns **no** `active` field, so the D8 `active` refusal is inert and
   cross-session/terminal opencode attachment is undetectable (fresh window
   allowed) — same gap codex always had, now the rule for both.
6. **Empty-thread visibility.** `has_conversation` hides seed threads (vscode
   spawns an empty thread, resume closes it immediately). If a user legitimately
   reuses seeds, switch to surfacing them with a muted "(empty)" marker instead
   of hiding them.

## 16. Rules the implementation must not violate

1. **One server per session id.** All opencode attach commands are client-mode
   against the configured shared server. Never emit a bare `opencode …` that
   could spawn a second server on a live id (split-brain, 2026-09-16).
2. **Never read opencode's SQLite while the server is attached.** HTTP API only.
3. **Verify renames.** Any "200 OK" from opencode is suspect (SPA fallback) —
   rename must re-read and confirm the title changed.
4. **The whole stack stays open source** (licenses in §4).
5. **The tangle is the build.** If a change isn't representable in the
   blueprint, the blueprint changes first; `make tangle` follows.

## 17. README / docs

`blueprint.html` (via `make weave`) is the readable export; this file is the
source. Decisions D1–D8 live beside the implementation here. Project memory
and additional ADRs are indexed in `.memory/wiki/index.md`; historical log
entries describe behavior at their recorded dates and may be superseded.

The forthcoming provider refactor is specified in
[PA-01](docs/provider-architecture.md). Its
[Stage 1 task](docs/handoffs/PA-01-stage-1.md) is an implementation assignment,
not a description of already implemented behavior. Executable changes still
belong in this blueprint's chunks and their accompanying prose.
