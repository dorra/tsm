# tsm

Minimal TUI for tmux session management. Pure Ruby, zero dependencies.

```
  tsm · v1.6.0 · [2 servers]

  local
  ❯ ● project-a                   now
    ○ dotfiles                     3d

  prod [main]
    ● api-workers                  5m

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
tsm                      Start TUI
tsm <server>             List sessions on server
tsm <server> <session>   Attach or create session
```

### Examples

```bash
tsm local                # List local sessions
tsm local dev            # Attach/create local 'dev'
tsm spacestation         # List sessions on spacestation
tsm spacestation api     # Attach/create 'api' on spacestation
```

### Options

```
tsm --install       Install to ~/.local/bin
tsm --update        Update local + all remote servers
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
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `a` | Add server |
| `Backspace` | Remove server |
| `m` | Set as main server |
| `s` | Sync config with main |
| `b` | Back |

## Server Configuration

When adding a new server, tsm is automatically installed on it and receives the current config.

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

### Update

`tsm --update` updates tsm locally and on all configured remote servers:

```
✓ Update erfolgreich!
  v1.7.8 → v1.7.9

Remote Server Updates

  prod... → v1.7.9
  staging... aktuell
  offline... fehlgeschlagen
```

Errors on individual servers don't stop the update process.

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
