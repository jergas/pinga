# pinga — session console for opencode & codex
# Literate build: blueprint.md is the source of truth; src/ is derived.

BLUEPRINT := blueprint.md
PY        := python3
WEAVE     ?= pandoc

.PHONY: all tangle weave check test lint build clean

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

clean:
	@rm -rf src target blueprint.html