**Obsidian**

@ghost research obsidian, especially its plugins and suggest those that might be useful to me

**GhOST reply, 2026-08-06 11:49:**

Given you just stood up a real vault today (the ad-astra `@astra` pipeline), here's what actually fits your profile — dev-heavy, git-integrated, PDF/legal-repo work, terminal-native:

* **Obsidian Git** — the standout for you specifically. Auto-commits/pushes your vault to a Git repo (GitHub/GitLab/Gitea) on a schedule, full version history, rollback, off-site backup. This is literally what `ad\_astra\_sync.sh` does by hand right now (schd job, daily commit+push) — worth checking whether this plugin could just replace that script entirely, or at least whether it's worth running alongside for the parts of the vault the `@astra` pipeline doesn't cover (your own manual vault edits, not just the auto-synced notes).
* **Dataview** — the most powerful plugin in the ecosystem generally: SQL-like queries over your notes, pulling from YAML frontmatter and inline fields. Given how much structured tracking you already do by hand (TODO.md, diary tables, memory files), this could let you query across notes instead of grepping — e.g. &quotall notes tagged @astra from the last month" as a live query instead of a manual list.
* **Templater** — automates structured note creation with dynamic content (dates, filenames, prompts). Less obviously load-bearing for you specifically since GhOST already generates a lot of your structured content, but genuinely useful for anything you type by hand.
* **Recommended starter stack per current 2026 consensus**: Dataview + Templater + Obsidian Git covers ~80% of power-user needs; add QuickAdd (fast capture) and Tasks (task management) for the rest. Given your existing TODO.md/diary system already handles task management and capture through GhOST, I'd start with just Dataview + Obsidian Git — the other two would be redundant with tooling you already have working.

@ghost ive got obsidian pointed at your notes export. Anything we could or should do there to trial the above?

**GhOST reply, 2026-08-12 — the vault trial, answered and partly done**

Your Obsidian is pointed at the notes export (~/.notesq/vault/md). What's worth doing there, concretely:

* **DONE — the vault is now a git repo with hourly snapshots.** Every Apple Note gets versioned automatically after each export (wired into the hourly export job; no Obsidian plugin needed, works even when Obsidian's closed). Practical payoff: any future &quotthe notes got mangled" event — like the 8/11 formatting disaster — becomes one git revert instead of a forensic recovery. Baseline commit holds all 4,488 files.
* **Install Dataview** — the one plugin that earns its slot on this vault: live queries over the export (&quotnotes modified this week," &quoteverything mentioning Dan," a table of @astra-tagged notes) instead of grepping. The export lacks YAML frontmatter, but Dataview's file metadata (mtime/path/links) covers your cases.
* **Skip Obsidian Git** (the plugin) — it wants to commit/push on Obsidian's schedule; this vault is a GENERATED mirror, so committing belongs with the exporter (done above), and ad\_astra\_sync already handles the @astra push side.
* **Skip Templater/QuickAdd/Tasks** — they're for authoring INTO a vault; yours flows one-way from Apple Notes, and GhOST + TODO.md already own capture/tasks.
* Already visible in your vault: the symlinked @astra tech-to-try + two-computer trackers.