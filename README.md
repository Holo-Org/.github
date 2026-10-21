# Holo-Org/.github

Shared GitHub Actions workflows and defaults for the Holo-Org organisation.

## Contents

| Path | What it is |
|---|---|
| [`.github/workflows/mirror.yml`](.github/workflows/mirror.yml) | Reusable workflow that mirrors a repository to another GitHub repository over SSH |
| [`.github/workflows/merge.yml`](.github/workflows/merge.yml) | Reusable workflow behind the `/merge` command |
| [`actions/merge`](actions/merge) | The composite action it calls, usable as a step on its own |
| [`workflow-templates`](workflow-templates) | Starter workflows offering the caller stubs from the Actions UI |
| [`rulesets`](rulesets) | Ruleset definitions to apply to repositories in this organisation |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml) | Lints this repository's own workflows, actions, shell and rulesets, and runs the actions' tests |

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
