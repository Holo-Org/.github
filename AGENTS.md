# Holo-Org/.github

Shared GitHub Actions workflows, templates and planning conventions for the
`Holo-Org` organisation. Consuming repositories track `@main`, so anything
merged here reaches the whole organisation immediately.

## Before you change anything

- [`CONTRIBUTING.md`](CONTRIBUTING.md) — commit, branch and pull request
  conventions. They are linted; read them first.
- [`docs/planning.md`](docs/planning.md) — issue types, fields and how work is
  scheduled.
- [`docs/labels.md`](docs/labels.md) — the four label namespaces.

Run the same checks CI runs before opening a pull request:

```bash
for t in actions/*/*.test.sh; do bash "$t" || break; done
```

```bash
nix shell nixpkgs#shellcheck nixpkgs#shfmt -c sh -c 'shellcheck -s bash actions/*/*.sh && shfmt -d actions/*/*.sh'
```

This repository has no `.git` directory: it is a non-colocated Jujutsu
repository. Use `jj`, and give `gh` the repository explicitly with `--repo
Holo-Org/.github` or `GH_REPO`, since it cannot infer one.

## Agent skills

### Issue tracker

Issues live in GitHub, typed and fielded at the organisation level. See
[`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md).

### Triage labels

The five canonical triage roles map onto the `acting:` namespace. See
[`docs/agents/triage-labels.md`](docs/agents/triage-labels.md).

### Domain docs

Single-context: one `CONTEXT.md` and `docs/adr/` at the root, created lazily.
See [`docs/agents/domain.md`](docs/agents/domain.md).
