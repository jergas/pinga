# PB-01 second review — viewer boundary corrections

2026-09-24. 119 tests/all-target lint/whitespace pass. Earlier form visibility,
rule precedence, paths and tracking separation improved. CHANGES REQUESTED,
same builder, narrow final batch; no installs/global edits/deployment.

1. Empty GLOW_CONFIG_HOME does NOT isolate config. Upstream main.go
   tryLoadConfigFromDefaultPlaces prepends that directory to other config paths;
   it does not replace them. Publish a valid minimal glow.yml there, use verified
   flags/config precedence, and neutralize behavior-changing ambient GLOW_*
   settings (e.g. GLOW_TUI=true conflicts with -p). Prove with a hostile personal
   config fixture against the actual supported release, or mark executable
   verification pending; an env-map assertion is not that test.
2. Current Glow declares cobra.MaximumNArgs(1); `glow -p -- %s` breaks on
   multiple selected files. Verify/pin the supported release and implement
   sequential one-file invocations or explicitly open only the focused file
   with a documented single-file policy. Never silently claim multi-file viewer
   support because a recorder executable accepted multiple args. The shell test
   manually emulates Yazi quoting and substitutes a recorder for Glow: label
   precisely what it proves and what still requires real-tool validation.
3. PAGER=less drops Glow's normal raw-color pager flag and can display ANSI
   escapes. Pin suitable `less -R` behavior for both viewers; account for ambient
   LESS options that can cause immediate exit. Check the actual pager executable
   too. Preserve filenames/-- handling. Review fallback failures as user-visible.

Primary source inspected (current main; verify target version):
https://raw.githubusercontent.com/charmbracelet/glow/master/main.go
Relevant: MaximumNArgs(1), pager invocation, tryLoadConfigFromDefaultPlaces.

Keep the scope small. Update blueprint/prose/report, add meaningful regressions,
run gates and repeat fidelity, return concise report. No fabricated installed
version or smoke claim: Yazi/Glow are not installed yet. Cite exact versions
for source-reviewed behavior. A real-tool smoke remains the acceptance step
after dependencies are installed by an authorized action.
