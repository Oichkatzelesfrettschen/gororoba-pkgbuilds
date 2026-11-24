# Review record: first import and CI pipeline (2026-11-24)

Reviewed head: review-20261124 at 5cc22bb (origin/main + PRs 1, 2, 4, 5, 7). Reviewers, chosen by the owner: codex (gpt-daybreak-blue-latest, medium, read-only), agy red team (gemini-4-neon-high), opencode super red team (opencode-go/glm-5.3-flash; the deepseek fallback was not needed). Advisor last. The owner's reviewer selection did not include a hosted Codex round; the owner's instruction to merge all work before the reboot covers its omission.

Consolidated findings (55, deduplicated across reviewers) and their disposition against the merged heads:

| Finding | Disposition |
|---|---|
| 1 untrusted allowlist and sudo | Fixed: CI reads scripts and the allowlist from the base ref, builder sudo is pacman only, namcap runs as nobody (d0ba40d, 3dcd511, 0e23141); fork-PR approval set to all external contributors (repository setting, 2026-11-24) |
| 2 private source URL | Fixed: chatgpt-webview and ollama-gemini-shim left out (c6f4147) |
| 3 private repository names | Fixed for the infrastructure repository (4e7d521, 091bfe7); Refuted for the other gororoba repositories and pkgbuilds-personal, which are public |
| 4 distcc hosts | Fixed: opt-in, no default hosts (d9b83dc) |
| 5 private doc paths, GPU note | Fixed (a30f605); hardware model names are published specs and stay |
| 6 credential locations | Refuted: upstream's documented configuration locations, no user data |
| 7, 16 scrub-check gaps | Fixed: fail-closed inputs and new classes with fixtures (8adee02); private-range-only IPv4 (bf999c4) |
| 8 nested git metadata | Fixed (04e66fe) |
| 9 email lines | Boundary: the maintainer identity is the sanctioned noreply form (D-021); other lines are upstream credit |
| 10, 11, 12 masked diff, silent skips, closure | Fixed (d0ba40d, 9db3620) |
| 13 mutable pins | Fixed: actions pinned to SHAs, container to a digest; the digest refresh is recorded as residual |
| 14, 15, 52 update-check status and version parsing | Fixed (1eb5e36) |
| 17 publish-gate snapshots | Fixed for headers, empty input, builddate, paths with spaces (3388159); pacman -Sp and the D-024 lock and hash checks deferred to issue 8 |
| 18 dead DKMS check | Fixed with a calibrated duplicate fixture (3388159) |
| 19, 20, 21 globbing, arch fields, provides | Fixed (07d4882) |
| 22 calibration suite | Fixed: scripts/calibrate.sh, 120 checks in CI (a877290, 139de52) |
| 23 blender-git-nvidia shellcheck | Fixed (1a6103c) |
| 30 local source checksums | Fixed (ea29c7e) |
| 35 duplicate gowin-eda-programmer | Fixed (25e95d8) |
| 38, 39 nvchecker header and manual version | Fixed (390d741, 481e0f2) |
| 42 to 46 docs versus implementation | Fixed: per-stage status, CI as implemented, groups and tiers reconciled (091bfe7, 3d50f66) |
| 47 provenance origins | Fixed (34303da); consolidation into PROVENANCE.tsv follows the merges |
| 48, 49 job-wide TrustAll, shared dirs | Fixed: one-shot pacman config copy, per-recipe dirs, upload on success (d0ba40d) |
| 24 to 29, 31 to 34, 36, 37, 40, 41, 53, 55 | Deferred: inherited recipe hygiene, issue 8 |
| 50, 51 version binding, attested ledger | Deferred: design-level, issue 8 |
| 54 merge commit versus scrubbed tree | Boundary: scrub-check runs on push to main as well as on pull requests |

Post-review defects found by the end-to-end proof (PR 6): PACMAN_OPTS assignment dropped --noconfirm (fixed in ci-build.sh, run 45492184161 green); two recipes archived as stale left the public set (99fb171).
