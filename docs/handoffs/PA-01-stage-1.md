# PA-01 Stage 1 — provider identity and registry

Task revision: 1 (2026-09-22). Status: ready for user delivery; not started.
Assignee: a NEW OpenCode session using DeepSeek. Reviewer: Codex architect.
Scope: Stage 1 only of `docs/provider-architecture.md`, revision 1.
Report: `docs/handoffs/PA-01-stage-1-report.md`.

## Why a new session

This changes architectural boundaries rather than continuing a local bug fix.
The current blueprint and recorded gotchas are the baseline. Earlier sessions
may carry obsolete assumptions about Codex naming or two-provider layout.
A fresh session can load the explicit task without that conversational baggage.
Use the experienced session later as a source of a specific missing historical
fact if necessary; do not run two implementers on the same checkout.

## Start here

1. Work in `/home/edgar/Projects/pinga`. Read `AGENTS.md`, then memory index,
   gotchas, and failed approaches. Read `docs/provider-architecture.md`, then
   this task in full. Read the relevant blueprint prose/chunks listed below.
2. Inspect `git status` and `git diff` BEFORE editing. Preparation HEAD was
   `e81cef7d78ef76e58bc421dc67d552de842284ef`; the working tree already contains
   documentation corrections and this packet. Those uncommitted changes are
   intentional input, not your implementation. Do not reset or overwrite them.
   Record actual starting HEAD and changed paths in the report.
3. Run `make tangle`, `make check`, `make test`, and `make lint` for a baseline.
   Record failures as pre-existing where established. Existing executable
   chunks had no automated tests during architecture preparation.
4. Begin implementation without another approval round if the checkout and
   task agree. Ask only when a material conflict or architectural ambiguity
   prevents correct work. Do not rely on a possibly unrelated auto-injected
   Mnemosyne handoff instead of this explicitly assigned task.

The user creates this conversation through their existing shared OpenCode
server. Do not start another bare OpenCode server or send prompts to other
sessions. No subagents are needed for this bounded task.

## Outcome

The provider list uses a registry of trait objects rather than `AnyProvider`.
Session identity no longer relies on a closed `ProviderKind` enum. A third
fake provider can be registered and exercised in tests with no edits to core
dispatch. The production application still opens with OpenCode on the left,
Codex on the right, and the same creation/resume/rename/tracking behavior.

## Required changes

### 1. Identity and metadata

- Implement `ProviderId` as the validated owned-string value described in the
  architecture. Provide normal equality/hash/ordering/debug and ergonomic
  access/display as needed. Do not add a crate merely to represent it.
- Add `SessionKey`, composed of provider ID and native session ID; reject an
  empty native ID when constructing a known key. Do not rewrite legacy empty
  IDs in the opened registry in this stage.
- Replace `Session.kind: ProviderKind` with `provider_id: ProviderId`. Keep
  `Session.id` as the native ID and preserve its other fields and helpers.
- Add provider descriptor metadata: instance ID, type key, display name.
  Constants for built-in IDs are fine; an enum exhaustively listing providers
  is not. Descriptor identity must match the identity stamped on its sessions.
- Built-in constructors may accept an instance ID so identity is not embedded
  in their list parsers. Only default instances are exposed by production
  configuration in this stage.

### 2. Trait and registry

- Replace `kind()` with descriptor access. Preserve `Send + Sync` and object
  safety. Retain `list`, `rename`, `attach_command`, and default-error `create`
  for this transitional stage; preserve their existing behavior.
- Remove `AnyProvider` and its forwarding implementation. Add a registry
  owning `Box<dyn Provider>`, ordered enumeration, and lookup by `ProviderId`.
  Insertion returns a useful error on duplicate IDs without replacing or
  changing the order of existing registrations. Unknown ID lookup must not
  accidentally dispatch to another provider.
- Put built-in imports/construction in one clearly named composition function
  at the provider boundary. It consumes existing config, registers exactly
  OpenCode then Codex, and returns errors rather than silently skipping one.
- Route the app's provider storage/access through that registry. The app may
  temporarily use ordered indices because its UI/tracking still require the
  historical two-provider order. Remove concrete adapter construction from
  the app. If constructors become fallible, propagate errors through the
  existing terminal cleanup path instead of adding panic/unwrap control flow.
