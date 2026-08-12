# GIT
- NEVER delete my data or my database!
- NO using 'git push --force'
- NO deleting repositories
- NO deleting remote branches, without explicit permission from ME
- NEVER use 'git reset' without explicit permission
- NEVER call `git checkout` without explicit permission
- NEVER change branches without asking or getting explicit permission
- NEVER revert other work that you didn't perform
- NEVER create new branches without asking
- NEVER use 'git --prune'

## Fetching and Pulling
- ALWAYS `git fetch` from all remotes before beginning work. Clearly indicate to the user if our branch is behind the remote. The user may wish to fast-forward / `git pull` -- but may not, so ALWAYS ASK.
- NEVER 'git pull' without asking the user

### Github (https://github.com/drewster99)
- My username / profile is "drewster99"
- I probably have 'gh' installed and it's probably already authenticated. You should ALWAYS prefer `gh` over driving the github API directly

### Bitbucket
- My username / profile is "drewster77" (https://bitbucket.org/drewster77)
- I am no longer creating new repos in bitbucket. Anything we actively touch in bitbucket should probably be migrated to github. Ask the user. The general way to migrate is: 1) checkout and pull EVERYTHING - all commits, branches, tags, etc. from the old bitbucket repo. 2) determine if the existing repo is a public or private one. 3) decide if we will rename the slug. New slugs are generally being "named-like-this", rather than being "NamedLikeThis". 4) Use `gh` to create the new repo with the new slug name and the appropriate public/private state. 5) If it is public, be sure to `touch __PUBLIC_REPO` in the repo root.6) Add the new remote to the local checkout repo, using its ssh URL (not https). 7) Push all to new repo. 8) Rename the old bitbucket repo by prefixing its name with "do_not_use_". So for example, if the old repo was named "NCCUserFeedbackKit", it should be renamed "do_not_use_NCCUserFeedbackKit" on bitbucket, and the new Github repo should be named "ncc-user-feedback-kit". 9) Remove the reference to the old remove from the local repo. 10) Summarize everything to the user.

# Repositories
- Repos checked out in ~/cursor or ~/Documents/ncc_source are PERSONAL repos
- Repos checked out in ~/clients or ~/Documents/clients are CLIENT repos
- Repos checked out in ~/checkouts, ~/Downloads, or /tmp/ are random repos from random folks that I was testing out for one purpose or another
- Any non-personal, non-client repo that I have forked for making changes is generally treated as a personal repo, and so will usually be found in ~/cursor or ~/Documents/ncc_source

## Important Repo Rules
- NEVER delete a repository
- NEVER delete local or remote branches
- NEVER use '--force' when pushing
- NEVER use 'git reset' locally without EXPLICIT permission
- NEVER change branch protection without EXPLICIT permission
- NEVER change branches without EXPLICIT permission
- NEVER create new branches without EXPLICIT permission

## Identification
- My name should always read as "Andrew Benson"

### Personal repos
- For all personal repos on Github and Bitbucket, as well as any open-source projects I've forked into Github, my commits SHOULD appear with the email "db@nuclearcyborg.com"
- It's possible some older repos or old commits might have "drewbenson@netjack.com". This is fine. Do not change them.
- New PERSONAL repos MUST be created in Github ONLY
- ALWAYS ask if the repo should be private or public. Default to private. For public repos, run `touch __PUBLIC_REPO` in the repo root to create an obvious reminder

#### My personal Github
- All my new repos are created under my "drewster99" Github profile
- I usually clone with ssh on these, like "git@github.com:drewster99/drews-chess-machine.git"
- On my local machine, these are generally cloned into ~/cursor/repo-slug-name
- On personal projects I generally work in "main". If I'm in a different branch, however, I probably want to be there. This will be evident if you already see various commits on the branch which have been pushed.

### Client repos
- If the local repo exists under ~/clients, it must be considered a client repo
- For all Enharmonic-related repos, which are generally found locally as ~/clients/Enharmonic or ~/checkouts/enh, should always use my "abenson@enharmonichq.com" email
- For other clients, use "db@nuclearcyborg.com"

## Slug naming
- New slugs should generally be lowercased with hyphen separations, like 'my-dog-identifier', even if the actual product is 'MyDogIdentifier'

### Creating new repos
- Use 'gh' to create them in my personal profile
- Ask if the repo should be public or private. If unclear, make it private
- For my personal PUBLIC repos Github (ONLY), `touch __PUBLIC_REPO` in the repository root to make sure it is always clear when we are not working in a private repo. If you find yourself in a public repo that is under my personal github profile that does not have this file, please add it.
- All personal and client repos should be present in my SourceTree. Add them if they're not there already and pay attention to the groupings. Random checkouts that are usually in my ~/checkouts folder should also be added, but in a 'checkouts' folder

## My personal Bitbucket
- My older personal repos exist under my personal "drewster77" bitbucket profile
- I generally clone with ssh on these like, "git@bitbucket.org:drewster77/poc-axis-adjusting-stack-view.git"
- DO NOT MAKE ANY NEW REPOS IN MY PERSONAL BITBUCKET ACCOUNT. I am slowly migrating away from it.
- Repositories that have already been migrated away will have slug names like "do_not_use_NCCEntitlementManager". I always rename these so that any existing remotes that might be misconfigured will not work. This is on purpose.

### Migration of my PERSONAL repos from Bitbucket to Github
- When migrating from Bitbucket to Github, we pull down the ENTIRE repo, all history, all branches, all refs, all tags, etc
- We push everything to the new repo -- again, ALL history, ALL refs, ALL branches, ALL tags, etc -- EVERYTHING
- We rename the slug on bitbucket, prefixing it with "do_not_use_", so a slug named "Foo-Bar" becomes "do_not_use_Foo-Bar"
- We remove the deprecated bitbucket remote from our local repo
- The new Github remote must be named 'origin'
- We celebrate by playing a short jingle - find one or make one up

## Client repositories
- Client repos are usually under ~/clients/CLIENT_NAME/REPO_SLUG, like ~/clients/Enharmonic/pot-mhm-product-tool
- Sometimes you might find them under ~/checkouts

## Random 3rd-party repos I'm trying or messing with
- If I don't plan to make changes, they should generally be checked out under ~/checkouts
- If I'm going to fork a repo and make changes, it should go in ~/cursor

## Some old repos
- Some old ones might be found in ~/Documents/ncc_source
