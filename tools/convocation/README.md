# convocation (tool + skill)

The process doc is `skills/convocation/SKILL.md`: isolated → adversarial → consensus. This tool runs one fan-out round headless:

```sh
convoke TASK.md --out out/ --agents claude,codex,qwen --tag round1
# ...write round-2 task files embedding the others' round-1 outputs, then:
convoke TASK2_claude.md --out out/ --agents claude --tag round2
```
Agents run in parallel, each isolated to its own output file (+.err). No cross-contamination by construction — an agent only ever sees what its task file contains.
