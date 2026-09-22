# swiftbar-gitlab-threads

A macOS menu bar counter for the GitLab review threads still waiting on you.

CodeRabbit and colleagues leave review comments on your merge requests. GitLab
only notifies you when someone mentions you, so unresolved threads pile up
unseen. This plugin keeps the count in the menu bar and lets you jump straight
to any thread.

```
🔀 6
─────────────────────────────────────────
🐰 34  ·  👤 1
─────────────────────────────────────────
platform  (16)
  design-system
  !17 (16) Update tokens for dark mode    ▸
─────────────────────────────────────────
clients / acme  (4)
  Acme Backend
  !119 (1) Reduce Sentry event volume     ▸
  Acme Mobile
  !422 (3) Fix ANR crash rate             ▸
─────────────────────────────────────────
Last check at 15:25:52 (12s ago)
Refresh now
```

The menu bar shows how many merge requests need attention. The dropdown groups
them by GitLab group and project, and each merge request expands into its
unresolved threads, previewed and linked to the exact comment anchor.

## Install

```bash
brew install --cask swiftbar
brew install glab jq
glab auth login --hostname gitlab.example.com

git clone https://github.com/OwnWeb/swiftbar-gitlab-threads.git
ln -s "$PWD/swiftbar-gitlab-threads/gitlab-threads.1m.sh" ~/.swiftbar/gitlab-threads.1m.sh
```

On first launch SwiftBar asks for a plugin folder: point it at `~/.swiftbar`.

## Configuration

Self-hosted instances need one line of configuration:

```bash
mkdir -p ~/.config
echo 'GITLAB_HOST=gitlab.example.com' > ~/.config/swiftbar-gitlab-threads.conf
```

| Variable | Default | Purpose |
| --- | --- | --- |
| `GITLAB_HOST` | `glab config get host` | GitLab instance, must match the host you ran `glab auth login` against |
| `BOT_AUTHOR` | `coderabbitai` | Username counted as a bot in the `🐰` / `👤` split |

The config file is sourced by the plugin, so environment variables work too.

## How it works

`glab` runs one GraphQL query for your open merge requests and their
discussions, keeping the threads that are resolvable and still unresolved. Each
thread is attributed to whoever commented last: if that is you, the ball is in
someone else's court, but the thread still counts as open.

Rendering never blocks. The script prints a cached menu in about 40ms and
fetches in the background when the cache is older than 30 seconds, so opening
the menu is instant even though the query takes a few seconds. A failed check
leaves the last known state in place and adds a red line with the time and the
cause.

## Requirements

macOS, [SwiftBar](https://github.com/swiftbar/SwiftBar),
[glab](https://gitlab.com/gitlab-org/cli), jq.

## License

MIT
