# Merging with `/merge`

A comment of `/merge` on a pull request squash-merges it, with the commit
message composed from the pull request itself. Nobody merges by hand: the
default branch is locked, and the organisation's automation app is the only
actor allowed to write to it.

Two things make that worth the trouble. The commit message stops depending on
whoever happens to press the button, and the merge is made by an app rather
than `GITHUB_TOKEN`, so a release workflow can react to the push — merges made
with `GITHUB_TOKEN` trigger nothing at all.

## What the commit looks like

For a pull request numbered 53, titled `engine: turn keys and buttons into
actions from the settings file`, whose Summary reads as the template asks:

```
engine: turn keys and buttons into actions from the settings file (#53)

The Client no longer reads fixed keys: each Action takes its keys and gamepad
buttons from `settings.zon`, which the Engine finds and writes with commented
defaults.

Closes #37
Co-authored-by: A Colleague <colleague@example.com>
```

- **The title** is the pull request title with ` (#53)` appended, because
  GitHub only adds the number to titles it composes itself.
- **The body** is the `## Summary` section, with HTML comments removed.
- **The footer** is the reference from `## Related issue`, then one
  `Co-authored-by` trailer per other person who wrote part of the branch.

Committers are deliberately not co-authors. Rebasing a branch onto its base
makes the rebaser the committer of every commit on it, and rebasing somebody
else's work is not co-writing it. So the trailers come from commit authors and
from `Co-authored-by` lines in the branch's own commit messages, and nothing
else.

## One-time organisation setup

1. The automation app must exist and hold the permissions in
   [`automation-bot.md`](automation-bot.md), with its private key in the
   `MERGE_APP_PRIVATE_KEY` organisation secret and its client id in the
   `MERGE_APP_CLIENT_ID` organisation variable.
2. Each repository needs the two rulesets from [`rulesets.md`](rulesets.md):
   `review` for the approval and the checks, and `restrict updates` to take the
   merge button away from everybody but the app.

Apply `restrict updates` **last**, once `/merge` works in that repository. The
lock stops everyone merging, so a repository locked before the command works
cannot be merged into at all.

## Per-repository setup

Add `.github/workflows/merge.yml`:

```yaml
name: Merge

on:
  issue_comment:
    types: [created]

jobs:
  merge:
    uses: Holo-Org/.github/.github/workflows/merge.yml@main
    secrets: inherit
```

It is also offered as a starter workflow: **Actions → New workflow → Merge on
/merge**.

**The file must be on the default branch.** `issue_comment` only fires for
workflows that are already there, so the stub does nothing while it sits in a
pull request — including its own.

## What it refuses, and why

| Refusal | Reason |
|---|---|
| The commenter lacks write access | Checked with the collaborator permission API, not `author_association`, which reports membership rather than whether somebody may push |
| The pull request is closed, a draft, or has conflicts | Nothing to merge |
| It belongs to a GitHub stack | Merging one layer merges the whole stack and gives every commit this one's message. See [`automation-bot.md`](automation-bot.md) |
| The commit title would exceed 72 columns | The convention's limit, measured on the title GitHub will store, `(#n)` included |
| The title is not `<area>: <subject>`, has a double space, or does not end in a letter or digit | The commit convention |
| A check has not finished, or did not pass | The bot's own rule, the same in every repository whatever its rulesets say |
| `## Summary` is empty | It becomes the commit body |
| `## Related issue` has no `Closes #123` or `Part of #123` | Required by the template, and an empty `Closes #` is refused rather than ignored |
| GitHub refused the merge | A requirement is unmet. The pull request's own merge box names it, so the comment does not try to |

A refusal is a **successful** run: the bot explains itself in a comment, puts a
👎 on the `/merge` comment, and exits zero. A red run means the bot itself
broke, not that the pull request was unacceptable.

On the way, `/merge` reacts 👀 when it starts and 🚀 when the merge lands.

## The manual fallback

When the comment path is unavailable, pass a pull request number instead:

```yaml
jobs:
  merge:
    uses: Holo-Org/.github/.github/workflows/merge.yml@main
    with:
      pull-request: '53'
    secrets: inherit
```

Or use the action directly as one step of a larger workflow, minting the token
yourself:

```yaml
- uses: actions/create-github-app-token@64ab729a6294000f5aa4a4bc0b73d1f32bc45510 # v3.3.0
  id: token
  with:
    client-id: ${{ vars.MERGE_APP_CLIENT_ID }}
    private-key: ${{ secrets.MERGE_APP_PRIVATE_KEY }}

- uses: Holo-Org/.github/actions/merge@main
  with:
    token: ${{ steps.token.outputs.token }}
    pull-request: '53'
```

## How it is tested

The parsing and composing live in
[`actions/merge/lib.sh`](../actions/merge/lib.sh) and have no network in them,
so [`lib.test.sh`](../actions/merge/lib.test.sh) exercises all of it and CI runs
those tests on every pull request. They cover the awkward cases: CodeRabbit
appending its own `## Summary by CodeRabbit` heading, guidance text inside HTML
comments, an empty `Closes #`, a rebased commit whose committer must not become
a co-author, an app among the commit authors, and a title that is fine with a
two-digit pull request number but not a four-digit one.

## Troubleshooting

**Nothing happens.** The stub is not on the default branch, or the comment does
not start with the word `/merge`. `/merged` and `/merge-please` are ignored
deliberately.

**Skipped runs after every comment.** Every comment on a pull request raises an
`issue_comment` event, so review bots that comment on each one produce a run
that the job's condition skips immediately. A skipped job costs no minutes and
never mints a token, so this is working as intended rather than noise to fix.

**`/merge` is for people with write access.** The commenter is not a
collaborator with push rights on that repository. Organisation membership is
not enough.

**`Cannot update this protected ref`.** The app is not in the bypass list of
the `restrict updates` ruleset, or it is there in `pull_request` mode rather
than `always`.

**A refusal naming a check nobody recognises.** Check runs and commit statuses
are separate mechanisms and the bot reads both. An integration reporting a
status that never turns green will block every merge in that repository.

## Limitations

- **Registered GitHub stacks cannot be merged.** The asynchronous merge API,
  which is the only one that will touch a stack, merges every layer at once and
  puts the one supplied message on every resulting commit. A chain of ordinary
  pull requests is not a stack and merges normally.
- **The wiring has not been exercised end to end.** The composition is unit
  tested and the merge mechanism was measured against a locked branch, but
  because `issue_comment` only fires for workflows already on the default
  branch, the trigger, the reactions and the refusal comments cannot be tried
  until this is merged. Treat the first live `/merge` as the test.
