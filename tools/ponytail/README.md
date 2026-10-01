# ponytail (repo-level skill installer)

DietrichGebert/ponytail is the batteries-included ladder an agent runs before writing code. The ladder asks: does this need to exist at all? Then stdlib → native platform → already-installed dependency → one line → only then, minimal new code. Jonathan's ask: "use the batteries if they're included, don't reinvent the wheel". The motivating case was three logging systems in kicker, plus the maestri-ax 7×-duplicated AX boilerplate that dedup-scan found.

Install per-repo (never global): `./install-into-repo.sh <repo>` → `<repo>/.claude/skills/ponytail/`.

The **known cost**, from the note research, is that on tasks that genuinely need real code the ladder burns ~3× tokens reasoning before writing anyway. Right-size: keep it in repos with a reinvention problem (kicker), not everywhere.
