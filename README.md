# Holo-Org/.github

Shared GitHub Actions workflows, templates and planning conventions for the
Holo-Org organisation.

## Contents

| Path | What it is |
|---|---|
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | The organisation's default contributing guide, inherited by every repository without one |
| [`.github/ISSUE_TEMPLATE`](.github/ISSUE_TEMPLATE) | The default issue forms and the five Agile templates, inherited the same way |
| [`.github/PULL_REQUEST_TEMPLATE.md`](.github/PULL_REQUEST_TEMPLATE.md) | The default pull request template, whose headings `/merge` parses |
| [`planning`](planning) | The label vocabulary and the closed vocabularies the lints check against |
| [`.github/labels.yml`](.github/labels.yml) | This repository's own components, as every repository has |
| [`.github/workflows/mirror.yml`](.github/workflows/mirror.yml) | Reusable workflow that mirrors a repository to another GitHub repository over SSH |
| [`.github/workflows/merge.yml`](.github/workflows/merge.yml) | Reusable workflow behind the `/merge` command |
| [`.github/workflows/label-sync.yml`](.github/workflows/label-sync.yml) | Reusable workflow that applies the label vocabulary to a repository |
| [`.github/workflows/lint-pr.yml`](.github/workflows/lint-pr.yml) | Reusable workflow that checks a pull request against the conventions |
| [`actions/merge`](actions/merge) | The composite action behind `/merge`, usable as a step on its own |
| [`actions/lint-pr`](actions/lint-pr) | The composite action behind the pull request lint, which reuses the merge action's title rule |
| [`workflow-templates`](workflow-templates) | Starter workflows offering the caller stubs from the Actions UI |
| [`rulesets`](rulesets) | Ruleset definitions to apply to repositories in this organisation |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml) | Lints this repository's own workflows, actions, shell, rulesets, templates and planning files, and runs the actions' tests |

## Planning

How work is described and scheduled — issue types and their fields, the
hierarchy, milestones, and what the board shows — is in
[docs/planning.md](docs/planning.md), with the label vocabulary in
[docs/labels.md](docs/labels.md) and the automation in
[docs/project-automation.md](docs/project-automation.md).

## Contributing

Consuming repositories track `@main`, so anything merged here reaches the whole
organisation immediately. On each pull request CI lints every workflow and the
shell inside it, lints and unit-tests the actions' scripts, and validates the
action, starter workflow and ruleset definitions; run the same checks locally
with `actionlint`, `shellcheck`, `shfmt`, `yq` and `jq`, and the tests with
`./actions/merge/lib.test.sh`. The linter versions CI uses are pinned by
checksum at the top of `ci.yml` and are bumped by hand.

## Mirroring

Any repository here can mirror itself to another GitHub repository — typically
an Epitech delivery repository — by setting a `MIRROR_URL` variable and adding a
short caller workflow. Repositories without that variable skip the job entirely.

See [docs/mirroring.md](docs/mirroring.md) for setup and troubleshooting.

## Merging

Pull requests merge through a `/merge` comment rather than the merge button: the
default branch is locked, and the organisation's automation app is the only actor
that may write to it. The commit message is composed from the pull request — its
title, its Summary section, its linked issue and its co-authors — so it no longer
depends on whoever presses the button, and because an app makes the merge rather
than `GITHUB_TOKEN`, a release workflow can react to the push.

See [docs/merging.md](docs/merging.md) for setup, what it refuses and why, and
the manual fallback.

## Branch protection

[`rulesets`](rulesets) holds the recommended rulesets: a reviewed pull request
with green CI on the default branch, a lock that reserves merging for the
organisation's automation app, and protection for release tags. The two branch
rulesets are deliberately separate, because their bypass lists are what keep the
app from being a way around review.

See [docs/rulesets.md](docs/rulesets.md) for what each one contains and the order
to apply them in, and [docs/automation-bot.md](docs/automation-bot.md) for the
app itself and the permissions it needs.
