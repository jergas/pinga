#!/usr/bin/env sh
# pinga installer — one script, every platform.
#
# Downloads the prebuilt pinga binary for this OS/arch from GitHub releases,
# verifies its sha256, installs it, and on Linux with systemd also deploys and
# enables the boot units (resurrect restore, save timer, bring-up).
#
# Works on Linux and macOS (POSIX sh; curl required). Windows is not
# supported: pinga's console and bring-up need tmux, systemd and /proc — use a
# Linux/macOS host or WSL, or `pinga remote connect` from any ssh-capable
# machine.
#
# Overrides:
#   PINGA_REPO=user/repo   default: jergas/pinga
#   PINGA_VERSION=vX.Y.Z   default: latest (uses the latest release)
#   PINGA_BASE_URL=...     full base URL for the release assets (testing)
#   PREFIX=/path           default: $HOME/.local
#   PINGA_SKIP_UNITS=1     skip the systemd unit deployment
set -eu

REPO="${PINGA_REPO:-jergas/pinga}"
VERSION="${PINGA_VERSION:-latest}"
PREFIX="${PREFIX:-${HOME}/.local}"

say() { printf 'pinga-installer: %s\n' "$*"; }
die() { say "error: $*" >&2; exit 1; }

[ -n "$(command -v curl)" ] || die "curl is required"

# ---- detect OS/arch ---------------------------------------------------------
os="$(uname -s)"
arch="$(uname -m)"
case "$os" in
    Linux) asset_os="linux" ;;
    Darwin) asset_os="macos" ;;
    *) die "unsupported OS: $os (pinga needs tmux/systemd; use Linux or macOS, or WSL)" ;;
esac
case "$arch" in
    x86_64|amd64) asset_arch="x86_64" ;;
    arm64|aarch64) asset_arch="aarch64" ;;
    *) die "unsupported architecture: $arch" ;;
esac

if [ -n "${PINGA_BASE_URL:-}" ]; then
    BASE_URL="$PINGA_BASE_URL"
elif [ "$VERSION" = "latest" ]; then
    BASE_URL="https://github.com/${REPO}/releases/latest/download"
else
    BASE_URL="https://github.com/${REPO}/releases/download/${VERSION}"
fi

ASSET="pinga-${asset_os}-${asset_arch}"
BINDIR="$PREFIX/bin"
mkdir -p "$BINDIR"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ---- download + verify ------------------------------------------------------
say "downloading $ASSET from $BASE_URL"
curl -fsSL -o "$tmp/$ASSET" "$BASE_URL/$ASSET" || die "download failed"
curl -fsSL -o "$tmp/$ASSET.sha256" "$BASE_URL/$ASSET.sha256" || die "checksum download failed"

if [ -x "$(command -v sha256sum)" ]; then
    CHECK="sha256sum -c"
elif [ -x "$(command -v shasum)" ]; then
    CHECK="shasum -a 256 -c"
else
    die "no sha256 tool found"
fi
( cd "$tmp" && $CHECK "$ASSET.sha256" ) >/dev/null || die "checksum mismatch — refusing to install"

install -m755 "$tmp/$ASSET" "$BINDIR/pinga"
say "installed $BINDIR/pinga"

# ---- systemd units (Linux only) ---------------------------------------------
if [ "$asset_os" = "linux" ] && [ -z "${PINGA_SKIP_UNITS:-}" ] && command -v systemctl >/dev/null 2>&1; then
    SYSTEMD_DIR="${SYSTEMD_DIR:-$HOME/.config/systemd/user}"
    say "deploying boot units to $SYSTEMD_DIR"
    curl -fsSL -o "$tmp/pinga-deploy.tar.gz" "$BASE_URL/pinga-deploy.tar.gz" || die "deploy bundle download failed"
    curl -fsSL -o "$tmp/pinga-deploy.tar.gz.sha256" "$BASE_URL/pinga-deploy.tar.gz.sha256" || true
    if [ -s "$tmp/pinga-deploy.tar.gz.sha256" ]; then
        ( cd "$tmp" && $CHECK pinga-deploy.tar.gz.sha256 ) >/dev/null || die "deploy bundle checksum mismatch"
    fi
    ( cd "$tmp" && tar xzf pinga-deploy.tar.gz )
    mkdir -p "$SYSTEMD_DIR"
    install -m755 "$tmp/pinga-tmux-save" "$BINDIR/pinga-tmux-save"
    install -m755 "$tmp/pinga-tmux-restore" "$BINDIR/pinga-tmux-restore"
    for f in pinga-tmux-save.service pinga-tmux-save.timer pinga-tmux-restore.service pinga-up.service; do
        install -m644 "$tmp/$f" "$SYSTEMD_DIR/$f"
    done
    systemctl --user daemon-reload >/dev/null 2>&1 || say "warning: daemon-reload failed"
    systemctl --user enable --now pinga-tmux-save.timer >/dev/null 2>&1 \
        || say "warning: could not enable pinga-tmux-save.timer"
    systemctl --user enable pinga-tmux-restore.service >/dev/null 2>&1 \
        || say "warning: could not enable pinga-tmux-restore.service"
    systemctl --user enable pinga-up.service >/dev/null 2>&1 \
        || say "warning: could not enable pinga-up.service"
    say "boot units enabled"
else
    say "no systemd user session (or skipped); only the binary was installed"
fi

say "done — run 'pinga' (or 'pinga remote connect <name>')"