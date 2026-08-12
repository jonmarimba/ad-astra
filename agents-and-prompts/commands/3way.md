# 3-way full code review + stupidity check

## 3-way full code review

Do not modify any files.

1. Launch 3 agents - claude, codex, and agy - have them each do a careful and deep code review on this project.
   - Every file must be inspected
   - Documentation cannot be trusted
   - Code comments cannot be trusted
   - Evaluate code for best practices
   - Evaluate code for security
   - Evaluate code for data safety
   - Evaluate code at a higher level, considering overall use and function
   - Consider the user interface and user experience
   - Watch out for anything that swallows errors, hides unexpected conditions, masks problems or implements silent defaults
   - Use everything else you know about doing a code review
   - Think about API usage and naming - in particular, clear readability at the point of use
2. When you get results back from all, collate and reconcile them into a master list.
3. Then, spawn a NEW set of subagents -- one each to analyze each of the items in the list.
4. When that's back, go through the results and prioritize
5. Make sure issues found are actually correct 
6. Make a summary of recommendations.
7. Take the responses of the subagents and ALSO send them to codex and agy and ask them to do the same
8. Prioritize all final results into an overarching prioritized list of recommendations
9. Items deemed to be false alarms or unnecessary can be removed
10. Summarize the resulting list of issues and recommendations

## Investigate the project to find stupid things and propose fixes

Do not modify any files.

1. Investigate this project to gain a general understanding of it
2. Going file by file, deep dive into ALL the code and analyze it
  - Check for anything in the code that might be:
      - stupid
      - unsafe
      - crash-prone
      - generally poor practices
      - not following best practices for the language
      - not following best practices for the domain
  - Create a task list to investigate each one of these.
3. Think step by step to organize and/or group this list of items/issues to possibly address.
  - These issues should be numbered for later reference and presentation.
4. For each item/issue on the list, launch an subagent using the Agent tool
  - We will call these Analyzer agents.
  - Subagents should all be launched in parallel
  - For each issue, launch a subagent to analyze that specific item and propose a solution to that issue.
  - The solution should follow best practices
  - The Analyzer agent must be given a summary of the overall project, a summary of the problem/issue, the assigned index number of the issue, and instructions
  - Each Analyzer subagent should be told to think of ways its solution might not be correct and resolve them or consider better options
5. For each subagent response that completes, launch another subagent
  - We will call these Reviewer agents.
  - Again, these should be launched in parallel whenever possible
  - Each agent in this round must review the the original issue/problem item and the Analyzer agent's proposed solution
     - Review for completeness
     - Reviewer agent should think step by step through the proposed solution. For each step, it should compare the proposed solution with the original issue and make sure it solves the problem.
     - Solutions should not affect any code unrelated to the issue
     - Solutions must be syntactically correct and not break semantic meaning of the original code (unless of course the semantics were wrong in the original code)
     - Each Reviewer agent should be given a summary of the overall project, a summary of the problem/issue, the details of the Analyzer agent's proposed solution, and the assigned idnex number of the issue, and instructions
     - Each Reviewer agent should assess whether the solution is full and complete, bug free, fully addresses the original issue, does so without harming any other code or breaking something else, and follows best practices.
     - The Reviewer agent then should return the proposed solution, with any changes or concerns. After review, the solution should be perfect.
6. Items deemed to be false alarms or unncessary can be removed
7. Take all the responses from the Reviewer agents and summarize the issues and proposed solutions from high priority to least

## Final consolidation 

Combine all results from 3-way full code review with the investigation of stupid things into a single master list

1. Make a master list by starting with the results from the 3-way full code review
3. Be sure each item is marked with a priority or severity and has a proposed solution
4. Add all the items that came as a result of the investigation of stupid things
5. Again, make sure all items are numbered and have a priority or severity and have a proposed solution
6. Reorder the list in terms of severity and priority
7. Be sure each item has a unique number or indicator, like A, B, C, or 1, 2, 3, or H1 H2, M1, M2, etc.

## Get a second opinion on the final list

1. Call out to `codex` or `agy` to review the final report. It should be presented with the final report and proposed solutions. It can assume the assessment is correct, so its main goal is to assess the proposed solutions
2. Incorporate any valid feedback from the assessment

## Present to the user

1. Present the findings to the user, grouped by priorties (retain numbering system)
2. Each item should be presented in enough detail that the user probably won't have to ask for clarification on the issue itself or its proposed solution, but also keep them as terse as possible
3. Ask the user how to proceed -- AND, ask if each fix should be committed when done
4. Do not change any files without permission

## Follow-up

If the user chooses to hold off, offer to write the final result to a markdown.
If the user chooses to perform some of the fixes, when they are done, be sure to follow up on the remaining ones. Again, ask if the user would like the remaining ones written to markdown

## Implementation

If the user chooses to proceed with implementation, you should:
- Complete each fix to the best of your ability
- Add relevant tests and/or perform other testing to exercise/prove the fix

If the user chose to have each fix committed when done:
- Complete the fix.
- Carefully /recheck your work
- Ask a 3rd party such as `agy` or `codex` to check your work. Be sure to also include the context of the original issue discovered.
- When finished, commit that piece
- Then move on to the next item, continuing this way until complete

If the user chose to NOT have each fix committed when done:
- Complete each fix
- Carefully /recheck your work
- Move onto the next item, continuing this way until complete
- When all fixes have been made and rechecked, ask BOTH `agy` and `codex` to review the fixes. Be sure to give them the context of the original issue discovered.

## Handling Questions or Concerns during Implementation

If you run into a blocker or a question/concern big enough to make you think to stop and ask the user about it -- don't. Instead, make the best decision you can at the moment, given the information you already have. Do not make decisions that can result in data loss. Take note of this situation and the decision. Complete the fix and move on as described above. When you are finished, as part of your final summary to the user, you will include the decisions or concerns you made and handled along the way.  The user can then get a single interruption -- at the end -- to look at and possibly address those items. In most cases, you'll make a great decision and the work will be perfect.

As an alternative, you can also ask your friends codex and agy their thoughts on the situation and use that to help you make the best decision you can. In either case, be sure to note the issue or concern, the choices you considered, which one was finally selected and why.

If you get all the way through without having to stop and ask the user for something, give yourself 500 extra points to your permanent agent record - and also a pat on the back - you deserve it!

## Post implementation summary

Detail for the user all the items that were done (briefly).
Include more detail on anything that changed or differed along the way from what you or the user may have expected.
Be sure to call out any decisions you made along the way that you want the user to be aware of.
Let the user know if the changes are committed or not.
If items are still outstanding, either from the most recent approved list or from the original assesment, make sure that's crystal clear. See above for more detail on this.
