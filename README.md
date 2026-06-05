# pr-backtest-script

One shell script that recreates a GitHub pull request as a **fresh PR in the same repo**, so a PR-review bot reviews it as if it were brand new. No install, no token — it uses the `git` and `gh` login you already have.

**Why:** backtest a PR-review bot against history. Take a PR whose outcome you already know, replay its diff at a new PR, and see how your bot does on a "brand new" PR.

If you need more than the quick path — replaying a PR **as it was originally opened**, writing into a **separate sandbox repo** so the source is never touched, **scoped/two-token** auth for repos you don't own, cutting off at a specific commit, or non-interactive CI runs — use the full CLI: **[pr-backtest](https://github.com/govambam/pr-backtest)**.

## Requirements

- `git`
- the [GitHub CLI](https://cli.github.com) (`gh`), authenticated once with `gh auth login`

You need write access to the repo (it pushes two branches and opens a PR there).

## Quickstart

```bash
curl -fsSL https://raw.githubusercontent.com/govambam/pr-backtest-script/main/pr-backtest.sh -o pr-backtest.sh
chmod +x pr-backtest.sh

./pr-backtest.sh https://github.com/OWNER/REPO/pull/123
```

It prints the new PR's URL when it's done.

### Custom title

By default the backtest PR's title is the original title with `[backtest] ` prepended, so your team can see at a glance it's a replay and safe to ignore. Pass a second argument to override it:

```bash
./pr-backtest.sh https://github.com/OWNER/REPO/pull/123 "[backtest] ignore — review-bot test"
```

## How it works

A PR is really just a diff between two commits: where the branch started (the **merge-base**) and where it ended (the PR **head**). The script recreates exactly those two endpoints as new branches and opens a PR between them.

1. **Read the PR.** `gh` looks up the PR's base branch and title using your existing login.
2. **Disposable clone.** It makes a blobless, no-checkout clone in a temp directory (`git clone --no-checkout --filter=blob:none`) — the commit graph only, no file contents, no working tree. It's deleted on exit no matter what, so none of your own repos or checkouts are touched. This is why you can run it from anywhere.
3. **Fetch the endpoints.** It fetches the PR head via the `refs/pull/N/head` ref (which works even when the PR came from a fork) and the tip of the base branch.
4. **Compute the merge-base.** `git merge-base` finds the commit the PR actually branched from. Pinning the new base branch *here* — rather than opening against the live base branch — is the key step: it makes the backtest's diff **identical** to the original PR's, no matter how the base branch has moved since the PR was opened.
5. **Push two branches.** It pushes both commits straight to `backtest-pr<N>-head` and `backtest-pr<N>-base` by SHA — no checkout, nothing of yours touched.
6. **Open the PR.** `gh pr create` opens `backtest-pr<N>-head` → `backtest-pr<N>-base`.

Because the clone is pushed back to the same origin it came from, the remote already has every object — so the blobs the blobless clone skipped are never needed, and even a huge repo clones in seconds.

## Scope & limits

This is deliberately the simplest possible version. It:

- recreates the **full PR** (every commit), not just the commits that existed when the PR was opened;
- writes into the PR's **own repo** (it does not isolate the source in a sandbox);
- assumes you have **write access** and a working `gh` login.

For any of those, reach for the full **[pr-backtest CLI](https://github.com/govambam/pr-backtest)**.

## Connecting a review bot

Whatever PR-review bot you use (e.g. [Macroscope](https://app.macroscope.com)) reviews the backtest PR like any other once the bot's GitHub app has access to the repo. If reviews don't fire automatically, trigger one by commenting on the backtest PR per your bot's convention — for Macroscope:

```
@macroscope-app review
```

## License

MIT
