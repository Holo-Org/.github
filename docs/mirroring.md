# Mirroring a repository

Pushes every branch, tag and Git LFS object of a repository in this organisation
to a GitHub repository over SSH, keeping the destination an exact copy.

A repository mirrors only once a `MIRROR_URL` variable is set on it. Everywhere
else the workflow is skipped, so the stub is safe to add anywhere.

## One-time organisation setup

### 0. Make this repository callable

If `Holo-Org/.github` is private, other repositories cannot call its reusable
workflow until access is granted: **Settings → Actions → General → Access →
Accessible from repositories in the 'Holo-Org' organisation**. That grant lets
outside collaborators on those repositories reach this one indirectly, so keep
it in mind before adding anything sensitive here.

Starter workflows offered from a private `.github` repository are not something
the current GitHub documentation confirms either way. If **Mirror repository**
does not appear under **Actions → New workflow**, copy the stub below by hand;
the reusable workflow itself is unaffected.

### 1. Choose the account the key belongs to

The destination repository is pushed to as a **user**, not as a deploy key: the
key must belong to a GitHub account that has write access to the destination and
whose key is SSO-authorised for the destination's organisation.

Prefer a dedicated machine-user account over a personal one. The key is shared by
every mirroring repository in this organisation, and it grants whatever its owner
can push to — not just the destination.

A given public key can be registered on **one** GitHub account only, so a key
already used as a deploy key elsewhere cannot be reused here.

### 2. Create the key

```sh
ssh-keygen -t ed25519 -C "holo-org mirror" -N "" -f mirror_key
```

The key must have no passphrase: the runner cannot answer a prompt.

### 3. Register and authorise it

1. Add `mirror_key.pub` to that account under **Settings → SSH and GPG keys**.
2. On the same page, use **Configure SSO** on the new key and authorise it for
   the destination organisation. Without this step every push fails even though
   the key is valid.

### 4. Store the private key

Add the contents of `mirror_key` (the file without `.pub`, including the
`-----BEGIN`/`-----END` lines) as an **organisation secret** named
`MIRROR_SSH_KEY`, with access granted to the repositories that will mirror.

Then delete the local copies.

## Per-repository setup

1. Add a repository **variable** named `MIRROR_URL` holding the destination SSH
   URL, for example `git@github.com:EpitechPromo2027/project-name.git`.
2. Add `.github/workflows/mirror.yml`:

   ```yaml
   name: Mirror

   on:
     push:
       branches: ['**']
       tags: ['**']
     delete:
     schedule:
       - cron: '17 4 * * *'
     workflow_dispatch:

   permissions:
     contents: read

   jobs:
     mirror:
       uses: Holo-Org/.github/.github/workflows/mirror.yml@main
       with:
         destination: ${{ vars.MIRROR_URL }}
       secrets: inherit
   ```

   This file is also offered as a starter workflow: **Actions → New workflow →
   Mirror repository**.

The `delete` trigger only fires for workflow files present on the default branch,
and scheduled runs are disabled automatically after 60 days without activity in
the repository.

## What gets mirrored

Every branch and every tag, force-pushed, with refs that no longer exist here
deleted on the destination, plus every Git LFS object they reference. Nothing
else is touched: pruning is limited to branches and tags, so unrelated
namespaces on the destination survive.

Not mirrored: pull requests, issues, releases, wikis and settings.

## LFS bandwidth

Every LFS download from this organisation counts against its monthly LFS
bandwidth quota, Actions downloads included. To keep that to new objects only,
the job keeps the LFS objects it has already downloaded in the repository's
Actions cache and restores them on the next run. A cache saved by a run on
another branch is not visible to runs on the default branch, so objects first
pushed on a feature branch are downloaded once more after merging.

On the other side, the objects pushed count against the destination owner's LFS
storage quota.

## Troubleshooting

**The job is skipped.** `MIRROR_URL` is unset or empty on that repository. Note
that a variable and a secret of the same name are different things; this one is a
variable.

**`MIRROR_SSH_KEY is not available to this repository`** — the organisation
secret exists but this repository is not in its access list.

**`ERROR: Permission to … denied to …`** — the key's account has no write access
to the destination, or the key is not SSO-authorised for the destination's
organisation.

**`Permission denied (publickey)`** — the secret is not a valid private key, or
it has a passphrase.

**`protected branch hook declined` / `refusing to delete`** — branch protection
or a ruleset on the destination is blocking the force-push or the pruning.
Exempt the key's account there.
