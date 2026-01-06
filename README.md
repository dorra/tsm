# tsm

Minimal TUI for tmux session management. Pure Ruby, zero dependencies.

```
  tsm · v1.5.2 · [2 servers]

  ── local ──────────────────────────
  ❯ ● project-a               3w    now
    ○ dotfiles                 1w     3d

  ── prod [main] ────────────────────
    ● api-workers              3w     5m

  ↑↓ nav  attach  new  detach  ⌫ del  config  quit
```

## Features

- List sessions sorted by last activity
- Create, attach, delete sessions
- Visual indicators for attached sessions
- **Multi-server support** - manage sessions across SSH servers
- **Server configuration sync** - bidirectional sync with main server
- Auto-update check (once per day)
- Self-installing with shell config

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/dorra/tsm/main/tsm -o tsm && chmod +x tsm && ./tsm
```

On first run, tsm will ask to install itself to `~/.local/bin` and configure your shell PATH.

### Manual install

```bash
./tsm --install
```

## Usage

```
tsm                 Start TUI
tsm --install       Install to ~/.local/bin
tsm --update        Update from GitHub
tsm --check         Check for updates
tsm --version       Show version
tsm --help          Show help
```

## Keybindings

### Main View

| Key | Action |
|-----|--------|
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `a` / `Enter` | Attach to session |
| `n` | New session (on current server) |
| `d` | Detach clients from session |
| `Backspace` | Delete session |
| `c` | Open server config |
| `u` | Update (when available) |
| `q` | Quit |

### Server Config (c)

| Key | Action |
|-----|--------|
| `a` | Add server |
| `Backspace` | Remove server |
| `m` | Set as main server |
| `y` | Sync config with main |
| `q` | Back |

## Server Configuration

Servers are stored in `~/.config/tsm/servers`:

```
# alias|host|user|port|is_main
local|||22|false
prod|prod.example.com|deploy|22|true
staging|staging.example.com|deploy|2222|false
```

### Sync

With a main server set, use `y` in server management to:
- **Push** local config to main server
- **Pull** config from main server

This enables sharing server configurations across machines.

## Configuration

Optional config file: `~/.config/tsm/config`

```
update_url=https://raw.githubusercontent.com/dorra/tsm/main/tsm
```

## Requirements

- Ruby (tested with 2.7+)
- tmux
- SSH keys configured for remote servers (no password prompts)

## License

MIT
