# Stage 3 / Antigravity — ready for supervised smoke testing

2026-09-23. Reviewed final correction batch. The candidate is ready for a
user-controlled live smoke test, not yet production/live-functionality verified.
Fixture tests cover the shared layout, retry identities, file-store conditional
updates, real process source collection and Antigravity adapter/app integration.

Architect final fixes: `p` retries the oldest pending unrecorded launch token,
with status text identifying its window/token; the keyboard handler is exercised
by the existing retry regression. Antigravity timestamp conversion is bounded
and uses checked milliseconds arithmetic. Preserve these blueprint changes.

## Run manually, inside an existing tmux session

The sample config preserves historical default OpenCode/Codex sources; adjust
them first if the user's current config uses different paths/endpoints. It does
not inherit custom naming/theme settings. This command uses a fresh tracking
directory, avoiding migration or writes to the normal Pinga tracking registry:

```sh
cd /home/edgar/Projects/pinga
pinga_test_state=$(mktemp -d /tmp/pinga-smoke.XXXXXX)
XDG_STATE_HOME="$pinga_test_state" PINGA_CONFIG="$PWD/docs/antigravity-smoke.toml" ./target/debug/pinga
```

Keep the printed variable/directory for a restart test; reuse the same value
rather than creating another directory. This isolates Pinga tracking ONLY:
choosing new/resume launches the real agy client and uses the configured live
Antigravity data. No such launch was performed by the architect.

1. Tab to Antigravity. An empty list is expected if there are no conversations.
2. Create one disposable conversation through `+ new session`; return to Pinga
   and refresh. Verify listing/title/directory against agy itself. Plain `agy`
   creation has no native ID in argv: its launch may remain pending and need
   not appear in the confirmed-running group. Do not guess the newest ID.
3. Close that disposable client deliberately, refresh, then select its listed
   conversation and press Enter. Verify the exact same conversation resumes,
   rather than merely a new app/window opening. Reopening a confirmed running
   exact-ID client should select its existing window.
4. Quit/restart Pinga using the SAME test tracking directory. Verify records,
   interrupted state and selection/navigation; test a narrow terminal too.

Report the failing step, visible error and observed behavior. Do not post private
conversation contents. If the runtime DB encoding/CLI differs from fixtures,
capture only the relevant schema/metadata and correct the adapter before wider
use. Rename remains unsupported. Config is opt-in; no normal config was changed.
