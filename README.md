# Holo-Org/.github

Shared GitHub Actions workflows and defaults for the Holo-Org organisation.

## Contents

| Path | What it is |
|---|---|
| [`.github/workflows/mirror.yml`](.github/workflows/mirror.yml) | Reusable workflow that mirrors a repository to another GitHub repository over SSH |
| [`workflow-templates/mirror.yml`](workflow-templates/mirror.yml) | Starter workflow offering the caller stub from the Actions UI |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml) | Lints this repository's own workflows |

## Contributing

Consuming repositories track `@main`, so anything merged here reaches the whole
organisation immediately. CI lints every workflow, including the shell inside
them, on each pull request; run the same check locally with `actionlint` and
`shellcheck`. The linter versions CI uses are pinned by checksum at the top of
`ci.yml` and are bumped by hand.

## Mirroring

Any repository here can mirror itself to another GitHub repository — typically
an Epitech delivery repository — by setting a `MIRROR_URL` variable and adding a
short caller workflow. Repositories without that variable skip the job entirely.

See [docs/mirroring.md](docs/mirroring.md) for setup and troubleshooting.
