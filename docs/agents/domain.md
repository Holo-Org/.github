# Domain docs

How to consume this repository's domain documentation before exploring the code.

## Read these first

- **`CONTEXT.md`** at the root, if it exists.
- **`docs/adr/`** — the ADRs touching the area you are about to work in.

If they do not exist, **proceed silently.** Do not flag their absence and do not
propose creating them up front; they are created lazily, when a term or a
decision actually gets settled.

This repository is single-context: one `CONTEXT.md` and one `docs/adr/` at the
root. There is no `CONTEXT-MAP.md`.

## Use the glossary's vocabulary

When your output names a domain concept — an issue title, a refactor proposal, a
hypothesis, a test name — use the term as `CONTEXT.md` defines it, rather than a
synonym the glossary avoids.

A concept missing from the glossary is a signal: either you are inventing
language the project does not use, or there is a real gap worth noting.

Note that **component** and **area** are distinct terms here, and easy to
conflate. See [../labels.md](../labels.md).

## Flag ADR conflicts

If your output contradicts an existing ADR, say so rather than quietly
overriding it:

> *Contradicts ADR-0007 (event-sourced orders), but worth reopening because…*
