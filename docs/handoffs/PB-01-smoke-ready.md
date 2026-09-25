# PB-01 — ready for dependency installation and real-tool smoke

2026-09-24. Final candidate independently passes 119 tests, all-target clippy,
generated-source/repeat-tangle fidelity and whitespace. Reviewed fixes cover
form errors, opener precedence, literal roots, private published configs and
single-file viewing. No further builder batch currently assigned.

This is readiness for smoke testing, not acceptance of untested interactive
behavior or a guarantee that every ambient viewer environment option is ignored.
Executable verification of Yazi substitution, Glow config/pager and return flow
is still pending. bat and less exist; Yazi/Glow do not.

Local Arch package metadata offers yazi 26.9.1-2 and glow 3.0.0-2, both MIT;
installation candidate: sudo pacman -S --needed yazi glow. No installation has
been performed. User confirmation is requested because this is a system package
change outside the no-install implementation batch.

After approval: install tools, verify versions, build candidate, test private
config against hostile ambient settings and selected filenames, then user smoke
`b` -> directory -> Markdown/code viewer -> q back to Yazi -> q back to Pinga.
Test both tmux and standalone terminal restoration. No normal viewer config
should be overwritten. Single-file viewing opens the first selected file.