- Do not add capabilities, execution-plan types, or unused future machinery
  just to make the target architecture appear complete.

### 3. Literate integration

Edit `blueprint.md` first; `src/` and `Cargo.toml` are generated artifacts.
Use real fence chunk IDs (hyphens), not only the conceptual module-map labels:

| Existing chunk | Generated file | Permitted edit |
| --- | --- | --- |
| `core-model` | `src/model.rs` | Identity types and session provider field |
| `prov-mod` | `src/provider/mod.rs` | Descriptor, trait, registry/composition, tests |
| `prov-opencode` | `src/provider/opencode.rs` | Constructor/identity stamping and descriptor only |
| `prov-codex` | `src/provider/codex.rs` | Constructor/identity stamping and descriptor only |
| `tui-app` | `src/tui/app.rs` | Registry construction/access and required compile adjustments |
| `core-main` | `src/main.rs` | Error propagation if required |

New focused model/registry test or module chunks are allowed. Each generated
file needs a first `path=` block so repeated tangling replaces, not repeatedly
appends, its contents. Keep all executable tests tanglable too.
Update relevant prose in §§6–9 and §11 to describe Stage 1 accurately; add
concrete coverage to §13. Retain the distinction between partial abstraction
and the full target. Do not split the blueprint or alter the tangle tool.

## Explicitly outside this stage

- Pi, Antigravity, runtime plugins, messaging tools, or OpenCode/MCP setup.
- New config schemas, reordering/disabling providers, or additional live instances.
- Replacing the two-column layout, fixed arrays, numeric opened registry, or
  extracting/reworking the launcher. Those known couplings remain for review.
- Changing Codex resume-by-title, SQLite queries/rename fallback, ancestor
  naming, sorting, or rollout filtering. Changing OpenCode routes/heuristics.
- Implementing automatic renaming or repairing unrelated known behavior.
- Installing/building into the user's PATH, restarting services/agents, or
  modifying real provider sessions/databases for validation.

Preserve mouse deferral/cooldown, grouping/header selection, interrupted-state
semantics, shared tracking locks, and current config/environment defaults.
Do not opportunistically format the whole blueprint. Do not commit the mixed
working tree; leave a reviewable diff and report for the architect.

## Acceptance checks

Automated tests must exercise behavior with fake adapters and temporary/local
fixtures, without a live OpenCode server, Codex home, tmux server, or model API:

1. Provider ID validation accepts the documented syntax and rejects invalid IDs.
2. Distinct provider IDs with the same native session ID produce different keys;
   equal keys compare equal; an empty known native ID is rejected.
3. Registry supports three fake providers in insertion order. Duplicate ID
   insertion fails without replacement/reordering. Unknown lookup is absent.
4. Lookup dispatches list/rename/attach/create to the intended fake adapter.
   A fake provider's failure does not remove or change the other registrations;
   the default unsupported create path returns an error rather than panicking.
5. Built-in composition preserves default IDs/order and consumes existing
   config values. Test configuration wiring without connecting to providers
   or inspecting the user's real files. Confirm fixture sessions carry the
   configured instance ID (including a non-default ID) for both adapters.
6. `ProviderKind` and `AnyProvider` are absent from executable chunks. Core app
   construction no longer mentions concrete adapter constructors. A fake third
   provider needs no new core dispatch branch. This is not yet proof of a
   three-provider UI; explicitly report that later work remains.

Run after implementation:

```sh
make tangle
make check
make test
make lint
git diff --check
```

Also verify that a second tangle leaves every generated file byte-for-byte
unchanged. Since `src/` is ignored by Git, `git diff` alone cannot check that;
compare hashes before/after. Record real command results and test counts, not
just a claim that the plan was followed. Use normal environment approval if a
required command is blocked; never bypass the sandbox.

## Completion and questions

Update the report template and append a dated entry to `.memory/wiki/log.md`.
Record actual quirks/decisions in project memory. Do not alter this task or
the target architecture to retroactively justify a deviation. Routine internal
names/layout are your choice within the required contracts; a scope change or
observable provider behavior change goes in the report as a question first.

Stop after Stage 1. Tell the user: "PA-01 Stage 1 is ready for architect review"
and give the report path, checks, and remaining blockers. Do not begin Stage 2.
The user will notify the architect, who reads the local diff/report directly.
