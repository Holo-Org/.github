# Holo-Org/.github

Shared GitHub Actions workflows, actions and defaults for the Holo-Org
organisation.

## Contents

| Path | What it is |
|---|---|
| [`.github/workflows/mirror.yml`](.github/workflows/mirror.yml) | Reusable workflow that mirrors a repository to another Git remote over SSH |
| [`actions/mirror`](actions/mirror) | The composite action behind it, usable as a step on its own |
| [`workflow-templates/mirror.yml`](workflow-templates/mirror.yml) | Starter workflow offering the caller stub from the Actions UI |

## Mirroring

Any repository here can mirror itself to a second remote — typically an Epitech
delivery repository — by setting a `MIRROR_URL` variable and adding a short
caller workflow. Repositories without that variable skip the job entirely.

See [docs/mirroring.md](docs/mirroring.md) for setup, options and
troubleshooting.
