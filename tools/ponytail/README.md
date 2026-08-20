# ponytail (repo-level skill installer)

DietrichGebert/ponytail — the batteries-included ladder an agent runs before writing code: does this need to exist at all → stdlib → native platform → already-installed dependency → one line → only then, minimal new code. Jonathan's ask: "use the batteries if they're included, don't reinvent the wheel" (motivating case: three logging systems in kicker; also the maestri-ax 7×-duplicated AX boilerplate dedup-scan found).

Install per-repo (never global): `./install-into-repo.sh <repo>` → `<repo>/.claude/skills/ponytail/`.

**Known cost (from the note research):** on tasks that genuinely need real code, the ladder burns ~3× tokens reasoning before writing anyway. Right-size: keep it in repos with a reinvention problem (kicker), not everywhere.
