# PA-01 Stage 1 implementation report

Task revision: 1.
Status: CORRECTIONS APPLIED — ready for architect re-review (R1/R2 addressed).

## Corrections applied (re-review round 2)

### R1 / P2 — SessionKey nonempty-ID invariant enforced

- `SessionKey` fields are now private (`provider`, `native_id`) with immutable
  accessors `provider()` and `native_id()`. Construction remains the validated
  `SessionKey::new`, which rejects an empty native ID. No mutable setters,
  serialization, or persistence changes were added. Equality/hash/ordering are
  preserved (derived on the private fields), and the rejection test plus new
  accessor assertions pass.
- Compile probe (temporary, removed afterward): a sibling-module probe file was
  added to `src/`, checked with `cargo`, then deleted and the tree re-tangled.
  Both bypass forms were rejected by the compiler:
  - struct-literal construction `SessionKey { provider, native_id: "" }` →
    `error[E0451]: fields `provider` and `native_id` of struct `SessionKey` are private`;
  - post-construction field access/mutation `key.native_id` →
    `error[E0616]: field `native_id` of struct `SessionKey` is private`.
  This is a recorded temporary compile probe, not a compile-fail dependency.

### R2 / P2 — Required acceptance behavior demonstrated

- New `builtin_composition_wires_config_into_adapters`: builds a `Config` with a
  non-default OpenCode URL (`http://127.0.0.1:6555`) and a temporary Codex home
  containing a rollout + `state_*.sqlite` fixture, obtains both adapters through
  `builtin_registry`, and asserts (a) the OpenCode attach command uses the
  configured URL and (b) Codex `list()` reads the temp fixture — never the
  real/default home. This proves config-to-registry wiring, not just metadata.
- `lookup_dispatches_to_the_intended_adapter` was replaced by
  `lookup_dispatches_all_operations_to_the_intended_adapter`: a recorded
  `Calls` struct (via `Arc<Mutex<…>>`, kept Send+Sync so the fake stays boxable)
  captures successful rename (recipient id, session native id, title) and create
  (recipient id, name, dir) through ID lookup, asserting recipient and inputs.
  A `CreateFake` overrides `create` for the successful path; the base `Fake`
  keeps the default unsupported `create` (errors, not panic). Fixture sessions
  now carry the fake's actual provider ID (no more `unused`).
- `duplicate_registration_fails_without_replacing_the_original`: registers a
  distinguishable replacement with the same ID, asserts rejection, and verifies
  the original's attach behavior remains after the rejected insertion (count and
  order assertions alone would not catch a replace-then-error).
- Test count rose from 11 to **12**; blueprint §13 rows were updated to match
  the strengthened checks.

## Starting state

- Actual starting HEAD: `e81cef7d78ef76e58bc421dc67d552de842284ef`
  (`pinga: cooperative state, grouped lists, modals, codex names, mouse default`).
  Matches the preparation HEAD named in the task packet.
- Pre-existing modified/untracked paths (intentional input, preserved, not
  reset or overwritten):
  - modified: `blueprint.md`, `.memory/wiki/gotchas.md`,
    `.memory/wiki/index.md`, `.memory/wiki/log.md`
  - untracked: `docs/` (architecture + stage-1 packet + this report),
    `.memory/wiki/notes/`
- Baseline commands (run before any implementation edit):
  - `make tangle` — ok (12 files tangled, same as derived tree)
  - `make check` — ok
  - `make test` — ok, **0 tests** (no automated tests pre-existing)
  - `make lint` — ok
  No pre-existing failures were observed.

## Delivered behavior

- Identity and registry:
  - `ProviderId` in `core-model` (`src/model.rs`): validated owned string
    (nonempty lowercase ASCII letters/digits plus `.`, `_`, `-`; rejects
    whitespace and other characters) with equality/hash/ordering/debug/display.
  - `SessionKey = (ProviderId, native_id)`; constructing a known key rejects an
    empty native id. Legacy empty IDs in the opened registry are not rewritten.
  - `Session.kind: ProviderKind` replaced by `Session.provider_id: ProviderId`;
    `Session.id` remains the opaque native id; all other fields/helpers kept.
  - `ProviderKind` and `AnyProvider` removed from all executable chunks.
  - `ProviderDescriptor { id, type_key, display_name }`; trait `kind()` replaced
    by `descriptor()`. Built-in constants: opencode/codex. Descriptor identity
    matches the `provider_id` stamped on each adapter's sessions.
  - `ProviderRegistry` owns `Box<dyn Provider>`, ordered iteration, lookup by
    `ProviderId`, ordered index access for the transitional app. Duplicate ID
    registration returns an error without replacing/reordering; unknown lookup
    is absent (never a fallback).
  - `builtin_registry(cfg)` composition function at the provider boundary builds
    exactly OpenCode then Codex from existing config and propagates errors.
