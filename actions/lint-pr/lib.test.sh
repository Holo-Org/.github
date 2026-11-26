#!/usr/bin/env bash
# Unit tests for lib.sh. Run from anywhere: ./actions/lint-pr/lib.test.sh
#
# The expected failure messages are Markdown, so backticks inside single quotes
# are code spans. lib.sh is sourced by a path only valid at run time.
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

kinds=$(printf 'feat\nfix\ndocs\nci')
components=$(printf 'engine\nserver\nsetup\nuncategorized')

# --- the branch ----------------------------------------------------------

check_branch 'feat/engine/add-the-thing' "$kinds" "$components" >/dev/null
check 'branch: a good name returns zero' 0 $?

check 'branch: a good name says nothing' '' \
	"$(check_branch 'feat/engine/add-the-thing' "$kinds" "$components")"

# A slug may carry slashes of its own; only the first two segments are read.
check 'branch: a slug may contain slashes' '' \
	"$(check_branch 'fix/server/handle/the/edge/case' "$kinds" "$components")"

check 'branch: two segments is refused' \
	'The branch is `feat/engine`, and a branch must read `<kind>/<component>/<slug>`.' \
	"$(check_branch 'feat/engine' "$kinds" "$components")"

check 'branch: no segments is refused' \
	'The branch is `mybranch`, and a branch must read `<kind>/<component>/<slug>`.' \
	"$(check_branch 'mybranch' "$kinds" "$components")"

check 'branch: an unknown kind is refused, and the kinds are listed' \
	'The branch kind is `feature`, and it must be one of: feat, fix, docs, ci.' \
	"$(check_branch 'feature/engine/thing' "$kinds" "$components")"

check 'branch: an unknown component is refused, and the components are listed' \
	'The branch component is `client`, and this repository has: engine, server, setup, uncategorized.' \
	"$(check_branch 'feat/client/thing' "$kinds" "$components")"

check 'branch: an empty slug is refused' \
	'The branch has no slug after `feat/engine/`.' \
	"$(check_branch 'feat/engine/' "$kinds" "$components")"

# A kind that is only a prefix of a legal one must not pass on the strength of it.
check 'branch: a kind matching only as a prefix is refused' \
	'The branch kind is `fea`, and it must be one of: feat, fix, docs, ci.' \
	"$(check_branch 'fea/engine/thing' "$kinds" "$components")"

# --- the component exception ---------------------------------------------

check 'exception: read from its own line' 'the migration and its caller land together' \
	"$(component_exception 'Some text.

Component exception: the migration and its caller land together

More text.')"

check 'exception: trailing whitespace is dropped' 'a reason' \
	"$(component_exception 'Component exception: a reason   ')"

check 'exception: absent yields nothing' '' \
	"$(component_exception 'No exception here.')"

# --- the component labels ------------------------------------------------

one=$(printf 'component: Engine\nrelease: patch')
two=$(printf 'component: Engine\ncomponent: Server')
three=$(printf 'component: Engine\ncomponent: Server\ncomponent: Setup')
none=$(printf 'release: patch\nacting: human')

check 'components: exactly one is accepted and printed' 'Engine' \
	"$(check_components "$one" 'A body.')"

check_components "$one" 'A body.' >/dev/null
check 'components: exactly one returns zero' 0 $?

check 'components: none is refused' \
	'This pull request has no `component:` label, and it needs exactly one.' \
	"$(check_components "$none" 'A body.')"

# The stack is the normal answer, so it is named before the exception is.
check 'components: two without a reason is refused, and the stack comes first' \
	'This pull request has two components (Engine, Server), and one concern takes one.
Build it as a stack, one layer per component, closing the issue from the top.
If they really cannot land apart, say why on a line of its own:

    Component exception: <reason>' \
	"$(check_components "$two" 'A body with no exception.')"

check 'components: two with a reason is accepted' \
	'Engine
Server' \
	"$(check_components "$two" 'Component exception: they cannot land apart.')"

check 'components: three is refused even with a reason' \
	'This pull request has 3 components, and at most two are ever allowed.' \
	"$(check_components "$three" 'Component exception: they cannot land apart.')"

# A label that merely contains the prefix is not a component.
check 'components: the prefix must start the label' \
	'This pull request has no `component:` label, and it needs exactly one.' \
	"$(check_components 'note: see component: Engine for context' 'A body.')"

# --- the release labels --------------------------------------------------

check 'release: none says nothing' '' "$(check_release "$none")"
check 'release: one says nothing' '' "$(check_release "$one")"
check 'release: two is refused' \
	'This pull request has 2 `release:` labels, and a merge causes one bump.' \
	"$(check_release "$(printf 'release: minor\nrelease: patch')")"

# --- the branch against the label ----------------------------------------

check 'agreement: the label matches the branch, ignoring case' '' \
	"$(check_branch_component 'feat/engine/thing' 'Engine')"

check 'agreement: a mismatch is refused' \
	'The branch says the component is `engine` and the label says `Server`.' \
	"$(check_branch_component 'feat/engine/thing' 'Server')"

# --- the component against the linked issue ------------------------------

issue=$(printf 'Engine\nServer')

check 'issue: a component the issue covers says nothing' '' \
	"$(check_issue_component 'Engine' "$issue")"

check 'issue: an issue with no components says nothing either way' '' \
	"$(check_issue_component 'Engine' '')"

check 'issue: a component the issue does not cover is refused' \
	'The component is `Setup`, and the linked issue covers: Engine, Server.
Either the issue is missing a component or this change belongs elsewhere.' \
	"$(check_issue_component 'Setup' "$issue")"

# --- the closing reference -----------------------------------------------

check 'ref: Closes' 'closes 37' "$(closing_ref 'Closes #37')"
check 'ref: Part of' 'part-of 15' "$(closing_ref 'Part of #15')"
check 'ref: case does not matter' 'closes 9' "$(closing_ref 'closes #9')"
check 'ref: none yields nothing' '' "$(closing_ref 'no reference here')"
check 'ref: an empty Closes yields nothing' '' "$(closing_ref 'Closes #')"

# --- one-line lists ------------------------------------------------------

check 'commas: a list becomes one line' 'a, b, c' "$(commas <<<"$(printf 'a\nb\nc')")"
check 'commas: one item has no comma' 'a' "$(commas <<<'a')"

# --- the title comes from the merge command ------------------------------

# Sourcing merge/lib.sh is what keeps the lint and the merge in step, so the
# rule is asserted here too: a change to one must break the other's tests.
check 'title: the merge command rule is in force' \
	'engine: do the thing (#53)' \
	"$(check_title 'engine: do the thing' 53)"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
