# tsm

Minimal TUI for tmux session management. Pure Ruby, zero dependencies.

```
  tsm · v1.1.0

  ❯ ● project-a               3w    now
    ○ server                   1w     2h
    ○ dotfiles                 1w     3d

  ↑↓nav  ⏎attach  new  del  quit
```

## Features

- List sessions sorted by last activity
- Create, attach, delete sessions
- Visual indicators for attached sessions
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

| Key | Action |
|-----|--------|
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `Enter` | Attach to session |
| `n` | New session |
| `d` | Delete session |
| `u` | Update (when available) |
| `q` | Quit |

## Configuration

Optional config file: `~/.config/tsm/config`

```
update_url=https://raw.githubusercontent.com/dorra/tsm/main/tsm
```

## Requirements

- Ruby (tested with 2.7+)
- tmux

## License

MIT
