# claude-statusline

Configure your Claude Code statusline to show limits, directory and git info

![demo](./.github/demo.png)

## What it shows

- **Model** — active Claude model name
- **Context** — visual progress bar and percentage of context window used
- **Directory & branch** — current folder and git branch
- **Session duration** — how long the current session has been running
- **Effort level** — the effort setting configured in Claude Code (low / medium / high)
- **Rate limits** — 5-hour and 7-day usage windows with reset times; extra budget if enabled
- **Skip-permissions indicator** — ⚡ shown when running with `--dangerously-skip-permissions`

## Install

Run the command below to set it up

```bash
npx @kamranahmedse/claude-statusline
```

It backs up your old statusline if any and copies the statusline script to `~/.claude/statusline.sh` (or `statusline.ps1` on Windows) and configures your Claude Code settings. Platform detection is automatic — use the same `npx` command on all platforms.

## Requirements

### All platforms

| Tool | Version | Purpose |
|------|---------|---------|
| Node.js | 18+ | required to run `npx` |
| jq | any stable | JSON parsing |
| curl | any | fetching rate-limit data |
| git | any | branch info |

### macOS

Install missing tools with Homebrew:

```bash
brew install jq
```

No other prerequisites — the built-in `security` command handles token retrieval.

### Windows

PowerShell 7.0+ (`pwsh`) is required. Windows PowerShell 5.x (`powershell.exe`) is **not** supported.

```
winget install jqlang.jq
winget install Git.Git
winget install Microsoft.PowerShell
```

After installing, restart your terminal so `jq`, `git`, and `pwsh` are on PATH.

If script execution is blocked, allow it for the current user:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Linux

No extra requirements beyond the all-platforms list above. Optionally install `secret-tool` (libsecret) for secure token storage:

```bash
# Debian / Ubuntu
sudo apt install libsecret-tools
```

## Uninstall

```bash
npx @kamranahmedse/claude-statusline --uninstall
```

If you had a previous statusline, it restores it from the backup. Otherwise it removes the script and cleans up your settings.

## License

MIT
