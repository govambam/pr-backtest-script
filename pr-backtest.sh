#!/usr/bin/env bash
# pr-backtest.sh — recreate a GitHub PR's diff as a fresh PR in the same repo,
# so a PR-review bot reviews it as if it were brand new.
#
# No install, no token. It uses the git + gh login you already have, and runs
# from anywhere: all work happens in a disposable temp clone, so none of your
# own repos or checkouts are ever touched.
#
#   ./pr-backtest.sh <pr-url> [commit]
#
# With no commit it recreates the whole PR. Pass a commit SHA from the PR to cut
# off there instead — the backtest spans the PR's base up to and including it.
#
# Examples:
#   ./pr-backtest.sh https://github.com/acme/api/pull/123
#   ./pr-backtest.sh https://github.com/acme/api/pull/123 a1b2c3d
#
# Requirements:
#   - git
#   - the GitHub CLI (gh), authenticated:  gh auth login
#   - write access to the repo (it pushes two branches and opens a PR there)

set -euo pipefail

url="${1:-}"
at_sha="${2:-}"
if [[ -z "$url" ]]; then
  echo "usage: pr-backtest.sh <pr-url> [commit]" >&2
  exit 1
fi

# Parse owner / repo / number out of the PR URL.
if [[ ! "$url" =~ github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  echo "Not a GitHub PR URL: $url" >&2
  echo "Expected something like: https://github.com/OWNER/REPO/pull/123" >&2
  exit 1
fi
owner="${BASH_REMATCH[1]}"
repo="${BASH_REMATCH[2]}"
num="${BASH_REMATCH[3]}"
slug="$owner/$repo"

# Read the original PR's base branch + title through your existing gh login.
read -r base_ref orig_title < <(
  gh pr view "$num" --repo "$slug" --json baseRefName,title \
     --jq '[.baseRefName, .title] | @tsv'
)

# Disposable clone in a temp dir, deleted on ANY exit (success, error, Ctrl-C).
tmp="$(mktemp -d -t pr-backtest-XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
g() { git -C "$tmp/repo" "$@"; }

# Blobless, no-checkout clone: the commit graph only — no file contents, no
# working tree. Auth comes from your normal git credential helper. Because we
# push back to the same origin we cloned from, the remote already has every
# object, so the missing blobs are never needed.
git clone --no-checkout --filter=blob:none \
  "https://github.com/$slug.git" "$tmp/repo"

# Fetch the PR head (the pull ref works even for fork PRs) and the base tip.
g fetch origin "refs/pull/${num}/head"
pr_head="$(g rev-parse FETCH_HEAD)"
g fetch origin "$base_ref"

# The base is ALWAYS the PR's merge-base (its branch point), so the backtest's
# diff matches the original PR's no matter how the base branch has moved since.
base_sha="$(g merge-base "$pr_head" FETCH_HEAD)"

# Head: the PR tip by default, or a cutoff commit if one was given. The PR's own
# commits, oldest-first, are exactly `base_sha..pr_head`.
if [[ -n "$at_sha" ]]; then
  # Resolve the cutoff against the PR's own commits (prefix match).
  hits=()
  while IFS= read -r c; do hits+=("$c"); done \
    < <(g rev-list "${base_sha}..${pr_head}" | grep -i "^${at_sha}")
  case "${#hits[@]}" in
    0) echo "${at_sha} is not a commit in PR #${num}." >&2; exit 1 ;;
    1) head_sha="${hits[0]}" ;;
    *) echo "${at_sha} is ambiguous (${#hits[@]} commits); use a longer SHA." >&2; exit 1 ;;
  esac
  scope_label="up to $(g rev-parse --short "$head_sha")"
else
  head_sha="$pr_head"
  scope_label="full PR"
fi

# Per-scope branch names (the short head SHA keeps a cutoff from colliding with
# the full-PR run of the same PR).
short="$(g rev-parse --short=12 "$head_sha")"
head_branch="backtest-pr${num}-${short}-head"
base_branch="backtest-pr${num}-${short}-base"

# Push both commits by SHA. No checkout; your working tree / current branch are
# never touched.
g push origin \
  "$head_sha:refs/heads/$head_branch" \
  "$base_sha:refs/heads/$base_branch"

# Open the backtest PR. "[backtest] " on the title lets your team see at a glance
# it's a replay and safe to ignore.
gh pr create --repo "$slug" \
  --head "$head_branch" --base "$base_branch" \
  --title "[backtest] $orig_title" \
  --body "Backtest of #${num} (${scope_label}) — recreated for PR-review-bot testing. Safe to ignore."
