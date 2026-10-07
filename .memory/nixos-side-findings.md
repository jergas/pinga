# NixOS findings, and the open push decision

Written 2026-10-06 by opencode, from the NixOS install of eris. Intended for
whoever picks up pinga on Omarchy. **No git operations were performed on this
repository** beyond adding these documentation files — no rebase, no commit, no
push. Nothing has been merged.

Context for the identity/authorisation questions below: `.memory/git-identity.md`.

## The short version

`master` is 8 commits ahead of `origin/master` and unpushed. A branch carrying
**all 8 of those commits plus one fix** is already open as
**https://github.com/jergas/pinga/pull/1** (`ahead_by=9`, `mergeable: CLEAN`).

So the work is not stranded on one disk, but it is also **not on `master`**, and
the decision to merge is still open with jergas. Nothing has been lost either
way — closing the PR and deleting the branch leaves `master` untouched.

The reason it was not simply pushed is the answer to the question that prompted
it: **the installer has not been shown to work outside Omarchy.** Details below,
because "we tested it on NixOS" would be a misleading summary.

## What was actually verified, on a second host

Tested from NixOS (eris, nixos-26.05, glibc 2.42) against the local fixture
server, using the installer's own `PINGA_BASE_URL` hook.

**Verified — the installer's own logic.** Asset selection for OS/arch, download,
sha256 fetch and verify, install with mode 755, deployment of all four systemd
unit files, `daemon-reload`, three `systemctl --user enable` calls, and the new
pre-install execute-check correctly rejecting a bad artifact and accepting a
good one. `sh -n` clean.

**Not verified — anywhere off Omarchy.**

1. `install.sh` has **never produced a working pinga** on a non-Omarchy host. On
   NixOS it either installed a dead binary (before the fix) or refuses with a
   diagnostic (after). Neither is "it works".
2. The **post-install state is still broken on NixOS.** `pinga-up.service` fails
   because `pinga-tmux-restore` cannot find `tmux`: a systemd *user* unit gets a
   minimal `PATH` with no `/run/current-system/sw/bin`. This is a second
   NixOS-specific defect, in the units rather than the installer, and it is
   **unfixed**. Even given a working binary, the boot path is unproven.
3. **The installer's default code path has never executed at all.** There are no
   releases and no tags on `jergas/pinga`, so `releases/latest/download` — the
   `BASE_URL` used when `PINGA_BASE_URL` is unset — has never been reached. Every
   test so far went through the local fixture.

Worth keeping distinct: what *did* work on NixOS was `make install`, a **source
build**. That is a different code path from `install.sh`, and its success says
nothing about the installer.

## Two concrete NixOS blockers, for whoever wants to fix them

1. **No musl-static artifact.** Release binaries are linked against glibc, and
   NixOS's `/lib64/ld-linux-x86-64.so.2` is a deliberate stub that only prints an
   explanation and exits 127. Either publish a static/musl build in
   `.github/workflows/release.yml`, or document source builds as the NixOS path.
2. **The systemd user units need an explicit `PATH`.** Independent of libc.
   Setting `Environment=PATH=` in the units (as the Omarchy `opencode.service`
   already does) would resolve it.

## The honest gate for "verified outside Omarchy"

Not yet reached. The real test is:

1. merge PR #1 (or push those 8 to `master`)
2. tag `v*` so the workflow produces an actual release
3. on a second host, run `sh deploy/install.sh` with **no** `PINGA_BASE_URL`

That exercises the default URL, a real release, and a clean host in one go. Cheap,
once merged. Until then the strongest defensible claim is: *verified on Omarchy;
installer logic verified on a second host; NixOS explicitly unsupported, with the
two blockers above named.* Anything stronger in the README would be ahead of the
evidence.

## Open decisions for jergas

- **Merge or re-author first?** The 9 commits are authored
  `Jergas Apwith <spam@jerx.net>`, which is **not verified** on the GitHub
  account, so they will show as unlinked rather than under the profile. Merging
  freezes that into permanent history. Re-authoring is described in
  `.memory/git-identity.md` — note it **aborts from Omarchy** until
  `/home/edgar/.gitconfig` exists, so set the identity first.
- **Whether to pursue NixOS as a supported platform.** Stated intent is that every
  system should be supported. That needs the musl artifact, not just the honest
  failure.

## Resolution (2026-10-07, Omarchy)

- The execute-check fix (PR #1) was cherry-picked onto the re-authored
  history as `87327ae`; PR #1 closed as consumed.
- Blocker 1 (no musl artifact) fixed: the Linux build in the release workflow
  now produces `x86_64-unknown-linux-musl` (static; runs on glibc AND musl
  distros incl. NixOS). Verification happens in CI on the first tagged run.
- Blocker 2 (unit PATH) fixed: all three units carry
  `Environment=PATH=/run/current-system/sw/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:%h/.local/bin`.
- The honest gate remains: tag `v*`, then run `sh deploy/install.sh` with no
  `PINGA_BASE_URL` on a second host.
