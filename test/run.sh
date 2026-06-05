#!/usr/bin/env bash
# Offline unit tests for pr-backtest.sh's pure helpers. No network, no gh/git.
# Run:  ./test/run.sh
set -uo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
# Sourcing defines the helpers without running main() (guarded by BASH_SOURCE).
# shellcheck source=../pr-backtest.sh
source "$here/pr-backtest.sh"
set +e   # take flow back from the sourced `set -e`

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

# parse_pr_url: accepts valid PR URLs, yields "owner repo number".
expect_parse() { # url  expected
  local got
  if got="$(parse_pr_url "$1")"; then
    got="$(printf '%s' "$got" | tr '\t' ' ')"
    if [[ "$got" == "$2" ]]; then ok "parse $1"; else no "parse $1 -> '$got' (want '$2')"; fi
  else
    no "parse $1 (rejected, want '$2')"
  fi
}
expect_reject() { # url
  if parse_pr_url "$1" >/dev/null 2>&1; then no "reject $1 (accepted)"; else ok "reject $1"; fi
}

expect_parse "https://github.com/acme/api/pull/123"       "acme api 123"
expect_parse "http://github.com/a/b/pull/1"               "a b 1"
expect_parse "https://github.com/acme/api/pull/123/files" "acme api 123"
expect_reject "https://github.com/acme/api/pulls/123"     # not /pull/
expect_reject "https://gitlab.com/a/b/pull/1"             # wrong host
expect_reject "https://notgithub.com/a/b/pull/1"          # lookalike host
expect_reject "https://github.com.evil.com/a/b/pull/1"    # lookalike host
expect_reject "not a url"

# is_sha: accepts hex of 4-40 chars, rejects everything else.
for s in a1b2c3d ABCDEF1 0000000000000000000000000000000000000000; do
  if is_sha "$s"; then ok "is_sha $s"; else no "is_sha $s (rejected)"; fi
done
for s in "" "xyz123" "a.c1234" "../etc" "12 34" "g1b2c3d"; do
  if is_sha "$s"; then no "is_sha '$s' (accepted)"; else ok "not is_sha '$s'"; fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
