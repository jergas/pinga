# pinga — session console for opencode & codex
# Literate build: blueprint.md is the source of truth; src/ is derived.

BLUEPRINT := blueprint.md
PY        := python3
WEAVE     ?= pandoc
BINDIR    ?= $(HOME)/.local/bin
SYSTEMD_DIR ?= $(HOME)/.config/systemd/user

.PHONY: all tangle weave check test lint build install uninstall clean

all: tangle

## Tangles src/ out of blueprint.md (zero deps, always works)
tangle:
	@$(PY) tools/tangle.py $(BLUEPRINT)

## Optional: render blueprint.md to a readable HTML export (needs pandoc)
weave:
	@$(WEAVE) --standalone --toc --metadata title="pinga blueprint" $(BLUEPRINT) -o blueprint.html
	@echo "wrote blueprint.html"

## CI-style gates against the tangled output
check:
	@cargo check

test:
	@cargo test

lint:
	@cargo clippy -- -D warnings

build:
	@cargo build --release

## Compile a release binary and put it on PATH as `pinga`, and install the
## tmux-reboot-survival timer. Ensures the literate source is tangled first,
## then installs the release binary + the tmux-save systemd user timer and
## attempts to enable it (non-fatal if there's no systemd user session).
install: tangle build
	@install -Dm755 target/release/pinga $(BINDIR)/pinga
	@install -Dm755 deploy/pinga-tmux-save $(BINDIR)/pinga-tmux-save
	@install -Dm755 deploy/pinga-tmux-restore $(BINDIR)/pinga-tmux-restore
	@install -Dm644 deploy/pinga-tmux-save.service $(SYSTEMD_DIR)/pinga-tmux-save.service
	@install -Dm644 deploy/pinga-tmux-save.timer $(SYSTEMD_DIR)/pinga-tmux-save.timer
	@install -Dm644 deploy/pinga-tmux-restore.service $(SYSTEMD_DIR)/pinga-tmux-restore.service
	@install -Dm644 deploy/pinga-up.service $(SYSTEMD_DIR)/pinga-up.service
	@echo "installed pinga -> $(BINDIR)/pinga"
	@echo "installed tmux-save timer + restore service + bring-up service -> $(SYSTEMD_DIR)/"
	@if command -v systemctl >/dev/null 2>&1 && systemctl --user daemon-reload >/dev/null 2>&1; then \
		systemctl --user enable --now pinga-tmux-save.timer >/dev/null 2>&1 && echo "enabled pinga-tmux-save.timer" || echo "warning: could not enable pinga-tmux-save.timer"; \
		systemctl --user enable pinga-tmux-restore.service >/dev/null 2>&1 && echo "enabled pinga-tmux-restore.service (runs at boot)" || echo "warning: could not enable pinga-tmux-restore.service"; \
		systemctl --user enable pinga-up.service >/dev/null 2>&1 && echo "enabled pinga-up.service (brings the session up at boot)" || echo "warning: could not enable pinga-up.service"; \
	else \
		echo "note: no systemd user session here; install the units manually (deploy/)"; \
	fi

uninstall:
	@rm -f $(BINDIR)/pinga $(BINDIR)/pinga-tmux-save $(BINDIR)/pinga-tmux-restore
	@rm -f $(SYSTEMD_DIR)/pinga-tmux-save.service $(SYSTEMD_DIR)/pinga-tmux-save.timer $(SYSTEMD_DIR)/pinga-tmux-restore.service $(SYSTEMD_DIR)/pinga-up.service
	@systemctl --user daemon-reload >/dev/null 2>&1 || true
	@echo "removed pinga + tmux-save timer + restore service + bring-up service"

clean:
	@rm -rf src target blueprint.html