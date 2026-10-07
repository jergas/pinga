# Git identity: two installs, two identities

Written 2026-10-06 by opencode, from the NixOS side of eris. This note exists
because the next agent to work on pinga will otherwise waste time wondering why
commits made here and commits made there carry different authors.

## The situation

eris is dual-booted: NixOS and Omarchy. They are separate installations with
separate `$HOME`s, and **git identity is per-user, not per-machine**:

| Install | `$HOME` | Identity |
|---|---|---|
| NixOS | `/home/jergas` | `Jergas Apwith <2859532+jergas@users.noreply.github.com>` |
| Omarchy | `/home/edgar` | *nothing configured* (see below) |

`/home` is shared between the two installs — both home directories are visible
from either OS — so a config file written from one is seen by the other. What is
*not* shared is `$HOME`, and therefore which global config git reads.

## Why the noreply address

The previous address, `spam@jerx.net`, is **not verified** on the GitHub account
(`github.com/jergas`). Unverified addresses do not get attributed: commits
authored with it show on GitHub as unlinked rather than under the profile.
GitHub's noreply form `2859532+jergas@users.noreply.github.com` fixes the
attribution and keeps a real address out of commit metadata. Same reasoning as
the `gh` decision: do not scatter addresses across the net.

## Current state on Omarchy

- There is **no `/home/edgar/.gitconfig`**.
- There **is** `/home/edgar/.config/git/config` — git's XDG global config, read in
  addition to `~/.gitconfig`. It holds the curated setup (`co`/`ci`/`st` aliases,
  `init.defaultBranch=master`, `pull.rebase=true`, `push.autoSetupRemote=true`,
  histogram diff, `commit.verbose`) but **has no `[user]` section**.
- Therefore `git commit` on Omarchy currently has no configured identity and will
  fail or fall back to a guessed `user@hostname`.
- **No `GIT_AUTHOR_*` / `GIT_COMMITTER_*` environment variables exist** anywhere in
  `/home/edgar/.bashrc`, `.bash_profile`, `/etc/environment` or `/etc/profile.d`.
  This matters: environment variables outrank config files in git, so if they
  existed, writing a config file would change nothing. They do not, so a config
  file will take effect.
- `trickster` still carries `spam@jerx.net` **repo-locally** (`.git/config`).
  That one is unaffected by any global change and needs a separate decision.

## How to set it — and the trap to avoid

**Do not use `sudo git config --global ...`.** `sudo` resets `HOME` to `/root`, so
that writes `/root/.gitconfig` and configures *root's* git. It fails silently:
the command succeeds and nothing changes for `edgar`. Always name the file.

As `edgar`, in Omarchy, no root needed and no ownership risk:

```bash
git config --global user.name  "Jergas Apwith"
git config --global user.email "2859532+jergas@users.noreply.github.com"
git var GIT_AUTHOR_IDENT      # verify
```

Or from any install, as root, naming the file explicitly:

```bash
sudo git config --file /home/edgar/.gitconfig user.name  "Jergas Apwith"
sudo git config --file /home/edgar/.gitconfig user.email "2859532+jergas@users.noreply.github.com"
sudo chown 1000:1000 /home/edgar/.gitconfig    # root would otherwise own it
```

Prefer the first form. The second exists for the case where you cannot log in as
`edgar`, and it is safe only because `--file` is explicit and ownership is fixed
afterwards.

## Eight commits still carry the old address

`master` is 8 commits ahead of `origin/master`, and all 8 are authored
`Jergas Apwith <spam@jerx.net>`. Author is frozen into the commit object at
creation time, so changing the config now does **not** rewrite them.

They can be re-authored safely: nothing is pushed, nobody else holds them, so no
force-push is involved.

```bash
cd /home/edgar/projects/pinga
git rebase --exec 'git commit --amend --no-edit --reset-author' @{u}
git log --format='%an <%ae>' @{u}.. | sort -u   # expect the noreply address
git push
```

**Do not** rebase past `@{u}` and do not touch `trickster`'s history without
asking. Rewriting already-pushed history elsewhere in the projects tree would
force-push and break existing clones; that trade is only worth it if there is a
specific reason, and there is not one here.

## Do not "fix" this from the wrong side

If a future agent sees commits attributed to `spam@jerx.net` and concludes the
config is broken, check `$HOME` first. Running git from NixOS against this repo
reads `/home/jergas/.gitconfig` — the *correct, new* identity — which makes it
look configured even while Omarchy is not. That mismatch between what two
installs report is the entire source of confusion here.

## "Is the rebase the same from either install?" — no, and it fails loudly

Asked on 2026-10-06, because the natural assumption is that `/home` is shared so
the repo is shared so the command is shared. The repo *is* shared. The *identity*
is not, and the failure mode is not subtle. Verified:

```
$ env HOME=/home/jergas git var GIT_AUTHOR_IDENT
Jergas Apwith <2859532+jergas@users.noreply.github.com> 1791351312 -0600

$ env HOME=/home/edgar git var GIT_AUTHOR_IDENT
Author identity unknown
```

So the identical command

```bash
git rebase --exec 'git commit --amend --no-edit --reset-author' @{u}
```

- **from NixOS** (`$HOME=/home/jergas`): works. `--reset-author` picks up
  `/home/jergas/.gitconfig` and stamps the noreply address on every commit.
- **from Omarchy** (`$HOME=/home/edgar`): **aborts on the first commit** with
  `Author identity unknown`, because `/home/edgar/.gitconfig` does not exist.
  It does *not* silently fall back to `edgar@nixos` — it stops. A rebase that
  dies halfway leaves the repo mid-operation, so fix the identity first.

Order that works from either install: set `/home/edgar/.gitconfig` (the commands
above), then rebase. `/home` being shared means that one file fixes both.

Confirm before rebasing:

```bash
git var GIT_AUTHOR_IDENT     # must print the noreply address, not "unknown"
git rev-parse --abbrev-ref master@{upstream}   # expect: origin/master
```

`origin` here is `https://github.com/jergas/pinga.git` and `origin/master` is
`a92cb7e`, 8 commits behind local `master`. So the push that follows is a normal
fast-forward — no force, and no fork needed.

## Resolution (2026-10-07, Omarchy)

- Identity set: `git config --global user.name "Jergas Apwith"` /
  `git config --global user.email "2859532+jergas@users.noreply.github.com"`.
  With no `~/.gitconfig` present, the write landed in the XDG global config
  (`~/.config/git/config`) — which in fact already held a `[user]` section with
  `spam@jerx.net` (the earlier note claimed it had none; that was wrong, and it
  is exactly where the old author came from). The value was overwritten in
  place; `git var GIT_AUTHOR_IDENT` now resolves to the noreply address.
- The 8 unpushed commits AND the NixOS-side docs commit were re-authored with
  `git rebase --exec 'git commit --amend --no-edit --reset-author' @{u}` —
  all authors are now the noreply address.
- The NixOS agent's execute-check fix (PR #1, `a730527`) was cherry-picked
  onto the re-authored master (`87327ae`); PR #1 was closed as consumed.
  History is now single-identity and fast-forward pushable from `a92cb7e`.
