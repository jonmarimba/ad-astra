# periphery (Swift dead-code detection)

The decided dead-code half of the dedup strategy (see tech-to-try §D). Install: `./install.sh` (which-first; brew via peripheryapp's tap). Run: `periphery-scan <repo>` — repo-level config in that repo's `.periphery.yml` (create once with `periphery scan --setup`, interactive, needs the project's real scheme/targets). Pairs with PMD/CPD (copy-paste) and the graphify-communities → convocation pass (semantic clones).
