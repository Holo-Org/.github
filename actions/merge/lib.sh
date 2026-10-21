#!/usr/bin/env bash
# Pure helpers for composing a squash commit from a pull request. Nothing here
# touches the network, so lib.test.sh can exercise all of it.
#
# Refusal messages are Markdown, posted as a pull request comment, so the
# backticks in them are code spans rather than command substitution.
# shellcheck disable=SC2016

# Removes HTML comments, including ones spanning several lines, so the
# guidance inside the pull request template is never read as prose.
strip_comments() {
	awk '
		{
			line = $0
			out = ""
			while (1) {
				if (incomment) {
					i = index(line, "-->")
					if (i == 0) {
						line = ""
						break
					}
					incomment = 0
					line = substr(line, i + 3)
					continue
				}
				i = index(line, "<!--")
				if (i == 0) {
					out = out line
					break
				}
				out = out substr(line, 1, i - 1)
				line = substr(line, i + 4)
				incomment = 1
			}
			if (!incomment || out != "") print out
		}
	'
}

# Drops leading and trailing blank lines.
trim_blank() {
	awk '
		{ lines[NR] = $0 }
		END {
			first = 1
			last = NR
			while (first <= NR && lines[first] ~ /^[[:space:]]*$/) first++
			while (last >= first && lines[last] ~ /^[[:space:]]*$/) last--
			for (i = first; i <= last; i++) print lines[i]
		}
	'
}

# section <heading> reads a comment-free body on stdin and prints that
# heading's lines, stopping at the next heading. The heading must match
# exactly, so "## Summary" never picks up "## Summary by CodeRabbit".
section() {
	awk -v want="$1" '
		/^#/ {
			inside = ($0 == want)
			next
		}
		inside { print }
	' | trim_blank
}

# check_title <title> <pr-number> prints why the title is unacceptable and
# returns 1, or prints the commit title and returns 0. The convention's limit
# is 72 columns on the commit title, so the number is part of the measurement.
check_title() {
	local title="$1" number="$2" composed
	composed="$title (#$number)"

	if [ "${#composed}" -gt 72 ]; then
		printf 'The commit title would be %d columns and the limit is 72, so the title is %d too long.\n' \
			"${#composed}" "$((${#composed} - 72))"
		return 1
	fi
	case "$title" in
	*"  "*)
		printf 'The title contains a double space.\n'
		return 1
		;;
	esac
	if ! grep -qE '^[a-z0-9/-]+: [a-z]' <<<"$title"; then
		printf 'The title must read `<area>: <subject>`, with a lowercase area and a lowercase verb.\n'
		return 1
	fi
	if ! grep -qE '[[:alnum:]]$' <<<"$title"; then
		printf 'The title must end in a letter or a digit.\n'
		return 1
	fi

	printf '%s\n' "$composed"
}

# issue_ref <related-issue-section> prints the canonical trailer, or prints why
# it cannot and returns 1.
issue_ref() {
	local text="$1" found
	found=$(grep -oiE '(closes|part of)[[:space:]]+#[0-9]+' <<<"$text" | head -1 || true)

	if [ -n "$found" ]; then
		case "$found" in
		[Cc]loses*) printf 'Closes #%s\n' "${found##*#}" ;;
		*) printf 'Part of #%s\n' "${found##*#}" ;;
		esac
		return 0
	fi
	if grep -qiE '(closes|part of)[[:space:]]*#' <<<"$text"; then
		printf 'Related issue has a `Closes #` with no issue number.\n'
	else
		printf 'Related issue must say `Closes #123` or `Part of #123`.\n'
	fi
	return 1
}

# coauthors <commits-json> <pull-request-author> prints one Co-authored-by
# trailer per other person who wrote part of the branch, in the order first
# seen.
#
# Only commit authors and Co-authored-by trailers count. Committers do not:
# rebasing a branch onto its base makes the rebaser the committer of every
# commit on it, and rebasing somebody's work is not co-writing it.
#
# Apps are dropped, by the linked account's type or a login ending in [bot],
# and so is the pull request author, who is the squash commit's own author.
coauthors() {
	jq -r --arg me "$2" '
		def trailers:
			.commit.message
			| split("\n")
			| map(select(test("^[ \t]*co-authored-by[ \t]*:"; "i")))
			| map(capture("co-authored-by[ \t]*:[ \t]*(?<name>[^<]+)<(?<email>[^>]+)>"; "i"))
			| map({
					name: (.name | sub("[ \t]+$"; "")),
					email: (.email | gsub("^[ \t]+|[ \t]+$"; "")),
					login: "",
					type: "User"
				})
			| .[];

		[ .[]
			| ( { name: .commit.author.name, email: .commit.author.email,
						login: (.author.login // ""), type: (.author.type // "User") },
					trailers )
		]
		| map(select(.name != null and .email != null and .name != "" and .email != ""))
		| map(select(.type != "Bot"))
		| map(select(.login | endswith("[bot]") | not))
		| map(select(.login != $me))
		| reduce .[] as $p ({ seen: {}, out: [] };
				($p.email | ascii_downcase) as $k
				| if .seen[$k] then .
					else { seen: (.seen + { ($k): true }), out: (.out + [$p]) }
					end)
		| .out
		| map("Co-authored-by: \(.name) <\(.email)>")
		| .[]
	' "$1"
}

# commit_body <summary> <issue-trailer> <coauthor-trailers> prints the body.
commit_body() {
	printf '%s\n\n%s\n' "$1" "$2"
	[ -z "$3" ] || printf '%s\n' "$3"
}
