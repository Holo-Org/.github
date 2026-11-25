# Contributing to a Holo-Org repository

This file is the organisation's default, so it applies to every repository here
unless that repository carries its own.

- **Reporting something** — a defect, a gap, an idea, a question. Any repository
  takes these, from anybody. Start at [filing an issue](#filing-an-issue).
- **Writing a change** — your own, or one you picked up. Start at
  [working on a change](#working-on-a-change).

The planning model behind it is in [docs/planning.md](docs/planning.md). Read
that if you want to know *why* an issue is typed the way it is; this file tells
you what to do.

## Filing an issue

Every issue carries a **type**, and the type decides which fields it gets. Pick
it from what you are reporting, not from how urgent it feels:

| You are reporting | Type |
|---|---|
| Something is broken | **Bug** |
| It works but should be better: faster, cleaner, more compatible, better tested | **Improvement** |
| You cannot build, install or package the project | **Build** |
| The documentation is wrong, missing or unclear | **Documentation** |
| You do not understand something, or a decision needs settling | **Question** |

The forms in the **New issue** menu set the type for you, so use them rather
than a blank issue. From the command line, pass it:

```bash
gh issue create --repo Holo-Org/<repo> --type Bug --title '…'
```

The **Initiative**, **Epic**, **Feature**, **Story** and **Task** templates are
the maintainers' planning vocabulary. A report you file stays the report it is;
when the work is scheduled, those are created underneath it — so nothing you
file gets retyped out from under you, and the thread you opened stays where the
outcome is discussed.

What makes a report useful is the same everywhere: what you did, what happened,
what you expected instead, and the smallest case that still shows it. Version,
platform and configuration if they could possibly matter.

## Working on a change

### Branches

A branch name says what kind of change it is and which component it touches,
because the commit title carries neither:

```
<kind>/<component>/<short-slug>
```

- **`<kind>`** is one of `feat`, `fix`, `docs`, `build`, `ci`, `refactor`,
  `cleanup`, `perf`, `test`, `deps` — the list in
  [`planning/conventions.yml`](planning/conventions.yml). It is linted, so
  extend it there rather than inventing one.
- **`<component>`** is a `component:` label value from this repository,
  lowercased. Its list is in that repository's `.github/labels.yml`.
- **`<short-slug>`** is a few words with hyphens.

So `feat/nix/pin-the-zig-toolchain`, `docs/hosting/explain-the-dns-records`,
`fix/web-hydration/match-the-server-markup`.

### Commits

One concern per commit. A commit is a patch that can go through revisions, so
amending and rebasing your branch into a coherent set of patches is encouraged.

**The title** reads `<area>: <imperative summary>`, lowercase except proper
names. The area is finer than the component and the list is open: reuse whatever
the log already says, so a component like `Engine` might hold `engine`, `world`
and `ecs`.

The hard limit is **85 columns on the commit title Git will store**, which
includes the area and the ` (#123)` that merging appends. The command refuses a
title over it, so measure the whole thing. Aim shorter: past about fourteen
words a title stops being readable at a glance, and usually means a commit doing
more than one thing.

**The body** records the decisions the diff cannot show — what somebody tracing
the history of a line would want to find. At most two paragraphs of three lines
each, no line over 85 columns. Leave it out when the title says everything.

**The footer** is trailer lines only, one `Key: value` per line, two blank lines
after the body. `Co-authored-by:` and the issue reference live there, and the
merge command writes both for you.

A title or body that will not fit these limits means the commit does too much.
Split it.

### Pull requests

**A pull request closes exactly one issue.** If yours would close two, it is two
pull requests — either independent, or one on top of the other.

**One `component:` label.** A change touching two components is two concerns,
and the normal answer is a **stack**: a chain of pull requests, one layer per
component, closing one issue between them. The topmost layer says
`Closes #123`; every other says `Part of #123`, so the issue closes once, when
the last layer lands.

Only where two genuinely cannot land apart — a change and the single caller that
would otherwise break — add a line to the description:

```
Component exception: <why they cannot land apart>
```

The lint then allows the second label and quotes your reason back. Reach for the
stack first.

**The template is a machine contract, not a suggestion.** The merge command
parses your description to compose the commit, so two headings must be there and
must be spelled exactly:

- `## Summary` becomes the commit body. Empty means nothing to merge with.
- `## Related issue` must contain `Closes #123` or `Part of #123`. A `Closes #`
  with no number is refused rather than ignored.

Guidance inside HTML comments is stripped, so leave the template's prompts in
place.

### Merging

Nobody presses the button. A comment of `/merge` on the pull request
squash-merges it, with the commit composed from the pull request itself. See
[docs/merging.md](docs/merging.md) for what it refuses and why.

## Labels

You need none of them to contribute: `component:` is described above, and
`external: first-issue` and `help-wanted` mark issues picked out for newcomers,
though nothing stops you taking another one. The rest is in
[docs/labels.md](docs/labels.md).
