# tsm

Minimal TUI for tmux session management. Pure Ruby, zero dependencies.

```
  tsm · v1.6.0 · [2 servers]

  local
  ❯ ● project-a                   now
    ○ dotfiles                     3d

  prod
    ● api-workers                  5m

  ↑↓ nav  attach  new  detach  ⌫ del  config  quit
```

## Features

- List sessions sorted by last activity
- Create, attach, delete sessions
- Visual indicators for attached sessions
- **Multi-server support** - manage sessions across SSH servers
- **Server configuration sync** - automatic via a central storage service
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
| `b` | Back |

## Server Configuration

When adding a new server, tsm is automatically installed on it and receives the current config.

Servers are stored in `~/.config/tsm/servers`:

```
# alias|host|user|port|machine_id
laptop|laptop.example.com|deploy|22|a5ed2efe-b7e0-4e8b-8728-2f1162fe227c
prod|prod.example.com|deploy|22|0cfd1ae9-6f9a-4679-9f31-6e4cfc8e948e
staging|staging.example.com|deploy|2222|
```

Each machine identifies its own entry via its machine-id
(`~/.config/tsm/machine-id`). Old 6-column files (with an `is_main` column)
are migrated automatically.

### Sync

With `storage_url` and `storage_token` configured (see below), the server
list syncs automatically across all installations:

- On TUI start, tsm pulls the shared list from the storage service.
- Every change (add/remove server) pushes the list immediately.
- Last write wins; sync failures never block the TUI.

Without those keys, tsm simply runs locally. The current sync state is shown
in the server config view (`c`). When you add a new server, tsm installs
itself there and hands over the storage credentials, so the new machine
joins the sync automatically.

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
storage_url=https://storage.example.com
storage_token=tnt_...
```

`storage_url`/`storage_token` point to a
[storage-for-agents](https://github.com/dorra/storage-for-agents) instance
and enable automatic config sync across machines.

## Troubleshooting

### tmux scrolling feels buggy / mouse wheel doesn’t scroll

If you’re seeing weird scrolling behavior in tmux, enable mouse support:

1) Open `~/.tmux.conf`
2) Add:

```tmux
set -g mouse on
```

3) Save and restart tmux.

## Requirements

- Ruby (tested with 2.7+)
- tmux
- SSH keys configured for remote servers (no password prompts)

## License

MIT
