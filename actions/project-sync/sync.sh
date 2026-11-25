#!/usr/bin/env bash
# Puts an issue or a pull request on the project board and computes everything
# the board shows about it. Every decision is in lib.sh; this file talks to
# GitHub.
#
# A repository with no board is normal, not a failure: the run exits zero.
# shellcheck disable=SC1091,SC2016
set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# GH_TOKEN (the planning app), GH_REPO, KIND, NUMBER and PROJECT_URL all come
# from action.yml. The conventions travel with this action.
conventions="$GITHUB_ACTION_PATH/../../planning/conventions.yml"
owner=${GH_REPO%%/*}
repo=${GH_REPO##*/}

gql() { gh api graphql --input -; }
q() { gh api graphql -f query="$1"; }

# --- the project ---------------------------------------------------------

if [ -n "${PROJECT_URL:-}" ]; then
	project=${PROJECT_URL%%\?*}
	project=${project##*/}
else
	# The convention the existing boards follow: the project is named after the
	# repository. Matched without regard to case, because "AREA" and "Area" are
	# the same board.
	project=$(q "{ organization(login:\"$owner\"){ projectsV2(first:50){ nodes{ number title closed } } } }" |
		repo="$repo" jq -r '.data.organization.projectsV2.nodes[]
      | select(.closed == false)
      | select((.title | ascii_downcase) == (env.repo | ascii_downcase))
      | .number' | head -1)
fi

if [ -z "$project" ]; then
	printf 'no project for %s; nothing to do\n' "$GH_REPO"
	exit 0
fi
printf 'board: project #%s\n' "$project"

board=$(q "{ organization(login:\"$owner\"){ projectV2(number:$project){ id
    status: field(name:\"Status\"){ ... on ProjectV2SingleSelectField { id options{ id name } } }
    started: field(name:\"Start date\"){ ... on ProjectV2FieldCommon { id } }
    ended: field(name:\"End date\"){ ... on ProjectV2FieldCommon { id } } } } }")
project_id=$(jq -r '.data.organization.projectV2.id' <<<"$board")
status_field=$(jq -r '.data.organization.projectV2.status.id' <<<"$board")
start_field=$(jq -r '.data.organization.projectV2.started.id // ""' <<<"$board")
end_field=$(jq -r '.data.organization.projectV2.ended.id // ""' <<<"$board")

if [ "$project_id" = null ] || [ "$status_field" = null ]; then
	printf '::error::project #%s has no Status field; the board schema has drifted\n' "$project"
	exit 1
fi

# option_id <name> resolves a Status option, failing loudly rather than writing
# to the wrong one.
option_id() {
	local id
	id=$(name="$1" jq -r '.data.organization.projectV2.field.options[]
    | select(.name == env.name) | .id' <<<"$board")
	if [ -z "$id" ]; then
		printf '::error::project #%s has no Status option %s\n' "$project" "$1" >&2
		return 1
	fi
	printf '%s\n' "$id"
}

# --- the item ------------------------------------------------------------

if [ "$KIND" = pr ]; then
	item=$(q "{ repository(owner:\"$owner\", name:\"$repo\"){ pullRequest(number:$NUMBER){
      id number title state isDraft merged reviewDecision } } }")
	node=$(jq -r '.data.repository.pullRequest' <<<"$item")
	content_id=$(jq -r '.id' <<<"$node")
	want=$(status_for_pr \
		"$(jq -r '.state' <<<"$node")" \
		"$(jq -r '.merged' <<<"$node")" \
		"$(jq -r '.isDraft' <<<"$node")" \
		"$(jq -r '.reviewDecision // ""' <<<"$node")")
	type=''
else
	item=$(q "{ repository(owner:\"$owner\", name:\"$repo\"){ issue(number:$NUMBER){
      id number title state stateReason
      issueType{ name }
      assignees(first:1){ totalCount }
      labels(first:50){ nodes{ name } }
      closedByPullRequestsReferences(first:10, includeClosedPrs:false){ totalCount }
      issueFieldValues(first:30){ nodes{
        ... on IssueFieldValueCommon { field{ ... on IssueFieldCommon { name } } }
        ... on IssueFieldSingleSelectValue { name }
        ... on IssueFieldDateValue { value } } } } } }")
	node=$(jq -r '.data.repository.issue' <<<"$item")
	content_id=$(jq -r '.id' <<<"$node")
	type=$(jq -r '.issueType.name // ""' <<<"$node")
	labels=$(jq -r '.labels.nodes[].name' <<<"$node")
	want=$(status_for_issue \
		"$(jq -r '.state' <<<"$node")" \
		"$(jq -r '.stateReason // ""' <<<"$node")" \
		"$(jq -r '.assignees.totalCount' <<<"$node")" \
		"$(jq -r '.closedByPullRequestsReferences.totalCount' <<<"$node")" \
		"$labels")
fi

if ! belongs_on_board "$KIND" "$type"; then
	printf 'a %s issue does not go on the board; nothing to do\n' "${type:-untyped}"
	exit 0
fi
printf 'status: %s\n' "$want"

# --- the board -----------------------------------------------------------

item_id=$(jq -n --arg p "$project_id" --arg c "$content_id" \
	'{query:"mutation($p:ID!,$c:ID!){addProjectV2ItemById(input:{projectId:$p,contentId:$c}){item{id}}}",
    variables:{p:$p,c:$c}}' | gql | jq -r '.data.addProjectV2ItemById.item.id')

option=$(option_id "$want") || exit 1
jq -n --arg p "$project_id" --arg i "$item_id" --arg f "$status_field" --arg o "$option" \
	'{query:"mutation($p:ID!,$i:ID!,$f:ID!,$o:String!){updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,fieldId:$f,value:{singleSelectOptionId:$o}}){projectV2Item{id}}}",
    variables:{p:$p,i:$i,f:$f,o:$o}}' | gql >/dev/null
printf 'set Status\n'

[ "$KIND" = pr ] && exit 0

# --- the issue's own fields and labels -----------------------------------

fields=$(q "{ organization(login:\"$owner\"){ issueFields(first:50){ nodes{
    ... on IssueFieldCommon { name }
    ... on IssueFieldSingleSelect { id options{ id name } }
    ... on IssueFieldDate { id } } } } }")
