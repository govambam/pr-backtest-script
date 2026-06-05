#!/usr/bin/env bash
# pr-backtest.sh — recreate a GitHub PR's exact diff as a fresh PR in the same
# repo, so a PR-review bot reviews it as if it were brand new.
#
# No install, no token. It uses the git + gh login you already have, and runs
# from anywhere: all work happens in a disposable temp clone, so none of your
# own repos or checkouts are ever touched.
#
#   ./pr-backtest.sh <pr-url> [title]
#
# Examples:
#   ./pr-backtest.sh https://github.com/acme/api/pull/123
#   ./pr-backtest.sh https://github.com/acme/api/pull/123 "[backtest] ignore — bot test"
#
# Requirements:
#   - git
#   - the GitHub CLI (gh), authenticated:  gh auth login
#
# What it does NOT do (use the full CLI for these — see the README):
#   - replay a PR "as it was originally opened" (this recreates the full PR)
#   - write into a separate sandbox repo / keep the source read-only
#   - scoped or two-token auth for repos you don't own

set -euo pipefail

url="${1:-}"
if [[ -z "$url" ]]; then
  echo "usage: pr-backtest.sh <pr-url> [title]" >&2
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

# Title: second arg wins; otherwise prepend "[backtest] " so your team can see
# at a glance that the PR is a replay and safe to ignore.
title="${2:-[backtest] $orig_title}"
head_branch="backtest-pr${num}-head"
base_branch="backtest-pr${num}-base"

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
head_sha="$(g rev-parse FETCH_HEAD)"
g fetch origin "$base_ref"

# The merge-base is the commit the PR actually branched from. Pinning the base
# branch here — instead of opening against the live base — makes the backtest's
# diff identical to the original PR's, no matter how the base has moved since.
base_sha="$(g merge-base "$head_sha" FETCH_HEAD)"

# Push both commits by SHA. No checkout; your working tree / current branch are
# never touched.
g push origin \
  "$head_sha:refs/heads/$head_branch" \
  "$base_sha:refs/heads/$base_branch"

# Open the backtest PR.
gh pr create --repo "$slug" \
  --head "$head_branch" --base "$base_branch" \
  --title "$title" \
  --body "Backtest of #${num} — recreated for PR-review-bot testing. Safe to ignore."
