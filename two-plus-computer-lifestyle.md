# Two-(plus)-computer lifestyle — environment management (@astra)

Companion tracker to `tech-to-try.md`, tracked in @astra and symlinked into the Obsidian vault. Purpose: tools/solutions for managing multiple computing environments so the multi-machine life actually works. Seeded 2026-08-12 from the "Two (plus) computer lifestyle" Apple Note.

**North star (the test every solution has to pass):** don't make JS wish he hadn't gone to Starbucks. The only friction allowed when leaving = unmount the backup drive, throw the M5 in the bag, go — and be comfortably productive in his usual environment, whether the day's machine is the M4 or the M5.

## The two that must stay in sync
- **MBP M4** — desktop laptop, lives home on the LG 5K, Time-Machine-only. Where GhOST + most LLM personalities live. General work, Xcode, SourceTree, LLM CLIs, always-on portal to Claude/Codex/ollama + @ghost.
- **MBP M5 Max** (maxed) — the EDC / travel / Starbucks laptop. Started as an M4 clone. Time Machine + Backblaze (inherited the M4's Backblaze slot). LM Studio + music tools. Occasional local-LLM host when home.
- **M4 stays home; M5 is the mobile EDC.** Sync is M4 ⇄ M5, controlled (see goals).

## The rest of the fleet (reference)
- **128GB Linux LLM box** (incoming from Micro Center) — LLM host + maybe small always-on home services.
- **Parents' 2× M4 Mac mini** — Speedway (NC, Samsung 4K) + Ceylon MN farm; their computing, Documents/Desktop via Dropbox.
- **iMac by the drums** — Logic appliance + video rig (Tascam Model 24, Earthworks OH pseudo-Glyn-Johns, Shure toms/snare, 3 Zoom cams → PIP switcher → capture card). One major OS behind; Tailscale NOT set up yet.
- **Charissa's MacBook Air** (ENH-owned).
- **Linode VPSs** — ENH (Maharam Jenkins, aged ENH site, OpenVPN, Newark, no Tailscale yet) + personal (Laurel Park hosting).
- **Docker** — LP dev envs on both M4 + M5 (M5's rebuilt fresh, not copied — proved it's easy).
- **iPads** (mini + Air w/ keyboard+pencil) — Maharam testing; aspirational, someday drive kicker.
- **iPhone Pro** (daily; ssh + Tailscale for brief connects) + **iPhone 13 mini** (backup/testing/nostalgia).
- Accounts: gmail (junk), jonathan@jonathansaggau.com (Workspace), enharmonichq.com (Workspace, +Charissa/Andrew), laurelparkmembers.info (Fastmail). Backblaze (1 machine), Dropbox, Time Machine (M4/M5/MN-mini/T7), Monarch, QuickBooks. Windstream fiber both houses, same SSID/auth (ENHQ).

## Goals (what "working" looks like)
1. **M4 ⇄ M5 controlled sync** of the basic work environment — some things auto, some update-one-updates-the-other-but-not-blindly, some explicitly manual.
2. Keep in sync (with the right control per item): **Xcode (multiple versions)**, SourceTree, SetApp apps, brew packages, **dotfiles**, Claude Code / Codex / Qwen (/ OpenCode? / Pi?), Documents/Desktop/Downloads (via Dropbox, partial, selective-sync to save disk).
3. Occasional **backup/migration of LLM personalities / ensembles**.
4. **Shrink/limit the Photo library** on each machine (idea: size-limited APFS volume or sparse image).
5. **Tailscale everywhere** + easy any-computer-to-any-computer connect (+ helper scripts).
6. **Small portable VMs** for: (a) kicker / Mac+iOS app work in isolation — so a UI-automation test run doesn't hijack the machine he's using, and so he can copy a VM to the M5 and work fast+local from the road instead of screen-sharing; (b) isolating **YOLO LLMs** (hygiene + balance token usage across multiple Claude accounts); (c) extra-small appliances to spin up a new kicker ensemble or a Linux/Docker box.

## Already in use
- **Tailscale** — on M4, M5, both parent minis, phone. **Gaps: Linodes, iMac, LLM box.**
- **Apple Screen Sharing** (not the pricey Remote Desktop) — M5→M4 from Starbucks over Tailscale; also parental IT. + ssh.
- **SetApp** (licensed M4+M5): Timing, BusyCal, Maestri. **Tart** VM basic setup on M5 (impressed).

## Tracked — to try / to set up (the actionable list, by goal)
- [ ] **Dotfiles sync** — `chezmoi` (templating + per-machine differences, best fit for "same but not identical M4/M5") vs. GNU Stow / `yadm` / a plain git dotfiles repo. Chezmoi handles the "mostly-shared, some-machine-specific" case cleanly.
- [ ] **brew sync** — `brew bundle dump`/`brew bundle` with a Brewfile in the dotfiles/@astra repo; diff-and-apply rather than blind auto-update. (Ties to the @astra per-tool Brewfile standard.)
- [ ] **App settings sync** — `mackup` (symlinks app prefs into Dropbox) — but selectively; some apps you do NOT want auto-synced. Evaluate which.
- [ ] **Xcode multiple versions** — `xcodes` (xcodesorg/xcodes CLI: install/switch multiple Xcodes) + `xcode-select`. Scriptable, reproducible across M4/M5.
- [ ] **CLI agent setup sync** (Claude/Codex/Qwen/OpenCode/Pi) — the Thursday reminder task; symlink-based (the Jean-Claude mechanism: settings.json + hooks/ symlinked, auth per-profile). Fold into the model-sync project.
- [ ] **Ollama / model availability sync** across machines + "the router thing" — see `PROJECTS.md` (auto-add frontier models, notify on new ones).
- [ ] **Documents/Desktop/Downloads** — finish Dropbox selective-sync setup (partial); decide what's selective to save disk.
- [ ] **Photo library size control** — Photos library on a **size-capped APFS volume** or a **sparse bundle**; or iCloud Photos "Optimize Mac Storage" (keeps originals in cloud, thumbnails local). Compare disk/behavior tradeoffs.
- [ ] **Tailscale gaps** — set up on the Linodes, the iMac, the LLM box. Then SSH config + small connect-any-to-any helper scripts.
- [ ] **Portable VMs (kicker/app work + YOLO isolation + ensemble spin-up)** — **Tart** (already, Apple-Silicon-native, OCI push/pull → copy a VM M4→M5), plus evaluate **UTM** and **Lima** for the Linux/Docker-appliance case. Key win: UI-automation test runs live in a VM, not on the machine you're using. (Cross-refs `tart.run` in tech-to-try.)
- [ ] **LLM personality / ensemble migration** — a documented export/import of a personality or ensemble between hosts (ties to the kicker install flow + Walrus/MemWal cross-tool memory experiment).
- [ ] **iMac catch-up** — one OS release behind + no Tailscale; bring current + on the tailnet so it's reachable.

## Cross-refs
`tech-to-try.md` (Tart, Exo, model tooling) · `PROJECTS.md` (model-sync, generic-messaging, per-tool Brewfile/install standard) · Thursday 8/13 reminder (sync CLI agent setup across both laptops + commit-hooks into legal repos).

## Model fleet architecture (OmniRoute hub) — added 2026-08-12
The through-line JS confirmed: **OmniRoute (local router @ :20128, web UI /dashboard) is the hub.** Every model host is just a `provider_node` OmniRoute auto-discovers models from; it ranks them (model_intelligence) into `auto/best-*` routing and GENERATES client configs (`omniroute setup-codex` → ~/.codex profiles; OpenCode provider block; etc.). Add a host = add one node, nothing else.
- **M4** — GhOST + always-on portal (this machine).
- **M5 (LM Studio, Tailscale :1234)** — PRIMARY play host (most RAM headroom); also "Dwarf Star" ds4 runner (:8008). Both already OmniRoute nodes.
- **128GB Strix Linux box (incoming, Micro Center)** — becomes the always-on host. Serve with **vllm** (ROCm; OpenAI + Anthropic-API compatible) or ollama → register as an OmniRoute node like the rest.
- **hot-models feeder** (building): watch HF/ollama trending filtered to the frontier watchlist → auto-pull the best-fitting tag onto the headroom host (M5 now, Linux box later) → OmniRoute discovers + ranks + config-gens → botline-ping JS "come play." Reachability-gated (does nothing while a host is asleep/in-the-bag).
- **omniroute sync** handles M4↔M5 config sync between OmniRoute instances.

## Missed on first pass — added from JS's note edits (2026-08-12)
- **FRAMING (load-bearing):** JS has *always hated* the multi-computer lifestyle and collapsed back to one laptop quickly every time he's tried. So this whole effort lives or dies on friction: it must be near-zero-touch or he abandons it. Design accordingly — automate ruthlessly, no per-machine babysitting. (Matches his standing "collapses to one laptop" pattern.)
- **New task — contacts sync:** standardize on jonathansaggau.com, remove duplicates.
- **New task — calendar cleanup:** archive + delete the old time-tracking calendars on the Google accounts (~150 dormant ones).
- **Documents-sync technique (his own):** symlink Desktop + Downloads into Dropbox (Documents already syncs). Works fine AS LONG AS iCloud "Desktop & Documents" sync is turned OFF — then the OS doesn't care that they're symlinks. Do this again.
- **Tailscale:** "can't believe it's free and this good" — happy with it; just needs the gap machines added.
- **Host purposes (refined):** the home local-LLM host "can't become critical infrastructure at home"; wants a "more persistent home LLM host" (the Strix box) AND a **prototype/test env for document-ingestion + TTS/STT ideas**.
- **iMac (drums):** stable Logic appliance + video rig with his favorite EQ/compression ready whenever; AKG room mic added to the Tascam/Earthworks/Shure/3-Zoom setup.
- **DEFER:** JS wants to *discuss* the two-computer plan later in the week / over the weekend — don't over-build it before that conversation.
