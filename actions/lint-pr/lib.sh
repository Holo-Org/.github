#!/usr/bin/env bash
# Pure checks on a pull request's shape. Nothing here touches the network, so
# lib.test.sh can exercise all of it.
#
# The title is checked by the merge command's own check_title, so a title this
# lint accepts is one /merge will accept. Sourcing it is what keeps the two from
# drifting apart, and a change to either one breaks both test suites.
#
# Failure messages are Markdown, posted as a pull request comment, so backticks
# inside single quotes are code spans.
# shellcheck disable=SC1091,SC2016
. "$(dirname "${BASH_SOURCE[0]}")/../merge/lib.sh"

# has_line <needle> reads a newline-delimited list on stdin and returns 0 when
# one line equals the needle exactly.
has_line() {
	grep -qxF -- "$1"
}

# values <prefix> reads labels on stdin and prints the part after the prefix,
# one per line. The prefix has to begin the line, and the comparison is literal:
# a label that merely mentions the prefix is not one of its values.
values() {
	awk -v p="$1" 'index($0, p) == 1 { print substr($0, length(p) + 1) }'
}

# commas reads a newline-delimited list on stdin and prints it on one line.
commas() {
	paste -sd, - | sed 's/,/, /g'
}

# check_branch <branch> <kinds> <components> prints why the branch name is
# unacceptable and returns 1, or prints nothing and returns 0. The kinds and
# components are newline-delimited.
check_branch() {
	local branch="$1" kinds="$2" components="$3" kind rest component slug

	case "$branch" in
	*/*/*) ;;
	*)
		printf 'The branch is `%s`, and a branch must read `<kind>/<component>/<slug>`.\n' "$branch"
		return 1
		;;
	esac

	kind=${branch%%/*}
	rest=${branch#*/}
	component=${rest%%/*}
	slug=${rest#*/}

	if ! has_line "$kind" <<<"$kinds"; then
		printf 'The branch kind is `%s`, and it must be one of: %s.\n' \
			"$kind" "$(commas <<<"$kinds")"
		return 1
	fi
	if ! has_line "$component" <<<"$components"; then
		printf 'The branch component is `%s`, and this repository has: %s.\n' \
			"$component" "$(commas <<<"$components")"
		return 1
	fi
	if [ -z "$slug" ]; then
		printf 'The branch has no slug after `%s/%s/`.\n' "$kind" "$component"
		return 1
	fi
}

# component_exception <body> prints the reason given for carrying two
# components, or nothing when none is given.
component_exception() {
	sed -n 's/^[[:space:]]*Component exception:[[:space:]]*//p' <<<"$1" |
		head -1 | sed 's/[[:space:]]*$//'
}

# check_components <labels> <body> prints why the component labels are
# unacceptable and returns 1, or prints the accepted component and returns 0.
# A second component is allowed only when the body says why they cannot land
# apart, because the normal answer is a stack rather than an exception.
check_components() {
	local labels="$1" body="$2" found count reason
	found=$(values 'component: ' <<<"$labels")
	count=$(grep -c . <<<"$found" || true)

	case "$count" in
	0)
		printf 'This pull request has no `component:` label, and it needs exactly one.\n'
		return 1
		;;
	1)
		printf '%s\n' "$found"
		return 0
		;;
	2)
		reason=$(component_exception "$body")
		if [ -z "$reason" ]; then
			printf 'This pull request has two components (%s), and one concern takes one.\n' \
				"$(commas <<<"$found")"
			printf 'Build it as a stack, one layer per component, closing the issue from the top.\n'
			printf 'If they really cannot land apart, say why on a line of its own:\n'
			printf '\n    Component exception: <reason>\n'
			return 1
		fi
		printf '%s\n' "$found"
		return 0
		;;
	*)
		printf 'This pull request has %d components, and at most two are ever allowed.\n' "$count"
		return 1
		;;
	esac
}

# check_release <labels> prints why the release labels are unacceptable and
# returns 1, or prints nothing and returns 0.
check_release() {
	local found count
	found=$(values 'release: ' <<<"$1")
	count=$(grep -c . <<<"$found" || true)
	if [ "$count" -gt 1 ]; then
		printf 'This pull request has %d `release:` labels, and a merge causes one bump.\n' "$count"
		return 1
	fi
}

# check_branch_component <branch> <component-label-value> prints why they
# disagree and returns 1, or prints nothing and returns 0.
check_branch_component() {
	local branch="$1" label="$2" rest from_branch
	rest=${branch#*/}
	from_branch=${rest%%/*}
	if [ "$(tr '[:upper:]' '[:lower:]' <<<"$from_branch")" != \
		"$(tr '[:upper:]' '[:lower:]' <<<"$label")" ]; then
		printf 'The branch says the component is `%s` and the label says `%s`.\n' \
			"$from_branch" "$label"
		return 1
	fi
}

# check_issue_component <component> <issue-components> prints why the pull
# request's component is not one the issue claims and returns 1, or prints
# nothing and returns 0. An issue with no components says nothing either way.
check_issue_component() {
	local component="$1" issue="$2"
	[ -n "$issue" ] || return 0
	if ! has_line "$component" <<<"$issue"; then
		printf 'The component is `%s`, and the linked issue covers: %s.\n' \
			"$component" "$(commas <<<"$issue")"
		printf 'Either the issue is missing a component or this change belongs elsewhere.\n'
		return 1
	fi
}

# closing_ref <body> prints "closes" or "part-of" and the issue number, or
# nothing when the body carries no reference.
closing_ref() {
	local found
	found=$(grep -oiE '(closes|part of)[[:space:]]+#[0-9]+' <<<"$1" | head -1 || true)
	[ -n "$found" ] || return 0
	case "$found" in
	[Cc]loses*) printf 'closes %s\n' "${found##*#}" ;;
	*) printf 'part-of %s\n' "${found##*#}" ;;
	esac
}
