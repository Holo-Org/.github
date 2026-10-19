#!/usr/bin/env bash
#
# Mirror a GitHub repository's branches and tags to a destination Git remote
# over SSH. Driven entirely by MIRROR_* environment variables set by action.yml.
#
set -euo pipefail

notice() { printf '::notice::%s\n' "$*"; }
warn() { printf '::warning::%s\n' "$*"; }
fail() {
	printf '::error::%s\n' "$*" >&2
	exit 1
}

output() {
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"
	fi
}

summary() {
	if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
		printf '%s\n' "$*" >>"$GITHUB_STEP_SUMMARY"
	fi
}

is_true() {
	case "${1,,}" in
	true | yes | 1 | on) return 0 ;;
	*) return 1 ;;
	esac
}

destination=${MIRROR_DESTINATION:-}
ssh_key=${MIRROR_SSH_KEY:-}
known_hosts_input=${MIRROR_KNOWN_HOSTS:-}
source_repository=${MIRROR_SOURCE_REPOSITORY:-${GITHUB_REPOSITORY:-}}
source_token=${MIRROR_SOURCE_TOKEN:-${GITHUB_TOKEN:-}}
branch_glob=${MIRROR_BRANCHES:-*}
tag_glob=${MIRROR_TAGS:-*}
server_url=${GITHUB_SERVER_URL:-https://github.com}

# Not configured for mirroring: say so once and succeed, so that the workflow
# can be wired up across the whole organisation without failing anywhere.
if [ -z "$destination" ]; then
	notice "No mirror destination configured; nothing to do."
	output mirrored false
	output branches 0
	output tags 0
	exit 0
fi

# Configured but unusable: that is a real misconfiguration, so fail loudly.
[ -n "$ssh_key" ] || fail "A destination is configured but no SSH key was provided."
[ -n "$source_repository" ] || fail "Could not determine which repository to mirror."
[ -n "$source_token" ] || fail "No token available to read the source repository."

port=''
case "$destination" in
ssh://*)
	rest=${destination#ssh://}
	rest=${rest#*@}
	hostport=${rest%%/*}
	host=${hostport%%:*}
	case "$hostport" in
	*:*) port=${hostport##*:} ;;
	esac
	dest_path=${rest#*/}
	;;
*://*)
	fail "Destination '$destination' is not an SSH URL; expected git@host:owner/repo.git or ssh://..."
	;;
*@*:*)
	rest=${destination#*@}
	host=${rest%%:*}
	dest_path=${rest#*:}
	;;
*)
	fail "Could not parse destination '$destination'; expected git@host:owner/repo.git or ssh://..."
	;;
esac
dest_path=${dest_path#/}

[ -n "$host" ] || fail "Could not determine the destination host from '$destination'."

# Refuse to mirror a repository onto itself: with --prune --force that would be
# a destructive no-op at best.
if [ "https://$host" = "$server_url" ] && [ "${dest_path%.git}" = "$source_repository" ]; then
	fail "Destination '$destination' is the source repository itself."
fi

refspecs=()
if [ "$branch_glob" != "false" ]; then
	refspecs+=("+refs/heads/${branch_glob}:refs/heads/${branch_glob}")
fi
if [ "$tag_glob" != "false" ]; then
	refspecs+=("+refs/tags/${tag_glob}:refs/tags/${tag_glob}")
fi
[ ${#refspecs[@]} -gt 0 ] || fail "Both branches and tags are disabled; there is nothing to mirror."

work=$(mktemp -d "${RUNNER_TEMP:-/tmp}/mirror.XXXXXXXX")
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

key_file="$work/id"
printf '%s\n' "$ssh_key" >"$key_file"
chmod 600 "$key_file"

known_hosts_file="$work/known_hosts"
if [ -n "$known_hosts_input" ]; then
	printf '%s\n' "$known_hosts_input" >"$known_hosts_file"
elif [ "$host" = "github.com" ]; then
	# Preferred over ssh-keyscan, which trusts whatever answers on the network.
	if ! curl --fail --silent --show-error --location --retry 3 https://api.github.com/meta |
		jq -r --arg h "$host" '.ssh_keys[] | "\($h) \(.)"' >"$known_hosts_file"; then
		warn "Could not read GitHub's published SSH host keys."
	fi
else
	keyscan_args=()
	[ -n "$port" ] && keyscan_args+=(-p "$port")
	ssh-keyscan "${keyscan_args[@]}" "$host" >"$known_hosts_file" 2>/dev/null || true
fi
[ -s "$known_hosts_file" ] || fail "Could not determine the SSH host keys for '$host'. Pass them via the known-hosts input."

ssh_command="ssh -i '$key_file' -o IdentitiesOnly=yes -o UserKnownHostsFile='$known_hosts_file' -o StrictHostKeyChecking=yes -o BatchMode=yes"
[ -n "$port" ] && ssh_command="$ssh_command -p $port"
export GIT_SSH_COMMAND="$ssh_command"
export GIT_TERMINAL_PROMPT=0

# A bare repo with explicit refspecs, rather than `clone --mirror`: it skips
# refs/pull/*, which the destination would reject, and transfers less.
src="$work/source.git"
git init --quiet --bare "$src"
git -C "$src" remote add origin "${server_url}/${source_repository}.git"
git -C "$src" config "http.${server_url}/.extraheader" \
	"AUTHORIZATION: basic $(printf 'x-access-token:%s' "$source_token" | base64 | tr -d '\n')"

echo "Fetching ${source_repository} ..."
git -C "$src" fetch --quiet --prune --no-tags origin \
	'+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*'

branch_count=$(git -C "$src" for-each-ref --format='%(refname)' refs/heads | wc -l | tr -d ' ')
tag_count=$(git -C "$src" for-each-ref --format='%(refname)' refs/tags | wc -l | tr -d ' ')
output branches "$branch_count"
output tags "$tag_count"

# An empty source with --prune would wipe the destination. Refuse instead.
if [ "$branch_count" -eq 0 ] && [ "$tag_count" -eq 0 ]; then
	notice "Source repository has no branches or tags; leaving the destination untouched."
	output mirrored false
	exit 0
fi

push_args=(--force)
is_true "${MIRROR_PRUNE:-true}" && push_args+=(--prune)
is_true "${MIRROR_DRY_RUN:-false}" && push_args+=(--dry-run)

echo "Pushing to ${host}:${dest_path} ..."
git -C "$src" push "${push_args[@]}" "$destination" "${refspecs[@]}"

if is_true "${MIRROR_LFS:-false}"; then
	if command -v git-lfs >/dev/null 2>&1; then
		echo "Transferring Git LFS objects ..."
		git -C "$src" lfs fetch --all origin
		if is_true "${MIRROR_DRY_RUN:-false}"; then
			notice "Dry run: skipping the LFS push."
		else
			git -C "$src" lfs push --all "$destination"
		fi
	else
		warn "LFS mirroring was requested but git-lfs is not installed on this runner."
	fi
fi

output mirrored true

summary "### Mirror"
summary ""
summary "| | |"
summary "|---|---|"
summary "| Source | \`${source_repository}\` |"
summary "| Destination | \`${host}:${dest_path}\` |"
summary "| Branches | ${branch_count} (\`${branch_glob}\`) |"
summary "| Tags | ${tag_count} (\`${tag_glob}\`) |"
summary "| Prune | $(is_true "${MIRROR_PRUNE:-true}" && echo yes || echo no) |"
is_true "${MIRROR_DRY_RUN:-false}" && summary "| Dry run | yes |"

echo "Done."
