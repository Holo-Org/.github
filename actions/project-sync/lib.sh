#!/usr/bin/env bash
# Pure decisions for the project board. Nothing here touches the network, so
# lib.test.sh can exercise all of it.
#
# Every Status on the board is computed, never set by hand, so these functions
# are the whole rule. The names they return must match the project's own Status
# options exactly; the caller resolves them to option ids and fails loudly when
# one is missing.
# shellcheck disable=SC2016

# values <prefix> reads labels on stdin and prints the part after the prefix,
# one per line. The prefix has to begin the line, compared literally.
values() {
	awk -v p="$1" 'index($0, p) == 1 { print substr($0, length(p) + 1) }'
}

# status_for_issue <state> <state-reason> <assignees> <open-prs> <labels>
# prints the Status the board should show.
#
# Closure wins over everything, then work actually being under way, then whose
# move it is. An issue with no acting label sits in Backlog, which is also what
# acting_fix will give it a label for.
status_for_issue() {
	local state="$1" reason="$2" assignees="$3" prs="$4" labels="$5" acting

	case "$state" in
	CLOSED | closed)
		case "$reason" in
		NOT_PLANNED | not_planned) printf 'Cancelled\n' ;;
		*) printf 'Fixed\n' ;;
		esac
		return 0
		;;
	esac

	if [ "${assignees:-0}" -gt 0 ] || [ "${prs:-0}" -gt 0 ]; then
		printf 'In Progress\n'
		return 0
	fi

	acting=$(values 'acting: ' <<<"$labels" | head -1)
	case "$acting" in
	agent | human) printf 'Ready\n' ;;
	*) printf 'Backlog\n' ;;
	esac
}

# status_for_pr <state> <merged> <draft> <review-decision> prints the Status the
# board should show for a pull request.
status_for_pr() {
	local state="$1" merged="$2" draft="$3" review="$4"

	if [ "$merged" = true ]; then
		printf 'Merged\n'
		return 0
	fi
	case "$state" in
	CLOSED | closed)
		printf 'Cancelled\n'
		return 0
		;;
	esac
	if [ "$draft" = true ]; then
		printf 'Created\n'
		return 0
	fi
	case "$review" in
	CHANGES_REQUESTED) printf 'Changes Requested\n' ;;
	APPROVED) printf 'Waiting Merge\n' ;;
	*) printf 'In Review\n' ;;
	esac
}

# hierarchy_from_title <title> <prefix-table> prints the Hierarchy level the
# title's prefix implies, or nothing when it carries none. The table is lines of
# "<level><tab><prefix>", which is how conventions.yml is read.
#
# A markdown issue template cannot set an issue field, so the prefix it puts in
# the title is the only thing that carries the level.
hierarchy_from_title() {
	local title="$1" table="$2" level prefix
	while IFS=$'\t' read -r level prefix; do
		[ -n "$prefix" ] || continue
		case "$title" in
		"$prefix"*)
			printf '%s\n' "$level"
			return 0
			;;
		esac
	done <<<"$table"
}

# acting_fix <state> <labels> prints what to do about the acting labels: lines
# of "add <label>", "remove <label>", or "ambiguous <a>, <b>" when an issue
# carries more than one, which is never guessed at.
acting_fix() {
	local state="$1" labels="$2" found count
	found=$(values 'acting: ' <<<"$labels")
	count=$(grep -c . <<<"$found" || true)

	case "$state" in
	CLOSED | closed)
		while IFS= read -r a; do
			[ -n "$a" ] || continue
			printf 'remove acting: %s\n' "$a"
		done <<<"$found"
		return 0
		;;
	esac

	case "$count" in
	0) printf 'add acting: maintainer\n' ;;
	1) ;;
	*) printf 'ambiguous %s\n' "$(paste -sd, - <<<"$found" | sed 's/,/, /g')" ;;
	esac
}

# dates_to_set <status> <have-start> <have-end> prints which date to stamp:
# "start" the first time work begins, "end" the first time it ends.
#
# Closing an issue that never reached In Progress leaves the start empty rather
# than inventing one, so the Timeline shows nothing for it instead of a bar that
# claims work began on the day it closed.
dates_to_set() {
	local status="$1" have_start="$2" have_end="$3"
	case "$status" in
	"In Progress")
		[ "$have_start" != 0 ] || printf 'start\n'
		;;
	Fixed | Cancelled)
		[ "$have_end" != 0 ] || printf 'end\n'
		;;
	esac
}

# belongs_on_board <kind> <issue-type> returns 0 when the item should be on the
# board. Pull requests always are; among issues, only Agile, because a board of
# requests is a board nobody can plan from.
belongs_on_board() {
	case "$1" in
	pr | pull_request) return 0 ;;
	esac
	[ "$2" = Agile ]
}
