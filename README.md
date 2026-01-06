# tsm

Minimal TUI for tmux session management. Pure Ruby, zero dependencies.

```
  tsm · v1.3.0

  ❯ ● project-a                3w    now
    ○ server                   1w     2h
    ○ dotfiles                 1w     3d

  ↑↓nav  ⏎attach  new  Detach  ⌫del  remote  Servers  quit
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
| `Enter` | Attach to session |
| `n` | New session (local only) |
| `D` | Detach clients from session |
| `Backspace` | Delete session |
| `r` | Toggle remote mode (fetch all servers) |
| `S` | Open server management |
| `u` | Update (when available) |
| `q` | Quit / back to local |

### Server Management (S)

| Key | Action |
|-----|--------|
| `a` | Add server |
| `Backspace` | Remove server |
| `m` | Set as main server |
| `y` | Sync config with main |
| `q` | Back |

## Remote Mode

Press `r` to fetch sessions from all configured servers:

```
  tsm · v1.3.0 · [3 servers]

  ── local ──────────────────────────
  ❯ ● my-project               5w    2m
    ○ dotfiles                 1w   12h

  ── prod [main] ────────────────────
    ● api-workers              3w    5m

  ── staging ────────────────────────
    ⚠ Connection failed

  ↑↓nav  ⏎attach  Detach  ⌫del  rlocal  Servers  quit
```

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
