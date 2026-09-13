**Two (plus) computer lifestyle**

Similar to tech to try I'd like to start tracking separately tools for managing multiple computing environments.

**Bottom line: don't make me wish I didn't go to Starbucks / don't make me do anything other than unmounting my backup drive and throwing my M5 in my bag to go somewhere and be comfortably productive in my usual environment even if sometimes daily the M4 and sometimes the M5**

*Note: the M4 can stay home. The M5 is my EDC mobile laptop.*

**Goals**

* MBP M4 &lt--> automatic sync and update of basic work environments.

+ Certain apps / tools (preferably when I update on one so updates the other but not automatically updating certain things)

- Xcode -- multiple versions
- Sourcetree
- Stuff from setapp
- Stuff from brew
- Dot files
- Claude code. Codex. Qwen. (Open code? Pi?)

+ Documents. Desktops. Downloads. (Via Dropbox. Partially setup. Some selective sync preferred to save disk space)
+ Occasional backup or migration of certain LLM personalities / ensembles
+ No matter what I do, my photo library gets big on both machines. I think I'd like to shrink or limit it somehow on each machine. If heard of folks keeping their photo library in a size limited APFS volume or a sparse image.

* Easy connection from any computer to any computer via tsilscale and maybe some shell scripts or whatnot
* (Small, portable, VM) environments for working on Kicker, Mac and IOS apps in isolation. And for moving those environments between Mac hosts. I'm increasingly relying on UI automation for that work and nothing is more annoying than having a UI test run take over a computer I'm actively using. It also kind of sucks to drive this stuff from Starbucks via screen sharing. Sometimes I just want stuff local and fast. So I'd like to be able to copy a VM to the m5 and bring my toys on the road.
* (Small, portable, VM) environments for isolating YOLO LLMs. I don't mind rolling the dice running YOLO LLMs on my working computers but that will eventually bite me so a little hygiene would be smart. This could help balance token usage of my multiple Claude accounts as well.
* (Extra small, portable, VM) environments for spinning up a new kicker ensemble or a Linux (docker probably) appliance

**I have or soon will have**

* MBP M4 where you (ghost) and most of my LLM personalities currently live. That's the desktop laptop; it lives connected to my LG 5k backed up only to local Time Machine. Purpose:

+ General work when I'm home. Xcode. Source tree. LLM CLIs
+ Always on portal to LLM CLIs of a commercial variety (Claude, Codex, ollama) and you (@ghost)

* MB5 M5 MAX maxed out configuration where I have LM studio and some music tools. It started as a clone of the M4. Backed up to local Time Machine and backblaze. It inherited the backblaze setup from the M4 replacing the M4 on backblaze. That's the laptop laptop Purpose:

+ Travel / Starbucks computer
+ Occasional local LLM host when I'm home working on the M4

* The 128GB RAM Linux LLM hosting dingus I'll pick up from microcenter. Purpose:

+ LLM Host
+ Maybe a few other little always on at home services in the future.

* My parents' M4 Mac mini currently at speedway attached to a (Samsung?) 4K. Purpose:

+ Mom and Dad's computing life when in NC. Documents and Desktop sync via Dropbox

* My parents identical M4 Mac mini on the farm in Ceylon, MN. Purpose:

+ Mom and Dad's computing life when in MN. Documents and Desktop sync via Dropbox

* My iMac running next to my drums. Tailscale not currently stop. One major OS release behind. This is a desktop desktop. Purpose:

+ LOGIC appliance and Video rig. Monitoring and recording drums. I play exclusively monitored via Tascam Model 24 and in-ears / headphones. Earthworks overheads in pseudo - Glynn Johns configuration. Shure mics on Toms and snare. I forget what on each Bass drum. Whatever Shane, the owner at drum center of Portsmouth recommended that they use on their YouTube channel. Three Zoom cameras attached to a 4 input PIP switcher and a video capture card on the iMac.

* Charissa has a MacBook Air Enharmonic owns
* Linux VPSs on Linode via Enharmonic for Maharam Jenkins, Enharmonic's aged web site, and an openVPN setup -- all in Newark. No Tailscale setup yet. Purpose:

+ ENH services above

* Linux VPS(s) on Linode that are on my personal account that host Laurel Park stuff. Purpose:

+ LP hosting

* Docker containers on M4 and M5 with Laurel Park dev envs setup. Works great on both. M5 LP docker env was not copied from M4. Rather, it proved I can get a new copy of the site up relatively easily. Purpose:

+ Laurel Park dev envs

* iPad mini. iPad Air with Apple's fancy keyboard and pencil (no idea where input the pencil -- that was an aspirational purchase). Purpose:

+ Mostly Maharam testing
+ Occasional entertainment
+ Note: I've never found iPadOS to be particularly useful, otherwise, despite spending a lot of money over time on overkill hardware aspirationally. I'm not going to force it. But I'd like to use these to drive kicker someday. Hence the apps.

* iPhone latest Pro. My daily driver. Purpose:

+ Besides usual iPhone stuff I'd like to drive kicker someday.
+ I have an ssh client and Tailscale on it, so I can connect briefly to (eg) an LLM running on the M4 or a Linode server when needs must.

