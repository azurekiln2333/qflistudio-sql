# SQL Git publication

Date: 2026-10-16. The user explicitly requested configuring and pushing the
five SQL repositories. All commands ran in `D:/MyNewProjects/qfli_sql`.

## Local configuration

`origin` fetches from CNB and has the five push URLs below. Local
`remote.pushDefault=origin` and `push.default=simple`, with `main` tracking
`origin/main`, make ordinary `git push` publish the current main branch to all
five repositories. Git remote settings are local `.git/config` metadata;
clones must configure their own push URLs.

| Host | Push URL | Initial main publication |
| --- | --- | --- |
| CNB | `https://cnb.cool/azurekiln/qflistudio-sql.git` | Success |
| GitHub | `https://github.com/azurekiln2333/qflistudio-sql.git` | Success |
| Gitee | `https://gitee.com/azurekiln/qflistudio-sql.git` | Success |
| GitCode | `https://gitcode.com/azurekiln/qflistudio-sql.git` | Success |
| GitLab | `git@gitlab.com:azurekiln-team/qflistudio-sql.git` | Success |

Fetch URL: `https://cnb.cool/azurekiln/qflistudio-sql.git`.

GitLab HTTPS reads succeeded but HTTPS push lacked a stored password. The
existing SSH key authenticated as `azurekiln`, and an SSH push created main
successfully. Only the GitLab push transport was changed to SSH; no credential
was generated, printed, or committed.

## Evidence and scope

- Initially no local remotes were configured. All five HTTPS `ls-remote`
  checks succeeded and returned no HEAD/main/master refs.
- Reviewed source commit `b3a204d63bb73ba60a2538c3925a41402b7d3aa7` was pushed
  to all five main branches without force. This publication record is committed
  and subsequently synchronized using the same ordinary origin push.
- Full reachable-history metadata inspection found 494 blobs, largest
  9,278,257 bytes. No LFS conversion or history rewriting was necessary.
- Pre-existing unstaged source changes and unrelated untracked files were
  preserved. Only this publication record, its scoped preflight note and the
  task execution checklist are included in the publication documentation commit.
- Shared core and other project workspaces were not modified or pushed.
- No application code changed; the existing release validation remains as
  recorded in `check.md`, including external signing and OHOS-device limits.

To inspect or use this local setup:

```powershell
git remote -v
git remote get-url --all --push origin
git push
```

The coordinator verifies each remote main hash against the final local HEAD
after the documentation push. A successful push does not change the remaining
store-signing requirements.
