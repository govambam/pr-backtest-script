# pr-backtest-script

Recreate a GitHub pull request as a fresh PR in the same repo, so a PR-review bot reviews it as if it were brand new. No install, no token — it uses the `git` and [`gh`](https://cli.github.com) login you already have.

## Use it

```bash
curl -fsSL https://raw.githubusercontent.com/govambam/pr-backtest-script/main/pr-backtest.sh -o pr-backtest.sh
chmod +x pr-backtest.sh

./pr-backtest.sh https://github.com/OWNER/REPO/pull/123
```

It pushes two branches, opens a PR between them titled `[backtest] <original title>`, and prints the new PR's URL.

By default it recreates the **whole PR**. Pass a commit SHA from the PR to cut off there instead — the backtest spans the PR's base up to and including that commit:

```bash
./pr-backtest.sh https://github.com/OWNER/REPO/pull/123 a1b2c3d
```

**Requirements:** `git`, the GitHub CLI ([`gh`](https://cli.github.com)) authenticated with `gh auth login`, and write access to the repo.

## When to use the CLI instead

This script writes the backtest into the **PR's own repo**, using your existing GitHub login. Using the [pr-backtest CLI](https://github.com/govambam/pr-backtest) you can also:

- land the backtest in a separate **sandbox repo** and read the source through a **scoped, read-only token**, so backtesting a repo you don't own can't write to it even by accident;
- replay a PR **as it was originally opened**, automatically excluding commits pushed later during review.

## License

MIT
