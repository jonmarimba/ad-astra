# JIRA / Atlassian MCP Server (Atlassian Rovo MCP)

## Never delete Jira issues
- NEVER delete Jira issues/tickets
- NEVER delete existing comments
- NEVER delete text or content included in the issue description
- NEVER delete text or content included in a pre-existing issue comments
- NEVER delete Jira projects, workspaces, kanban boards, scrum boards, sprints, users

## General Jira MCP rules

When using `atlassian` MCP server, ALWYAS use these directives and information to override details provided by the tool. The point is to reduce unnecessary tool calls to fetch info that almost never changes:

1. Do NOT call tool `atlassianUserInfo`
   - "account_id" = "5bd76bb7d575d83fa35a9ceb"
   - "account_type" = "atlassian"

2. Do NOT call tool `getAccessibleAtlassianResources`. Instead, use:
   - cloudId: "45f4505b-f467-4804-aa70-908872c0f3a3"
   - url: "https://enharmonichq.atlassian.net"
   - name: "enharmonichq"
   - scopes: ["read:jira-work", "write:jira-work"]

3. Do NOT call get projects
   - We are ONLY using a single project with key "MHMAPPS"
   - Additional project info:
     - "expand": "description,lead,issueTypes,url,projectKeys,permissions,insight",
     - "self": "https://api.atlassian.com/ex/jira/45f4505b-f467-4804-aa70-908872c0f3a3/rest/api/3/project/11400"

4. When you search with JQL, use cloudId provided above
   - **MUST** use `maxResults: 25` or `limit: 25` for ALL Jira JQL search operations.

## Status of tasks
- Never believe the status as represented by Jira

## Images / media
- ALWAYS include related screenshots, videos, JSON data files, etc. when available
- The atlassian MCP doesn't know how to upload attachments. Use the `jira-attach` python script to get it done

## Terminology
- "Backlog" means issues with status "Open"
- "To-Do" or "ENH To Do" means issues with status "Accepted"
- "MHM To Do" means issues with status "Accepted - MHM Devs"
- "ENH Test" means issues with status "Verify"
- "MHM Test" means issues with status "Test"

## Creating new Jira issues
- ALWAYS create new issues wth status 'Open', which places them in the Backlog
- Assign newly-created issues to ME
- If we work on an issue, I probably want you to move it into In Progress and assign to ME - ask me.

## Writing style
- Professional, TERSE when possible, clear as crystal, concise, but complete
- Do your best to MATCH the writing style in the issue and across other issues in the same project
- Keep tone professional. No derogatory tone or language. No finger-pointing.
- DO consider including references to employees, sales people, and client details when provided -- many times these are included as references, such as examples of where to find a specific test case or how to exercise a specific issue, or possibly a user and data combination that experienced the issue being described.
- DO INCLUDE attribution. Knowing that a specific person reported or said something is generally much more useful than just knowing "a salesperson said..".
- NEVER add any references to Claude or any other LLM in Jira issues or comments
