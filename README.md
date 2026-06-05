# pr-backtest-script

Recreate a GitHub pull request as a fresh PR in the same repo, so a PR-review bot reviews it as if it were brand new. No install, no token — it uses the `git` and [`gh`](https://cli.github.com) login you already have.

## Use it

```bash
curl -fsSL https://raw.githubusercontent.com/govambam/pr-backtest-script/main/pr-backtest.sh -o pr-backtest.sh
chmod +x pr-backtest.sh

./pr-backtest.sh https://github.com/OWNER/REPO/pull/123
```

It pushes two branches, opens a PR between them titled `[backtest] <original title>`, and prints the new PR's URL.

By default it recreates the **whole PR**. To replay it at an earlier point in time:

```bash
# only the commits that existed when the PR was opened (drop later pushes)
./pr-backtest.sh <pr-url> --as-opened

# cut off at a specific commit (recreate up to and including it)
./pr-backtest.sh <pr-url> --at a1b2c3d
```

**Requirements:** `git`, the GitHub CLI ([`gh`](https://cli.github.com)) authenticated with `gh auth login`, and write access to the repo.

## When to use the CLI instead

This script writes the backtest into the **PR's own repo**, using your existing GitHub login. The full [pr-backtest CLI](https://github.com/govambam/pr-backtest) adds the one thing this can't: it can land the backtest in a separate **sandbox repo** and read the source through a **scoped, read-only token**, so backtesting a repo you don't own can't write to it even by accident. Reach for it when you need that isolation — otherwise this script does the job.

## License

MIT
