# Recommended rulesets

Ready-to-apply ruleset definitions for repositories in this organisation, in
[`../rulesets`](../rulesets). They encode one rule: **everything reaches the
default branch through a reviewed pull request, merged by the automation app.**

Organisation-level rulesets need a GitHub Team plan — `GET /orgs/Holo-Org/rulesets`
answers `403 Upgrade to GitHub Team` — so these are applied per repository. They
work on the Free plan because the repositories here are public.

| File | What it does | Apply it |
|---|---|---|
| [`review.json`](../rulesets/review.json) | Requires a reviewed pull request, green CI, squash merges, linear history | Every repository |
| [`restrict-updates.json`](../rulesets/restrict-updates.json) | Locks the default branch so only the app can write to it | Repositories with `/merge` working |
| [`release-tags.json`](../rulesets/release-tags.json) | Stops `v*` tags being moved or deleted | Repositories that publish releases |

## The two branch rulesets are a pair, and must stay separate

`review` holds the rules that protect the code: an approval, resolved threads,
green checks. `restrict updates` holds the lock that stops humans merging by
hand. They are two rulesets rather than one because their bypass lists differ,
and that difference is the whole safety argument:

- **`restrict updates` lists only the app.** Not the `Bypass rulesets` team, not
  administrators. If a human can bypass the lock, they can push to the default
  branch directly and the convention is gone.
- **`review` does not list the app.** The app asks to bypass rules when it
  merges, and that request lifts only the rules of rulesets naming it. Add the
  app here and `/merge` becomes a way around review — approvals and CI included.

See [`automation-bot.md`](automation-bot.md) for the experiment that establishes
this; it is a measured property of the API, not an assumption.

## Applying them

`review.json` carries **two** placeholders, both marked `EDIT ME`, and both must
be replaced before it will apply.

The **CI check name** must match the check exactly as GitHub reports it, which
for a workflow job is the job's display name:

```sh
gh api "repos/Holo-Org/<repo>/commits/$(git rev-parse HEAD)/check-runs" \
  --jq '[.check_runs[].name]'
```

The **required reviewer team** is the project's own team, and the field wants its
numeric id, not its slug:

```sh
gh api orgs/Holo-Org/teams --jq '.[] | {id, slug}'
```

Leaving a placeholder in gets you a `422` that does not say which one:

```
Invalid property /rules/4: data matches no possible input.
```

`/rules/4` is the rule's index in the `rules` array — the fifth, which is
`pull_request`, so that message means the team id. A bad check name is accepted
silently instead, and simply never passes.

Then post each file:

```sh
gh api -X POST repos/Holo-Org/<repo>/rulesets --input rulesets/review.json
```

The web interface also offers **Settings → Rules → New ruleset → Import a
ruleset**, which takes the same JSON. That route is untested here; the `gh api`
one above is what these files were validated against.

**Order matters.** Apply `review` as soon as a repository has CI. Apply
`restrict updates` *only once `/merge` works there* — the lock makes the merge
button unavailable to everybody, so a repository that is locked before the
command exists cannot be merged into at all.

## Choices worth knowing about

**Squash only.** `allowed_merge_methods` is `["squash"]`. A rebase merge keeps
the branch's own commit messages, so neither the title check nor the
Summary-to-body mapping that `/merge` performs would mean anything for those
commits.

**Signatures are required.** Every commit that reaches the default branch is a
squash commit GitHub built, and GitHub signs those — measured, not assumed; see
[`automation-bot.md`](automation-bot.md). So the rule is satisfied by both merge
paths and by the merge button, and it costs the two teammates who use plain git
nothing, since their own branch commits never land on the default branch
directly. What it buys is that nothing *else* can arrive there unsigned.

**Code-owner review is required, and that costs nothing.** Without a
`CODEOWNERS` file the rule has no owners to demand a review from, so it is
inert; R-Type has carried it with no `CODEOWNERS` since 2026-10-15 and every
pull request since has merged. Leaving it on means a repository that later adds
a `CODEOWNERS` file gets the enforcement without anybody remembering to turn the
rule on.

**Branches need not be up to date.** `strict_required_status_checks_policy` is
`false`. Setting it `true` would force a rebase onto the default branch before
every merge, which catches semantic conflicts that CI on the branch alone
misses — at the cost of a rebase per pull request. Worth revisiting if a
semantic conflict ever reaches the default branch.

**Stale approvals are dismissed on push**, and the last push must itself be
approved. Together these mean a force-push after approval sends the pull request
back for review, which is the behaviour `/merge` relies on when it refuses a
pull request whose head has moved.

**One approval must come from the project's own team.** `required_reviewers`
demands an approval from a named team for files matching `*`, which on top of
`required_approving_review_count: 1` means the approval cannot come from an
outside collaborator. The team differs per project, so it is the second of the
file's two placeholders. Keep `"type": "Team"`; only the id changes.

## If `/merge` breaks

With `restrict updates` active, nobody can merge while the command is down.
Two ways out, in order of preference:

1. Set that ruleset's enforcement to `disabled` — it keeps the configuration and
   the bypass list intact:

   ```sh
   gh api -X PUT repos/Holo-Org/<repo>/rulesets/<id> -f enforcement=disabled
   ```

2. Add yourself to its bypass list temporarily. Remember to take yourself out
   again; a forgotten entry is indistinguishable from a deliberate one.

Do not delete the ruleset — recreating it means getting the bypass list right
again, and an empty bypass list silently locks the app out too.

## Notes

- The `update` rule accepts an `update_allows_fetch_and_merge` parameter and
  then reports it as `null`. Harmless; it is the fork-syncing escape hatch and
  means nothing for a branch that is not a fork.
- `bypass_actors[].actor_id` for the app is the **app ID**, `2433939`, with
  `actor_type: "Integration"` — not the installation ID. It is also the
  organisation variable `MERGE_APP_ID`, if a workflow ever has to build this
  list itself.
- Rulesets whose enforcement is `evaluate` or `disabled` are not returned by
  `GET /repos/{owner}/{repo}/rules/branches/{branch}`, so that endpoint shows
  what is actually in force rather than what is configured.