* iPhone 13 Mini. Purpose:

+ Backup phone. App testing. Kid backup phone.
+ Nostalgia. Favorite iPhone form factor. Ever. I still type faster on this thing.

* Mail / document / contacts / calendar services

+ Saggau@gmail.com. Plain google account. Junk mail goes here.
+ Jonathan@jonathansaggau.com. Google workspace account with only this email. Google threatens to make me pay occasionally. Hasn't so far.
+ Enharmonichq.com. Google workspace account for me. Charissa. Andrew.
+ Laurelparkmembers.info. Fastmail.

* Other services

+ Apple accounts sync some stuff like notes.
+ Apple accounts for software dev stuff
+ Backblaze backup for one computer. Also has some old drummer recordings I can probably get rid of. Holds a backup of some of my old hard drives containing grad school stuff and whatnot
+ Dropbox
+ Time Machine drives on M4, M5, parents MN mini. Samsung T7. Little portable things.
+ Linode personal and Enharmonic
+ Monarch for personal and basic business finances (net worth tracking)
+ Quickbooks for Enharmonic books.
+ Entertainment

- DirectTV originally for parents at speedway. They use the directTV dongles there. We also use it on AppleTV devices at home. Hank and Andrea like some sports. American ninja warrior. Soccer. Comes with Hulu
- Amazon prime comes with streaming. I think I paid to stop the ads. Fallout. Reacher.
- HBO comes with my ATT plan. House hunters. We put beachfront bargain hunt on when we leave the dog alone.
- Occasionally sub to paramount plus to binge Star Trek
- AppleTV plus or whatever they call it this week. Ted Lasso. Enough said. Everything else is B- to B+ TV we occasionally watch
- Netflix with ads. Andrea likes shitty dating shows.

+ Ring doorbells at both houses. A couple ring battery cams I tend to forget to charge.
+ Windstream fiber at both houses. 2 gig at Tyndall with the windstream mesh (Motorola?) routers. 1 Gig at speedway with my aging eero setup. Both same SSID and auth: ENHQ

**Tools I already use to varying degrees**

* Tailscale

+ Currently setup on M4, M5 laptops, both parental Mac mini's, my phone
+ Need to setup on Linodes, iMac, LLM dingus.

* Apple's built in screen sharing (not their weirdly expensive Remote Desktop thing from the App Store)

+ I've found this very useful from M5 to M4 running from Starbucks connecting through Tailscale
+ I also use this for parental IT

* Usual nerd stuff for remote login (ssh)
* Setapp is licensed on both M4 and M5. from there I use

+ Timing
+ Busycal
+ Maestri

* Tart VM basic setup on M5 (experimenting and impressed so far)

***GhOST reply, 2026-08-12 07:00:***

Started the separate tracker, parallel to tech-to-try. Canonical in @astra: ~/svnCheckouts/js-db-ad-astra/two-plus-computer-lifestyle.md, symlinked into your Obsidian vault (~/.notesq/vault/md/two-plus-computer-lifestyle.md) so it shows up alongside tech-to-try. It captures the full fleet inventory, your goals, what you already use, and a tracked to-try/to-set-up list with real candidate tools per goal — dotfiles (chezmoi), brew sync (Brewfile), Xcode versions (xcodes), Tailscale gaps (Linodes/iMac/LLM box), photo-library-on-a-size-capped-APFS-volume, portable VMs (Tart/UTM/Lima so UI-test runs don't hijack your machine), and CLI-agent + ollama model sync (which ties into Thursday's sync reminder and the model-sync project). North star kept front and center: don't make you wish you hadn't gone to Starbucks.

*Note: I've always hated the multiple work computer lifestyle. I've collapsed to one laptop machine pretty quickly each time I've tried.*

* Fix contacts sync - standardize on jonathansaggau.com. Remove dups.
* Archive and delete old time tracking calendars on Google accounts.

**Tools I already use to varying degrees**

* Tailscale

+ Currently setup on M4, M5 laptops, both parental Mac mini's, my phone
+ Need to setup on Linodes, iMac, LLM dingus.
+ I can't believe this is free so far for my use and this good

* Apple's built in screen sharing (not their weirdly expensive Remote Desktop thing from the App Store)

+ I've found this very useful from M5 to M4 running from Starbucks connecting through Tailscale
+ I also use this for parental IT

* Usual nerd stuff for remote login (ssh)
* Setapp is licensed on both M4 and M5. from there I use

+ Timing
+ Busycal
+ Maestri

* Tart VM basic setup on M5 (experimenting and impressed so far)
* Dropbox syncs documents. I've symlinked desktop and downloads in the past into Dropbox. I should do that again. As long as you make sure iCloud desktop and documents sync is turned off the OS doesn't care of Documents and Desktop and Downloads are symlinks into Dropbox.
* Home grown screenshots on a timer tool for checking in on time tracking. Kind of last ditch &quotwhat the hell was I doing?"

**I have or soon will have**

+ Local LLM host when I'm home working on the M4. Can't become critical infrastructure at home.
+ More persistent home LLM Host
+ Prototype / test env for document ingestion and TTS STT ideas.

