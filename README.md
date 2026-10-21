# Holo-Org/.github

Shared GitHub Actions workflows, actions and defaults for the Holo-Org
organisation.

## Contents

| Path | What it is |
|---|---|
| [`.github/workflows/mirror.yml`](.github/workflows/mirror.yml) | Reusable workflow that mirrors a repository to another Git remote over SSH |
| [`actions/mirror`](actions/mirror) | The composite action behind it, usable as a step on its own |
| [`workflow-templates/mirror.yml`](workflow-templates/mirror.yml) | Starter workflow offering the caller stub from the Actions UI |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml) | Lints this repository's own workflows, actions and shell |

## Contributing

Consuming repositories track `@main`, so anything merged here reaches the whole
organisation immediately. CI lints every workflow, the action metadata and
`mirror.sh` on each pull request; run the same checks locally with
`actionlint`, `shellcheck`, `shfmt` and `yq`. The linter versions CI uses are
pinned by checksum at the top of `ci.yml` and are bumped by hand.

## Mirroring

Any repository here can mirror itself to a second remote — typically an Epitech
delivery repository — by setting a `MIRROR_URL` variable and adding a short
caller workflow. Repositories without that variable skip the job entirely.

See [docs/mirroring.md](docs/mirroring.md) for setup, options and
troubleshooting.
