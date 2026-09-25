# PA-01 Stage 2 — fourth review / endpoint validation only

2026-09-22. CHANGES REQUESTED. Same implementation session; recommend High
reasoning. Preserve prior fixes. Stage 3 remains unassigned.

Independent validation: 60 tests, check, lint, repeat-tangle fidelity, and
whitespace checks pass. Test compilation emits unused-mut warnings. E's local
creation retention is accepted for this stage. D's Unicode panic and tri-state
comparison are fixed, but endpoint validation remains incomplete.

## Remaining P1: malformed endpoint is still positive absence

Architect compiled the unchanged endpoint functions in a temporary Rust probe.
All four of these return `Different` against `http://localhost:4096`:

- `http://bad host:4096`
- `http://localhost:banana`
- `http://localhost:99999`
- `1http://localhost:4096`

These are malformed, not positively different endpoints. The matcher therefore
still allows malformed process evidence to erase tracking. Checking only empty
scheme/host is not sufficient validation. Fix the class of inputs, not just
these four examples.

## Bounded implementation contract

For this stage it is sufficient to understand a conservative ASCII HTTP(S)
subset. Return Unknown for every unsupported form; wider URL support is not
required. Before producing Equal/Different:

1. Require scheme exactly HTTP or HTTPS, case-insensitive.
2. Reject non-ASCII, whitespace/control bytes, backslashes, userinfo, fragments,
   bracketed/unbracketed IPv6, and other unsupported authority syntax as Unknown.
   This deliberately permits conservative Unknown for Unicode hosts, never panic.
3. Accept a nonempty ASCII DNS/IPv4-shaped hostname: dot-separated nonempty
   labels of ASCII alphanumerics and internal hyphens; reject leading/trailing
   hyphens and unsupported punctuation. No DNS lookup. Reject invalid numeric
   IPv4 addresses rather than claiming they identify another server.
4. Optional port: exactly one colon followed by nonempty decimal digits parsing
   into a u16. Alphabetic, missing, signed, overflowing ports are Unknown.
5. Preserve path/query bytes and case; normalize only the agreed trailing path
   slashes. Reject malformed percent escapes; do not decode/reinterpret them.
6. Only after both endpoints pass validation may comparison establish Different.
   Preserve the existing localhost/127.0.0.1 equivalence policy.

You may use a URL library plus conservative raw-input checks instead, but do
not rely on a forgiving parser silently repairing malformed inputs. Document
the supported subset next to the literate implementation.

## Required evidence and completion

Add table-driven malformed/unsupported cases covering each rule above, BOTH
accepted attach argv shapes, and valid equal/different endpoints. Include
Unicode no-panic and existing path/query/trailing-slash regressions.

Add a test that actually routes malformed process argv through the OpenCode
adapter AND application reconciliation: initial tracked record + live window
+ successful provider list + malformed endpoint evidence must preserve both
record and startup eligibility. The current report cites a fake precomputed
Ambiguous result; that does not demonstrate adapter-to-app integration.

Run all gates and repeat-tangle verification. Remove introduced unused-mut
test warnings while touching those fixtures. Update the report to cite actual
tests, distinguishing adapter tests, policy tests, and integrated tests.
Keep previous review files immutable. No live provider/tmux operations,
installation, Stage 3 work, or deployment. Return for architect review.