- Built-in composition and application integration:
  - `tui::app` stores a `ProviderRegistry` and accesses providers by index
    (`provider(i) -> &dyn Provider`). No concrete adapter constructors remain in
    the app. `App::new` is now fallible and its error propagates through the
    existing terminal-cleanup path in `core-main`.
  - The `create`/`rename`/`attach_command`/`list` signatures and behavior are
    unchanged for the built-ins.
- Blueprint sections/chunks changed:
  - Chunks: `core-model`, `prov-mod`, `prov-opencode`, `prov-codex`, `tui-app`,
    `core-main`. New append chunk `prov-codex-tests` (codex temp-home fixture).
  - Prose updated: §6 (architecture), §7 (module map), §8 (added decision D9),
    §9.1/§9.2 (data contracts), §11.4 (provider trait), §13 (test plan + first
    automated tests).
- Intentionally remaining transitional coupling (out of scope, preserved):
  - The app still uses the two historical provider indices for UI/tracking; the
    launcher still recognizes built-in process arguments; the opened registry
    persists numeric provider positions; the two-column layout and fixed arrays
    are unchanged. A third provider is now registerable in tests, but a
    three-provider **UI** is not yet implemented — that later work remains.

## Validation

| Check | Command or test | Result / count |
| --- | --- | --- |
| Baseline | `make tangle && make check && make test && make lint` | ok; 0 tests; lint clean |
| ID/key behavior | `model::tests` | 3 pass (incl. R1 accessors) |
| Three fake providers / duplicate / missing lookup | `provider::tests` | 3 pass |
| Dispatch (all ops, recorded), failure isolation, default create | `provider::tests` | 2 pass |
| Built-in composition (metadata + config wiring) and identity fixtures | `provider::tests` + opencode/codex fixtures | 4 pass |
| R1 compile probe (temporary) | sibling-module probe via `cargo` | construct → E0451; field access → E0616 (both rejected) |
| Check | `make check` | ok |
| Tests | `make test` | 12 passed, 0 failed |
| Lint | `make lint` | ok (`cargo clippy -- -D warnings`) |
| Repeat tangle hashes | sha256sum before/after 2nd `make tangle` | byte-for-byte identical |
| Diff whitespace | `git diff --check` | clean |
| Absence in executable chunks | `rg 'ProviderKind\|AnyProvider\|pub native_id\|pub provider:' src/` | none found |
| Concrete ctors out of app | `rg 'OpencodeProvider::new\|CodexProvider::new' src/tui src/main.rs` | none found |

Test count 12, all passing: `provider_id_accepts_documented_syntax`,
`provider_id_rejects_invalid_ids`,
`session_key_distinguishes_providers_and_rejects_empty_native` (now also asserts
the immutable accessors), `registry_supports_three_fakes_in_insertion_order`,
`duplicate_registration_fails_without_replacing_the_original`,
`unknown_lookup_is_absent`,
`lookup_dispatches_all_operations_to_the_intended_adapter`,
`a_provider_failure_is_local_to_it`,
`builtin_composition_preserves_default_ids_order_and_types`,
`builtin_composition_wires_config_into_adapters`,
`provider::opencode::tests::fixture_sessions_carry_configured_instance_id`,
`provider::codex::tests::fixture_sessions_carry_configured_instance_id`.

## Deviations, questions, and limitations

- No material conflict or architectural ambiguity required an escalation.
  No scope change was made; observable provider behavior is unchanged.
- No deviations from the assigned scope. `ProviderRegistry` index access and the
  fallible `App::new` were the only judgment calls, and both follow the task's
  explicit allowance (transitional index use; propagate constructor errors
  through the existing cleanup path rather than unwrapping).
- Limitations (tested vs untested): all Stage 1 tests use fake adapters and
  temporary/local fixtures with no live server, codex home, tmux server, or
  model API. The legacy/planned provider, naming, and launcher test rows in
  §13 remain planned, not automated. The codex fixture exercises `list()` end
  to end against a synthetic `~/.codex` (rollout + `state_*.sqlite`).
- Question for the reviewer (no action needed to land Stage 1): `ProviderId` is
  owned and validated in `core::model`; the descriptor's `type_key`/`display_name`
  are `&'static str`. When later stages add per-instance configuration or
  non-built-in providers, those two fields may need to become owned strings —
  that is a Stage 2+ concern, not handled here.

## Reviewer entry points

- Chunk IDs: `core-model`, `prov-mod`, `prov-opencode`, `prov-codex`,
  `prov-codex-tests`, `tui-app`, `core-main`.
- Test names (all in `#[cfg(test)]`): the 12 listed above under `src/model.rs`,
  `src/provider/mod.rs`, `src/provider/opencode.rs`, `src/provider/codex.rs`.
- Most useful for review (including the R1/R2 corrections):
  `builtin_composition_wires_config_into_adapters` (config → registry wiring),
  `lookup_dispatches_all_operations_to_the_intended_adapter` (recorded
  recipient/args for create+rename through ID lookup),
  `duplicate_registration_fails_without_replacing_the_original`,
  the private-field compile probe evidence in `core-model`/`SessionKey`, and
  the `tui::app::App::new` / `provider()` wiring in `tui-app`.