# PA-01 Stage 1 — architect review

Review revision: 1, 2026-09-22.
Task reviewed: PA-01 Stage 1, revision 1.
Verdict: CHANGES REQUESTED. Do not start Stage 2 yet.

## Independent validation

- Read the implementation report and inspected executable chunk differences
  against preparation HEAD `e81cef7d78ef76e58bc421dc67d552de842284ef`, separating
  the architect's prior documentation corrections from implementation changes.
- Generated files matched the blueprint before tangling; two successive
  `make tangle` runs produced byte-identical generated outputs.
- `make check`: passed. `make test`: 11 passed, 0 failed. `make lint`: passed.
  `git diff --check`: passed.
- No live provider sessions, real Codex home, or tmux state were modified.
- Overall structure and scope are correct: enum dispatch was replaced,
  built-in composition is outside the TUI, and constructor errors propagate
  through the existing cleanup path. Existing runtime behavior was preserved
  in the inspected changes. This is static review plus fixture validation,
  not a live terminal/UI smoke-test claim.

## Required corrections

### R1 / P2 — SessionKey does not enforce its nonempty-ID invariant

Location: `blueprint.md`, `core-model`, `SessionKey` fields (review-time lines
499–502; generated `src/model.rs` lines 35–38).

Both fields are public, so another module can construct an empty key directly
or clear `native_id` after the validated constructor succeeds. An independent
temporary Rust program compiled against the actual model and confirmed both:

```rust
SessionKey { provider: valid_provider_id, native_id: String::new() }
// Or, after successful construction:
key.native_id.clear();
```

This defeats the known-session identity guarantee on which subsequent tracking
work will rely. The constructor test alone cannot establish the invariant.

Make the key representation private and expose immutable accessors. Keep the
validated constructor as the construction path; do not expose mutable access
to the native ID. Preserve equality/hash/ordering and the existing rejection
test. No mutable setters, serialization machinery, or persistence changes are
needed in this stage. Verify the two bypass forms no longer compile from a
sibling module; this may be a recorded temporary compile probe rather than a
new compile-fail testing dependency.

### R2 / P2 — Required behavior is not demonstrated by the acceptance tests

Location: `blueprint.md`, `prov-mod`, registry tests, especially
`builtin_composition_preserves_default_ids_order_and_types` (review-time line
806) and `lookup_dispatches_to_the_intended_adapter` (line 764).

The composition test uses only `Config::default()` and checks metadata. It
would still pass if composition ignored `cfg.opencode_url` or `cfg.codex_home`.
The direct Codex fixture tests its constructor, not config-to-registry wiring.
The implementation itself currently passes the right fields; the missing
evidence is important because preserving that wiring is an explicit acceptance
criterion and the report describes it as covered.

Add a composition test using a non-default OpenCode URL and a temporary Codex
home containing a fixture. Obtain adapters through `builtin_registry` and
verify the OpenCode attach command uses that URL and Codex listing reads that
fixture. Never list the real/default Codex home. No live HTTP server is needed
to establish this configuration wiring.

The dispatch fake does not override `create`, and successful rename has no
observable argument capture. The current tests check list/attach, one rename
error, and default unsupported create, but do not prove all four operations
reach the intended fake with the supplied inputs. Add distinguishable fake
implementations/recorded calls for successful create and rename through ID
lookup, asserting recipient, session, title, and directory as applicable.
Keep a separate fake using the default unsupported create implementation.
Fixture sessions should carry the fake's actual provider ID rather than
`unused`, so test data respects the documented adapter identity contract.

Also strengthen duplicate rejection with a distinguishable replacement fake:
after the rejected insertion, verify the original fake's behavior remains.
The existing count/order assertions alone would miss replacement followed by
an error. This is the already-assigned "without replacement" criterion.

Update the implementation report and blueprint test-coverage claims to match
the checks actually performed. Do not expand into Stage 2 or provider protocol
changes. These corrections complete Stage 1's original identity and acceptance
requirements.

## Non-blocking design answers

- `ProviderDescriptor.type_key` and `display_name` being `&'static str` is
  acceptable for Stage 1. Configurable display names will need owned strings
  in the later configuration task; do not preempt that work here.
- The app's checked index access followed by `expect` preserves its prior
  indexing precondition while built-in composition always supplies two
  providers. This is not a constructor-error regression. Remove the fixed
  indexing assumption when generic provider views are introduced.
- Remaining fixed UI arrays and numeric tracking are intentional Stage 1
  limitations, not findings against this implementation.

## Return workflow

Use the SAME DeepSeek/OpenCode implementation conversation for these focused
corrections; its task context is useful now. Read this review, change executable
chunks/prose in `blueprint.md`, run the original checks and repeat-tangle hash
comparison, and update `PA-01-stage-1-report.md` with R1/R2 evidence and the new
test count. Append a project log entry. Leave this review unchanged as the
record of what was requested. No commit/install/live-session mutations.

Tell the user "PA-01 Stage 1 corrections are ready for architect re-review."
The architect will write the next review result after inspecting the fixes.
