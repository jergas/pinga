# Memory Update Log

## [2026-09-16] INIT | Created project memory vault
## [2026-09-16] SETUP | Initialised pinga vault via mnemosyne/init-memory-system.sh; recorded eris ergonomics + persistence architecture as ADR 0002, session gotchas, and mirrored notes into ai-memory (project pinga)
## [2026-09-16] FIX | Resolved opencode session split-brain (two servers on ses_f5416a477ffef4yNuMa5BLYWlJ); kept systemd :4096 backend + tmux client, exited stray TUI. Created tmux window layout in session `main`: `edgar` (opencode) / `codex` / `shell`
## [2026-09-17] TOOLING | Consolidated codex to the standalone 0.154.0 only: removed mise tool + pacman openai-codex (0.153.4); `command -v codex` now → ~/.local/bin/codex in every shell
## [2026-09-17] SPEC | Wrote pinga's literate blueprint (blueprint.md, ~1400 lines): requirements R1–R11, verified opencode/codex integration (§5), decisions D1–D7, 12 tanglable code chunks
## [2026-09-17] TOOLING | Added literate toolchain: tools/tangle.py (zero-dep), tools/tangle.lua (pandoc), Makefile (tangle/weave/check/test/lint). AGENTS.md build commands switched from pnpm placeholders to real ones
## [2026-09-17] BUILD | First tangle compile: fixed opencode rename borrow (E0515), codex Instantish FromStr (E0277), added tui::mod, wrote real layout_rects/hit_rect helpers, made handle_key arm-splitting clean. GATES GREEN: cargo check + clippy -D warnings + cargo test
## [2026-09-17] TEST | First manual run: R10 handoff works (codex resumed via pinga, pinga returned). Resumed thread was an EMPTY vscode seed (01a0ad0f) — codex exited cleanly (task_complete, exit 0), not a crash. Added has_conversation() seed-thread filter to provider::codex list() so empty threads don't appear resumable
## [2026-09-17] FIX | Rename editing: replaced blind String buffer with TextEdit line editor (char buffer + cursor, ←/→/Home/End/Delete/Backspace) + visible bottom overlay "rename: <text> ▌ [Enter apply · Esc cancel]". QUIT: teardown now also DisableMouseCapture + Show cursor (SGR mouse sequences were leaking to the shell after q), and q exits 0 instead of Rust printing Error: quit
## [2026-09-17] TEST | Rename confirmed working + persistent across quit/rerun (opencode re-read confirmation proves the write lands); q exits clean, no SGR mouse leak. Awaiting tmux-path (R9) test before commit
