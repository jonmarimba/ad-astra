**Ponytail**

Ponytail - less code skill ???

@ghost - Useful to keep autonomous bots from going all “build the space shuttle” on us?

**GhOST reply, 2026-08-06 12:00:**

Real, verified directly (checked GitHub's API myself after getting burned by a hallucinated star count earlier tonight): DietrichGebert/ponytail, MIT licensed, 97,266 stars — genuinely viral, not hype. Tagline: &quotmakes your AI agent think like the laziest senior dev in the room." Mechanism: a short decision ladder the agent runs before writing code —

* does this need to exist at all?

YAGNI, skip if not;

* does stdlib already do it?

use it;

* native platform feature?

use it;

* already-installed dependency?

use it;

* is it one line?

make it one line;

* only then, the minimum that actually works.

Explicitly NOT on the choppable list: trust-boundary input validation, error handling that prevents data loss, security, accessibility — it's scoped to cut architectural over-engineering, not cut corners on correctness/safety. Benchmark claim: 80-94% less code across Claude, Codex, and Copilot in reproducible tests.

Directly relevant to tonight's own postmortem material — this is close to a packaged, adoptable answer to exactly the &quotpremature optimization / unjustified complexity" pattern that cost you real debugging time across mailq/shotq/notesq/schd, and matches Keel's own self-diagnosis about kicker's failure mode.

Real documented limitation, not just upside — found via independent testing cited in coverage: on a user-authentication task, WITHOUT ponytail an agent produced 30 lines in 32 seconds for 2,300 tokens;

WITH ponytail, 40 lines, two minutes, 6,000 tokens — the agent burned extra tokens reasoning through the decision ladder before concluding it needed to write real (non-trivial) code anyway. So it's not free — for tasks that genuinely need real complexity, the ladder itself becomes overhead.

Worth trialing on a few real tasks (maybe the Fable+Sol spec work itself) rather than blanket-adopting, given that failure mode is a real, current, independently-confirmed one, not theoretical.

@ghost - put a wrapper / installer for this in @astra. Can we use it to refactor things smaller?

**GhOST reply, 2026-08-19:**

**Already in @astra** at *tools/ponytail/* — *install-into-repo.sh* plus a README, with test coverage in *tools/tests/test-installers-which-first.sh*. Verified by running it into a scratch repo rather than by reading it: it installs both *ponytail* and *ponytail-audit* into *.claude/skills/*, skipping anything already present.

One honest caveat about how it fetches: it pulls fresh from raw.githubusercontent on every run rather than vendoring a snapshot, which is the right shape per @astra's own rule. But it does a basic download sanity check, not validation — *curl -f* catches an HTTP failure and a grep for “name:” rejects an obviously wrong body, and nothing pins a commit or verifies integrity. Unpinned upstream pull, so what lands is whatever is on main that day.

**Can we use it to refactor things smaller? Yes — that is what the second skill is for.** *ponytail-audit* is a whole-repo scan for over-engineering that produces a ranked list of what to delete, simplify, or replace with stdlib and native equivalents. It is a one-shot report and does not apply fixes, so trialing it costs nothing but reading. Its output is a candidate list, not a verdict — the rankings are its opinion and want checking before anything gets deleted.

**Proposed first trial: @astra itself.** It has thirty-odd tools, several added in the last few days, and I wrote a document last night that duplicated an existing spec — so it is a genuine candidate rather than a tidy demo. Scoped hard: one read-only audit, a ranked list of delete/simplify/reuse candidates each naming the claimed existing substitute and its owning tool, no code changes, no new docs or tools, then peer review of the top few before anything is acted on. That also tests the thing worth knowing about ponytail — whether it finds a real actionable simplification or just produces prose.

Worth remembering the documented downside from the earlier research: on a task that genuinely needs real complexity the ladder is pure overhead — an independently-tested authentication task went from 30 lines in 32 seconds and 2,300 tokens WITHOUT ponytail, to 40 lines in two minutes and 6,000 tokens WITH it, because the agent reasoned through the ladder before concluding it had to write real code anyway. Trial it on specific work rather than adopting it blanket.