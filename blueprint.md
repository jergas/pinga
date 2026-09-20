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

## 5. Verified integration surface (recon, eris 2026-09-17)

Everything below was probed **live**; treat it as the contract pinga depends on.

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
    six restored the original value exactly). **To-pin at implementation time.**
  - Catch: unhandled POST routes return the SPA `index.html` (HTTP 200!) — a
    rename that "succeeds" against a wrong path changes nothing. Always verify
    by re-reading `GET /session`.
  - Storage: `~/.local/share/opencode/opencode.db` (SQLite, `session` table with
    `title`, `agent`, `model`, `time_created`, `time_updated`, token/cost
    columns). Reading it **live on an attached server risks racing** the
    server's own writes — use the HTTP API, never the DB file.
- Attach client: `opencode attach http://127.0.0.1:4096 -s <id>` (client TUI;
  exits cleanly when the user quits session view — good for R10).

### 5.2 codex (standalone 0.154.0)

- Home: `~/.codex/`. Thread names live in **`~/.codex/session_index.jsonl`**,
  one JSON object per line: `{"id":"<uuid>","thread_name":"<name>","updated_at":"RFC3339"}`
  — appended (codex appends, does not rewrite); last entry for an id wins. The
  resume picker and `codex resume <name>` read this file.
- Rollouts: `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl` — uuid is
  the thread id; useful for sessions that have no `thread_name` yet (derive the
  label from the first user line) and for created/updated timestamps (file mtime
  fallback).
