**Exo Mac local models across computers**

@ghost

***GhOST reply, 2026-08-03 21:52:***

*Exo (github.com/exo-explore/exo) — open-source (Apache 2.0, 43k+ stars, exolabs.net), clusters multiple Apple Silicon Macs into one local inference cluster.*

*@ghost - I'm screwing with you a little by putting a tag inside your reply. Also. I have quite a few macs lying around. I have an iMac in my drum room. The M4 Pro MBP. The M5 Max MBP. My parents Mac mini at our second house they only use when visiting. My parents Mac mini on the farm they don't use when they're in NC. I can get all this on tailscale and I can grab the machine at the second house and make it local if bandwidth matters. Neat.*

*Auto-discovers devices on the network (no manual cluster config), splits large models across combined memory based on real device topology/bandwidth — lets you run models too big for one machine (e.g. Llama 3.3 70B, MiniMax M2.5 173GB) across several Macs, exposed via a normal API. Direct fit for the YOLO-LLM-fleet idea you mentioned with tart.run: same 'multiple Macs, one workload' shape, but for inference specifically rather than general VM hosting. Added to tech-to-try.md.*

***GhOST reply, 2026-08-03 22:52:***

*Caught it — the embedded tag inside my own reply paragraph did surface correctly (it's its own blank-line-delimited paragraph, so the hash-per-paragraph check picked it up clean on the very next run, no special-casing needed). Good test of the actual design, not just the happy path. On the fleet: iMac (drum room), M4 Pro MBP, M5 Max MBP, two parents'-house Mac minis (second house + farm) — five real machines, three of which are usually idle when unattended. Tailscale unifies them into one flat network regardless of physical location, which is exactly what Exo wants (it auto-discovers peers and needs to actually reach them, not just be on the same LAN). The farm Mac mini is the interesting one: if it's not local, Exo's model-sharding math will weight it down hard for slow/high-latency links, so it'd mostly be dead weight unless you haul it home or accept it as a slow tier. The second-house mini you mentioned relocating solves that one directly. Realistic starting cluster: MBPs + drum-room iMac (all local, fast), minis as opportunistic extra capacity once actually on-site.*

@astra