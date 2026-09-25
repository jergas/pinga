# PA-01 Stage 2 — third review / two remaining blockers

2026-09-22. Verdict: CHANGES REQUESTED. Same DeepSeek/OpenCode session.
Preserve resolved A–C work; implement this bounded correction batch, then stop
for review. Stage 3 remains unassigned. No deployment or live provider mutation.

Independent validation: 56 tests, check, lint, whitespace, generated-source
fidelity and two repeat tangles all pass. Startup eligibility transitions,
strict argv shapes, resume capability guard, and actual suspension/restoration
failure handling are improved. Two previous requirements remain incomplete.

## D / P1 — endpoint parsing must be fallible without proving absence

`opencode::endpoint_parts` uses `chars().position(...)` as a byte slice offset.
`http://é/abc` panics inside the multibyte character. Architect reproduced this
by compiling the unchanged parser in a temporary standalone Rust probe.
The same probe shows `http:///oops` accepted with an empty host.

More importantly, `endpoints_match` maps parse failure to false, and both exact
attach argv branches interpret false as a positively different server. Thus
`opencode attach not-a-url -s ses_x` produces no candidate, allowing tracking
to be dropped. The existing `unparseable_attach_is_ambiguous` test only tests
missing argv, not an unparseable endpoint in an otherwise accepted argv shape.

Use validated URL parsing or a genuinely bounded parser. Distinguish equivalent,
positively different, and unknown endpoints; unknown yields Ambiguous. Reject
unsupported forms conservatively, without panicking. Do not silently discard
userinfo or alter fragment bytes into a claim of equivalence. Preserve the
agreed host/loopback and trailing-path-slash policy and query/path case.
Fix the contradictory stacked normalization comments along with the code.

Tests must cover Unicode authorities (no panic), missing/empty host, malformed
URLs in BOTH supported attach shapes, and valid different servers (still no
match). Exercise malformed evidence through reconciliation to demonstrate
record and initial eligibility retention. No live network or DNS required.

## E / P2 — retain a newly created identity independently of list visibility

`create_new_session` appends the known session to the snapshot. Foreground
`open_session` immediately calls `refresh`, which replaces that snapshot with
the successful list result. If the just-created session is not yet returned,
its identity is lost after the launch failure. The new retention test masks
this by setting `f.list_out = vec![fake_session("one")]` before creation.
The same overwrite affects a later refresh after a plan/tmux launch failure.

Keep an explicit in-memory set of locally created, not-yet-observed sessions,
keyed by SessionKey. Merge these into successful snapshots without duplicates
until the provider listing has actually observed them; then normal authoritative
listing policy applies. A retry must resume the retained identity, never call
create again. This is not a persisted successful-open record and does not
require changing Stage 2's on-disk format. Keep failure status useful.

Add an actual application sequence: create returns known identity, foreground
spawn fails, list succeeds empty on the immediate AND subsequent refreshes,
identity remains selectable, retry resumes with create count still one. Cover
eventual list visibility without duplicate rows and subsequent ordinary removal;
also assert retention across refresh after a plan or tmux spawn failure.

## Delivery

Implement via blueprint chunks and adjacent prose; update the report with D/E
test evidence and correct its obsolete startup_eligible tuple description.
Run tangle/check/test/lint, repeat-tangle fidelity and diff whitespace checks.
Use the same session and one writer. Do not edit previous review packets.
The architect has changed only review/memory documentation, not implementation.