- Resume: `codex resume <name-or-uuid>` runs the codex TUI against that thread.
- Rename from outside: append `{"id","thread_name","updated_at"}` to
  `session_index.jsonl` (O(1), matches codex's own writer). This is the
  mechanism the CLI's `/rename` uses (upstream "conversation naming" work), and
  it is what the picker/name-resume consult.

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
                       │  base_url + key + model      │◄── seed = recent user text
                       └──────────────┬───────────────┘
                                      │ suggest(title) / rename(sess,title)
┌──────────┐  HTTP /session  ┌────────▼───────────────────────────┐
│opencode  │◄── GET/POST ────│  provider::opencode               │
│ :4096    │                 │  list / rename / attach_cmd       │
└──────────┘                 └───────────────┬───────────────────┘
                             provider trait  │ Session list
┌──────────┐  files:          ┌──────────────▼───────────────────┐
│ codex    │◄─session_index   │  provider::codex                 │
│ ~/.codex │   + rollouts     │  list / rename(append) / attach  │
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

1. **providers** — turn the §5 surfaces into a uniform `Provider` trait;
2. **naming** — turn a session's recent text into a short title;
3. **tui + launcher** — present, navigate, and hand off.

The refresh loop is a simple poll: on an interval (and right after any
return-to-console or rename) every provider's `list()` is re-run; both columns
re-render from the latest snapshots. No threads, no async — `crossterm`
`event::poll(timeout)` doubles as the tick so input stays responsive.

## 7. Module map (chunks → files)

| Chunk | File | Responsibility |
|-------|------|----------------|
| `pkg::manifest` | `Cargo.toml` | deps, metadata |
| `core::config` | `src/config.rs` | config load, env overrides |
| `core::model` | `src/model.rs` | `Session`, `ProviderKind` + derived display helpers |
| `prov::mod` | `src/provider/mod.rs` | `Provider` trait + dispatch enum |
| `prov::opencode` | `src/provider/opencode.rs` | §5.1 adapter (HTTP) |
| `prov::codex` | `src/provider/codex.rs` | §5.2 adapter (files) |
| `name::engine` | `src/naming.rs` | Ollama/keyed suggestion + heuristic fallback |
| `core::launcher` | `src/launcher.rs` | tmux detection, new-window, tty handoff |
| `tui::theme` | `src/tui/theme.rs` | purple/green palette (§14) |
| `tui::app` | `src/tui/app.rs` | the console: layout, keys, mouse, handoff loop |
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
  `GET /session`; rename via the pinned compat route (§5.1) and verify by
  re-reading.
- **D3 codex rename = append to `session_index.jsonl`.** Matches upstream's own
  semantics. If codex someday locks that file, fall back to the app-server
  control socket (`~/.codex/app-server-control/…sock`) with the same JSON
  contract.
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
- **D7 Literate workflow = `make tangle` gate.** `src/` is derived; CI runs
  `cargo check`/`clippy`/`test` against tangled output so the document and code
  can't diverge silently.
- **D8 One window per session, adopt-or-refuse.** Re-opening never spawns a
  duplicate. Priority, per provider: (1) a tmux window pinga created (tracked
  by window id) is selected again; (2) an untracked same-session window whose
  process argv carries the session marker — `-s <id>` in `opencode attach`, or
  the resume name in `codex resume <name>` — is adopted when unambiguous (the
  pane's process tree is walked, so a TUI launched in a shell counts); (3)
  opencode-only fallback: **no `-s` in the argv**, but exactly one `opencode
  attach` window exists and this session is the newest-updated (`opencode`
  bare `attach` binds to the most recent session) -> adopt it; several attach
  windows, or one attached to a different session, are refused — this
  opencode build exposes **no** per-session attachment signal, so anything
  cross-terminal is undetectable and deliberately opens a fresh window
  (documented gap); (4) otherwise a fresh window is created and tracked.
  `f` forces past any refusal. codex has no liveness signal at all: only the
  argv marker can adopt an already-open codex thread. Mouse: single
  click selects, double-click (same cell, ≤ 500 ms) opens; `Enter` always
  opens. Double-open is separate from repeat-open: the guard above is also
  enforced for double-clicks.

## 9. Data contracts

### 9.1 `Session` (provider-agnostic)

```text
kind        Opencode | Codex
id          ses_… | <codex thread uuid>
title       Option<String>        # best label (codex: thread_name first)
slug        Option<String>        # opencode only
directory, agent, model: Option<String>
created_ms, updated_ms: Option<u64>
active      bool
```

`display_title()`: `title` → `slug` → bounded `id`. Providers never invent
facts; every field maps 1:1 to a verified source (§5).

### 9.2 `Provider`

```text
kind()                 -> ProviderKind
list()                 -> Result<Vec<Session>>
rename(&Session,&str)  -> Result<()>   # after rename: re-list to confirm
attach_command(&Session)-> String      # shell command the launcher runs
```

### 9.3 `NameEngine`

```text
suggest(seed: &str) -> String   # ≤ 40 chars, no quotes/newlines
configured?  base_url + key + model  → remote path
otherwise    call heuristic(seed)     → kebab of first ~4 words
```

The suggestion prompt (system turn) is:
"Answer with a short, descriptive session title, 2-6 words. No quotes, no
markdown, no punctuation explosion." + one user turn with the seed.

## 10. Handoff semantics (R9/R10)

`launcher::open(session, cmd, label)`:

```text
if in_tmux():
    session_name = tmux display-message -p '#{S}'            # current
    tmux new-window -t <session_name> -n <label> '<cmd>'     # R9
else:
    suspend()          # LEAVE alternate screen + disable raw  (R10)
    run_in_foreground('<cmd>')  # sh -c, inherited stdio; blocks
    restore()          # re-enter alt screen + raw + redraw
    refresh()          # lists may have changed under us
```

The suspend inside ratatui is just: `disable_raw_mode()` + `LeaveAlternateScreen`
on `io::stdout`, run the child with `Stdio::inherit()`, wait for `exit`, then
`EnableAlternateScreen` + `enable_raw_mode()` and redraw. This is exactly the
"pass control, return when it exits" behaviour of R10 with no exec weirdness:
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
ureq = { version = "2", default-features = false, features = ["json"] }
```

### 11.2 Configuration (`core::config`)

Reading order: default `~/.config/pinga/config.toml` (parsed leniently), then
environment overrides. `PINGA_API_KEY` is the primary secret channel so the
key never needs to live in the repo the keyboard trusts least.

``` {.rust #core-config path="src/config.rs"}
use serde::Deserialize;
use std::path::PathBuf;

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct Config {
    pub opencode_url: String,          // shared opencode server base URL
    pub codex_home: PathBuf,           // ~/.codex
    pub ollama_base_url: Option<String>, // local engine (no key)
    pub ollama_model: Option<String>,
    pub api_base_url: Option<String>,  // keyed OpenAI-compatible engine
    pub api_model: Option<String>,
    pub api_key: Option<String>,
    pub auto_rename: bool,             // auto-suggest names for newer sessions
    pub refresh_secs: u64,
    pub theme: String,                 // "magic" (the purple/green palette)
}

impl Default for Config {
    fn default() -> Self {
        let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("."));
        Self {
            opencode_url: "http://127.0.0.1:4096".into(),
            codex_home: home.join(".codex"),
            ollama_base_url: Some("http://127.0.0.1:11434".into()),
            ollama_model: Some("llama3.2".into()),
            api_base_url: None,
            api_model: None,
            api_key: None,
            auto_rename: false,
            refresh_secs: 5,
            theme: "magic".into(),
        }
    }
}

impl Config {
    pub fn load() -> Self {
        let path = std::env::var("PINGA_CONFIG")
            .map(PathBuf::from)
            .unwrap_or_else(|_| dirs::config_dir().unwrap_or_default().join("pinga/config.toml"));
        let raw = std::fs::read_to_string(&path).unwrap_or_default();
        let mut cfg: Config = toml::from_str(&raw).unwrap_or_default();
        if let Ok(k) = std::env::var("PINGA_API_KEY") { cfg.api_key = Some(k); }
        if let Ok(u) = std::env::var("PINGA_OPENCODE_URL") { cfg.opencode_url = u; }
        if let Ok(m) = std::env::var("PINGA_MODEL") {
            if cfg.ollama_base_url.is_some() { cfg.ollama_model = Some(m.clone()); }
            if cfg.api_base_url.is_some() { cfg.api_model = Some(m); }
        }
        cfg
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
```

### 11.3 The session model (`core::model`)

A tiny, provider-agnostic view. `display_title`, `short_id`, and `age` keep the
TUI free of formatting policy.

``` {.rust #core-model path="src/model.rs"}
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProviderKind { Opencode, Codex }

impl ProviderKind {
    pub fn label(self) -> &'static str {
        match self { ProviderKind::Opencode => "opencode", ProviderKind::Codex => "codex" }
    }
}

#[derive(Debug, Clone)]
pub struct Session {
    pub kind: ProviderKind,
    pub id: String,
    pub title: Option<String>,
    pub slug: Option<String>,
    pub directory: Option<String>,
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
```

### 11.4 The provider trait (`prov::mod`)

`Provider` is the seam that keeps §5 knowledge inside two adapters and the
console free of opencode/codex specifics. `attach_command` returns a raw shell
command the launcher runs (R9/R10) — constructors bake in §5/§5.4 rules
(client-mode opencode attach against the shared server; codex resume by name).

``` {.rust #prov-mod path="src/provider/mod.rs"}
pub mod codex;
pub mod opencode;

use crate::model::{ProviderKind, Session};

pub trait Provider: Send + Sync {
    fn kind(&self) -> ProviderKind;
    fn list(&self) -> anyhow::Result<Vec<Session>>;
    fn rename(&self, session: &Session, title: &str) -> anyhow::Result<()>;
    /// Shell command that attaches to this session (client-mode, one server rule).
    fn attach_command(&self, session: &Session) -> String;
    /// Create a fresh session server-side and return it. Providers that cannot
    /// create sessions programmatically (codex) default to an error; the app
    /// routes those to a `cd <dir> && <bin>` window instead.
    fn create(&self, _name: &str, _dir: &str) -> anyhow::Result<Session> {
        Err(anyhow::anyhow!("{} cannot create a session programmatically",
                            self.kind().label()))
    }
}

pub enum AnyProvider {
    Opencode(opencode::OpencodeProvider),
    Codex(codex::CodexProvider),
}

impl Provider for AnyProvider {
    fn kind(&self) -> ProviderKind {
        match self {
            AnyProvider::Opencode(p) => p.kind(),
            AnyProvider::Codex(p) => p.kind(),
        }
    }
    fn list(&self) -> anyhow::Result<Vec<Session>> {
        match self {
            AnyProvider::Opencode(p) => p.list(),
            AnyProvider::Codex(p) => p.list(),
        }
    }
    fn rename(&self, s: &Session, t: &str) -> anyhow::Result<()> {
        match self {
            AnyProvider::Opencode(p) => p.rename(s, t),
            AnyProvider::Codex(p) => p.rename(s, t),
        }
    }
    fn attach_command(&self, s: &Session) -> String {
        match self {
            AnyProvider::Opencode(p) => p.attach_command(s),
            AnyProvider::Codex(p) => p.attach_command(s),
        }
    }
    fn create(&self, name: &str, dir: &str) -> anyhow::Result<Session> {
        match self {
            AnyProvider::Opencode(p) => p.create(name, dir),
            AnyProvider::Codex(p) => p.create(name, dir),
        }
    }
}
```

### 11.5 opencode adapter (`prov::opencode`)

**Only ever talks HTTP to the shared server.** `GET /session` is the list
source. Rename uses the empirically-pinned compat route (probe all six forms,
§5.1) and then re-reads the session to confirm the write actually landed —
because a miss returns the SPA HTML with HTTP 200 and silently does nothing.

``` {.rust #prov-opencode path="src/provider/opencode.rs"}
use anyhow::{anyhow, Result};
use serde_json::Value;
use std::time::Duration;
use ureq::{Agent, AgentBuilder};

use crate::model::{ProviderKind, Session};

pub struct OpencodeProvider {
    base: String,
    agent: Agent,
}

impl OpencodeProvider {
    pub fn new(base: &str) -> Self {
        Self {
            base: base.trim_end_matches('/').to_string(),
            agent: AgentBuilder::new().timeout(Duration::from_secs(5)).build(),
        }
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
                kind: ProviderKind::Opencode,
                id,
                title,
                slug,
                directory,
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
        Ok(Some(Self::from_value(body)))
    }

    fn from_value(v: Value) -> Session {
        Session {
            kind: ProviderKind::Opencode,
            id: v["id"].as_str().unwrap_or_default().to_string(),
            title: v.get("title").and_then(|t| t.as_str()).map(str::to_string),
            slug: v.get("slug").and_then(|t| t.as_str()).map(str::to_string),
            directory: v.get("directory").and_then(|t| t.as_str()).map(str::to_string),
            agent: v.get("agent").and_then(|t| t.as_str()).map(str::to_string),
            model: v.get("model").and_then(|t| t["id"].as_str()).map(str::to_string),
            created_ms: v["time"]["created"].as_u64(),
            updated_ms: v["time"]["updated"].as_u64(),
            active: false,
        }
    }

    fn attach_command(&self, s: &Session) -> String {
        // Client-mode attach to the ONE shared server (never a bare opencode).
        format!("opencode attach {} -s {}", self.base, s.id)
    }

    /// Create a fresh session on the shared server. The server binds sessions
    /// to its own cwd (a "directory" in the payload is not honoured for the
    /// global project), so the directory is accepted for symmetry but the
    /// session lives wherever the server lives. Title lands directly.
    fn create(&self, name: &str, dir: &str) -> Result<Session> {
        let payload = serde_json::json!({ "directory": dir, "title": name });
        let body: Value = self.agent.post(&format!("{}/session", self.base))
            .send_json(&payload)?
            .into_json()?;
        if body.get("id").and_then(|i| i.as_str()).unwrap_or_default().is_empty() {
            return Err(anyhow!("POST /session returned no id"));
        }
        Ok(Self::from_value(body))
    }
}

impl crate::provider::Provider for OpencodeProvider {
    fn kind(&self) -> ProviderKind { ProviderKind::Opencode }
    fn list(&self) -> Result<Vec<Session>> { self.list() }
    fn rename(&self, s: &Session, t: &str) -> Result<()> { self.rename(s, t) }
    fn create(&self, name: &str, dir: &str) -> Result<Session> { self.create(name, dir) }
    fn attach_command(&self, s: &Session) -> String { self.attach_command(s) }
}
```

### 11.6 codex adapter (`prov::codex`)

Reads `session_index.jsonl` (thread names, newest append wins) and scans the
rollout tree for threads that have no name yet. Renaming is an append to the
same index file — codex's own contract. `attach_command` prefers the name
(when one exists) for `codex resume`.

``` {.rust #prov-codex path="src/provider/codex.rs"}
use anyhow::{Context, Result};
use serde_json::Value;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::model::{ProviderKind, Session};

pub struct CodexProvider { home: PathBuf }

impl CodexProvider {
    pub fn new(home: &Path) -> Self {
        Self { home: home.to_path_buf() }
    }

    fn index_path(&self) -> PathBuf { self.home.join("session_index.jsonl") }

    fn list(&self) -> Result<Vec<Session>> {
        let mut names: HashMap<String, (String, Option<u64>)> = HashMap::new();
        // session_index.jsonl: {"id","thread_name","updated_at"} appended lines
        if let Ok(raw) = fs::read_to_string(self.index_path()) {
            for line in raw.lines() {
                let Ok(v) = serde_json::from_str::<Value>(line) else { continue };
                if let (Some(id), Some(name)) = (v["id"].as_str(), v["thread_name"].as_str()) {
                    let updated = v["updated_at"].as_str().and_then(parse_rfc3339_ms);
                    names.insert(id.to_string(), (name.to_string(), updated));
                }
            }
        }
        // rollout tree provides id + fallback timestamps + first-prompt seed
        let mut out: Vec<Session> = Vec::new();
        for rollout in self.rollouts()? {
            // Skip seed threads: sessions spawned empty by the vscode originator
            // are a single session_meta line, and codex's resume of an empty
            // thread ends the TUI immediately (observed on eris 2026-09-17).
            if !has_conversation(&rollout) { continue; }
            let id = rollout_title_id(&rollout).unwrap_or_default();
            let updated = names.get(&id).and_then(|(_, u)| *u)
                .or_else(|| file_mtime_ms(&rollout));
            let title = names.get(&id).map(|(n, _)| n.clone());
            out.push(Session {
                kind: ProviderKind::Codex,
                id,
                title,
                slug: None,
                directory: None,
                agent: None,
                model: None,
                created_ms: None,
                updated_ms: updated,
                active: false,
            });
        }
        out.sort_by_key(|s| std::cmp::Reverse(s.updated_ms.unwrap_or(0)));
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
        let line = serde_json::json!({
            "id": s.id,
            "thread_name": title,
            "updated_at": rfc3339_now(),
        });
        use std::io::Write;
        let mut f = fs::OpenOptions::new()
            .create(true).append(true).open(self.index_path())
            .with_context(|| format!("open {}", self.index_path().display()))?;
        writeln!(f, "{line}")?;
        Ok(())
    }

    fn attach_command(&self, s: &Session) -> String {
        match &s.title {
            Some(name) => format!("codex resume {}", shell_quote(name)),
            None => format!("codex resume {}", s.id),
        }
    }
}

fn parse_rfc3339_ms(s: &str) -> Option<u64> {
    // RFC3339 "2026-09-08T10:39:38.49962476Z" -> epoch millis (best effort, no chrono dep)
    let t = time_ish::parse(s).ok()?;
    Some(t.to_ms())
}

// Minimal RFC3339 -> epoch-ms parser (keeps deps to zero; swap for chrono if it bites).
mod time_ish {
    pub struct Instantish(u64);
    pub fn parse(s: &str) -> Result<Instantish, &'static str> {
        let (dt, _z) = s.split_once('Z').or_else(|| s.split_once('z')).ok_or("tz")?;
        let (date, time) = dt.split_once('T').ok_or("t")?;
        let mut it = date.split('-'); let y: u32 = it.next().ok_or("y")?.parse().ok().ok_or("y")?;
        let mo: u32 = it.next().ok_or("m")?.parse().map_err(|_| "m")?;
        let d: u32 = it.next().ok_or("d")?.parse().map_err(|_| "d")?;
        let mut it = time.split(':');
        let h: u32 = it.next().ok_or("h")?.parse().map_err(|_| "h")?;
        let mi: u32 = it.next().ok_or("min")?.parse().map_err(|_| "min")?;
        let sec_parts: Vec<&str> = it.next().ok_or("s")?.split('.').collect();
        let s: u32 = sec_parts[0].parse().map_err(|_| "s")?;
        let ms: u64 = if sec_parts.len() > 1 { format!("{:.0}", sec_parts[1].chars().take(3).collect::<String>().parse::<f64>().unwrap_or(0.0)).parse().unwrap_or(0) }
                      else { 0 };
        let days = days_from_civil(y, mo, d);
        let secs = days as u64 * 86400 + (h as u64 * 3600 + mi as u64 * 60 + s as u64);
        Ok(Instantish(secs * 1000 + ms))
    }
    impl Instantish { pub fn to_ms(&self) -> u64 { self.0 } }

    fn days_from_civil(y: u32, mo: u32, d: u32) -> i64 { /* Howard Hinnant's algorithm */
        let y = y as i64 - (mo <= 2) as i64;
        let era = y.div_euclid(400);
        let yoe = y - era * 400;
        let mp = (mo + 9) % 12;
        let doy = (153 * mp as i64 + 2) / 5 + d as i64 - 1;
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
        era * 146097 + doe - 719468
    }
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
    // rollout-2026-09-08T03-58-22-01a08074-….jsonl  -> last dash segment is the thread id
    let stem = p.file_stem()?.to_string_lossy();
    stem.rsplit('-').next().map(str::to_string)
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

fn shell_quote(s: &str) -> String {
    if s.chars().all(|c| c.is_alphanumeric() || c == '-' || c == '_' || c == ' ') {
        s.to_string() // needless quoting only when needed
    } else {
        format!("'{}'", s.replace('\'', "'\\''"))
    }
}

impl crate::provider::Provider for CodexProvider {
    fn kind(&self) -> ProviderKind { ProviderKind::Codex }
    fn list(&self) -> Result<Vec<Session>> { self.list() }
    fn rename(&self, s: &Session, t: &str) -> Result<()> { self.rename(s, t) }
    fn attach_command(&self, s: &Session) -> String { self.attach_command(s) }
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

``` {.rust #core-launcher path="src/launcher.rs"}
use anyhow::{anyhow, Result};
use std::process::{Command, Stdio};

/// True when this process runs under tmux (R6/R9). tmux sets $TMUX.
pub fn in_tmux() -> bool {
    match std::env::var_os("TMUX") {
        Some(v) => !v.is_empty(),
        None => false,
    }
}

fn current_tmux_session() -> Result<String> {
    let out = Command::new("tmux").args(["display-message", "-p", "#{S}"]).output()?;
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

/// R9: open a session in a NEW tmux window of the current tmux session,
/// returning the new window's id (@NNN) so D8 can select it on re-open.
pub fn open_in_tmux_returning(label: &str, command: &str) -> Result<String> {
    let session = current_tmux_session()?;
    let out = Command::new("tmux")
        .args(["new-window", "-P", "-F", "#{window_id}", "-t", &session, "-n", label, command])
        .output()?;
    let id = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if id.is_empty() { return Err(anyhow!("tmux new-window failed")); }
    Ok(id)
}

/// D8: bring an existing tmux window (by id, e.g. `@123` or `main:2`) to the
/// foreground so "take me to the already-open one" works.
pub fn tmux_select_window(win: &str) -> Result<()> {
    let status = Command::new("tmux").args(["select-window", "-t", win])
        .stdout(Stdio::null()).stderr(Stdio::inherit())
        .status()?;
    if !status.success() { return Err(anyhow!("tmux select-window failed")); }
    Ok(())
}

/// D8: is this window id still alive anywhere (tracked windows can be killed
/// behind pinga's back)? Cheap grep over `list-windows -a`.
pub fn tmux_window_alive(win: &str) -> Result<bool> {
    let out = Command::new("tmux").args(["list-windows", "-a", "-F", "#{window_id}"]).output()?;
    let hay = String::from_utf8_lossy(&out.stdout);
    Ok(hay.lines().any(|line| line.trim() == win))
}

/// D8: find a window in the CURRENT tmux session that is already running this
/// session. We walk each window's pane process tree looking for `marker` —
/// the session id as it appears in `opencode attach <url> -s <id>`, or the
/// resume name in `codex resume <name>`. Argv matching (not window names, which
/// default to "codex"/"opencode") lets us adopt sessions the user opened by
/// hand. Adopted only when exactly one window matches; ambiguous -> not found.
pub fn find_open_window(marker: &str) -> Result<Option<String>> {
    let session = current_tmux_session()?;
    let out = Command::new("tmux").args(["list-windows", "-t", &session,
        "-F", "#{window_id}\t#{pane_pid}"]).output()?;
    let mut found: Vec<String> = Vec::new();
    for line in String::from_utf8_lossy(&out.stdout).lines() {
        let mut it = line.splitn(2, '\t');
        let (Some(id), Some(pid)) = (it.next(), it.next()) else { continue };
        if pid_runs_needles(pid.trim(), &[marker])? {
            found.push(id.trim().to_string());
        }
    }
    Ok(match found.len() {
        1 => found.pop(),   // exactly one -> adopt
        _ => None,          // none, or ambiguous -> treat as not found
    })
}

/// D8 fallback: an `opencode attach` window whose argv carries no `-s <id>`
/// (e.g. `opencode attach http://localhost:4096`) still counts as "this server
/// is open in that window". Returns ALL matches; the caller decides adopt vs
/// refuse on count + recency, since the server exposes no per-session
/// attachment signal.
pub fn find_opencode_attach_windows() -> Result<Vec<String>> {
    let session = current_tmux_session()?;
    let out = Command::new("tmux").args(["list-windows", "-t", &session,
        "-F", "#{window_id}\t#{pane_pid}"]).output()?;
    let mut found: Vec<String> = Vec::new();
    for line in String::from_utf8_lossy(&out.stdout).lines() {
        let mut it = line.splitn(2, '\t');
        let (Some(id), Some(pid)) = (it.next(), it.next()) else { continue };
        if pid_runs_needles(pid.trim(), &["opencode", "attach"])? {
            found.push(id.trim().to_string());
        }
    }
    Ok(found)
}

/// -1b: is a specific window currently RUNNING this session (its pane argv
/// carries every `needle`)? Distinguishes "session still open" from "session
/// closed but the window remained" — e.g. after `/exit`, the pane drops back
/// to a shell, so the session should stop being tracked rather than be flagged
/// as interrupted.
pub fn window_runs(win: &str, needles: &[&str]) -> Result<bool> {
    let out = Command::new("tmux").args(["list-panes", "-t", win, "-F", "#{pane_pid}"]).output()?;
    for pid in String::from_utf8_lossy(&out.stdout).lines() {
        let pid = pid.trim();
        if pid.is_empty() { continue; }
        if pid_runs_needles(pid, needles)? { return Ok(true); }
    }
    Ok(false)
}

/// Does `pid` (or any descendant, bounded) have every `needle` in its argv?
/// Handles sessions launched in an interactive shell, where the pane's process
/// is the shell and the attach TUI is a child. Depth is capped so a long-lived
/// shell's process tree can't balloon the walk.
fn pid_runs_needles(pid: &str, needles: &[&str]) -> Result<bool> {
    let mut stack: Vec<(String, u32)> = vec![(pid.to_string(), 0)];
    while let Some((p, depth)) = stack.pop() {
        let out = Command::new("ps").args(["-p", &p, "-o", "args="]).output()?;
        let args = String::from_utf8_lossy(&out.stdout);
        if needles.iter().all(|n| args.contains(n)) { return Ok(true); }
        if depth >= 3 { continue; }
        let children = Command::new("pgrep").args(["-P", &p]).output()?;
        for c in String::from_utf8_lossy(&children.stdout).lines() {
            let child = c.trim().to_string();
            if !child.is_empty() { stack.push((child, depth + 1)); }
        }
    }
    Ok(false)
}

/// R10: block in the foreground, inheriting the terminal, return on exit.
pub fn run_in_foreground(command: &str) -> Result<()> {
    // `status()` only errors if the spawn itself fails; exit codes from
    // quitting an attach TUI are a normal way to come back to pinga.
    Command::new("sh").arg("-c").arg(command).status()?;
    Ok(())
}

/// Quote a string for the shell so a path/name with spaces or quotes survives
/// `sh -c` (used when composing `cd <dir> && <bin>` for a fresh codex window).
pub fn shell_quote(s: &str) -> String {
    if s.chars().all(|c| c.is_alphanumeric() || c == '-' || c == '_' || c == '.' || c == '/') {
        s.to_string()
    } else {
        format!("'{}'", s.replace('\'', "'\\''"))
    }
}
```

### 11.9 TUI module & theme (`tui::mod`, `tui::theme`)

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

### 11.10 The console (`tui::app`)

The heart. Two scrolling columns, arrow keys, full mouse support, inline rename
with a prefilled suggestion, and the handoff loop that honors R9 (tmux window)
or R10 (take the terminal, come back).

``` {.rust #tui-app path="src/tui/app.rs"}
use std::io::Stdout;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use anyhow::anyhow;
use crossterm::event::{self, Event, KeyCode, KeyEventKind, MouseButton, MouseEventKind};
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, Clear, ClearType};
use ratatui::backend::CrosstermBackend;
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::Style;
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, List, ListItem, Paragraph};
use ratatui::{Frame, Terminal};

use crate::config::Config;
use crate::launcher;
use crate::model::{now_ms, Session};
use crate::naming::NameEngine;
use crate::provider::{AnyProvider, Provider};

use super::theme;

const HELP: &str = "↑↓ select · ←→ column · click select · dbl-click/Enter open · Enter on '+' new · r rename · s suggest · m mouse · o auto · f force · q quit";
pub const QUIT_MSG: &str = "quit";

/// D8: two clicks on the same cell within this window count as one open.
const DOUBLE_MS: Duration = Duration::from_millis(500);
/// After a tmux window switch, swallow mouse downs for this long so a stray
/// press can't be read as a new selection once pinga gets focus back.
const SWITCH_COOLDOWN: Duration = Duration::from_millis(250);

/// A mouse-initiated open that must wait until the button is released before
/// touching the tmux window layout — switching mid-click lands the release
/// (or a stray press) in the newly-faced attach TUI, which opencode reads as
/// "click on message" -> its Message Actions popup.
enum Plan {
    Select { win: String },                    // window pinga created
    Adopt { win: String, id: String },         // same session, opened by hand
    Spawn { label: String, cmd: String, id: String },  // fresh window
}

/// One row of a column's visual list, in display order: the fixed "+ new
/// session" row, then any interrupted (orphaned) sessions, then the rest.
#[derive(Debug, Clone, Copy)]
enum VRow { New, Int(usize), Sess(usize) }

/// The bottom-line editor modes. Rename edits one title; NewSession is a
/// two-field form (name then working directory) for the "+ new session" row.
enum EditState {
    Rename(TextEdit),
    NewSession { name: TextEdit, cwd: TextEdit, field: u8 },  // 0 = name, 1 = cwd
}

pub struct App {
    cfg: Config,
    providers: Vec<AnyProvider>,
    opencode: Vec<Session>,   // snapshot of opencode sessions
    codex: Vec<Session>,      // snapshot of codex sessions
    focus: usize,             // 0 = opencode, 1 = codex
    sel: [usize; 2],          // selected row index per column
    naming: NameEngine,
    edited: Option<EditState>,  // Some(editor) => bottom-line input mode
    mouse_on: bool,
    last_poll: Instant,
    error: Option<String>,
    opened: Vec<(usize, String, String)>,   // (provider, session id, tmux window id) — D8
    interrupted: [Vec<String>; 2],  // ids in each column orphaned by a crash (window dead)
    last_click: Option<(Instant, usize, usize)>,  // (time, column, row) — D8 double-click
    force_open: bool,         // 'f' bypasses the D8 "already open elsewhere" refusal
    pending: Option<Plan>,    // D8: deferred mouse open (executed on mouse Up)
    mouse_ignore_until: Option<Instant>,  // D8: swallow stray downs after a switch
    needs_clear: bool,     // after a bare-terminal suspend, force a full repaint
    did_startup_reconcile: bool,  // interrupted-flagging runs once, at startup
}

#[derive(Debug, Clone, Copy)]
struct Rects { left: Rect, right: Rect }

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
    pub fn new(cfg: Config) -> Self {
        let (base, key, model) = cfg.naming_endpoint()
            .map(|(b, k, m)| (Some(b), k, m))
            .unwrap_or((None, None, "fallback-heuristic".into()));
        let providers = vec![
            AnyProvider::Opencode(crate::provider::opencode::OpencodeProvider::new(&cfg.opencode_url)),
            AnyProvider::Codex(crate::provider::codex::CodexProvider::new(&cfg.codex_home)),
        ];
        Self {
            cfg,
            providers,
            opencode: Vec::new(),
            codex: Vec::new(),
focus: 0,
            sel: [0, 0],
            naming: NameEngine::new(base, key, model),
            edited: None,
            mouse_on: false,
            last_poll: Instant::now(),
            error: None,
            opened: load_opened_state(),
            interrupted: [Vec::new(), Vec::new()],
            last_click: None,
            force_open: false,
            pending: None,
            mouse_ignore_until: None,
            needs_clear: false,
            did_startup_reconcile: false,
        }
    }

    fn provider(&self, i: usize) -> &AnyProvider { &self.providers[i] }

    fn refresh(&mut self) {
        // NOTE: self.error is NOT cleared here. Status lines like "already
        // open … f to force" must STICK until the next user action, so they
        // are cleared in handle_key / handle_mouse instead of vanishing on the
        // next poll tick.
        if let Some(plan) = self.pending.take() {
            if let Err(e) = self.execute(plan) {
                self.error = Some(e.to_string());
            }
        }
        match self.provider(0).list() {
            Ok(list) => { self.sel[0] = self.sel[0].min(list.len()); self.opencode = list; }
            Err(e) => self.error = Some(e.to_string()),
        }
        match self.provider(1).list() {
            Ok(list) => { self.sel[1] = self.sel[1].min(list.len()); self.codex = list; }
            Err(e) => self.error = Some(e.to_string()),
        }
        self.compute_interrupted();
        self.last_poll = Instant::now();
    }

    /// Reconcile the persisted "opened" list against the servers. For each
    /// entry pinga opened previously: if the session no longer exists on the
    /// server it was dropped/deleted there — remove it from tracking and tell
    /// the user once. If it still exists but its tmux window is dead, the
    /// session was orphaned (e.g. a power failure) — mark it "interrupted" so
    /// the user can resume it. Persist any reconciliation back to disk.
    fn compute_interrupted(&mut self) {
        // Only the FIRST reconcile (right after startup) may flag sessions as
        // "interrupted": those windows died while pinga was NOT running to see
        // them close, so a crash/reboot orphaned them. Once pinga is live, a
        // tracked window that dies means the user closed the session — drop it
        // from tracking instead, so an intentional /exit never shows as
        // interrupted (and is never wrongly carried into the next startup).
        let first = !self.did_startup_reconcile;
        self.did_startup_reconcile = true;
        let mut interrupted: [Vec<String>; 2] = [Vec::new(), Vec::new()];
        let mut gone = 0usize;
        let mut kept: Vec<(usize, String, String)> = Vec::new();
        let mut changed = false;
        // Snapshot which session ids exist on each server before draining the
        // tracked list, so the immutable read doesn't clash with the mutable
        // move below.
        let server_ids: Vec<Vec<String>> = self.snapshots().iter()
            .map(|v| v.iter().map(|s| s.id.clone()).collect())
            .collect();
        for (p, id, win) in std::mem::take(&mut self.opened) {
            let exists = server_ids[p].contains(&id);
            if !exists {
                // Session vanished server-side (deleted/expired). Drop tracking.
                gone += 1;
                changed = true;
                continue;
            }
            let alive = launcher::tmux_window_alive(&win).unwrap_or(false);
            if !alive {
                if first {
                    // Window gone while pinga wasn't running — orphaned by a
                    // crash/reboot. Offer it for resume.
                    interrupted[p].push(id.clone());
                    kept.push((p, id, win));
                } else {
                    // pinga is live and the window is gone: the user closed it.
                    changed = true;
                }
                continue;
            }
            // Window alive: is the session still attached in it, or did the
            // user close it (e.g. /exit leaves the pane as a shell)?
            let marker = self.session_marker(p, &id);
            let running = launcher::window_runs(&win, &[marker.as_str()]).unwrap_or(false);
            if running {
                kept.push((p, id, win));   // still open — keep tracking
            } else {
                changed = true;            // closed by the user — stop tracking
            }
        }
        self.opened = kept;
        self.interrupted = interrupted;
        if changed { save_opened_state(&self.opened); }
        if gone > 0 {
            self.error = Some(format!(
                "{gone} session(s) pinga had open no longer exist on the server — removed from tracking"
            ));
        }
    }

    /// The argv marker that proves a tracked window is still running this
    /// session: opencode's `-s <id>`, or codex's `resume <name>`.
    fn session_marker(&self, p: usize, id: &str) -> String {
        if p == 0 { return id.to_string(); }
        self.snapshots()[p].iter().find(|s| s.id == id)
            .and_then(|s| s.title.clone()).filter(|t| !t.is_empty())
            .unwrap_or_else(|| id.to_string())
    }

    fn snapshots(&self) -> [&Vec<Session>; 2] { [&self.opencode, &self.codex] }

    /// Visual row count for a column: the sessions plus the fixed "+ new
    /// session" row at index 0.
    /// Visual rows for a column, in display order: the fixed "+ new session" row,
    /// then interrupted (orphaned) sessions, then the remaining sessions.
    fn visual_rows(&self, idx: usize) -> Vec<VRow> {
        let snap = &self.snapshots()[idx];
        let mut v = Vec::with_capacity(snap.len() + 1);
        v.push(VRow::New);
        for (i, s) in snap.iter().enumerate() {
            if self.interrupted[idx].iter().any(|id| id == &s.id) { v.push(VRow::Int(i)); }
        }
        for (i, s) in snap.iter().enumerate() {
            if !self.interrupted[idx].iter().any(|id| id == &s.id) { v.push(VRow::Sess(i)); }
        }
        v
    }

    /// Number of visual rows (used for selection clamping / scroll bounds).
    fn list_len(&self, idx: usize) -> usize { self.visual_rows(idx).len() }

    /// The focused row is the "+ new session" element (visual row 0).
    fn on_new_row(&self) -> bool { self.sel[self.focus] == 0 }

    /// Run the event loop; returns when the user quits.
    pub fn run(&mut self, term: &mut Terminal<CrosstermBackend<Stdout>>) -> anyhow::Result<()> {
        self.refresh();
        loop {
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
            // After a bare-terminal child (an attach TUI) has run on this same
            // terminal, its writes clobbered cells ratatui's diff buffer thinks
            // are unchanged, so a normal draw can leave stale content. Force a
            // full repaint so the list actually comes back.
            if self.needs_clear {
                term.clear()?;
                self.needs_clear = false;
            }
            term.draw(|f| self.render(f))?;
        }
    }

    fn handle_key(&mut self, code: KeyCode) -> anyhow::Result<()> {
        use KeyCode::*;
        // A deferred mouse open that never got its Up (rare) is flushed here.
        if let Some(plan) = self.pending.take() {
            self.execute(plan)?;
        }
        self.error = None;   // any key dismisses a status line
        if self.edited.is_some() {
            return self.handle_edit_key(code);
        }
        // Arms that must propagate a Result leave early.
        match code {
            Char('q') | Esc => return Err(anyhow!(QUIT_MSG)),
            Enter => return self.open_selected(false),
            Char('m') => return self.toggle_mouse(),
            Char('s') => return self.suggest_current(false),
            Char('f') => return self.open_selected_force(),  // D8: bypass refusal
            _ => {}
        }
        // Pure state mutations; trailing Ok keeps the match unit-typed.
        match code {
            Up => self.sel[self.focus] = self.sel[self.focus].saturating_sub(1),
Down => {
                let n = self.snapshots()[self.focus].len();   // last session row
                self.sel[self.focus] = (self.sel[self.focus] + 1).min(n);
            }
            Left | Char('h') if self.focus > 0 => self.focus -= 1,
            Right | Char('l') if self.focus < 1 => self.focus += 1,
            Char('r') => self.start_rename(),
            Char('o') => self.cfg.auto_rename = !self.cfg.auto_rename,
            _ => {}
        }
        Ok(())
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
                Enter => {
                    let title = e.text();
                    self.edited = None;
                    self.apply_rename_to_focused(&title)?;
                    Ok(())
                }
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
            Some(EditState::NewSession { name, cwd, field }) => {
                match code {
                    Esc => { self.edited = None; Ok(()) }
                    Tab => { *field = 1 - *field; Ok(()) }
                    Enter => {
                        if *field == 0 {
                            *field = 1;   // name -> cwd
                            Ok(())
                        } else {
                            let name = name.text();
                            let cwd = cwd.text();
                            self.edited = None;
                            self.create_new_session(&name, &cwd)
                        }
                    }
                    // Text-editing keys act on whichever field is active. The
                    // `active` borrow is scoped to this arm so it can't clash
                    // with the immutable `name`/`cwd` reads in the Enter arm.
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
                }
            }
            None => Ok(()),
        }
    }

    fn focused_session(&self) -> Option<&Session> {
        match self.visual_rows(self.focus).get(self.sel[self.focus]) {
            Some(VRow::Int(i)) | Some(VRow::Sess(i)) => self.snapshots()[self.focus].get(*i),
            _ => None,
        }
    }

    fn open_selected(&mut self, from_mouse: bool) -> anyhow::Result<()> {
        if self.on_new_row() {
            // "+ new session": open the name/cwd form, cwd prefilled with
            // pinga's current directory for convenience.
            let cwd = std::env::current_dir()
                .map(|p| p.to_string_lossy().to_string())
                .unwrap_or_default();
            self.edited = Some(EditState::NewSession {
                name: TextEdit::new(""),
                cwd: TextEdit::new(&cwd),
                field: 0,
            });
            return Ok(());
        }
        let Some(s) = self.focused_session().cloned() else { return Ok(()) };
        let label = s.display_title().chars().take(24).collect::<String>();
        let cmd = self.provider(self.focus).attach_command(&s);
        if launcher::in_tmux() {
            self.open_in_tmux_guarded(&s, &label, &cmd, from_mouse)?;   // D8
        } else {
            // Bare-terminal mode: there is no alternate window to navigate to,
            // so an opencode session attached elsewhere is refused unless 'f'.
            if s.active && !self.force_open {
                self.error = Some(format!("{} is already open elsewhere — f to force",
                                          s.display_title()));
                return Ok(());
            }
            self.suspend_for(&cmd)?;                            // R10: pass control
            self.refresh();
        }
        self.force_open = false;
        Ok(())
    }

    fn open_selected_force(&mut self) -> anyhow::Result<()> {
        self.force_open = true;
        self.open_selected(false)
    }

    /// Spawn a fresh window for a brand-new session (no dedup — the session
    /// didn't exist a moment ago). tmux: new window + track it; bare: pass the
    /// terminal and come back.
    fn spawn_new(&mut self, label: &str, cmd: &str, id: &str) -> anyhow::Result<()> {
        if launcher::in_tmux() {
            let win = launcher::open_in_tmux_returning(label, cmd)?;
            self.opened.push((self.focus, id.to_string(), win));
            save_opened_state(&self.opened);
            self.mouse_ignore_until = Some(Instant::now() + SWITCH_COOLDOWN);
        } else {
            self.suspend_for(cmd)?;
            self.refresh();
        }
        Ok(())
    }

    /// The "+ new session" row's submit: create + open in the focused harness.
    fn create_new_session(&mut self, name: &str, cwd: &str) -> anyhow::Result<()> {
        let name = name.trim();
        let dir = if cwd.trim().is_empty() {
            std::env::current_dir().map(|p| p.to_string_lossy().to_string()).unwrap_or_default()
        } else { cwd.trim().to_string() };
        let label = if name.is_empty() {
            None
        } else {
            Some(name.chars().take(24).collect::<String>())
        };
        if self.focus == 0 {
            let s = self.provider(0).create(name, &dir)?;
            let label = label.unwrap_or_else(|| s.display_title().chars().take(24).collect::<String>());
            let cmd = self.provider(0).attach_command(&s);
            self.spawn_new(&label, &cmd, &s.id)
        } else {
            // codex has no server-side create: open a bare `codex` in the
            // directory and let it mint its own session. The requested name
            // becomes the tmux window label; the thread itself is named by
            // codex (rename with 'r' later for something specific).
            let cmd = format!("cd {} && codex", launcher::shell_quote(&dir));
            let label = label.unwrap_or_else(|| "codex".to_string());
            self.spawn_new(&label, &cmd, "")
        }
    }

    /// D8: never spawn a second window for one session. Priority: tracked
    /// window -> select it; a same-session window whose process argv carries
    /// this session's marker -> adopt it; opencode `active` elsewhere -> refuse
    /// (`f` forces); else create a fresh window and record its id.
    fn open_in_tmux_guarded(&mut self, s: &Session, label: &str, cmd: &str,
                            from_mouse: bool) -> anyhow::Result<()> {
        if let Some((_, _, win)) = self.opened.iter()
            .find(|(i, id, _)| *i == self.focus && *id == s.id)
            .cloned()
        {
            if launcher::tmux_window_alive(&win)? {
                return self.commit_or_defer(Plan::Select { win }, from_mouse);
            }
            self.opened.retain(|(i, id, _)| !(*i == self.focus && *id == s.id));
            // Window was killed behind our back -> reopen below.
        }
        // Marker that appears in the attach argv (opencode `-s <id>`; codex
        // `resume <name>`) so the adopt heuristic can't misfire on a bare
        // `codex`/`opencode` window that isn't this session.
        let marker = if self.focus == 0 {
            s.id.clone()
        } else {
            s.title.clone().filter(|t| !t.is_empty()).unwrap_or_else(|| s.id.clone())
        };
        if let Some(win) = launcher::find_open_window(&marker)? {
            return self.commit_or_defer(Plan::Adopt { win, id: s.id.clone() }, from_mouse);
        }
        if self.focus == 0 {
            // opencode fallback: an `attach` window without `-s <id>` can't be
            // matched by argv. The server exposes no per-session attachment
            // signal, so the safe heuristics are: exactly ONE attach window
            // AND this session is the newest-updated (opencode's bare attach
            // binds to the most recent session) -> adopt it; exactly one
            // attach window on a DIFFERENT session -> this session is not open
            // here, spawn normally; several attach windows -> ambiguous,
            // refuse rather than silently copying.
            let attach_wins = launcher::find_opencode_attach_windows()?;
            if attach_wins.len() == 1 {
                let is_newest = self.opencode.iter()
                    .filter_map(|o| o.updated_ms)
                    .max()
                    .is_some_and(|mx| s.updated_ms.is_some_and(|up| up >= mx));
                if is_newest {
                    let win = attach_wins[0].clone();
                    return self.commit_or_defer(Plan::Adopt { win, id: s.id.clone() }, from_mouse);
                }
            } else if !attach_wins.is_empty() && !self.force_open {
                self.error = Some(format!("{} — {} opencode attach window(s); f to open a new one",
                                          s.display_title(), attach_wins.len()));
                return Ok(());
            }
        }
        if s.active && !self.force_open {
            self.error = Some(format!("{} is already open elsewhere — f to force",
                                      s.display_title()));
            return Ok(());
        }
        self.commit_or_defer(Plan::Spawn {
            label: label.to_string(), cmd: cmd.to_string(), id: s.id.clone(),
        }, from_mouse)
    }

    /// From a keyboard action the tmux change happens now; from a mouse
    /// double-click it waits for the button to come up so the release of the
    /// second click can't be delivered to the newly-faced attach TUI.
    fn commit_or_defer(&mut self, plan: Plan, from_mouse: bool) -> anyhow::Result<()> {
        self.force_open = false;
        if from_mouse {
            self.pending = Some(plan);
            return Ok(());
        }
        self.execute(plan)
    }

    fn execute(&mut self, plan: Plan) -> anyhow::Result<()> {
        match plan {
            Plan::Select { win } => {
                launcher::tmux_select_window(&win)?;       // take me to it
            }
            Plan::Adopt { win, id } => {
                self.opened.push((self.focus, id, win.clone()));
                launcher::tmux_select_window(&win)?;       // same session, not ours
            }
            Plan::Spawn { label, cmd, id } => {
                let win = launcher::open_in_tmux_returning(&label, &cmd)?;
                self.opened.push((self.focus, id, win));
            }
        }
        save_opened_state(&self.opened);
        // Any window layout change after a mouse open can leak a stray press;
        // swallow down events for a beat so pinga doesn't act on it on return.
        self.mouse_ignore_until = Some(Instant::now() + SWITCH_COOLDOWN);
        Ok(())
    }

    fn suspend_for(&mut self, cmd: &str) -> anyhow::Result<()> {
        disable_raw_mode()?;
        crossterm::execute!(std::io::stdout(),
            crossterm::cursor::Show, crossterm::event::DisableMouseCapture)?;
        launcher::run_in_foreground(cmd)?;                   // blocks until child exits
        enable_raw_mode()?;
        crossterm::execute!(std::io::stdout(), Clear(ClearType::All))?;
        if self.mouse_on {
            crossterm::execute!(std::io::stdout(), crossterm::event::EnableMouseCapture)?;
        }
        self.needs_clear = true;   // full repaint next frame (child clobbered the screen)
        Ok(())
    }

    fn suggest_current(&mut self, commit: bool) -> anyhow::Result<()> {
        let Some(s) = self.focused_session().cloned() else { return Ok(()) };
        let seed = self.seed_for(&s);
        let name = self.naming.suggest(&seed);
        if commit {
            self.provider(self.focus).rename(&s, &name)?;
            self.refresh();
        } else {
            self.edited = Some(EditState::Rename(TextEdit::new(&name)));   // prefill for manual rename (R4/R5)
        }
        Ok(())
    }

    fn start_rename(&mut self) {
        let pre = self.focused_session().map(|s| s.display_title().to_string()).unwrap_or_default();
        self.edited = Some(EditState::Rename(TextEdit::new(&pre)));
    }

    fn apply_rename_to_focused(&mut self, title: &str) -> anyhow::Result<()> {
        if let Some(s) = self.focused_session().cloned() {
            self.provider(self.focus).rename(&s, title)?;
            self.refresh();
        }
        Ok(())
    }

    /// Seed for the name engine: the most recent user-visible intent.
    fn seed_for(&self, s: &Session) -> String {
        match (&s.title, &s.slug) {
            (Some(t), _) if !t.is_empty() => t.clone(),
            (_, Some(slug)) => slug.clone(),
            _ => s.id.clone(),
        }
    }

    fn handle_mouse(&mut self, m: &crossterm::event::MouseEvent, area: Rect) -> anyhow::Result<()> {
        let body = body_rect(area);
        let Rects { left, right } = layout_rects(body);
        let (col, row) = hit_rect(m.column, m.row, left, right);
        match m.kind {
            MouseEventKind::ScrollDown => {
                let n = self.snapshots()[self.focus].len();
                self.sel[self.focus] = (self.sel[self.focus] + 1).min(n);
            }
            MouseEventKind::ScrollUp => {
                self.sel[self.focus] = self.sel[self.focus].saturating_sub(1);
            }
            MouseEventKind::Down(MouseButton::Left) => {
                // A stray down right after a window switch is not a conscious
                // click on our rows — drop it and reset double-click state.
                if let Some(until) = self.mouse_ignore_until {
                    if Instant::now() < until {
                        self.mouse_ignore_until = None;
                        self.last_click = None;
                        return Ok(());
                    }
                }
                self.error = None;   // any explicit click dismisses a status line
                if let (Some(c), Some(r)) = (col, row) {
                    if r <= self.snapshots()[c].len() {
                        self.focus = c;
                        self.sel[c] = r;
                        // D8: single click selects only; a quick second click
                        // on the same cell opens (double-click pattern).
                        let is_double = self.last_click
                            .filter(|(t, pc, pr)| t.elapsed() < DOUBLE_MS && *pc == c && *pr == r)
                            .is_some();
                        self.last_click = Some((Instant::now(), c, r));
                        if is_double {
                            return self.open_selected(true);
                        }
                    }
                }
            }
            // The double-click's plan is executed when the button comes back
            // up, so its release can't leak into the attach TUI we switch to.
            MouseEventKind::Up(_) => {
                if let Some(plan) = self.pending.take() {
                    return self.execute(plan);
                }
            }
            _ => {}
        }
        Ok(())
    }

    fn render(&self, f: &mut Frame) {
        let area = f.area();
        let vert = Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Length(1), Constraint::Min(0)])
            .split(area);
        let Rects { left, right } = layout_rects(vert[1]);

        let header = Line::from(vec![
            Span::styled(" pinga ", theme::focus_style()),
            Span::styled(" · ", theme::dim_style()),
            // Reserve the fixed prefix width (" pinga " + " · ") so the help
            // text can never push past the right edge of the terminal.
            Span::styled(
                Self::fit(HELP, usize::from(vert[0].width).saturating_sub(
                    unicode_width::UnicodeWidthStr::width(" pinga  · "),
                )),
                theme::dim_style(),
            ),
        ]);
        f.render_widget(Paragraph::new(header).style(theme::surface_style()), vert[0]);

        self.render_column(f, left, 0);
        self.render_column(f, right, 1);

        if let Some(edit) = &self.edited {
            let line = match edit {
                EditState::Rename(e) => self.rename_line(e, area.width),
                EditState::NewSession { name, cwd, field } => self.new_session_line(name, cwd, *field, area.width),
            };
            let rect = Rect::new(area.x, area.bottom().saturating_sub(1), area.width, 1);
            f.render_widget(Paragraph::new(line).style(theme::surface_style()), rect);
        } else if let Some(e) = &self.error {
            let line = Rect::new(area.x, area.bottom().saturating_sub(1), area.width, 1);
            f.render_widget(Paragraph::new(Self::fit(e, usize::from(area.width))).style(theme::warn_style()), line);
        }
    }

    /// Bottom-line for the rename editor: keep the cursor block and the
    /// [Enter/Esc] hint visible by trimming the after-cursor text when short.
    fn rename_line(&self, e: &TextEdit, width: u16) -> Line<'_> {
        let text = e.text();
        let cursor = e.cursor();
        let before: String = text.chars().take(cursor).collect();
        let full_after: String = text.chars().skip(cursor).collect();
        let hint = "  [Enter apply · Esc cancel]";
        let cursor_style = Style::default().bg(theme::FG).fg(theme::BG);
        let budget = usize::from(width)
            .saturating_sub(9 /* " rename: " */ + unicode_width::UnicodeWidthStr::width(before.as_str()) + 1 + hint.chars().count());
        let after = Self::fit(&full_after, budget);
        Line::from(vec![
            Span::styled(" rename: ", theme::codex_accent()),
            Span::styled(before, theme::text_style()),
            Span::styled("▌", cursor_style),
            Span::styled(after, theme::dim_style()),
            Span::styled(hint, theme::dim_style()),
        ])
    }

    /// Bottom-line for the "+ new session" form (one field at a time).
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
        let budget = usize::from(width)
            .saturating_sub(prefix + unicode_width::UnicodeWidthStr::width(before.as_str()) + 1 + hint.chars().count());
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

    /// Clip `text` to a budget of terminal COLUMNS (wide glyphs count double)
    /// so a long line can't overflow the right edge of its rect.
    fn fit(text: &str, max: usize) -> String {
        use unicode_width::UnicodeWidthChar;
        let mut s = String::new();
        let mut w = 0usize;
        for c in text.chars() {
            if w + c.width().unwrap_or(0) > max {
                break;
            }
            w += c.width().unwrap_or(0);
            s.push(c);
        }
        s
    }

    fn render_column(&self, f: &mut Frame, area: Rect, idx: usize) {
        let snap = &self.snapshots()[idx];
        let title = format!(" {} ({}) ", match idx { 0 => "opencode", _ => "codex" }, snap.len());
        let border = if idx == self.focus { theme::focus_style() } else { theme::idle_style() };
        let brand = if idx == 1 { theme::codex_accent() } else { theme::focus_style() };
        let block = Block::default()
            .title(Span::styled(title, brand))
            .borders(Borders::ALL).border_style(border);
        let inner = block.inner(area);
        f.render_widget(&block, area);

        let mut items: Vec<ListItem> = Vec::new();
        for (visual, row) in self.visual_rows(idx).into_iter().enumerate() {
            let selected = visual == self.sel[idx];
            match row {
                VRow::New => {
                    let style = if selected { theme::selected_style() } else { theme::codex_accent() };
                    items.push(ListItem::new(Line::from(Span::styled(" + new session", style))));
                }
                // Interrupted = orphaned by a crash/reboot; offered for resume.
                VRow::Int(i) => {
                    let s = &snap[i];
                    let style = if selected { theme::selected_style() } else { theme::warn_style() };
                    let spans = vec![
                        Span::styled(" ⚠ interrupted ", theme::warn_style()),
                        Span::styled(s.display_title(), style),
                        Span::styled(format!(" {}", s.age(now_ms())), theme::dim_style()),
                    ];
                    items.push(ListItem::new(Line::from(spans)));
                }
                VRow::Sess(i) => {
                    let s = &snap[i];
                    let marker = if s.active { "●" } else { "·" };
                    let title_style = if selected { theme::selected_style() } else { theme::text_style() };
                    let meta_style = if selected { Style::default().fg(theme::DIM) } else { theme::dim_style() };
                    let spans = vec![
                        Span::styled(format!(" {marker} "), theme::dim_style()),
                        Span::styled(s.display_title(), title_style),
                        Span::styled(format!(" {}", s.age(now_ms())), meta_style),
                    ];
                    items.push(ListItem::new(Line::from(spans)));
                }
            }
        }
        f.render_widget(List::new(items), inner);
    }
}

/// Where pinga persists the set of sessions it has opened (so interrupted
/// sessions can be detected across restarts). ~/.local/state/pinga/opened.json
fn opened_state_path() -> PathBuf {
    let base = dirs::state_dir()
        .unwrap_or_else(|| dirs::home_dir().unwrap_or_default().join(".local/state"));
    base.join("pinga").join("opened.json")
}

fn load_opened_state() -> Vec<(usize, String, String)> {
    std::fs::read_to_string(opened_state_path()).ok()
        .and_then(|s| serde_json::from_str::<Vec<(usize, String, String)>>(&s).ok())
        .unwrap_or_default()
}

fn save_opened_state(opened: &[(usize, String, String)]) {
    if let Ok(json) = serde_json::to_string(opened) {
        let p = opened_state_path();
        if let Some(parent) = p.parent() { let _ = std::fs::create_dir_all(parent); }
        let _ = std::fs::write(p, json);
    }
}

/// The area below the one-line header.
fn body_rect(area: Rect) -> Rect {
    let vert = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(1), Constraint::Min(0)])
        .split(area);
    vert[1]
}

/// Split the body into two equal columns.
fn layout_rects(body: Rect) -> Rects {
    let cols = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
        .split(body);
    Rects { left: cols[0], right: cols[1] }
}

/// Map terminal coords to (column index, row index inside that column's list).
/// Borders occupy the outer ring, so rows start one cell below the column's top.
fn hit_rect(x: u16, y: u16, left: Rect, right: Rect) -> (Option<usize>, Option<usize>) {
    for (idx, r) in [(0usize, left), (1usize, right)] {
        if x >= r.x && x < r.right() {
            if y > r.y && y < r.bottom().saturating_sub(1) {
                return (Some(idx), Some((y - r.y - 1) as usize));
            }
            return (Some(idx), None);
        }
    }
    (None, None)
}
```

> **Note.** The chunk is self-contained: the helpers (`body_rect`,
> `layout_rects`, `hit_rect`) and the single-click-open policy are real code
> now, not stubs. The **auto-rename pass** (§12) is deliberately left out of
> `refresh()` in this scaffolding so the loop stays obvious; it lands in the
> same function when §12's trigger policy is finalized. Mouse is opt-in with
> `m` so plain terminals never get capture surprises.

### 11.11 Entrypoint (`core::main`)

Tiny on purpose: terminal in/out is here, the loop is in `tui::app`.

``` {.rust #core-main path="src/main.rs"}
// Scaffold stage: the provider contract (§11.4–11.7) and theme (§11.9) declare
// the full data model and palette up front; the first TUI pass only reads a
// subset. `make lint` stays green while the remaining fields get wired in.
#![allow(dead_code)]

mod config;
mod launcher;
mod model;
mod naming;
mod provider;
mod tui;

use std::io;

use crossterm::terminal::{disable_raw_mode, enable_raw_mode,
                          EnterAlternateScreen, LeaveAlternateScreen};
use ratatui::backend::CrosstermBackend;
use ratatui::Terminal;

fn main() -> anyhow::Result<()> {
    let cfg = config::Config::load();
    enable_raw_mode()?;
    crossterm::execute!(io::stdout(), EnterAlternateScreen)?;
    let result = run_console(cfg);
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

fn run_console(cfg: config::Config) -> anyhow::Result<()> {
    let backend = CrosstermBackend::new(io::stdout());
    let mut term = Terminal::new(backend)?;
    let mut app = tui::app::App::new(cfg);
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

## 12. Event flow & refresh

- Snapshot-pull: every `refresh_secs/4` of input idle, or immediately after
  handoffs/renames. Both providers re-list; the two columns re-render. Sorting
  is by `updated_ms` desc, newest on top.
- Auto-rename (R5): when enabled, the name engine runs on a session the first
  time it appears with a still-default title *and* has crossed 3 minutes of age
  (so we don't rename the just-created one the user is starting to type in).
  Manual rename (`r`) preloads the current title **or** the latest suggestion
  (`s` to refresh the prefill) — R4/R5 in one small flow.
- Handoff durability: after R10 returns, `refresh()` runs because the agent
  executed commands and the session lists changed underneath us.

## 13. Acceptance & test plan

| Area | Test | Gate |
|------|------|------|
| Provider (opencode) | unit: parse a captured `GET /session` fixture; rename hits the pinned route and re-reads | `cargo test` |
| Provider (codex) | unit: build sessions from a fixture `session_index.jsonl` + rollout tree; rename appends a line | `cargo test` |
| Naming | unit: heuristic caps ≤ 40; remote path mocked (deny offline) | `cargo test` |
| Launcher | unit: `in_tmux()` true/false; run_in_foreground runs `sh -c` | `cargo test` |
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
   (`POST|PATCH|PUT /session/<id>(/rename)`) — pin during implementation by
   sending one distinct title per candidate and re-reading `GET /session`
   (§5.1 already has the harness). Wrap the heuristic (try-all, verify) so a
   future opencode release that adds a real `/api/…/rename` slot maps to it.
2. **codex thread naming vs its SQLite titles.** We act on
   `session_index.jsonl` (what the picker/name-resume read); if codex moves to
   its state DB as source of truth, extend the adapter — the `Provider` seam
   isolates that.
3. **Auto-rename trigger definition.** "3 min old + default title" is a
   starting policy; make it config-driven (`auto_rename_min_age`).
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
source. No separate ADR file yet — decisions D1–D7 above *are* the ADR and live
where the code is born. (Move them into `.memory/wiki/adrs/` if pinga grows
beyond one crate.)