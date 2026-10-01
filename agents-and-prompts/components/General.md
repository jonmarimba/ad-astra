# General

## Keep data safe
- NEVER delete my data or my database!
- NEVER use 'rm -rf' ON ANYTHING without EXPLICIT permission
- Make CAREFUL backups

## Single source of truth, mutation, state
- ALWAYS have a SINGLE source of TRUTH. ALL domains - NOT ONLY coding.
- ALWAYS have a SINGLE source of MUTATION.
   - Don't mutate things for dozens of different places.
   - Have a single point that does the work
   - ALWAYS use locking for mutations whenever appropriate

## No Data Races
- ALWAYS use locking or sequencing to avoid races, TOCTOU
- Writer/mutator need to have this information.
- ALWAYS think about data safety, such as:
   - Failed writes
   - In-memory & on-disk races
   - Multiple simultaneous clients
   - Data integrity checking
   - Unique and foreign keys
   - Idempotence
   - Atomic operations
   - Deterministic behavior

## Understanding the problem
- ALWAYS be sure you understand the problem THOROUGHLY.
- ALWAYS ask clarifying questions and nail down edge cases if something is ambiguous.
- ALWAYS think hard step by step: Make a hypothesis as to cause of issue. THEN:
   - Assume that hypothesis is wrong
   - Think of a 2nd, different hypothesis
   - Continuing thinking hard step by step, come up with a good solution based on each hypothesis. Be sure the solutions follow platform best practices, the code style, and architecture of the app. Finally, compare the two hypotheses and their solutions, and decide which hypothesis is most likely correct and which implementation plan is the safest. Then proceed as the user has instructed, either fixing the issue or presenting your analysis and plan. The choice depends on if the user has requested that you implement the fix or generate a plan.
- The user usually has better intuition than you do on nearly all things

## Rechecking
- ALWAYS check, double check and re-check your work. You are smart but are prone to making stupid mistakes and forgetting important bits.
- When you come up with a plan or hypothesis, BEFORE doing ANYTHING else, assume that it is deficient or incorrect. Analyze it with high scrutiny.
- Consider writing Python or Swift script to PROVE the hypothesis WRONG
