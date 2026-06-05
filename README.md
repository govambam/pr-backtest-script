# pr-backtest-script

Recreate a GitHub pull request as a fresh PR in the same repo, so a PR-review bot reviews it as if it were brand new. No install, no token — it uses the `git` and [`gh`](https://cli.github.com) login you already have.

## Use it

```bash
curl -fsSL https://raw.githubusercontent.com/govambam/pr-backtest-script/main/pr-backtest.sh -o pr-backtest.sh
chmod +x pr-backtest.sh

./pr-backtest.sh https://github.com/OWNER/REPO/pull/123
```

It pushes two branches (`backtest-pr<N>-base` and `backtest-pr<N>-head`), opens a PR between them titled `[backtest] <original title>`, and prints the new PR's URL.

**Requirements:** `git`, the GitHub CLI ([`gh`](https://cli.github.com)) authenticated once with `gh auth login`, and write access to the repo.

## When to use the CLI instead

This script recreates the **full PR** in the **PR's own repo**. Use the full [pr-backtest CLI](https://github.com/govambam/pr-backtest) when you need to:

- backtest a repo you don't own without writing to it — it lands the PR in a separate **sandbox** repo and only ever reads the source;
- replay a PR **as it was originally opened**, excluding commits pushed later during review.

## License

MIT
