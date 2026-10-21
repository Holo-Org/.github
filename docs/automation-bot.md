# The organisation's automation app

`holo-org-project-automation-bot` is a GitHub App owned by `Holo-Org` and
installed on every repository in it. Workflows use it instead of
`GITHUB_TOKEN` when an action must be attributed to the organisation rather
than to a workflow run, or when its effects must trigger further workflows.

| | |
|---|---|
| App ID | `2433939`, as the organisation variable `MERGE_APP_ID` |
| Client ID | `Iv23lis6ybqptYTV2fPa`, as the organisation variable `MERGE_APP_CLIENT_ID` |
| Installation ID | `98599516` (organisation-wide, all repositories) |
| Private key | The organisation secret `MERGE_APP_PRIVATE_KEY` |

The two identifiers are **variables**, not secrets: neither is confidential —
both are readable from `GET /apps/{app_slug}` by anyone — and a variable is not
masked in logs, so a failing run shows which app it tried to authenticate as
rather than `***`. Only the private key is a secret, and it is the only one of
the three that grants anything. All three are organisation-wide, so a workflow
in any repository here can reach them.

Mint a token with
[`actions/create-github-app-token`](https://github.com/actions/create-github-app-token):

```yaml
- id: token
  uses: actions/create-github-app-token@64ab729a6294000f5aa4a4bc0b73d1f32bc45510 # v3.3.0
  with:
    client-id: ${{ vars.MERGE_APP_CLIENT_ID }}
    private-key: ${{ secrets.MERGE_APP_PRIVATE_KEY }}
```

Pass the client ID through `client-id`. The `app-id` input still works, and
`vars.MERGE_APP_ID` is kept for anything that needs the numeric form — the
ruleset bypass lists do — but the action has deprecated that input and a run
using it logs a warning.

**A reusable workflow here can read these directly.** There is no
`vars: inherit` to match `secrets: inherit`, so it is worth saying that none is
needed: `vars` resolves inside a `workflow_call` workflow, verified on
2026-10-28. A shared workflow in this repository therefore reads
`vars.MERGE_APP_CLIENT_ID` itself and needs no input for it, while the private
key still has to arrive through `secrets: inherit` or an explicit `secrets:`
block. The check was run with caller and callee in this repository, so it does
not distinguish whether `vars` resolves against the caller or the callee — a
distinction that does not matter while these are organisation variables visible
to every repository.

## Why an app at all

A merge made with `GITHUB_TOKEN` is a dead end. GitHub's documentation is
explicit that "events triggered by the `GITHUB_TOKEN` will not create a new
workflow run", and names "a GitHub App installation access token or a personal
access token" as the workaround. Label-triggered releases therefore cannot
observe a merge that `GITHUB_TOKEN` performed — the push to `main` would
trigger nothing at all.

An app also keeps the privilege off any human account: the identity allowed to
write to a locked `main` is one the organisation owns and whose key can be
rotated without touching anybody's personal credentials.

## Permissions the `/merge` command needs

| Permission | Level | Why |
|---|---|---|
| Contents | write | Creating the squash commit on the base branch. GitHub documents both merge endpoints as requiring Contents write. |
| Pull requests | write | Reading the pull request's title, body, labels, commits and head SHA, and commenting on it. |
| Issues | write | Posting the refusal comment and the reactions on the `/merge` comment. A pull request's conversation comments and their reactions are issue endpoints, not pull-request ones. |
| Checks | read | The bot's own gate: every check run on the head SHA must have completed successfully before it merges. |
| Commit statuses | read | The same gate. Statuses and check runs are different things, and a repository may report through either — Codecov uses both. |
| Deployments | read | Reading deployment state, where a repository gates merges on an environment. |
| Metadata | read | Mandatory for every app; granted implicitly. |

**This set is fixed.** The bot asks for the same permissions in every repository
and behaves the same way in every repository, whatever rules a particular
repository's rulesets happen to carry. A command whose code or permissions
varied by repository would be a command nobody could reason about, and a
permission granted "when needed" is a permission granted during an incident.

Where the bot cannot evaluate a requirement itself, it does not try. GitHub
refuses the merge, and the pull request page already shows which requirement is
unmet — not which rule, but the requirement, which is what a reader wants. So
the bot reports that the merge was refused and leaves the detail where GitHub
already presents it properly.

Two permissions it deliberately lacks:

- **No Administration.** The right to write to a locked branch comes from the
  branch ruleset's bypass list, not from a permission on the app.
- **No Actions.** The bot does not inspect workflow runs; it reads check runs
  and statuses, which are the two permissions above.

## How the merge itself works

There are two ways to perform the merge, and both have been shown to work
against a locked branch. The synchronous REST endpoint is not one of them: it
has no `bypass_rules` parameter and cannot ask for the bypass at all.

**`gh pr merge --squash --admin`**, with `--subject`, `--body` and
`--match-head-commit`, is the shorter path. `gh` is already on every hosted
runner, it talks to GraphQL `mergePullRequest`, and `--admin` requests the same
narrow bypass. Measured on 2026-10-29 against a locked branch:

| Rules on the branch | Plain | `--admin` |
|---|---|---|
| Lock the app bypasses, plus a required check it does not | refused: *the base branch policy prohibits the merge* | refused: *Required status check "probe-never-green" is expected.* |
| Lock alone | refused, same message | **merged**, `verified: true` |

So `--admin` clears the lock and nothing else — the required check still stopped
it, exactly as `bypass_rules: true` does. The title and body landed verbatim,
with no ` (#4)` appended.

**`PUT /repos/{owner}/{repo}/pulls/{number}/merge-async`** with
`bypass_rules: true` is the longer path: a JSON payload, a `uuid`, and a polling
loop. It is what GitHub's reference recommends, and it is the only option that
can touch a stacked pull request at all. Its findings follow, and the stack
case has a section of its own below.

Three facts established by experiment on this repository on 2026-10-21, against
a branch carrying an `update` rule ("Restrict updates") with the app as a
bypass actor in `always` mode:

1. **Being in the bypass list is not enough.** With `bypass_rules: false` the
   merge failed with `Repository rule violations found / Cannot update this
   protected ref.` The same request with `bypass_rules: true` merged. The bypass
   must be asked for explicitly on every call.
2. **`actor_id` in the bypass list is the app ID**, `2433939`, with
   `actor_type: "Integration"` — not the installation ID.
3. **A caller-supplied `commit_title` is used verbatim.** GitHub appends
   ` (#123)` only to the title it composes itself, so a workflow that supplies
   the title must append the pull request number itself to match the commits
   already on `main`.

The resulting commit keeps the pull request author as its **author** and records
`GitHub <noreply@github.com>` as its **committer**, so authorship survives the
merge and only co-author trailers need composing.

### The commit is verified

GitHub signs the commit it builds, so the merge lands with
`verification.verified: true` and `reason: "valid"`. Checked on the probe commit
and against the squash commits already on R-Type's `main`, which the merge
button produced: identical in shape — author preserved, committer `GitHub`,
signature valid. Merging through the app is no regression on that front.

Be precise about what the badge attests, though. The signature is **GitHub's**,
not the author's: it says GitHub built this commit through an authenticated API
call, not that the person named as author signed anything. A commit you make
locally and sign yourself carries a different and stronger claim. Nothing is
lost by merging through the app, because the merge button's commits were already
GitHub-signed — but a squash commit's signature has never attested to the
author's own key, and still does not.

Because these commits are signed, a `required_signatures` rule on the default
branch is satisfiable: squash merges are the only commits that land there, and
every one of them is signed by GitHub. That rule is **not** in
[`review.json`](../rulesets/review.json) — adding it is a decision, not a
consequence.

## The bypass is narrow, and that is the whole safety argument

`bypass_rules: true` asks to bypass "repository rules the actor is permitted to
bypass". Verified on 2026-10-21 against a branch carrying **two** rulesets — a
lock the app bypassed, and a required status check with an empty bypass list:

```
Repository rule violations found

Required status check "probe-never-green" is expected.
```

The merge was refused, with `bypass_rules: true`, and the message named the
offending rule. So the request is not a blanket override: it lifts only the
rules of rulesets that list the app, and every other ruleset still applies.

**The invariant this rests on: the app must be a bypass actor in the
"Restrict updates" ruleset and in no other.** Adding it to the bypass list of
the ruleset that carries approvals and required checks would turn `/merge` into
a way around review, which is the opposite of its purpose. Anybody changing a
ruleset's bypass list should read this paragraph first.

### `mergeable_state` cannot be used as the gate

A locked base branch reports `mergeable_state: "blocked"` even when every check
is green and nothing else stands in the way — the lock alone is enough, despite
the app being able to bypass it. Measured both with the required check in place
and with the lock as the only ruleset; `blocked` in both cases, while
`mergeable` stayed `true`.

A pre-flight must therefore examine the specific gates — check runs and the
combined status on the head SHA — and never `mergeable_state`, which on `main`
will always say `blocked`.

Note also that the combined status and the check runs are different things. On
the probe the combined status was `pending` with an empty `statuses` array while
two check runs were in progress, so a bot reading only `/commits/{sha}/status`
would have seen nothing at all.

## Stacked pull requests

GitHub's *stacks* — a chain of pull requests registered as one object, generally
available since 2026-10-06 — cannot be merged a layer at a time. Measured twice
on 2026-10-29, with a two-pull-request stack whose base branch carried the lock:

1. **`gh pr merge --admin` refuses outright**, and says why:

   > This pull request is part of a stack and must be merged using the
   > asynchronous merge REST API.

2. **`merge-async` on the bottom layer merges the whole stack.** Targeting the
   `position: 1` pull request, with `bypass_rules: true`, left *two* new commits
   on the base branch and both pull requests merged — the second layer included,
   which was never asked for.

3. **Every commit gets the same message.** Both commits carried the one
   `commit_title` and `commit_message` supplied for the bottom layer:

   ```
   probe: the bottom layer only

   If this message appears twice, the stack merged as one.
   ```

   The second commit's message describes the first commit's change.

`gh stack merge` *can* merge up to a chosen layer, but it states that "bypassing
merge requirements is not supported for stacks", so it cannot write to a locked
branch. There is therefore no way, on a locked default branch, to merge one
layer of a registered stack with a commit message of its own.

**A chain of pull requests is not a stack.** A pull request whose base is
another pull request's head has `stack: null` unless somebody registered it with
`gh stack`, and `/merge` handles it exactly like any other: one squash commit,
its own message, and GitHub retargets the dependent pull request when the merged
head branch is deleted. R-Type's pull requests are all `stack: null`. So this
limitation bites only if the team adopts `gh stack`, and the bot distinguishes
the two by reading `stack` rather than by looking at the base branch.

## Status flow

A successful call returns `202` with `status: "pending"` and a `uuid`. Poll
`GET /repos/{owner}/{repo}/pulls/{number}/merge-async/{uuid}` until the status
leaves `pending`:

```
pending  "Merge request enqueued."      → keep polling
pending  "Merge request is in progress." → keep polling
merged   details.sha is the new commit   → success
failed   details.message says why        → report it
```

`enqueued` is a distinct status, reached only through a merge queue, and it does
not mean the pull request merged. The wording "Merge request enqueued." on a
`pending` response is unrelated to it.
