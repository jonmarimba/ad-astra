# jira-attach

Attach files to a Jira issue, and build or extend its comments and description with inline images and file cards. Pure Python 3 standard library; the API token lives in the macOS keychain.

## Setup

1. **Make it runnable and put it on your PATH**

   ```sh
   chmod +x jira-attach
   ln -s "$PWD/jira-attach" /usr/local/bin/jira-attach   # or anywhere on your PATH
   ```

2. **Create an Atlassian API token** at <https://id.atlassian.com/manage-profile/security/api-tokens>

   Use a classic (unscoped) or coarsely-scoped token — it needs `read:jira-work` and `write:jira-work`. A finely-scoped token generally 404s on issues it cannot see.

3. **Configure**

   ```sh
   jira-attach --configure
   ```

   Prompts for your Jira site (e.g. `https://your-team.atlassian.net`) and the email of the Atlassian account the token belongs to, then asks for the token itself.

4. **Check it**

   ```sh
   jira-attach ABC-123 some-screenshot.png
   ```

## Atlassian MCP server

`jira-attach` handles attachments; the Atlassian MCP server handles everything else (issues, comments, JQL, Confluence). It is a remote HTTP server at `https://mcp.atlassian.com/v1/mcp/authv2` and authenticates over OAuth in the browser — no token needed.

Install it at user scope (available in every project):

**Claude Code**

```sh
claude mcp add --transport http --scope user atlassian https://mcp.atlassian.com/v1/mcp/authv2
```

The server is added unauthenticated — `claude mcp list` reports `! Needs authentication` until you log in. Complete OAuth by running `/mcp` inside an interactive Claude Code session and selecting `atlassian`. There is also a `claude mcp login atlassian` subcommand. It needs a real TTY and fails with `stdin isn't a terminal` when run from a script or from a tool-driven shell.

**Codex**

```sh
codex mcp add atlassian --url https://mcp.atlassian.com/v1/mcp/authv2
```

That single command is enough. Codex probes the URL, detects OAuth support, opens the browser, and blocks until the callback lands — no separate login step. Use `codex mcp login atlassian` only to re-authenticate later. Confirm with `codex mcp list`, which should show `atlassian … enabled  OAuth`.

Codex MCP servers live in `~/.codex/config.toml` and are always global; there is no per-project scope.

**Antigravity (`agy`)**

Antigravity has no `mcp` subcommand — edit the global config at `~/.gemini/config/mcp_config.json` and merge the `atlassian` entry into whatever `mcpServers` map is already there:

```json
{
  "mcpServers": {
    "atlassian": {
      "serverUrl": "https://mcp.atlassian.com/v1/mcp/authv2"
    }
  }
}
```

The config key is right; `serverUrl` is Antigravity's field for a remote server. But **this does not currently work** — treat the block above as a record of what was tried, not a working recipe.

Two blockers, in order:

1. The endpoint answers `401` with `WWW-Authenticate: Bearer` until authorized, and the `agy` CLI exposes no MCP OAuth flow — there is no `agy mcp` subcommand at all. Authorization has to happen in the Antigravity IDE under **Additional Options (…) > MCP Servers**.
2. That IDE authorization was attempted and refused, reporting that an administrator has restricted the domain. Antigravity enforces admin-controlled URL allowlisting, so `mcp.atlassian.com` appears to be blocked upstream of any local config.

With config in place but no authorization, `agy` silently loads zero Atlassian tools and logs nothing about the failure — no error, no warning. Three checks confirm it: the tool list contains only other servers' tools. A prompted Atlassian call reports no such tools, while the same prompt against an authorized server reaches the permission gate. And `~/.gemini/antigravity-cli/mcp/` has no `atlassian` tool-cache directory.

Local stdio servers need no authorization and do work from the config file alone.

## Rules for coding agents

[`jira-rules-for-agents.md`](jira-rules-for-agents.md) holds the Jira working rules for coding agents. They cover what must never be deleted, and which MCP lookups to skip with the answers to use instead. They also set status terminology and the writing style for issues and comments. Paste it into the agent's instructions — global `CLAUDE.md`, `AGENTS.md`, or equivalent — or reference it from there.

It is written for one specific Atlassian site, project, and workflow. Customize these before using it anywhere else:

| In the file | Why it is specific to one setup |
| --- | --- |
| `account_id` | Your Atlassian account id (`atlassianUserInfo` returns it once) |
| `cloudId`, `url`, `name`, `scopes` | Your site. `cloudId` is at `https://<your-site>/_edge/tenant_info`; scopes must match what your token or OAuth grant actually allows |
| Project key `MHMAPPS`, and the `self` URL | Your project. That URL embeds both the cloudId and the numeric project id, so it changes with either |
| Terminology (Backlog, ENH/MHM To-Do, Test) | Workflow status names are per-project, and these map local jargon onto them |
| "Create new issues with status Open" | The right starting status depends on your workflow |
| `jira-attach` reference under Images / media | Assumes the script is on `PATH` under that name |
| Writing style and attribution | Team convention |

The rest — never deleting content, `maxResults: 25` on JQL searches, not trusting the status Jira reports — are working habits rather than site facts. Keep or drop them.

## Where settings are kept

| What | Where |
| --- | --- |
| Site + account email | `~/.config/jira-attach/config.json` (mode `0600`) |
| API token | macOS keychain, service `atlassian-api-token`, account = your email |

Nothing secret is written to the config file.

Precedence for each setting: command-line option, then environment, then config file, then a prompt. `--site` / `--email` apply to a single run and are not saved; re-run `--configure` to change what is saved.

Environment overrides: `JIRA_SITE`, `JIRA_EMAIL`, `JIRA_KEYCHAIN_SERVICE`, `JIRA_CLOUD_ID`, `JIRA_ATTACH_CONFIG`.

Replace a revoked or rotated token with `jira-attach --reset-token`.

## Usage

```sh
# Attach only
jira-attach ABC-123 shot.png spec.pdf

# New comment with full wiki formatting and an inline image
jira-attach --comment ABC-123 --text 'h3. Findings' --image shot.png --text 'Details in [^spec.pdf].' --file spec.pdf

# Replace a comment / the description
jira-attach --replace-comment 45210 ABC-123 --text '*Updated* summary.'
jira-attach --replace-description ABC-123 --text 'h2. Overview' --image arch.png

# Append without rewriting what is already there (plain text + media only)
jira-attach --append-comment 45210 ABC-123 --text 'A follow-up note.' --image b.png
jira-attach --append-description ABC-123 --text 'Update:' --file log.txt
```

`--text`, `--image`, and `--file` are repeatable and are emitted in the order given. Append mode never reconverts existing content, so it cannot render formatting — it rejects wiki/markdown in `--text` rather than silently flattening it. Use `--comment` or `--replace-description` for formatted additions.

Run `jira-attach --help` for the full option list; the script's module docstring has the long-form notes.
