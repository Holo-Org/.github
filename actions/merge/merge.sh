#!/usr/bin/env bash
# Squash-merges a pull request, composing the commit from the pull request
# itself. Everything it decides is in lib.sh; this file does the talking to
# GitHub.
#
# A refusal is a successful run: the script explains itself on the pull
# request and exits zero. A non-zero exit means the script itself broke.
#
# Refusal messages are Markdown, so backticks in single quotes are code spans.
# shellcheck disable=SC1091,SC2016
set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# GH_TOKEN, GH_REPO, PR, COMMENT_ID, COMMENT_BODY and ACTOR all come from
# action.yml, which is the only caller. set -u reports a missing one rather
# than letting a default paper over it.

react() {
	[ -n "$COMMENT_ID" ] || return 0
	gh api --silent -X POST \
		"repos/$GH_REPO/issues/comments/$COMMENT_ID/reactions" \
		-f content="$1" || true
}

refuse() {
	printf 'refused: %s\n' "$1"
	react "-1"
	gh api --silent -X POST "repos/$GH_REPO/issues/$PR/comments" -f body="$1"
	exit 0
}

# A comment has to say /merge, and "/merged" does not. Without a body there is
# no way to tell, so nothing is assumed and nothing is acknowledged: the
# manual path has no comment to react to anyway.
if [ -n "$COMMENT_ID" ]; then
	word=$(printf '%s' "$COMMENT_BODY" | tr -d '\r' | head -1 | awk '{ print $1 }')
	if [ "$word" != /merge ]; then
		printf 'the comment begins with "%s", not /merge; nothing to do\n' "$word"
		exit 0
	fi
	react eyes
fi

# author_association would answer a different question: it reports membership,
# not whether this person may push. An unknown or absent actor fails the
# request and lands on "none", so the check cannot be skipped into.
permission=$(gh api "repos/$GH_REPO/collaborators/$ACTOR/permission" \
	--jq '.permission' 2>/dev/null || echo none)
case "$permission" in
admin | write | maintain) ;;
*) refuse "\`/merge\` is for people with write access, and yours is \`$permission\`." ;;
esac

pr=$(gh api "repos/$GH_REPO/pulls/$PR") || exit 1

state=$(jq -r '.state' <<<"$pr")
[ "$state" = open ] || refuse "This pull request is $state."
[ "$(jq -r '.draft' <<<"$pr")" = false ] || refuse "This pull request is a draft."

# A registered stack cannot be merged a layer at a time: the asynchronous API
# merges every layer and gives them all this commit's message. Measured, not
# assumed; see docs/automation-bot.md.
[ "$(jq -r '.stack // "null"' <<<"$pr")" = null ] || refuse \
	"This pull request belongs to a GitHub stack. Merging one layer merges the
whole stack and puts this commit's message on every commit, so \`/merge\` will
not do it. Use \`gh stack merge\`, or take the pull request out of the stack."

[ "$(jq -r '.mergeable' <<<"$pr")" != false ] ||
	refuse "This pull request has conflicts with its base branch."

head=$(jq -r '.head.sha' <<<"$pr")
author=$(jq -r '.user.login' <<<"$pr")

title=$(check_title "$(jq -r '.title' <<<"$pr")" "$PR") || refuse "$title"

# Nothing merges over a check that is red or still running. This is the bot's
# own rule, the same in every repository, whatever the rulesets happen to say.
runs=$(gh api --paginate "repos/$GH_REPO/commits/$head/check-runs" \
	--jq '.check_runs[]' | jq -s '.') || exit 1
pending=$(jq -r '[.[] | select(.status != "completed") | .name] | join(", ")' <<<"$runs")
[ -z "$pending" ] || refuse "These checks have not finished yet: $pending."
unhappy=$(jq -r '
	[.[] | select(.conclusion | IN("success", "neutral", "skipped") | not) | .name]
	| join(", ")' <<<"$runs")
[ -z "$unhappy" ] || refuse "These checks did not pass: $unhappy."

# Commit statuses are a different mechanism from check runs, and an empty list
# reports "pending", which is not a failure.
status=$(gh api "repos/$GH_REPO/commits/$head/status") || exit 1
if [ "$(jq -r '.statuses | length' <<<"$status")" -gt 0 ] &&
	[ "$(jq -r '.state' <<<"$status")" != success ]; then
	refuse "These statuses did not pass: $(jq -r '
		[.statuses[] | select(.state != "success") | .context] | join(", ")' <<<"$status")."
fi

body=$(jq -r '.body // ""' <<<"$pr" | strip_comments)

summary=$(section '## Summary' <<<"$body")
[ -n "$summary" ] || refuse \
	"The Summary section is empty, and it becomes the commit body, so there is
nothing to merge with."

reference=$(issue_ref "$(section '## Related issue' <<<"$body")") || refuse "$reference"

commits=$(mktemp)
trap 'rm -f "$commits"' EXIT
gh api --paginate "repos/$GH_REPO/pulls/$PR/commits" --jq '.[]' | jq -s '.' >"$commits" || exit 1

message=$(commit_body "$summary" "$reference" "$(coauthors "$commits" "$author")")

printf 'merging as:\n%s\n\n%s\n' "$title" "$message"

# --admin asks to bypass only the rules this app is a bypass actor for, which
# is the branch lock and nothing else: a failing check or a missing approval
# still refuses the merge.
if out=$(gh pr merge "$PR" --squash --admin \
	--subject "$title" --body "$message" --match-head-commit "$head" 2>&1); then
	react rocket
	printf 'merged\n'
	exit 0
fi

printf '%s\n' "$out"
refuse "GitHub refused the merge. Its own merge box on this pull request says
which requirement is unmet.

\`\`\`
$out
\`\`\`"
