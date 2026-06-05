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

usage() {
  echo "usage: pr-backtest.sh <pr-url> [commit]" >&2
}

# Parse a GitHub PR URL into a tab-separated "owner<TAB>repo<TAB>number", or
# return 1 if it is not a github.com PR URL. Anchored so a lookalike host
# (notgithub.com, github.com.evil.com) is rejected rather than misparsed.
parse_pr_url() {
  [[ "$1" =~ ^https?://github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]] || return 1
  printf '%s\t%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
}

# True when the argument is a syntactically valid (possibly abbreviated) SHA.
# Keeps user input out of the cutoff grep as anything other than a hex prefix.
is_sha() {
  [[ "$1" =~ ^[0-9a-fA-F]{4,40}$ ]]
}

main() {
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
  esac

  local url="${1:-}"
  local at_sha="${2:-}"
  if [[ -z "$url" ]]; then
    usage
    exit 1
  fi

  local parsed
  if ! parsed="$(parse_pr_url "$url")"; then
    echo "Not a GitHub PR URL: $url" >&2
    echo "Expected something like: https://github.com/OWNER/REPO/pull/123" >&2
    exit 1
  fi
  local owner repo num
  IFS=$'\t' read -r owner repo num <<<"$parsed"
  local slug="$owner/$repo"

  if [[ -n "$at_sha" ]] && ! is_sha "$at_sha"; then
    echo "Not a commit SHA: $at_sha (expected 4–40 hex characters)." >&2
    exit 1
  fi

  # Read the original PR's base branch + title through your existing gh login.
  local base_ref orig_title
  read -r base_ref orig_title < <(
    gh pr view "$num" --repo "$slug" --json baseRefName,title \
       --jq '[.baseRefName, .title] | @tsv'
  )

  # Disposable clone in a temp dir, deleted on ANY exit (success, error, Ctrl-C).
  # The positional mktemp template is honored on both GNU and BSD/macOS; the
  # `-t` form is not, so it is avoided.
  local tmpbase tmp
  tmpbase="${TMPDIR:-/tmp}"
  tmp="$(mktemp -d "${tmpbase%/}/pr-backtest-XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT INT TERM
  g() { git -C "$tmp/repo" "$@"; }

  # Blobless, no-checkout clone: the commit graph only — no file contents, no
  # working tree. Auth comes from your normal git credential helper. Because we
  # push back to the same origin we cloned from, the remote already has every
  # object, so the missing blobs are never needed.
  git clone --no-checkout --filter=blob:none \
    "https://github.com/$slug.git" "$tmp/repo"

  # Fetch the PR head (the pull ref works even for fork PRs) and the base tip.
  g fetch origin "refs/pull/${num}/head"
  local pr_head
  pr_head="$(g rev-parse FETCH_HEAD)"
  g fetch origin "$base_ref"

  # The base is ALWAYS the PR's merge-base (its branch point), so the backtest's
  # diff matches the original PR's no matter how the base branch has moved since.
  local base_sha
  base_sha="$(g merge-base "$pr_head" FETCH_HEAD)"

  # Head: the PR tip by default, or a cutoff commit if one was given. The PR's
  # own commits, oldest-first, are exactly `base_sha..pr_head`.
  local head_sha scope_label
  if [[ -n "$at_sha" ]]; then
    local hits=()
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
  local short head_branch base_branch
  short="$(g rev-parse --short=12 "$head_sha")"
  head_branch="backtest-pr${num}-${short}-head"
  base_branch="backtest-pr${num}-${short}-base"

  # Push both commits by SHA. No checkout; your working tree / current branch are
  # never touched.
  g push origin \
    "$head_sha:refs/heads/$head_branch" \
    "$base_sha:refs/heads/$base_branch"

  # Open the backtest PR. "[backtest] " on the title lets your team see at a
  # glance it's a replay and safe to ignore. If a backtest PR already exists for
  # this exact scope (a re-run), point at it instead of failing on gh's error.
  local out
  if out="$(gh pr create --repo "$slug" \
        --head "$head_branch" --base "$base_branch" \
        --title "[backtest] $orig_title" \
        --body "Backtest of #${num} (${scope_label}) — recreated for PR-review-bot testing. Safe to ignore.")"; then
    echo "$out"
  else
    local existing
    existing="$(gh pr list --repo "$slug" --head "$head_branch" --json url --jq '.[0].url' 2>/dev/null || true)"
    if [[ -n "$existing" ]]; then
      echo "Backtest PR already exists:" >&2
      echo "$existing"
      exit 0
    fi
    exit 1
  fi
}

# Run only when executed directly, so test/run.sh can source the helpers above
# without triggering a real backtest.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
