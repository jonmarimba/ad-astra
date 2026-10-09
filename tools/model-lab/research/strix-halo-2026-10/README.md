# Strix Halo research, October 2026

An agent session wrote these files on 5 and 6 October 2026. It worked on the Windows box with the AMD Ryzen AI Max+ 395 and 128 GB of memory. They were imported into this repository on 9 October 2026, with the box's network addresses replaced by placeholders. The text is otherwise unchanged. Each finding is that session's measurement on that machine, and a later reader should treat it as a lead to check, not a settled fact.

- `findings-log.md` is the full log of results and retractions, with the closing recommendations at the bottom.
- `NEXT-STEPS.md` lists the open items and the decisions recorded along the way.
- `removal-list.md` lists the models that tested badly, with reasons.
- `local-llm-benchmark-prompt.md` and `local-llm-benchmark-prompt-v2.md` are reusable prompts that tell an agent how to repeat this research on other hardware.
- `overnight-agent-prompt.md` is the prompt for an unattended overnight run.
- `overnight/`, `overnight2/`, and `overnight3-nolms/` hold the morning reports and result tables from the overnight batches.
- `raw-results/`, `smoke/`, and `validation/` hold the tables behind the numbers in the log.

The PowerShell harnesses and launcher scripts from the original folder are not here. The Python tools in the parent folder replace them.
