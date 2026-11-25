#!/usr/bin/env bash
# Unit tests for lib.sh. Run from anywhere: ./actions/project-sync/lib.test.sh
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

ready=$(printf 'acting: agent\ncomponent: Engine')
human=$(printf 'acting: human')
triage=$(printf 'acting: maintainer')
reporter=$(printf 'acting: reporter')
bare=$(printf 'component: Engine')

# --- an issue's status ---------------------------------------------------

check 'issue: closed as completed is Fixed' Fixed \
	"$(status_for_issue CLOSED COMPLETED 0 0 "$ready")"
check 'issue: closed as not planned is Cancelled' Cancelled \
	"$(status_for_issue CLOSED NOT_PLANNED 0 0 "$ready")"

# Closure beats everything, including an assignee left behind.
check 'issue: closed wins over an assignee' Fixed \
	"$(status_for_issue CLOSED COMPLETED 1 1 "$ready")"

check 'issue: an assignee means In Progress' 'In Progress' \
	"$(status_for_issue OPEN '' 1 0 "$ready")"
check 'issue: an open linked pull request means In Progress' 'In Progress' \
	"$(status_for_issue OPEN '' 0 1 "$triage")"

check 'issue: ready for an agent is Ready' Ready \
	"$(status_for_issue OPEN '' 0 0 "$ready")"
check 'issue: ready for a human is Ready' Ready \
	"$(status_for_issue OPEN '' 0 0 "$human")"
check 'issue: waiting on triage is Backlog' Backlog \
	"$(status_for_issue OPEN '' 0 0 "$triage")"
check 'issue: waiting on the reporter is Backlog' Backlog \
	"$(status_for_issue OPEN '' 0 0 "$reporter")"
check 'issue: no acting label is Backlog' Backlog \
	"$(status_for_issue OPEN '' 0 0 "$bare")"

# A label that merely mentions the prefix is not an acting label.
check 'issue: a label mentioning the prefix does not count' Backlog \
	"$(status_for_issue OPEN '' 0 0 'note: see acting: agent for context')"

# --- a pull request's status --------------------------------------------

check 'pr: merged is Merged' Merged "$(status_for_pr CLOSED true false APPROVED)"
check 'pr: closed unmerged is Cancelled' Cancelled "$(status_for_pr CLOSED false false '')"
check 'pr: a draft is Created' Created "$(status_for_pr OPEN false true '')"
check 'pr: changes requested' 'Changes Requested' \
	"$(status_for_pr OPEN false false CHANGES_REQUESTED)"
check 'pr: approved is Waiting Merge' 'Waiting Merge' \
	"$(status_for_pr OPEN false false APPROVED)"
check 'pr: open and awaiting review' 'In Review' \
	"$(status_for_pr OPEN false false REVIEW_REQUIRED)"
check 'pr: merged wins over draft' Merged "$(status_for_pr CLOSED true true '')"

# --- the hierarchy level from the title ---------------------------------

table=$(printf 'Initiative\t[Initiative]: \nEpic\t[Epic]: \nFeature\t[Feature]: \nStory\t[Story]: \nTask\t[Task]: ')

check 'hierarchy: an epic' Epic "$(hierarchy_from_title '[Epic]: group the work' "$table")"
check 'hierarchy: a task' Task "$(hierarchy_from_title '[Task]: do the thing' "$table")"
check 'hierarchy: no prefix yields nothing' '' \
	"$(hierarchy_from_title 'just a title' "$table")"
check 'hierarchy: the prefix must start the title' '' \
	"$(hierarchy_from_title 'see [Epic]: elsewhere' "$table")"

# Initiative and Epic both begin with "[" and must not be confused.
check 'hierarchy: an initiative is not an epic' Initiative \
	"$(hierarchy_from_title '[Initiative]: the big one' "$table")"

# --- the acting labels --------------------------------------------------

check 'acting: an open issue with none gets triage' 'add acting: maintainer' \
	"$(acting_fix OPEN "$bare")"
check 'acting: an open issue with one is left alone' '' \
	"$(acting_fix OPEN "$ready")"
check 'acting: two is reported, never guessed at' 'ambiguous agent, human' \
	"$(acting_fix OPEN "$(printf 'acting: agent\nacting: human')")"
check 'acting: closing strips the label' 'remove acting: agent' \
	"$(acting_fix CLOSED "$ready")"
check 'acting: closing with none does nothing' '' \
	"$(acting_fix CLOSED "$bare")"

# --- the dates ----------------------------------------------------------

check 'dates: reaching In Progress stamps the start' start \
	"$(dates_to_set 'In Progress' 0 0)"
check 'dates: already started stamps nothing' '' \
	"$(dates_to_set 'In Progress' 1 0)"
check 'dates: closing stamps the end' end "$(dates_to_set Fixed 1 0)"
check 'dates: cancelling stamps the end too' end "$(dates_to_set Cancelled 1 0)"
check 'dates: an end already there is left alone' '' "$(dates_to_set Fixed 1 1)"

# Closing something that never started leaves the start empty rather than
# inventing one on the closing day.
check 'dates: closing does not backfill a missing start' end \
	"$(dates_to_set Fixed 0 0)"
check 'dates: Backlog and Ready stamp nothing' '' "$(dates_to_set Ready 0 0)"

# --- what belongs on the board ------------------------------------------

belongs_on_board pr '' && r=yes || r=no
check 'board: a pull request always belongs' yes "$r"
belongs_on_board issue Agile && r=yes || r=no
check 'board: an Agile issue belongs' yes "$r"
belongs_on_board issue Bug && r=yes || r=no
check 'board: a Bug does not' no "$r"
belongs_on_board issue '' && r=yes || r=no
check 'board: an untyped issue does not' no "$r"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
