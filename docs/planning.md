# How planning works

Everything is tracked on GitHub: issues, their types and fields, milestones, and
one project board per project.

The model has two halves, and most confusion about it comes from mixing them:

- **The inbox** is what people report. A `Bug`, an `Improvement`, a `Build`
  problem, a `Documentation` gap, a `Question`. Anybody opens these, they
  describe a *request*, and they are never scheduled directly.
- **The schedule** is `Agile`. These are the maintainers' own tasks: the things
  that go on a board, carry dates, and get worked on. They describe *work*.

A report becomes work by gaining `Agile` children, not by changing type. That
one rule explains most of what follows.

## Issue types

Types are set at the organisation level, so the vocabulary is the same in every
repository. The type decides which fields the issue carries — GitHub pins them
per type, so you only ever see the fields that apply.

| Type | Means | Fields it carries |
|---|---|---|
| **Bug** | Something is broken | `Kind`, `Origin` |
| **Improvement** | Works, but should be better | `Category` |
| **Build** | Cannot build, install or package | — |
| **Documentation** | Docs wrong, missing or unclear | — |
| **Question** | Something is unclear, or a decision needs settling | `Wayfinder` |
| **Extra Deliverable** | Scope nobody asked for, offered anyway | — |
| **Agile** | A unit of the maintainers' own planned work | `Priority`, `Effort`, `Target date`, `Hierarchy` |

## From a report to work

A reported issue is a request, and it stays one. When you decide to act on it:

1. Create one or more `Agile` issues for the actual work.
2. Make them **sub-issues** of the report.
3. Schedule them — priority, effort, a target date, a milestone.

The report closes when its last child closes. Nothing is retyped, so a `Bug`
keeps its `Kind` and `Origin`, the reporter's thread stays where the outcome is
discussed, and the rule that a pull request closes exactly one issue stays true:
the pull request closes the `Agile` task, not the report.

This is also why `Bug` and `Improvement` carry no dates. They are not
schedulable, by design. If you catch yourself wanting a target date on a `Bug`,
what you want is an `Agile` child.

## The Agile fields

### Hierarchy

Where the item sits in the breakdown. It is declared rather than derived,
because a story with no parent yet still has a level.

| Level | Means | Has a branch? |
|---|---|---|
| **Initiative** | A collection of epics driving at one goal. Only where the work needs one — across milestones, or across packages in one repository. | No |
| **Epic** | A theme grouping related stories and features. | No |
| **Feature** | A planned requirement that does not need splitting up. | Yes |
| **Story** | A planned requirement with several parts. | No; its tasks do |
| **Task** | A unit of work needed to complete a story. | Yes |

Each level has its own issue template, because what is worth writing down
differs: an epic needs a scope boundary, a story needs design notes, a task
needs a definition of done. A markdown template cannot set an issue field, so
the template puts `[Epic]: ` and the like in the title and the automation reads
the level from it.

Sub-issues are what link the levels. The level is checked against that graph, so
a `Task` cannot be the parent of an `Epic`.

### Priority

**Priority is not urgency.** It answers one question: *how much of the rest of
the work waits on this?* Set it as if time were infinite; deadlines are the
target date's job.

| Level | Means |
|---|---|
| **Urgent** | Most of what is left waits on this; little else moves until it lands. |
| **High** | Several other issues depend on this, directly or one step away. |
| **Medium** | Something depends on this, but the rest can proceed around it. |
| **Low** | Nothing depends on this; it can land whenever without changing the plan. |

What *actually* blocks what is recorded with native issue dependencies, which
are the real gate. Priority lets you order issues that share a target date
without walking the graph.

### Dates and milestones

**Target date** is when this issue should be done, and it is the conventional
notion of priority: the issue with the nearest or most overdue target date is
the one to work on next.

**A milestone's due date is the real deadline.** Target dates are the interim
dates you set yourself to arrive there in time, so an issue targeted *after* its
milestone's due date is a contradiction, and the lint says so.

**`Start date` and `End date` are the board's, not the issue's.** They are
filled in for you, the first time work begins and the first time it ends, and
they record what happened rather than anything anyone decided — which is why
they sit with `Status` rather than among the issue's own fields. The Roadmap
view shows what was planned against them; the Timeline shows what happened.

A milestone title begins with its kind, because the two fail in opposite
directions:

- **`Defence: …`** — a school defence. The date cannot move, so when it is at
  risk you cut scope. An overdue one is an error.
- **`Release: …`** — a **major** release. The scope is the point, so the date may
  move. An overdue one is a warning.

Only major releases get a milestone. Minor and patch releases happen
continuously out of merged pull requests, from their `release:` labels. So the
milestone and the label are not two ways of saying the same thing: the milestone
is a plan, the label is what causes a release.

### Effort

Relative size, `XS` to `XL`, for spotting the items that need breaking down.

## Questions and Wayfinder

A `Question` is either a plain thread — something is unclear, somebody answers,
it closes — or a piece of a **wayfinder map**: a planned stretch of research and
decision-making, broken into tickets that are resolved until the way is clear.
The `Wayfinder` field says which:

| Value | Means |
|---|---|
| **map** | The map itself: notes, decisions so far, and what is still fog. |
| **research** | Surface a fact from documentation or other sources. Runs unattended. |
| **grilling** | A conversation to settle a decision. Needs a human. |
| **prototype** | A cheap artefact built to react to. Needs a human. |
| **task** | Manual work that unblocks a decision. |

An `Agile` issue may be **blocked by** a wayfinder ticket, which is the point of
the arrangement: work that depends on an unmade decision is visibly stalled
rather than quietly guessed at. Blocking is recorded with native issue
dependencies and nothing else.

## The project board

One board per project, created from the organisation's project template.

The board's fields split along one line: **what a person decides lives on the
issue, what the automation observes lives on the board.** So `Priority`,
`Effort`, `Target date` and `Hierarchy` are organisation issue fields, visible
and filterable on the issue itself; `Status`, `Start date` and `End date` belong
to the project, because nothing sets them by hand.

What is on it: **`Agile` issues**, nothing from the inbox, and **pull
requests**, which is why half the `Status` options are about review.

**`Status` is computed, not set.** You do not move cards; you change the things
it is derived from:

| For an issue | Comes from |
|---|---|
| `Backlog` | `acting: reporter` or `acting: maintainer` |
| `Ready` | `acting: agent` or `acting: human` |
| `In Progress` | an assignee, or an open linked pull request |
| `Fixed` | closed as completed |
| `Cancelled` | closed as not planned |

Pull request statuses — `Created`, `In Review`, `Changes Requested`,
`Waiting Merge`, `Merged` — come from the pull request's own events.

How, and what is not wired up yet, is in
[project-automation.md](project-automation.md).

## What you set, and what is set for you

| Set by you | Set for you |
|---|---|
| Issue type, and the fields it pins | `Start date` and `End date` |
| `Priority`, `Effort`, `Target date` | `Hierarchy`, from the template's title prefix |
| Milestone | Every `Status` on the board |
| Dependencies and sub-issues | Board membership |
| `acting:`, whenever you hand the issue on | |
| `component:` | |
