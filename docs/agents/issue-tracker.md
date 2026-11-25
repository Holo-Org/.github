# Issue tracker: GitHub

Issues live as GitHub issues, typed and fielded at the organisation level. Use
the `gh` CLI. The model is in [../planning.md](../planning.md); this file is the
operations.

This repository has no `.git` directory, so `gh` cannot infer which repository
it is in. Pass `--repo Holo-Org/<name>`, or export `GH_REPO`, on every call.

**The one rule to hold on to:** a reported issue is a request and stays one.
`Bug`, `Improvement`, `Build`, `Documentation` and `Question` are what people
report; `Agile` is work the maintainers scheduled. Never retype a report to
schedule it — create `Agile` sub-issues under it.

## Operations

- **Create**: `gh issue create --repo <r> --type <Type> --title '…' --body '…'`.
  The type is required; an untyped issue is a lint failure.
- **Read**: `gh issue view <n> --repo <r> --comments`.
- **List what you may take**:
  `gh issue list --repo <r> --state open --label 'acting: agent'`.
- **Label**: `gh issue edit <n> --repo <r> --add-label '…'` / `--remove-label`.
  Quote every label: they all contain a space and a colon.
- **Close**: `gh issue close <n> --repo <r> --comment '…'`, with
  `--reason 'not planned'` where it will not be actioned.

## Issue fields

Fields are an organisation-level feature and are not in `gh issue` yet. Read
them over GraphQL on `issue.issueFieldValues`, write them with
`setIssueFieldValue`. The definitions and their options are on
`organization.issueFields`, and `issueType.pinnedFields` says which fields a
type carries.

Do not set a field the issue's type does not pin, and do not invent an option
name — read the field's options first.

## Sub-issues and blocking

- **Sub-issues** are the real parent/child link. A task list in the body is for
  readers, not for the graph.
- **Blocking** is native issue dependencies, and nothing else. There is no
  `blocked` label, deliberately.
- An issue is available when it has no open blocker and no assignee.

## Claiming work

Assign yourself, then set `acting:` to what is true after your turn. It is
**advisory, not a lock**: GitHub has no atomic label operation, so two agents
can both read `acting: agent` and both start. Where a fleet must not collide,
one orchestrator hands out the work.

## Wayfinding

A `Question` with its `Wayfinder` field set is part of a map. Resolve a ticket by
commenting the answer, closing it, and appending a pointer to the map's
decisions.
