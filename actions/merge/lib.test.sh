#!/usr/bin/env bash
# Unit tests for lib.sh. Run from anywhere: ./actions/merge/lib.test.sh
#
# The expected refusal messages are Markdown, so backticks inside single
# quotes are code spans. lib.sh is sourced by a path only valid at run time.
# shellcheck disable=SC1091,SC2016
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
. ./lib.sh

passed=0
failed=0

check() {
	local what="$1" want="$2" got="$3"
	if [ "$want" = "$got" ]; then
		passed=$((passed + 1))
	else
		failed=$((failed + 1))
		printf '✗ %s\n  want: %s\n  got:  %s\n' "$what" "$(printf '%q' "$want")" "$(printf '%q' "$got")"
	fi
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat >"$work/template.md" <<'MD'
<!-- Keep this pull request small and focused. -->

## Summary

<!-- One or two sentences. What does this do and why?
     This becomes the body of the squash commit. -->

The widget no longer reads its settings from the environment: each one takes
its values from the configuration file instead.

## Related issue

<!-- Use "Closes #123" to close it on merge. -->

Closes #37

## Reviewer focus

Nothing tricky.
MD

cat >"$work/review-bot.md" <<'MD'
## Summary

The summary a person wrote.

## Related issue

Part of #15

<!-- This is an auto-generated comment: summarize by coderabbit.ai -->

## Summary by CodeRabbit

- **New Features**
  - Something a review bot appended.
MD

cat >"$work/empty.md" <<'MD'
## Summary

<!-- One or two sentences. What does this do and why? -->

## Related issue

Closes #
MD

# --- the Summary section -------------------------------------------------

check 'summary: taken from the template' \
	'The widget no longer reads its settings from the environment: each one takes
its values from the configuration file instead.' \
	"$(strip_comments <"$work/template.md" | section '## Summary')"

# A review bot that appends its own "## Summary by ..." heading must not be
# mistaken for the section, which is why the heading is matched exactly.
check 'summary: a bot heading beginning "## Summary" is not it' \
	'The summary a person wrote.' \
	"$(strip_comments <"$work/review-bot.md" | section '## Summary')"

check 'summary: empty when only the guidance comment is there' '' \
	"$(strip_comments <"$work/empty.md" | section '## Summary')"

check 'summary: a heading that is absent yields nothing' '' \
	"$(strip_comments <"$work/template.md" | section '## Nonexistent')"

# --- the Related issue section -------------------------------------------

check 'issue: Closes with a number' 'Closes #37' \
	"$(issue_ref "$(strip_comments <"$work/template.md" | section '## Related issue')")"

check 'issue: Part of with a number' 'Part of #15' \
	"$(issue_ref "$(strip_comments <"$work/review-bot.md" | section '## Related issue')")"

check 'issue: an empty Closes is refused, not ignored' \
	'Related issue has a `Closes #` with no issue number.' \
	"$(issue_ref "$(strip_comments <"$work/empty.md" | section '## Related issue')")"

check 'issue: no reference at all is refused' \
	'Related issue must say `Closes #123` or `Part of #123`.' \
	"$(issue_ref 'nothing here')"

issue_ref 'Closes #12' >/dev/null
check 'issue: a good reference returns zero' 0 $?
issue_ref 'nothing' >/dev/null
check 'issue: a bad reference returns one' 1 $?

# --- the title -----------------------------------------------------------

# The convention's limit is 72 columns on the commit title, so the pull
# request number is part of the measurement. A flat 64-column rule on the
# title alone would reject this one, whose commit title is only 71.
long='module: a subject that is exactly sixty-five characters in length'
check 'fixture: that title really is 65 characters' 65 "${#long}"

check 'title: 65 characters is fine with a two-digit number' \
	"$long (#53)" \
	"$(check_title "$long" 53)"

check 'title: the same title is one too long with a four-digit number' \
	'The commit title would be 73 columns and the limit is 72, so the title is 1 too long.' \
	"$(check_title "$long" 1234)"

check 'title: a double space is refused' 'The title contains a double space.' \
	"$(check_title 'module: double  space' 1)"
check 'title: a capitalised area is refused' \
	'The title must read `<area>: <subject>`, with a lowercase area and a lowercase verb.' \
	"$(check_title 'Module: lowercase subject' 1)"
check 'title: a capitalised subject is refused' \
	'The title must read `<area>: <subject>`, with a lowercase area and a lowercase verb.' \
	"$(check_title 'module: Capitalised' 1)"
check 'title: a missing space after the colon is refused' \
	'The title must read `<area>: <subject>`, with a lowercase area and a lowercase verb.' \
	"$(check_title 'module:nospace' 1)"
check 'title: a trailing full stop is refused' 'The title must end in a letter or a digit.' \
	"$(check_title 'module: trailing period.' 1)"
check 'title: a slash in the area is allowed' 'build/tool: set up the project (#7)' \
	"$(check_title 'build/tool: set up the project' 7)"

check_title 'module: do the thing' 1 >/dev/null
check 'title: a good title returns zero' 0 $?
check_title 'bad' 1 >/dev/null
check 'title: a bad title returns one' 1 $?

# --- co-authors ----------------------------------------------------------

# Every commit carries both an author and a committer, equal for an ordinary
# commit. Here the second commit has been rebased, so its committer is
# somebody who did not write it, and the third was made by an app.
cat >"$work/commits.json" <<'JSON'
[
	{ "commit": { "author": { "name": "First Author", "email": "first@example.com" },
	              "committer": { "name": "First Author", "email": "first@example.com" },
	              "message": "module: the first change" },
	  "author": { "login": "first-author", "type": "User" },
	  "committer": { "login": "first-author", "type": "User" } },
	{ "commit": { "author": { "name": "Second Author", "email": "second@example.com" },
	              "committer": { "name": "The Rebaser", "email": "rebaser@example.com" },
	              "message": "module: the second change\n\nCo-authored-by: A Pairing Colleague <pair@example.com>" },
	  "author": { "login": "second-author", "type": "User" },
	  "committer": { "login": "the-rebaser", "type": "User" } },
	{ "commit": { "author": { "name": "Helpful App[bot]", "email": "app@example.com" },
	              "committer": { "name": "Helpful App[bot]", "email": "app@example.com" },
	              "message": "module: a change an app made" },
	  "author": { "login": "helpful-app[bot]", "type": "Bot" },
	  "committer": { "login": "helpful-app[bot]", "type": "Bot" } },
	{ "commit": { "author": { "name": "Second Author", "email": "second@example.com" },
	              "committer": { "name": "Second Author", "email": "second@example.com" },
	              "message": "module: the same author again" },
	  "author": { "login": "second-author", "type": "User" },
	  "committer": { "login": "second-author", "type": "User" } }
]
JSON

# Rebasing somebody's work is not co-writing it, so The Rebaser must not
# appear. The trailer must: ^ and $ anchor to the whole string in jq's regex
# engine, so an anchored pattern silently matched nothing here.
check 'coauthors: authors and trailers, in the order first seen' \
	'Co-authored-by: Second Author <second@example.com>
Co-authored-by: A Pairing Colleague <pair@example.com>' \
	"$(coauthors "$work/commits.json" first-author)"

check 'coauthors: a rebase does not make the rebaser a co-author' 0 \
	"$(coauthors "$work/commits.json" first-author | grep -c 'The Rebaser' || true)"

check 'coauthors: an app is never a co-author' 0 \
	"$(coauthors "$work/commits.json" first-author | grep -c 'Helpful App' || true)"

check 'coauthors: the pull request author is never a co-author' \
	'Co-authored-by: First Author <first@example.com>
Co-authored-by: A Pairing Colleague <pair@example.com>' \
	"$(coauthors "$work/commits.json" second-author)"

echo '[]' >"$work/none.json"
check 'coauthors: no commits means no trailers' '' \
	"$(coauthors "$work/none.json" first-author)"

# --- the whole body ------------------------------------------------------

check 'body: summary, reference and trailers' \
	'A summary.

Closes #37
Co-authored-by: A B <a@b.example>' \
	"$(commit_body 'A summary.' 'Closes #37' 'Co-authored-by: A B <a@b.example>')"

check 'body: no trailers leaves no trailing blank line' \
	'A summary.

Part of #15' \
	"$(commit_body 'A summary.' 'Part of #15' '')"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
