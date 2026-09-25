# PB-01 / first review — corrections requested

2026-09-24. Independent 108 tests, all-target lint, tangle fidelity and
whitespace pass. Not accepted yet. Same DeepSeek builder, preserve provider
work; no install/global config/deployment. Correct this batch then report.

1. **Visible errors:** commit_browse errors set self.error while Browse stays
   open, but render prioritizes edited over error and the modal contains no
   error line. Invalid paths/missing tools therefore appear to do nothing.
   Show errors alongside the still-editable form in BOTH modal and inline modes.
   Test rendered output after failing Enter, not just self.error contents.

2. **Actual opener selection:** append_rules leaves Yazi default text/code/image/
   archive rules ahead of the proposed bat fallback. Defaults open editors,
   external apps and extractors. Replace the open.rules list for this private
   profile: Markdown -> Glow, supported text/code -> bat, unsupported -> clear
   refusal. Don't claim binary refusal without testing bat's actual behavior.
   Upstream default source inspected:
   https://raw.githubusercontent.com/sxyazi/yazi/main/yazi-config/preset/yazi-default.toml
   Ensure this applies to the supported release. Add end-of-options handling;
   verify filenames reach viewers intact through the OPENER shell/placeholder
   boundary, not merely Pinga's outer Yazi argv. Profile string contains tests
   do not prove this. Cover leading '-', quotes, spaces, Unicode and multi-select.

3. **Isolation and profile publication:** packet requires isolation for all
   three tools, not only Yazi. Explicitly pin private/minimal Glow and bat
   configs and pager behavior using supported flags/env. Test hostile ambient
   config/pager settings cannot replace intended viewers. Do not overwrite
   global config. A shared fixed .yazi.toml.tmp is unsafe with concurrent Pinga
   instances: use unique temp publication or locking and test concurrent writers.
   Resolve profile/state paths absolute for launches after cwd changes; reject
   unrepresentable paths, never to_string_lossy into another pathname. Keep
   browser override scoped to browsing; explain/revert the incidental change
   that now makes PINGA_STATE_DIR also relocate provider tracking.

4. **Root semantics:** start_browse only checks absolute, not existing directory.
   Missing/deleted/file-valued session directories must fall back to Pinga cwd.
   resolve_directory trims real path whitespace despite the literal-path
   contract; preserve nonempty paths exactly, including leading/trailing spaces.
   Explicitly reject non-UTF-8 canonical roots/profile paths rather than silently
   substituting replacement characters. Test zero-provider Browse via the actual
   key handler, missing cwd and fallback cases. Keep invalid edits intact.

5. **Evidence/report:** add actual browse-path partial-suspend/spawn/restore and
   tmux failure tests and installed-location/profile-lifetime assertions; don't
   cite successful launch tests as failure coverage. Separate doc-verified from
   executable-tested behavior. Correct generic Debian Yazi installation claims
   unless verified for a named supported release; this host is Arch. No real
   Yazi/Glow smoke is required to fabricate a pass: list it as pending, but pin
   supported versions and provide reviewable install/manual test instructions.

Implement through blueprint prose/chunks; run all original gates and update
PB-01-report.md with corrected requirement-to-test mapping. Return concise
results directly to Pinga architect thread 01a0cb2e-e31c-7e33-8094-ac926ac14b53.
