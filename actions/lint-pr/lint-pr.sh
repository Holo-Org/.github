#!/usr/bin/env bash
# Checks a pull request against the organisation's conventions. Everything it
# decides is in lib.sh; this file does the talking to GitHub and the reporting.
#
# Every failure is collected and reported together, because fixing them one
# round trip at a time is what makes a lint hated.
#
# The report is one comment, edited in place on every run, so a pull request
# never accumulates a column of stale lint comments.
# shellcheck disable=SC1091,SC2016
set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# GH_TOKEN, GH_REPO and PR come from action.yml. The planning files travel with
# this action: GitHub checks out the whole repository that holds it, so they sit
# two levels up from the action's own directory and need no checkout of their
# own in the calling repository.
root="$GITHUB_ACTION_PATH/../.."
conventions="$root/planning/conventions.yml"
shared_labels="$root/planning/labels.yml"
marker='<!-- holo-org: pull-request-lint -->'

for f in "$conventions" "$shared_labels"; do
	[ -f "$f" ] || {
		printf '::error::%s is missing; the action was checked out wrong\n' "$f"
		exit 1
	}
done

kinds=$(yq -r '.branch_kinds[]' "$conventions")

# Components are the shared ones plus whatever the repository itself declares.
# A repository with no file of its own is fine: it has only the shared two.
components=$(yq -r '.shared[] | select(.name | test("^component: ")) | .name' \
	"$shared_labels" | sed 's/^component: //')
own=$(mktemp)
trap 'rm -f "$own"' EXIT
if gh api "repos/$GH_REPO/contents/.github/labels.yml" --jq '.content' 2>/dev/null |
	base64 -d >"$own" 2>/dev/null && [ -s "$own" ]; then
	components=$(printf '%s\n%s\n' "$components" "$(yq -r '.components // {} | keys | .[]' "$own")")
fi
components=$(grep -v '^$' <<<"$components" | sort -u)
components_lower=$(tr '[:upper:]' '[:lower:]' <<<"$components")

pr=$(gh api "repos/$GH_REPO/pulls/$PR") || exit 1
title=$(jq -r '.title' <<<"$pr")
branch=$(jq -r '.head.ref' <<<"$pr")
labels=$(jq -r '.labels[].name' <<<"$pr")
body=$(jq -r '.body // ""' <<<"$pr" | strip_comments)

failures=()
fail() { failures+=("$1"); }

# --- the title, by the merge command's own rule ---------------------------

if ! out=$(check_title "$title" "$PR"); then
	fail "**The title.** $out

A title reads \`<area>: <imperative summary>\`, lowercase, and the limit is
measured on the commit title Git will store — \` (#$PR)\` included. The area is
finer than the component: reuse what the log already says."
fi

# --- the branch ----------------------------------------------------------

if ! out=$(check_branch "$branch" "$kinds" "$components_lower"); then
	fail "**The branch name.** $out

A branch reads \`<kind>/<component>/<slug>\`, so \`feat/nix/pin-the-toolchain\`.
The kinds are in \`planning/conventions.yml\`; the components in this
repository's own \`.github/labels.yml\`."
fi

# --- the sections the merge command parses --------------------------------

if [ -z "$(section '## Summary' <<<"$body")" ]; then
	fail "**The Summary section is empty.** It becomes the commit body, so
\`/merge\` will refuse this pull request as it stands. One or two sentences on
what the change does and why it is right, wrapped at 85 columns."
fi

if ! out=$(issue_ref "$(section '## Related issue' <<<"$body")"); then
	fail "**The Related issue section.** $out

Use \`Closes #123\` on a single pull request, or on the last layer of a stack.
Use \`Part of #123\` on every other layer, so the issue closes once."
fi

# --- the labels ----------------------------------------------------------

if ! out=$(check_release "$labels"); then
	fail "**The release labels.** $out

Keep the largest bump that applies and drop the rest."
fi

component=""
if ! out=$(check_components "$labels" "$body"); then
	fail "**The component label.** $out"
else
	component=$out
	reason=$(component_exception "$body")
	[ -z "$reason" ] || printf '::notice::component exception accepted: %s\n' "$reason"
fi

single=$([ -n "$component" ] && [ "$(grep -c . <<<"$component")" = 1 ] && echo yes || echo no)

# --- the branch and the label must agree ---------------------------------

if [ "$single" = yes ] && ! out=$(check_branch_component "$branch" "$component"); then
	fail "**The branch and the label disagree.** $out

They name the same thing, so one of them is wrong."
fi

# --- the linked issue ----------------------------------------------------

ref=$(closing_ref "$body")
if [ -n "$ref" ] && [ "$single" = yes ]; then
	number=${ref##* }
	if issue=$(gh api "repos/$GH_REPO/issues/$number" 2>/dev/null); then
		if ! out=$(check_issue_component "$component" \
			"$(jq -r '.labels[].name' <<<"$issue" | values 'component: ')"); then
			fail "**The component is not one the linked issue covers.** $out"
		fi
	else
		fail "**The linked issue does not exist.** The description references
#$number and reading it failed. Check the number."
	fi
fi

# --- report --------------------------------------------------------------

report=$(mktemp)
trap 'rm -f "$own" "$report"' EXIT
{
	printf '%s\n' "$marker"
	if [ "${#failures[@]}" -eq 0 ]; then
		printf '### Conventions: all clear\n\n'
		printf 'Title, branch, sections and labels all check out.\n'
	else
		printf '### Conventions: %d to fix\n\n' "${#failures[@]}"
		for f in "${failures[@]}"; do
			printf -- '- %s\n\n' "$f"
		done
		printf 'The conventions are in '
		printf '[CONTRIBUTING.md](https://github.com/Holo-Org/.github/blob/main/CONTRIBUTING.md).\n'
	fi
	printf '\n<sub>Edited in place on every push.</sub>\n'
} >"$report"

cat "$report" >>"$GITHUB_STEP_SUMMARY"
cat "$report"

# A pull request from a fork gets a read-only token, so commenting fails there.
# The summary above is the whole report either way, and a lint that cannot
# comment has still done its job.
existing=$(gh api --paginate "repos/$GH_REPO/issues/$PR/comments" \
	--jq ".[] | select(.body | startswith(\"$marker\")) | .id" 2>/dev/null | head -1)
if [ -n "$existing" ]; then
	jq -Rs '{body: .}' <"$report" |
		gh api --silent -X PATCH "repos/$GH_REPO/issues/comments/$existing" --input - ||
		printf '::warning::could not update the lint comment\n'
else
	jq -Rs '{body: .}' <"$report" |
		gh api --silent -X POST "repos/$GH_REPO/issues/$PR/comments" --input - ||
		printf '::warning::could not post the lint comment\n'
fi

[ "${#failures[@]}" -eq 0 ] || {
	printf '::error::%d convention check(s) failed\n' "${#failures[@]}"
	exit 1
}
printf 'everything checks out\n'
