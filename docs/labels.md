# Labels

Labels carry the moving parts: what a merge should release, whose move it is,
which component a change touches, and what newcomers may pick up. Everything
*descriptive* about an issue lives in its type and fields instead — see
[planning.md](planning.md).

Four namespaces, which GitHub sorts alphabetically into one flat list.

## `release:` — on pull requests only

`major`, `minor`, `patch`. Marks the version bump a merge should cause. The
release workflow reads it from the merged pull request, takes the largest where
several apply, and tags. No label, no release.

This is how minor and patch releases happen: continuously, out of merged pull
requests. Only a major release gets a milestone.

## `acting:` — whose move it is

Exactly one on every open issue, and none on a closed one. It is the axis the
board's `Status` does not have: `Status` says where the work has got to,
`acting:` says who is holding it.

| Label | Means |
|---|---|
| `acting: reporter` | Waiting on whoever filed it for something nobody else knows. |
| `acting: maintainer` | Needs classifying or deciding before anyone can start. |
| `acting: agent` | Fully specified; a fresh agent session can take it as written. |
| `acting: human` | Needs a person: implementation, design, or judgement an agent should not make. |

Whoever last touched the issue sets it. It is a label rather than a field
because an agent can read it with one `gh issue list --label` call and no app
token.

**It drives the board.** An issue waiting on its reporter or on triage is
`Backlog`; one ready for an agent or a human is `Ready`. So you move work by
changing this label, and the board follows.

## `component:` — the area of the code

One vocabulary per repository, in that repository's own `.github/labels.yml`,
so adding a component is a change to the repository it belongs to.

**A component is not a commit area.** The component is coarse and closed: a
change is in one of them, or it belongs somewhere else. The area in a commit
title is finer and open — reuse whatever the log already uses. One component
usually covers several areas.

- **On a pull request: exactly one.** Two components are two concerns, so the
  change is normally a **stack**, one layer per component, closing one issue
  between them.
- **On an issue: as many as apply.** `implement OAuth2` really does span the
  backend and the frontend before anybody has written it.

Where two genuinely cannot land apart — a change and the single caller that
would otherwise break — a `Component exception:` line in the pull request
description lets the lint through and quotes the reason back. A component that
keeps needing one is a sign the vocabulary is wrong.

`component: uncategorized` means nobody has looked yet, and is a different
colour because it is not a component.

## `external:` — newcomer-facing

`first-issue` and `help-wanted`. Hints for people arriving at a repository with
users, with no effect on anything automated.

## Where the truth is

- [`planning/labels.yml`](../planning/labels.yml) here — the shared labels,
  identical everywhere.
- `.github/labels.yml` in each repository — that repository's components, and
  the one you will usually want.

A workflow applies both, so a label edited by hand is reverted on the next run.
GitHub's organisation-level default labels seed a repository at creation and are
never linked back afterwards, which is the drift this sync undoes. Archived
repositories are skipped.
