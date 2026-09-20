# pinga — session console for opencode & codex
# Literate build: blueprint.md is the source of truth; src/ is derived.

BLUEPRINT := blueprint.md
PY        := python3
WEAVE     ?= pandoc
BINDIR    ?= $(HOME)/.local/bin

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

## Compile a release binary and put it on PATH as `pinga`.
## Ensures the literate source is tangled first, then installs the release
## binary into $(BINDIR) (default ~/.local/bin, which is on this user's PATH).
install: tangle build
	@install -Dm755 target/release/pinga $(BINDIR)/pinga
	@echo "installed pinga -> $(BINDIR)/pinga"

uninstall:
	@rm -f $(BINDIR)/pinga
	@echo "removed $(BINDIR)/pinga"

clean:
	@rm -rf src target blueprint.html