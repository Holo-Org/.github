# Project automation

The board is a presentation of the issues, maintained by workflows in this
repository. Nobody drags a card, and `Status` is computed rather than set.

## Why not the built-in project workflows

GitHub's own project automations are free and need no token, and they are all
switched off deliberately:

1. **They only ever set `Status`.** The `Hierarchy` level, the dates, and
   membership filtered by issue type are all out of their reach.
2. **They cannot tell an issue from a pull request** finely enough for a board
   that gives the two different status vocabularies.
3. **They live in the project's settings**, so they are invisible in review, not
   versioned, and not copied when a project is created from the template.

## The two apps

`GITHUB_TOKEN` cannot touch an organisation project — GitHub's wording is that
it *"is scoped to the repository level and cannot access projects"*. So the sync
needs an app, and it is not the one behind `/merge`.

| App | Holds | Job |
|---|---|---|
| `holo-org-project-automation-bot` | Contents write, and read or write on pull requests, issues, checks, statuses and deployments — see [automation-bot.md](automation-bot.md) | `/merge` |
| `holo-org-planning-bot` | Issues write, organisation projects read and write, **no Contents** | labels, fields, the board |

The merge app can write commits to a locked default branch. Giving that right to
something whose job is moving cards would undo the reason its permission set is
fixed, so the planning app has no Contents permission at all and a bug in the
board sync cannot reach a branch.

## Which project

In order: the repository variable **`PROJECT_URL`**; failing that, the
organisation project whose title matches the repository name, compared without
regard to case; failing that, the job exits zero, because a repository with no
board is normal.

Fields are resolved **by name** at run time, not by stored id, because every
project created from the template gets its own. A renamed or missing field fails
the job rather than writing to the wrong one.

## What the sync does

On an issue being opened, edited, labelled, assigned, closed or reopened:

- **Membership**: added when its type is `Agile`, and not otherwise.
- **`Hierarchy`**: read once from the title prefix the template supplied, per
  [`planning/conventions.yml`](../planning/conventions.yml). A markdown template
  cannot set an issue field, which is why the prefix exists.
- **`Status`**: computed from the `acting:` label, the assignees, whether a
  linked pull request is open, and how the issue was closed. The table in
  [planning.md](planning.md) is the whole rule.
- **`acting:`**: `acting: maintainer` added when none is present, all of them
  removed when the issue closes, two of them reported rather than guessed at.
- **`Start date`** the first time it reaches `In Progress`, **`End date`** the
  first time it closes. Both are the project's own fields rather than the
  issue's, because they record what the automation observed rather than anything
  a person decided. Closing something that never started leaves the start empty
  rather than inventing one on the closing day.

On a pull request: added always, with `Status` from the event — `Created` while
a draft, `In Review` once ready, `Changes Requested`, `Waiting Merge` on
approval, `Merged`, or `Cancelled` when closed unmerged.

## Wiring a repository

Three stubs, each calling a reusable workflow here, all offered under
**Actions → New workflow**:

| Stub | Does |
|---|---|
| `.github/workflows/labels.yml` | Applies the label vocabulary |
| `.github/workflows/lint-pr.yml` | Checks a pull request against the conventions |
| `.github/workflows/project-sync.yml` | Keeps the board in step |

Plus `.github/labels.yml` holding that repository's components, and
`PROJECT_URL` if its board is not named after it. **A workflow file only fires
once it is on the default branch**, so the first one lands through a pull
request like anything else.

## Not wired up yet

The nightly planning lint: closing a milestone whose last issue has closed,
reporting an overdue `Defence:` milestone as an error and a `Release:` one as a
warning, an issue whose `Target date` falls after its milestone's due date, and
a `Hierarchy` level that contradicts the sub-issue graph.

`Priority` is set by hand. It is a reading of the dependency graph, so it could
be computed, but not until dependency edges are recorded consistently enough to
compute from.
