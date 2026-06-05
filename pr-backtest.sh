#!/usr/bin/env bash
# pr-backtest.sh — recreate a GitHub PR's diff as a fresh PR in the same repo,
# so a PR-review bot reviews it as if it were brand new.
#
# No install, no token. It uses the git + gh login you already have, and runs
# from anywhere: all work happens in a disposable temp clone, so none of your
# own repos or checkouts are ever touched.
#
#   ./pr-backtest.sh <pr-url> [scope]
#
# Scope (default: the full PR):
#   (none)          recreate the whole PR — every commit
#   --as-opened     only the commits that existed when the PR was opened
#                   (drops anything pushed later during review)
#   --at <commit>   cut off at a specific commit (up to and including it)
#
# Examples:
#   ./pr-backtest.sh https://github.com/acme/api/pull/123
#   ./pr-backtest.sh https://github.com/acme/api/pull/123 --as-opened
#   ./pr-backtest.sh https://github.com/acme/api/pull/123 --at a1b2c3d
#
# Requirements:
#   - git
#   - the GitHub CLI (gh), authenticated:  gh auth login
#   - write access to the repo (it pushes two branches and opens a PR there)

set -euo pipefail

usage() { echo "usage: pr-backtest.sh <pr-url> [--as-opened | --at <commit>]" >&2; }

url=""
mode="full"
at_sha=""
while (( $# )); do
  case "$1" in
    --full)      mode="full" ;;
    --as-opened) mode="as-opened" ;;
    --at)        shift; at_sha="${1:-}"; mode="at"
                 [[ -n "$at_sha" ]] || { echo "--at needs a commit SHA" >&2; exit 1; } ;;
    --at=*)      at_sha="${1#--at=}"; mode="at" ;;
    -h|--help)   usage; exit 0 ;;
    -*)          echo "unknown option: $1" >&2; usage; exit 1 ;;
    *)           if [[ -z "$url" ]]; then url="$1"
                 else echo "unexpected argument: $1" >&2; usage; exit 1; fi ;;
  esac
  shift
done
[[ -n "$url" ]] || { usage; exit 1; }

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

# Pick the head commit for the chosen scope. The PR's own commits, oldest-first,
# are exactly `base_sha..pr_head`.
scope_label="full PR"
case "$mode" in
  full)
    head_sha="$pr_head"
    ;;

  at)
    # Resolve the cutoff against the PR's own commits (prefix match, like the CLI).
    hits=()
    while IFS= read -r c; do hits+=("$c"); done \
      < <(g rev-list "${base_sha}..${pr_head}" | grep -i "^${at_sha}")
    case "${#hits[@]}" in
      0) echo "--at ${at_sha} is not a commit in PR #${num}." >&2; exit 1 ;;
      1) head_sha="${hits[0]}" ;;
      *) echo "--at ${at_sha} is ambiguous (${#hits[@]} commits); use a longer SHA." >&2; exit 1 ;;
    esac
    scope_label="cutoff at $(g rev-parse --short "$head_sha")"
    ;;

  as-opened)
    # The PR "as opened": every commit dated at or before the PR's open time,
    # dropping anything pushed later. Same heuristic the CLI uses (committer date
    # vs the PR's createdAt). gh's built-in jq turns the timestamp into epoch
    # seconds; git reports each commit's committer date the same way (%ct).
    t="$(gh pr view "$num" --repo "$slug" --json createdAt --jq '.createdAt | fromdateiso8601')"
    head_sha="$pr_head"          # default: nothing was pushed after open
    scope_label="as opened"
    prev=""
    while IFS= read -r c; do
      ct="$(g show -s --format=%ct "$c")"
      if (( ct > t )); then
        if [[ -n "$prev" ]]; then
          head_sha="$prev"       # last commit at or before open time
        else
          # Even the first commit post-dates the open: the branch was rebased /
          # force-pushed after opening, so the as-opened set is unrecoverable.
          head_sha="$pr_head"
          scope_label="full PR (as-opened unavailable — branch rewritten after open)"
          echo "Note: this PR's branch was rewritten after it was opened; the" >&2
          echo "      'as opened' state can't be recovered — recreating the full PR." >&2
        fi
        break
      fi
      prev="$c"
    done < <(g rev-list --reverse "${base_sha}..${pr_head}")
    ;;
esac

# Per-scope branch names (the short head SHA keeps different scopes of the same
# PR from colliding).
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
