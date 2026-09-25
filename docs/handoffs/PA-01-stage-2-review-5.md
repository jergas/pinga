# PA-01 Stage 2 — acceptance

2026-09-22. ACCEPTED for the assigned scope.

Independent validation: 62 tests; make check/test/lint; generated-source
fidelity before tangling; two repeat tangles; git diff --check. All pass,
without the previous test compilation warnings.

The final endpoint change implements the requested conservative HTTP(S)
grammar and Unknown propagation. The integrated regression test registers the
real OpenCode adapter, supplies process evidence and a seeded successful-list
snapshot, then checks record and startup-eligibility retention in the app.
It does not contact a live provider. Local creation retention and prior
lifecycle/capability/terminal fixes remain accepted.

Limits: this is fixture-based acceptance, not deployment or a live tmux/harness
smoke test. Unsupported URL forms intentionally yield Unknown. Two-slot UI,
numeric legacy tracking and in-memory pending launches remain transitional.
Stage 3 is now assigned separately; Pi/Antigravity are still out of scope.
