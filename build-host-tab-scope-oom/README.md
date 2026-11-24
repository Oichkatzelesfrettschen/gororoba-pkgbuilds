# Terminal tab scopes and systemd-oomd on the build host

The build host runs each Ptyxis tab and each tmux server in its own user scope
(`ptyxis-spawn-UUID.scope`, `tmux-spawn-UUID.scope` under `app.slice`). A
Claude Code, codex or agy session and every command it starts live in that
scope. Package `private-cachyos-system-tuning` sets `ManagedOOMSwap=kill` on
the root slice and the user slices with `SwapUsedLimit=90%`, so when memory
and swap both pass 90% systemd-oomd kills the descendant cgroup that holds the
most swap, provided it holds more than 5% of total swap.

## Measured

- 2026-11-16 23:46 UTC: systemd-oomd killed one tab scope of 353 processes
  with a 41.9 GiB swap peak; the tab held an agent session and the builds it
  had started inside its own scope. The session and every job ended together.
- 2026-11-17 01:10 UTC, 22 live tab and tmux scopes: 21 have a swap peak of
  1.7 GiB or less and one has 14.9 GiB. Memory peaks reach 39 GiB; anonymous
  memory is 1.2 GiB or less per scope.
- 2026-11-17 01:36 UTC, `memory.stat` of the same scopes: `shmem` is 0.0 GiB
  in each and the rest of `memory.current` is `file` (page cache); the
  largest scope holds 28.6 GiB, of which 27.6 GiB is page cache. `/tmp` is
  ext4, so files written there count as page cache and need no swap.
- systemd 262; a tab scope shows `OOMPolicy=stop`, `MemoryMax=infinity`,
  `MemorySwapMax=infinity`, `ManagedOOMPreference=none`.

## Mechanism of the drop-in

[10-tab-scope-oom.conf](10-tab-scope-oom.conf) gives each tab scope a 2 GiB
swap budget, a 16 GiB memory limit, `ManagedOOMPreference=avoid` and
`OOMPolicy=continue`. The swap budget keeps a tab under the 5% eligibility
threshold of the swap kill (3.19 GiB at 63.9 GiB of swap;
`THRESHOLD_SWAP_USED_PERCENT 5` in `src/oom/oomd-manager.h` at tag v262, applied
to `swap_total` in `oomd-manager.c`), which is the route
that exists because the swap kill reads the preference only on root-owned
cgroups (systemd.resource-control(5), "ManagedOOMPreference="). The preference
covers the memory-pressure kill. A job that outgrows 16 GiB inside a tab is
reclaimed (page cache first) and then loses its largest process to the kernel,
while the shell and the agent keep running. Heavy work belongs in
`bounded-workload COMMAND` (its slice allows 60% of RAM and 12 GiB of swap)
or on a compute host.

The package `build-host-tab-scope-oom` ([PKGBUILD](PKGBUILD)) installs the drop-in for both scope prefixes under
`/usr/lib/systemd/user/`, where every user manager reads it; pacman's post-transaction hook reloads the user
manager, which applies it to open scopes as well as new ones. `pacman -R build-host-tab-scope-oom` removes both files, and the reload returns every scope to the stock settings
measured above (read 2026-11-19 on a tab scope: `OOMPolicy=stop`, `MemoryMax` and `MemorySwapMax` `infinity`); a
scope that its launcher started with its own `ManagedOOMPreference` keeps that transient value. Build and install follow [the packaging README](../README.md).

## Open

- A live scope above 16 GiB (one held 28.6 GiB at the read above) has its
  page cache reclaimed down to the limit when the limit reaches it, which
  slows that session's next file reads and kills nothing while the excess is
  page cache.
- Measured 2026-11-19 01:24 UTC after `pacman -U`: a tab scope opened before the install shows
  `MemoryMax=17179869184`, `MemorySwapMax=2147483648`, `ManagedOOMPreference=avoid` and
  `OOMPolicy=continue`, so the reload applies the drop-in to existing scopes.
- hypothesis: the largest process of an over-budget tab is the job and not
  the agent CLI. An agent process above the job's size would be the kernel's
  choice; the falsifier is a memcg OOM line in the journal that names the
  agent.
- A threshold change in total swap moves the 5% line; the budget stays valid
  while total swap exceeds 40 GiB.
- Konsole in the capsule under Windows keeps all tabs in one application
  scope, so this drop-in does not cover it.
