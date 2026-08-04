# jira-attach

Attach files to a Jira issue, and build or extend its comments and description with
inline images and file cards. Pure Python 3 standard library; the API token lives in
the macOS keychain.

## Setup

1. **Make it runnable and put it on your PATH**

   ```sh
   chmod +x jira-attach
   ln -s "$PWD/jira-attach" /usr/local/bin/jira-attach   # or anywhere on your PATH
   ```

2. **Create an Atlassian API token** at
   <https://id.atlassian.com/manage-profile/security/api-tokens>

   Use a classic (unscoped) or coarsely-scoped token — it needs `read:jira-work` and
   `write:jira-work`. A finely-scoped token generally 404s on issues it cannot see.

3. **Configure**

   ```sh
   jira-attach --configure
   ```

   Prompts for your Jira site (e.g. `https://your-team.atlassian.net`) and the email
   of the Atlassian account the token belongs to, then asks for the token itself.

4. **Check it**

   ```sh
   jira-attach ABC-123 some-screenshot.png
   ```

## Where settings are kept

| What | Where |
| --- | --- |
| Site + account email | `~/.config/jira-attach/config.json` (mode `0600`) |
| API token | macOS keychain, service `atlassian-api-token`, account = your email |

Nothing secret is written to the config file.

Precedence for each setting: command-line option, then environment, then config file,
then a prompt. `--site` / `--email` apply to a single run and are not saved; re-run
`--configure` to change what is saved.

Environment overrides: `JIRA_SITE`, `JIRA_EMAIL`, `JIRA_KEYCHAIN_SERVICE`,
`JIRA_CLOUD_ID`, `JIRA_ATTACH_CONFIG`.

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

`--text`, `--image`, and `--file` are repeatable and are emitted in the order given.
Append mode never reconverts existing content, so it cannot render formatting — it
rejects wiki/markdown in `--text` rather than silently flattening it. Use `--comment`
or `--replace-description` for formatted additions.

Run `jira-attach --help` for the full option list; the script's module docstring has
the long-form notes.
