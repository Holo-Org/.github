# The asynchronous merge API for a `/merge` bot

Last verified: 2026-10-21.

A `/merge` comment on a pull request makes a workflow squash-merge it through an organisation-owned GitHub App token, with the commit message composed from the pull request title and body. This note checks what [`PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge-async`](https://docs.github.com/en/rest/pulls/pulls#merge-a-pull-request-asynchronously) and its polling endpoint [`GET .../merge-async/{uuid}`](https://docs.github.com/en/rest/pulls/pulls#get-the-result-of-an-asynchronous-merge) actually promise, and what they leave unsaid. The target is the `Holo-Org` organisation on the GitHub Free plan, with public repositories.

## Short answer

- **"Stacked pull requests" is a named, documented GitHub feature**, not a loose description. A stack is a *linked* chain of pull requests held by GitHub as an object, with a `stack` field on each member. Public preview 2026-07-30, generally available 2026-10-06, on all github.com plans. [[1]](#1-what-github-means-by-stacked-pull-requests)
- **The sync endpoint cannot merge a stack or use a merge queue**, in GitHub's own words. [[2]](#2-why-the-synchronous-endpoint-is-out)
- **Merge queues are available to `Holo-Org`** (public repositories owned by an organisation), but nothing turns one on by default, and the documented way to enable one on Free is the *branch protection rule* setting, not a ruleset rule. So `merge_action: default` resolves to a direct merge unless an administrator has enabled a queue. [[3]](#3-merge_action-in-full), [[4]](#4-merge-queues-on-github-free)
- **A bot must treat `enqueued` as "queued", never "merged".** [[5]](#5-statuses-and-polling)
- **Merging a mid-stack pull request silently merges every pull request below it.** The bot should read the `stack` field before merging and refuse unless the pull request is at position 1. This is my recommendation; the documented facts behind it are in section 6. [[6]](#6-pull-requests-that-are-part-of-a-stack)
- **Whether GitHub appends ` (#123)` to an explicit `commit_title` is not documented.** [[8]](#8-explicit-commit_title-and-the-123-suffix)

## How the sources were read

Every claim links to its owner. Three kinds of primary source were used, all from GitHub:

- **The REST reference.** The pages on docs.github.com are generated from GitHub's published OpenAPI description. I read the description itself, [`github/rest-api-description` at `755ee33`](https://github.com/github/rest-api-description/tree/755ee33b4a81d51f6f07a902cce26cbec3b822f2/descriptions/api.github.com) (2026-10-18), file `api.github.com.2022-11-28.json`, and checked the rendered [REST reference](https://docs.github.com/en/rest/pulls/pulls) against it for the merge-async and synchronous-merge descriptions: the wording matched. The `2026-03-10` description holds an identical merge-async operation. The file is 13 MB and has no line anchors, so I cite it by operation name: `pulls/merge-async`, `pulls/get-merge-async-result`, `pulls/merge`.
- **The prose documentation.** I read the Markdown source of docs.github.com in [`github/docs` at `3a444c0`](https://github.com/github/docs/tree/3a444c04d005e5d91e29ee0658fd5c9bbeaecf24) (2026-10-20), and spot-checked the rendered page for each quotation I rely on.
- **The changelog** at github.blog/changelog, each entry fetched directly.

A web search was used only to find changelog URLs. Where a statement is my own reasoning, it is marked **Recommendation** or **Inference**.

## 1. What GitHub means by "stacked pull requests"

**It is a named feature with its own documentation section.** The definition, from the [About stacked pull requests](https://docs.github.com/en/pull-requests/get-started/about-stacked-prs) page ([source](https://github.com/github/docs/blob/3a444c04d005e5d91e29ee0658fd5c9bbeaecf24/content/pull-requests/get-started/about-stacked-prs.md)):

> Stacked pull requests are two or more pull requests in the same repository, where: The first, or bottom, pull request targets the stack's trunk … Each subsequent pull request targets the branch of the pull request below it.

So the base branch of each pull request is the head branch of the one below. But the feature is more than that shape. A stack is a **linked object**: the quickstart says pull requests created with `gh stack submit` "are automatically linked together as a stack on GitHub" ([quickstart](https://docs.github.com/en/pull-requests/get-started/stacked-prs-quickstart)), and the rollout guide says the `stack` field "is `null` for standalone pull requests" ([Roll out stacked pull requests](https://docs.github.com/en/pull-requests/tutorials/roll-out-stacked-prs)). Whether GitHub adopts, on its own, a pull request that merely happens to target another pull request's head branch is **not documented**.

What the feature adds, all documented:

- A `stack` object on pull request resources: stack number, size, the pull request's one-based position (1 is the bottom) and the stack's base branch ([OpenAPI schema `pull-request-stack`](https://github.com/github/rest-api-description/blob/755ee33b4a81d51f6f07a902cce26cbec3b822f2/descriptions/api.github.com/api.github.com.2022-11-28.json); [APIs and webhooks](https://docs.github.com/en/pull-requests/reference/stacked-pull-requests-apis-and-webhooks)).
- A Stacks REST API, whose `GET /repos/{owner}/{repo}/stacks` accepts a `pull_request` query parameter that filters "to the stack containing this repository pull request number" (same OpenAPI file, operation under `/repos/{owner}/{repo}/stacks`).
- Rules and CI evaluated against the **stack base**, not the branch directly below ([Stacked pull requests reference](https://docs.github.com/en/pull-requests/reference/stacked-pull-requests)).
- Same-repository only; "Cross-fork stacks are not supported" ([reference](https://docs.github.com/en/pull-requests/reference/stacked-pull-requests)).

**When it was introduced** (changelog):

| Date | Entry | What it says |
| --- | --- | --- |
| 2026-07-30 | [Stacked pull requests are now in public preview](https://github.blog/changelog/2026-07-30-stacked-pull-requests-are-now-in-public-preview/) | "rolling out in public preview to all repositories over the coming days"; merge queue support "rolling out progressively over the coming weeks" |
| 2026-10-01 | [GitHub async merge API generally available](https://github.blog/changelog/2026-10-01-github-async-merge-api-generally-available/) | the async merge API is "the only merge API that supports stacked pull requests" |
| 2026-10-06 | [Stacked pull requests generally available](https://github.blog/changelog/2026-10-06-stacked-pull-requests-generally-available/) | "available on all github.com plans" |

I found no earlier changelog entry for the async merge API (no preview announcement). Whether one exists is **not established**.

Why the merge-async description mentions stacks: "This is the required API for merging stacked pull requests. For a stacked pull request, the operation includes all open downstack pull requests." ([merge-async reference](https://docs.github.com/en/rest/pulls/pulls#merge-a-pull-request-asynchronously))

## 2. Why the synchronous endpoint is out

The exact wording, from the note at the top of [Merge a pull request](https://docs.github.com/en/rest/pulls/pulls#merge-a-pull-request) (OpenAPI operation `pulls/merge`):

> We recommend using the asynchronous merge API instead. This endpoint does not support stacked pull requests or merging with a merge queue.

GitHub gives a reason for **stacks**, in [Stacked pull requests APIs and webhooks](https://docs.github.com/en/pull-requests/reference/stacked-pull-requests-apis-and-webhooks) ([source](https://github.com/github/docs/blob/3a444c04d005e5d91e29ee0658fd5c9bbeaecf24/content/pull-requests/reference/stacked-pull-requests-apis-and-webhooks.md)):

> A stack cannot be merged with the legacy synchronous merge endpoints or mutations. … Merging a pull request stack may involve several pull requests that may take a few minutes to merge. Because of this, the merge runs in the background when you submit a merge request and then you can poll for the result.

The merge-async reference adds that background processing "allows certain types of errors to be retried and reduces the risk of timeouts for complex merges."

For **merge queues**, GitHub states the limitation but gives no reason. That is **not documented**.

Both stated reasons for choosing merge-async hold: the recommendation is in the [sync reference](https://docs.github.com/en/rest/pulls/pulls#merge-a-pull-request) and repeated in the [changelog](https://github.blog/changelog/2026-10-01-github-async-merge-api-generally-available/) ("now the recommended path for programmatically merging pull requests instead of the synchronous REST endpoint or GraphQL mutations"). The sync request body lists only `commit_title`, `commit_message`, `sha` and `merge_method` (OpenAPI operation `pulls/merge`); only merge-async lists `merge_action` and `bypass_rules`.

## 3. `merge_action` in full

Request body of merge-async, from the [reference](https://docs.github.com/en/rest/pulls/pulls#merge-a-pull-request-asynchronously) (OpenAPI operation `pulls/merge-async`):

> `direct_merge` merges the pull request directly without using a merge queue; `merge_queue` adds the pull request to a merge queue; `default` uses a merge queue if one is configured for the target branch, or merges directly otherwise. If omitted, defaults to `default`.

| Value | Behaviour | Source |
| --- | --- | --- |
| `default` (also what you get if omitted) | Merge queue if "one is configured for the target branch"; otherwise a direct merge | quoted above |
| `direct_merge` | Direct merge, "without using a merge queue" | quoted above |
| `merge_queue` | Adds the pull request to a merge queue | quoted above |

**What `default` does with no queue configured:** it merges directly. That is the entire documented statement.

Things the reference does **not** say:

- What `merge_queue` does when no queue is configured on the target branch. Not documented.
- What `direct_merge` does when the branch *requires* a merge queue. Not documented. The merge-async description says only that "Branch protection rules and repository rules are not run at this stage, only basic pull request state checks are performed", and the stacks page that a rule failure "is reported as a failed result while polling".
- Whether `commit_title`, `commit_message` and `merge_method` are ignored or rejected when the action resolves to a queue. The parameters say "Only supported for direct merges". The queue then uses its own configured merge method: "Merge method: Select which method to use when merging queued pull requests" ([Managing a merge queue](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)). What happens to a supplied `commit_title` is not documented.
- The default of `merge_method` when omitted. Not documented. The response schema's `merge_method` enum includes a fourth value, `default`, which appears in the merge-queue example response.

Other request parameters, for completeness (same reference):

- `sha`: "SHA that pull request head must match to allow merge. If not provided, the current head of the PR at the time of the request will be used; if the PR is pushed in between the merge being requested and being executed, the merge will be cancelled." Which status a cancellation reports is not documented.
- `bypass_rules`: boolean, default `false`, "Whether to bypass repository rules that the authenticated actor is permitted to bypass." GitHub Apps can be put on a ruleset's bypass list ([Creating rulesets for a repository](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository), list of eligible bypass actors includes "GitHub Apps"). For a stack, only the bottom pull request can be merged with bypass ([Stacked pull requests reference](https://docs.github.com/en/pull-requests/reference/stacked-pull-requests)).

**Recommendation.** Because the bot always supplies a squash message, send `merge_action: direct_merge` explicitly. With `default`, an administrator enabling a queue later would flip the request into the path where `commit_title` and `commit_message` are documented as unsupported, with unknown handling.

## 4. Merge queues on GitHub Free

**Yes, for public repositories owned by an organisation.** The authoritative statement is the "Who can use this feature?" line of [Managing a merge queue](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue) (rendered; [source reusable](https://github.com/github/docs/blob/3a444c04d005e5d91e29ee0658fd5c9bbeaecf24/data/reusables/gated-features/merge-queue.md)):

> Pull request merge queues are available in any public repository owned by an organization, or in private repositories owned by organizations using GitHub Enterprise Cloud.

The general-availability changelog agrees: "available on private and public repos on the GitHub Enterprise Cloud plan and all public repos owned by organizations" ([2023-07-12](https://github.blog/changelog/2023-07-12-pull-request-merge-queue-is-now-generally-available/)). Free organisations get "unlimited public repositories with a full feature set" ([GitHub's plans](https://docs.github.com/en/get-started/learning-about-github/githubs-plans)). `Holo-Org` public repositories qualify.

Caveats an implementer should know:

1. **How to turn it on.** The documented route is the branch protection setting: "Repository administrators can require a merge queue by enabling the branch protection setting 'Require merge queue' in the protection rules for the base branch" ([Managing a merge queue](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue); also [Managing a branch protection rule](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/managing-a-branch-protection-rule)).
2. **The ruleset rule is documented only for Enterprise.** The "Require merge queue" rule section in the rulesets documentation is gated on a feature file that lists only `ghec` and `ghes >=3.15` ([`repo-rules-merge-queue.yml`](https://github.com/github/docs/blob/3a444c04d005e5d91e29ee0658fd5c9bbeaecf24/data/features/repo-rules-merge-queue.yml), "Docs for the Public Beta of the merge queue repository rule"). The rendered [Available rules for rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets) page, which is the Free/Pro/Team version, has no such rule. Whether it works on Free anyway is **not documented**.
3. **Rulesets themselves are available on Free for public repositories** ([gated-features source](https://github.com/github/docs/blob/3a444c04d005e5d91e29ee0658fd5c9bbeaecf24/data/reusables/gated-features/repo-rules.md)), so that is not the obstacle.
4. **A queue needs CI to cooperate.** Workflows must trigger on `merge_group` ([Managing a merge queue](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)).
5. **GitHub's pricing page does not list merge queue.** I fetched [github.com/pricing](https://github.com/pricing) and neither "queue", "stack" nor "ruleset" appears in the page text, so the docs statement above is the only plan statement.

**Consequence for the bot.** Both states are reachable but only by deliberate configuration. With no queue (today's default), `default` means a direct merge and you will never see `enqueued`. If an administrator enables "Require merge queue" on a branch, `default` will return `enqueued` and the bot must handle it.

## 5. Statuses and polling

`status` is one of `pending`, `merged`, `enqueued`, `failed` (OpenAPI schema `pull-request-merge-async-result`). The `details` object differs by status. Source for the table: the [merge-async](https://docs.github.com/en/rest/pulls/pulls#merge-a-pull-request-asynchronously) and [polling](https://docs.github.com/en/rest/pulls/pulls#get-the-result-of-an-asynchronous-merge) references and that schema.

| Status | Meaning | `details` fields | Where it appears |
| --- | --- | --- | --- |
| `pending` | The request is accepted and not finished. | `message`, `uuid`, `merge_method`, `merge_action`, `expected_head_sha`; `bypass_rules` optional | `PUT` 202 (new request); `PUT` 409 (one already pending); `GET` 200 while in progress |
| `merged` | "The pull request was merged into the base branch. The response includes the merge commit OID." | `message`, `sha` | `PUT` 200 (already merged); `GET` 200 on completion |
| `enqueued` | "The pull request was added to a merge queue." | `message` only | `PUT` 200 (already in a queue); `GET` 200 on completion |
| `failed` | "The request failed. The response includes a message describing the failure." | `message` only | `PUT` 400 (not mergeable now, for example "Pull request is closed."); `GET` 200 on completion (for example "Merge conflict: the pull request could not be merged.") |

Points worth stating:

- **`GET` returns 200 for all four statuses.** Its documented responses are only 200, 403 and 404, so a bot must read `status` from the body, not infer it from the HTTP code. `PUT` is the one that varies the code (200, 202, 400, 409).
- **`failed` can come from two places.** Immediately with HTTP 400 ("basic pull request state checks": closed, draft), or later during polling. Branch protection and rulesets run late: "Branch protection and repository rules are evaluated later, when the merge actually runs, and a rule failure is reported as a failed result while polling" ([APIs and webhooks](https://docs.github.com/en/pull-requests/reference/stacked-pull-requests-apis-and-webhooks)). That sentence is in the stacks page, but the merge-async description makes the same split ("not run at this stage"), so a bot should expect it for every request.
- **Retention.** "The result of an asynchronous merge request is retained for 24 hours after its most recent update. After this window the request expires and this endpoint returns a `404` response for its UUID." ([polling reference](https://docs.github.com/en/rest/pulls/pulls#get-the-result-of-an-asynchronous-merge))
- **`enqueued` is final for the request and is not a merge.** The reference: "An `enqueued` result is final for the merge queue requests and does not mean the pull request has merged. This result does not change when the merge queue later merges the pull request." To learn the outcome, the same page points to [Check if a pull request has been merged](https://docs.github.com/en/rest/pulls/pulls#check-if-a-pull-request-has-been-merged) (`GET .../pulls/{n}/merge`: 204 if merged, 404 if not; empty body).
- **What a bot should conclude from `enqueued`.** That the pull request is in the queue, nothing more. **Recommendation:** reply "queued", not "merged". If you need the final outcome, subscribe to the `pull_request` `closed` event with `merged: true`, or poll the "check if merged" endpoint; the queue can still eject the pull request. GitHub documents that the queue removes a pull request that "no longer meets merge requirements or if a queue check fails" ([Merging a pull request with a merge queue](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/merging-a-pull-request-with-a-merge-queue)).
- **Polling cadence.** No interval, backoff or timeout is documented for the polling endpoint. **Not documented.** Complexity can mean "a few minutes" for stacks (quoted in section 2).
- **Token permissions.** In the docs' permission data, merge-async and the polling `GET` both require the GitHub App permission **Contents: write** (the polling endpoint is listed as `write` too, not `read`); the sync merge needs the same ([`server-to-server-permissions.json`](https://github.com/github/docs/blob/3a444c04d005e5d91e29ee0658fd5c9bbeaecf24/src/github-apps/data/fpt-2022-11-28/server-to-server-permissions.json); rendered [Permissions required for GitHub Apps](https://docs.github.com/en/rest/overview/permissions-required-for-github-apps)). Both are marked enabled for GitHub Apps in the OpenAPI `x-github` block.

## 6. Pull requests that are part of a stack

### What the documentation establishes

1. **Merging is bottom-up and cumulative.** "You cannot merge a mid-stack pull request in isolation, the pull requests below it will always merge with it." and "The selected pull request and all unmerged pull requests below it land on the base branch together as a single operation" ([Merging stacked pull requests](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/merging-stacked-pull-requests)). The merge-async description matches: "the operation includes all open downstack pull requests."
2. **It is gated on every pull request below.** All must be approved with passing checks, and the stack must have a "fully linear history" ([Stacked pull requests reference](https://docs.github.com/en/pull-requests/reference/stacked-pull-requests)).
3. **Squash gives one commit per pull request.** "Merging `n` pull requests creates `n` squashed commits on the base branch" ([reference](https://docs.github.com/en/pull-requests/reference/stacked-pull-requests)).
4. **Pull requests above stay open and are retargeted.** "Merge part of the stack by merging a mid-stack pull request. The pull requests below it merge too, and the pull requests above stay open and automatically re-target the stack's base branch." ([About stacked pull requests](https://docs.github.com/en/pull-requests/get-started/about-stacked-prs)). Also: "After the merge, the next unmerged pull request is automatically rebased to target the stack base directly" ([Merging stacked pull requests](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/merging-stacked-pull-requests)).
5. **Atomicity, with a documented inconsistency.** The APIs page says "A stack merge request is atomic, meaning either the whole group of pull requests merges, or is added to the merge queue, or none of it is." The [troubleshooting page](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-stacked-pull-requests) says that if a failure occurs part way, "Pull requests below it that merged successfully remain landed on the base branch." Both pages are current as of the commit read; they do not agree, and I cannot say which is right.
6. **No auto-merge.** "Auto-merge is not supported for stacked pull requests" ([Merging stacked pull requests](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/merging-stacked-pull-requests)). The 2026-10-06 changelog says auto-merge for stacks is "rolling out over the next few weeks"; the two disagree, and I treat the docs as the later, more specific statement only provisionally.
7. **Closed middle pull request.** "Closing a pull request in the middle of a stack blocks all pull requests above it from being mergeable" ([troubleshooting](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-stacked-pull-requests)).
8. **A merge queue ejects the pull requests above one that is removed** ([same page](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-stacked-pull-requests)).
9. **Bypass:** only the lowest unmerged pull request, per the reference quoted in section 3 and the [GA changelog](https://github.blog/changelog/2026-10-06-stacked-pull-requests-generally-available/) ("merge the lowest unmerged pull request in a stack").

### Automatic retargeting, two separate mechanisms

**(a) Classic retargeting (not stack-specific).** Changelog [2020-05-19, Pull Request Retargeting](https://github.blog/changelog/2020-05-19-pull-request-retargeting/): previously, when a pull request's head branch was merged and deleted, other open pull requests based on it "would be automatically closed. Now … the pull requests will be retargeted—the base branch of each pull request will be updated to the merged pull request's base branch." The current docs ([source reusable](https://github.com/github/docs/blob/3a444c04d005e5d91e29ee0658fd5c9bbeaecf24/data/reusables/pull_requests/retargeted-on-branch-deletion.md), shown on [Merging a pull request](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/merging-a-pull-request)):

> If you delete a head branch after its pull request has been merged, GitHub checks for any open pull requests in the same repository that specify the deleted branch as their base branch. GitHub automatically updates any such pull requests, changing their base branch to the merged pull request's base branch.

The trigger is **deleting the head branch**, not merging. If the head branch stays, nothing in the documentation says the dependants are retargeted. The same page notes the repository "may automatically delete the head branch after merging" ([Managing the automatic deletion of branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-the-automatic-deletion-of-branches)).

**(b) Stack-specific.** Changelog [2026-10-06](https://github.blog/changelog/2026-10-06-stacked-pull-requests-generally-available/): "Branching stacks retarget automatically. When a stack's base branch is deleted, GitHub automatically retargets the stack instead of closing its bottom pull request." That is about the **stack's base** (trunk) being deleted, not about the lower pull request merging. The merge case is covered by item 4 above (the next pull request is rebased to target the stack base), from the docs and the [public preview changelog](https://github.blog/changelog/2026-07-30-stacked-pull-requests-are-now-in-public-preview/) ("the pull requests above it stay open and automatically rebase and retarget").

### What it implies for a squash-merge bot (recommendations)

Documented facts are above; the rules below are my reading of them.

1. **Detect the stack before merging.** `GET /repos/{owner}/{repo}/pulls/{n}` and read `stack`. It is `null` for standalone pull requests (rollout guide, quoted in section 1). If non-null, it carries `position`, `size`, `base.ref`.
2. **Refuse unless `stack.position` is 1.** From a mid-stack `/merge`, GitHub would land every pull request below it (fact 1), and the bot's `commit_title` and `commit_message` come from only one of them. Posting a refusal that names the bottom pull request is the safe behaviour.
3. **The commit message for a stack merge is undefined in the documentation.** Fact 3 says there are `n` squash commits, but neither the merge-async reference nor any stacks page says which message each of the `n` commits receives when you supply one `commit_title` and `commit_message`. **Not documented.** Merging one layer at a time, bottom first, avoids the question, because with position 1 and its predecessors already merged only one pull request is open, and the message you build from that pull request is the one that applies. (When the bottom pull request merges, the next one moves to position 1 after the automatic retarget; the bot should wait for that, see point 5.)
4. **A pull request whose base is not the default branch and has no `stack`.** The docs do not call this a stack. Merging it lands the change into the intermediate branch, not `main`. **Recommendation:** refuse when `base.ref` is not the repository's default branch, unless you decide otherwise on purpose. For a position-1 stack member whose `stack.base.ref` is a release branch, the same check should compare against `stack.base.ref`, not the default branch.
5. **After merging a layer, do not assume the next one is immediately retargeted.** The documentation says the next pull request is "automatically rebased", but gives no timing. Re-read `base.ref` and `stack.position` before acting on a second `/merge`, and expect a rebase to change the head SHA (a `sha` you captured earlier will be stale).
6. **If you ever merge unlinked, hand-built chains** (a child pull request whose base is the parent's head branch, no `stack` object): squash-merging the parent leaves the child's branch holding the original commits. GitHub's only statement on a close relative is general: "If you keep working on the same head branch after a squash merge, later pull requests can include commits that were already squashed into the base branch. This can make merge conflicts more likely" ([Pull request merges](https://docs.github.com/en/pull-requests/reference/pull-request-merges)). How retargeting interacts with squash for unlinked chains is **not documented**.

## 7. Rate limits, concurrency and 409

**409 on merge-async.** "If another asynchronous merge request is already pending for this pull request, a `409` response returns that request's UUID and merge options instead." ([reference](https://docs.github.com/en/rest/pulls/pulls#merge-a-pull-request-asynchronously)) The 409 body has `status: "pending"` and the existing request's `uuid`, `merge_method`, `merge_action` and `expected_head_sha`. The documented response description is "if there is an existing merge request already enqueued for this pull request".

- **Bot handling (recommendation).** Treat 409 as success of a duplicate: take the `uuid` from the body and poll it. **Inference:** since the body returns "that request's … merge options", a second `/merge` with a different message does not replace the first one's options, so the bot should compare `details.merge_method` and `details.merge_action` and say so if they differ. Whether the second request's `commit_title` is stored or discarded is not documented, and the 409 body has no field for it.
- **Do not confuse it with the sync endpoint's 409**, which means "Conflict if sha was provided and pull request head did not match" (OpenAPI operation `pulls/merge`). In merge-async a head mismatch is handled differently: the merge "will be cancelled", with no documented status code or message.

**Other status codes** (same reference): 200 already merged or already queued; 202 accepted; 400 "not ready to be merged", `status: "failed"` (closed, draft); 403 forbidden; 404 not found; 422 "Validation failed, or the endpoint has been spammed." (the generic `validation_failed` response in the OpenAPI components, not specific to this endpoint). The reference documents no other conditions for 403 or 422.

**Rate limits.** No limit specific to merge-async or the polling endpoint is documented. **Not documented.** The general limits that apply to a GitHub App installation token ([Rate limits for the REST API](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api); [source reusable, secondary](https://github.com/github/docs/blob/3a444c04d005e5d91e29ee0658fd5c9bbeaecf24/data/reusables/rest-api/secondary-rate-limit-rest-graphql.md); [source reusable, installations](https://github.com/github/docs/blob/3a444c04d005e5d91e29ee0658fd5c9bbeaecf24/data/reusables/rest-api/primary-rate-limit-github-app-installations.md)):

- **Primary:** installation tokens get "the installation's minimum rate limit of 5,000 requests per hour" off Enterprise Cloud, rising by 50 per hour per repository beyond 20 repositories and per user beyond 20 users, capped at 12,500.
- **Secondary:** "No more than 100 concurrent requests"; "No more than 900 points per minute are allowed for REST API endpoints"; most `POST`, `PATCH`, `PUT` or `DELETE` requests cost 5 points, most `GET` requests 1; and "In general, no more than 80 content-generating requests per minute and no more than 500 content-generating requests per hour". "Some endpoints have lower content creation limits." Whether a merge counts as content-generating is not stated for merge-async; the synchronous endpoint's description warns that "Creating content too quickly using this endpoint may result in secondary rate limiting", and merge-async's OpenAPI metadata carries `triggersNotification: true`, but its prose does not repeat the warning.
- **On exceeding a limit:** 403 or 429; honour `retry-after`; otherwise wait at least a minute, then back off exponentially. Making requests serially is advised ([Best practices](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api)).
- **Polling cost:** each poll is one request against both the primary limit and, as a `GET`, 1 secondary point. With a 24-hour retention (section 5) the bot has a generous window, so polling with a backoff, not a tight loop, fits.

## 8. Explicit `commit_title` and the ` (#123)` suffix

**Not documented.** Stated plainly:

- The merge-async parameter reads "Title for the automatic commit message. Only supported for direct merges." The synchronous parameter reads "Title for the automatic commit message." Neither page says anything about appending a pull request number, to an explicit title or to a default one (OpenAPI operations `pulls/merge-async`, `pulls/merge`).
- Neither page says merge-async treats `commit_title` differently from the synchronous endpoint, apart from the "Only supported for direct merges" qualifier.
- A full-text search of the `content/` and `data/` trees of [`github/docs` at `3a444c0`](https://github.com/github/docs/tree/3a444c04d005e5d91e29ee0658fd5c9bbeaecf24) for the pattern `(#<digits>)` finds no statement that a number is appended to a squash title.
- The only primary statements that mention the number are about the **default message offered in the web interface**, not the API: the changelog [2022-08-23](https://github.blog/changelog/2022-08-23-new-options-for-controlling-the-default-commit-message-when-merging-a-pull-request/) says that for squash merging the "Pull request title" option gives "pull request title and number on the first line", and the default option uses "the pull request title and number and list of commits (if the pull request contains multiple commits)". The repository settings in the REST reference (`squash_merge_commit_title`: `PR_TITLE` or `COMMIT_OR_PR_TITLE`) describe the default title without mentioning a number (OpenAPI operation `repos/update`).

So whether GitHub adds ` (#123)` to a caller-supplied title, or only to its own default, **cannot be established from primary sources**. **Recommendation:** if the suffix matters (for example for changelog tooling), have the bot add or omit it itself and check the result with a test merge in a scratch repository, because the documentation will not settle it. I did not run that test.

## Settled by experiment, not by documentation

Run on `Holo-Org/.github` on 2026-10-21, against a throwaway branch carrying an
`update` rule with the app as a bypass actor in `always` mode. Recorded in
[`../automation-bot.md`](../automation-bot.md).

- **A bypass actor must still ask for the bypass.** `bypass_rules: false` failed
  with `Repository rule violations found / Cannot update this protected ref.`
  The identical request with `bypass_rules: true` merged. Listing the app in a
  ruleset's bypass list is not sufficient on its own, which rules out the
  synchronous endpoint entirely: it has no such parameter.
- **`bypass_actors[].actor_id` is the app ID**, not the installation ID, with
  `actor_type: "Integration"`.
- **GitHub does not append ` (#123)` to an explicit `commit_title`.** A supplied
  title lands verbatim, so a bot that composes the title must append the pull
  request number itself.
- **For a squash merge, `details.sha` is the squashed commit** on the base
  branch, not a separate merge commit.
- **A stack merges as one, and every commit gets the same message.** Targeting
  the `position: 1` pull request of a two-layer stack with `bypass_rules: true`
  merged both pull requests and left two commits on the base branch, each
  carrying the single `commit_title` and `commit_message` supplied for the
  bottom layer. There is no way to merge one layer with a message of its own.
- **`gh pr merge` refuses a stacked pull request**, pointing at the asynchronous
  API by name; `gh stack merge` can merge up to a chosen layer but cannot bypass
  merge requirements, so it cannot write to a locked branch.
- **A chain of pull requests is not a stack**: `stack` is `null` unless the
  chain was registered with `gh stack`, and such pull requests merge normally.
- **The squash commit keeps the pull request's author** and records `GitHub` as
  its committer, so only co-author trailers need composing.

## What I could not establish from primary sources

- Whether any changelog entry announced an async-merge **preview** before the 2026-10-01 GA entry.
- Whether GitHub auto-adopts a pull request into a stack when its base happens to be another pull request's head branch, without `gh stack submit` or the Stacks API.
- Why the synchronous endpoint cannot support merge queues (the limitation is stated; no reason is given).
- What `merge_queue` does when no queue is configured; what `direct_merge` does when the branch requires a queue; whether `commit_title`, `commit_message` or `merge_method` are ignored or rejected when `default` resolves to a queue.
- The default `merge_method` when omitted.
- Which status or message a cancellation reports when the head moved after the request ("the merge will be cancelled").
- Whether a stack merge is all-or-nothing: the APIs page says atomic, the troubleshooting page describes partial landing. The two contradict each other.
- Whether stacks support auto-merge: the docs say no, the 2026-10-06 changelog says it is rolling out.
- How classic retargeting (head branch deleted) interacts with squash merges of unlinked chains.
- Whether the ruleset "Require merge queue" rule works on the Free plan (documented for Enterprise only; the branch protection setting is the documented Free route).
- Any rate limit or concurrency limit specific to merge-async or its polling endpoint; any recommended polling interval or timeout.
- Whether a repeated `/merge` with different options, hitting 409, stores or discards the new options.
- Whether a `uuid` from one pull request, queried under another pull request's number, returns 404 or the result.
- Anything about merge queues or stacks on the Free plan from GitHub's pricing page: [github.com/pricing](https://github.com/pricing) does not mention them, so the plan statements rest on the documentation and changelog only.