field_id() { name="$1" jq -r '.data.organization.issueFields.nodes[] | select(.name == env.name) | .id' <<<"$fields"; }

# Hierarchy comes from the title prefix, because a markdown template cannot set
# a field. It is written once and never overwritten.
have_hierarchy=$(jq -r '[.issueFieldValues.nodes[] | select(.field.name == "Hierarchy")] | length' <<<"$node")
if [ "$have_hierarchy" = 0 ]; then
	table=$(yq -r '.hierarchy[] | [.level, .prefix] | @tsv' "$conventions")
	level=$(hierarchy_from_title "$(jq -r '.title' <<<"$node")" "$table")
	if [ -n "$level" ]; then
		hid=$(field_id Hierarchy)
		oid=$(name="$level" jq -r '.data.organization.issueFields.nodes[]
      | select(.name == "Hierarchy") | .options[] | select(.name == env.name) | .id' <<<"$fields")
		if [ -n "$oid" ]; then
			jq -n --arg i "$content_id" --arg f "$hid" --arg o "$oid" \
				'{query:"mutation($i:ID!,$f:ID!,$o:ID!){setIssueFieldValue(input:{issueId:$i,issueFields:[{fieldId:$f,singleSelectOptionId:$o}]}){clientMutationId}}",
          variables:{i:$i,f:$f,o:$o}}' | gql >/dev/null
			printf 'set Hierarchy to %s\n' "$level"
		else
			printf '::warning::no Hierarchy option %s\n' "$level"
		fi
	fi
fi

# Start date and End date are the project's own fields, not the issue's: they
# record what the automation observed rather than anything a person decides, so
# they live with Status. The Roadmap view shows what was planned, the Timeline
# what happened.
dates=$(q "{ node(id:\"$item_id\"){ ... on ProjectV2Item {
    started: fieldValueByName(name:\"Start date\"){ ... on ProjectV2ItemFieldDateValue { date } }
    ended: fieldValueByName(name:\"End date\"){ ... on ProjectV2ItemFieldDateValue { date } } } } }")
have_start=$(jq -r 'if .data.node.started.date then 1 else 0 end' <<<"$dates")
have_end=$(jq -r 'if .data.node.ended.date then 1 else 0 end' <<<"$dates")

# stamp <field-id> <label> writes today into a project date field.
stamp() {
	if [ -z "$1" ]; then
		printf '::warning::project #%s has no %s field\n' "$project" "$2"
		return 0
	fi
	jq -n --arg p "$project_id" --arg i "$item_id" --arg f "$1" --arg d "$(date -u +%Y-%m-%d)" \
		'{query:"mutation($p:ID!,$i:ID!,$f:ID!,$d:Date!){updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,fieldId:$f,value:{date:$d}}){projectV2Item{id}}}",
      variables:{p:$p,i:$i,f:$f,d:$d}}' | gql >/dev/null
	printf 'set %s\n' "$2"
}

while IFS= read -r which; do
	case "$which" in
	start) stamp "$start_field" 'Start date' ;;
	end) stamp "$end_field" 'End date' ;;
	esac
done <<<"$(dates_to_set "$want" "$have_start" "$have_end")"

while IFS= read -r action; do
	[ -n "$action" ] || continue
	case "$action" in
	"add "*) gh issue edit "$NUMBER" --repo "$GH_REPO" --add-label "${action#add }" >/dev/null &&
		printf 'added %s\n' "${action#add }" ;;
	"remove "*) gh issue edit "$NUMBER" --repo "$GH_REPO" --remove-label "${action#remove }" >/dev/null &&
		printf 'removed %s\n' "${action#remove }" ;;
	"ambiguous "*) printf '::warning::%s carries two acting labels (%s); not guessing\n' \
		"#$NUMBER" "${action#ambiguous }" ;;
	esac
done <<<"$(acting_fix "$(jq -r '.state' <<<"$node")" "$labels")"