* My iMac running next to my drums. Tailscale not currently there. One major OS release behind. This is a desktop desktop. Purpose:

+ Stable LOGIC appliance and Video rig. Monitoring and recording drums with mt favorite EQ and compression settings ready whenever. I play exclusively monitored via Tascam Model 24 and in-ears / headphones. Earthworks overheads in a pseudo - Glynn Johns configuration. Shure mics on Toms and snare. I forget what on each Bass drum. Whatever Shane, the owner at drum center of Portsmouth recommended that they use on their YouTube channel. Three Zoom cameras attached to a 4 input PIP switcher and a video capture card on the iMac. AKG room mic.
+ Laurelparkmembers.info. Fastmail

@ghost - Let's discuss later in the week or over the weekend.

@ghost - For now start researching environment sync solutions for max / unix systems. I used to use one 20ish years ago, but have no idea what it was. Sort of rsync on steroids.

**GhOST reply, 2026-08-18: environment sync for Mac/Unix**

**The one you used 20 years ago was almost certainly Unison.** Released 1998 out of Benjamin Pierce's group at UPenn, Mac/Unix/Windows, runs over SSH. Your phrase “rsync on steroids” is precisely how it was described at the time, and the difference is exactly that: rsync is one-way and clobbers the destination, while Unison is genuinely **bidirectional** — you can change files on either side and it reconciles, flagging real conflicts instead of silently picking a winner. That was the headline feature and there was very little else doing it in 2006. It is still maintained and still works.

Its two known weaknesses are the reason you would not simply reinstall it today. It **bogs down as file counts and sizes grow**, because it does full scans rather than watching the filesystem. And it is **version-fragile across machines** — historically both ends needed a matching build, at times even the same OCaml compiler version, which is miserable when one machine is an OS release behind. Your iMac is exactly that case.

**Three modern options, and they are not interchangeable:**

**1. Mutagen** — the direct descendant, written in Go, explicitly inspired by Unison. Built for the case you have: continuous sync between machines you are actively working on. It **auto-installs its own agent over SSH on first connect**, which kills the version-matching problem outright, and it runs a persistent daemon on native filesystem events with sub-second latency rather than rescanning. If you want the Unison experience without the Unison pain, this is it.

**2. Syncthing** — decentralised, peer-to-peer, no cloud. This is a **Dropbox replacement**, built for long-lived always-on sync, not for active development. Good for a documents-and-media set that should simply exist on every machine. Pairs naturally with Tailscale, which you already run — though note your iMac is not on Tailscale yet, so that machine needs solving separately either way.

**3. Declarative config instead of syncing** — chezmoi or Nix/home-manager. Different philosophy: rather than copying state between machines, you describe the environment once and rebuild it anywhere. Handles the “my shell, my tools, my dotfiles are the same everywhere” half properly, which file sync handles badly. Does not address data.

**What I would actually suggest,** given three machines with genuinely different jobs (the laptops as working environments, the iMac as a stable Logic/video appliance you deliberately keep frozen): do not try to make one tool cover it. Use **Mutagen between the two laptops**, where you want live bidirectional sync of work in progress. Use **declarative config** for shell and tooling so a rebuilt machine matches without copying anything. Leave the iMac out of continuous sync entirely — an appliance whose value is that its settings never move is the wrong thing to point a sync daemon at; give it scheduled one-way pulls of what it needs and nothing else.

Not yet done: none of this is installed or tested. Say which of the three you want and I will set it up and prove it moves a file both directions before declaring it works.

@ghost. Maybe a weekend thing? Stick these in tech to try under a Mac sync heading linking back to this note somehow and maybe make a little note in the calendar for the weekend. I have a wall to finish repairing, a climbing session, a postcard I haven’t really started, and taxes due in, like, a few weeks and Hank has a comp on Saturday and people I don’t feel like hanging out with are coming over afterward. Yay.

**GhOST reply, 2026-08-18:**

Both done.

**tech-to-try** now has a section G, “Mac sync — the two-computer lifestyle (weekend project)”, linking back to the full tracker. It is deliberately a POINTER rather than a copy of the items: two lists of the same things drifting apart is exactly the failure the tool distribution spent today fixing, and a duplicated tracker would rot the same way. The tracker stays canonical at *js-db-ad-astra/two-plus-computer-lifestyle.md*, symlinked into the vault beside tech-to-try.

**Calendar:** Saturday 23 Aug, 11am ET, on the ghost calendar — “Mac sync — discuss the two-computer plan”. Deliberately clear of Mustang Week on the 24th. The notes carry the open decision so you do not have to reload it: nothing is installed or tested yet, and the first choice is dotfiles sync, where chezmoi leads Stow and yadm because it handles the mostly-shared-with-machine-specific-differences case that M4 and M5 actually are. Name one and it gets set up and proven to move a file both directions before anyone calls it working.

Kept your north star at the top of the section, because it is the thing that decides every item under it: don't make you wish you hadn't gone to Starbucks. You have collapsed back to one laptop every previous attempt, so anything needing per-machine babysitting is already the wrong answer.

Go finish the wall.