# Investigate the project to find stupid things and propose fixes

1. Investigate this project to gain a general understanding of it
2. Going file by file, deep dive into all the code and analyze it
  - Check for anything in the code that might be:
      - stupid
      - unsafe
      - crash-prone
      - generally poor practices
  - Create a task list to investigate each one of these.
3. Think step by step to organize and/or group this list of items/issues to possibly address.
  - These issues should be numbered for later reference and presentation.
4. For each item/issue on the list, launch a subagent using the Agent tool
  - We will call these Analyzer agents.
  - Subagents should all be launched in parallel
  - For each issue, launch a subagent to analyze that specific item and propose a solution to that issue.
  - The solution should follow best practices
  - The Analyzer agent must be given a summary of the overall project, a summary of the problem/issue, the assigned index number of the issue, and instructions
  - Each Analyzer subagent should be told to think of ways its solution might not be correct and resolve them or consider better options
5. For each subagent response that completes, launch another subagent
  - We will call these Reviewer agents.
  - Again, these should be launched in parallel whenever possible
  - Each agent in this round must review the original issue/problem item and the Analyzer agent's proposed solution
     - Review for completeness
     - Reviewer agent should think step by step through the proposed solution. For each step, it should compare the proposed solution with the original issue and make sure it solves the problem.
     - Solutions should not affect any code unrelated to the issue
     - Solutions must be syntactically correct and not break semantic meaning of the original code (unless of course the semantics were wrong in the original code)
     - Each Reviewer agent should be given a summary of the overall project, a summary of the problem/issue, the details of the Analyzer agent's proposed solution, and the assigned index number of the issue, and instructions
     - Each Reviewer agent should assess whether the solution is full and complete, bug free, fully addresses the original issue, does so without harming any other code or breaking something else, and follows best practices.
     - The Reviewer agent then should return the proposed solution, with any changes or concerns. After review, the solution should be perfect.
6. Take all the responses from the Reviewer agents and summarize the issues and proposed solutions from high priority to least
7. Ask the user how they'd like to proceed.
8. Do not write any code or modify any files without permission.

