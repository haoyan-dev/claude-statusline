# claude-statusline

Configure your Claude Code statusline to show limits, directory and git info

![demo](./.github/demo.png)

## Install

Run the command below to set it up

```bash
npx @kamranahmedse/claude-statusline
```

It backups your old status line if any and copies the status line script to `~/.claude/statusline.sh` (or `statusline.ps1` on Windows) and configures your Claude Code settings. Platform detection is automatic — use the same `npx` command on all platforms.

## Requirements

- [jq](https://jqlang.github.io/jq/) — for parsing JSON
- curl — for fetching rate limit data
- git — for branch info

On macOS:

```bash
brew install jq
```

On Windows (PowerShell 7+ required):

```
winget install jqlang.jq
winget install Git.Git
winget install Microsoft.PowerShell
```

After installing, restart your terminal so `jq`, `git`, and `pwsh` are available on PATH.

## Uninstall

```bash
npx @kamranahmedse/claude-statusline --uninstall
```

If you had a previous statusline, it restores it from the backup. Otherwise it removes the script and cleans up your settings.

## License

MIT
