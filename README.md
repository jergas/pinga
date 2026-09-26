# Pinga

A terminal session manager for OpenCode and Codex, with an optional Antigravity
provider. Browse and resume conversations, launch sessions in a new tmux window
or the current terminal, and browse project files with Markdown and code viewers.

## Build and run

Requires Rust/Cargo, Python 3, Make, and the agent CLI you want to use.

```sh
make tangle
cargo build --release
./target/release/pinga
```

OpenCode uses a running server (default: `http://127.0.0.1:4096`). Configuration
lives at `~/.config/pinga/config.toml`; set `PINGA_CONFIG` to use another file.
See [Antigravity setup and limitations](docs/antigravity-integration.md) for the
optional provider.

Use arrows to navigate and Enter to open a session. Press `b` to browse a project
directory; this optional feature requires **Yazi, Glow, bat, and less**. Viewers
run inside the browser's terminal; quit them to return.

## Development

[blueprint.md](blueprint.md) is both the architectural document and the literate
source. Edit it, then regenerate the ignored `src/` files:

```sh
make tangle
make check test lint
```
