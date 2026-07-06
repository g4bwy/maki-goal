# maki-goal-plugin

Long-running goal management plugin for [maki](https://github.com/gabvee/maki). Provides persistent objectives with lifecycle management, multi-goal support, Sisyphus mode (ordered sequential execution), and intent drafting flows.

Ported from [pi](https://pi.dev) plugin [pi-goal](https://github.com/capyup/pi-goal)

## Features

- **Agent tools** for goal lifecycle: create, read, update (complete, pause, resume, abort, tweak), list, focus, archive
- **User commands** for interactive control: `/goal-set`, `/goal-list`, `/goal-pause`, `/goal-resume`, `/goal-abort`, `/goal-clear`, `/goal-tweak`
- **Sisyphus mode** for ordered sequential execution without preflight steps
- **Intent drafting** via `/goals` and `/sisyphus` commands for goal definition before committing
- **Persistent storage** -- goals survive across maki sessions
- **Status line hint** showing the focused goal
- **Keybinding** -- `Ctrl+G` to toggle the goal list picker
- **Autocmds** -- refreshes goal state on turn end and session reset

## Installation

1. Copy all `goal*.lua` files into your maki config `lua/` directory:

```bash
mkdir -p ~/.config/maki/lua
cp goal*.lua ~/.config/maki/lua/
```

2. Add `require("goal")` to your `~/.config/maki/init.lua`:

```lua
require("goal")
```

3. Create a `plugin.toml` in your config directory to grant filesystem permissions:

```toml
[permissions]
fs_read = true
fs_write = true
```

## Usage

### Agent tools

The plugin registers these tools that the LLM agent can call:

| Tool | Description |
|------|-------------|
| `goal_get` | Read the current goal state |
| `goal_set` | Create a new goal and focus it |
| `goal_update` | Update goal lifecycle (complete, pause, resume, abort, tweak) |
| `goal_list` | List all open goals |
| `goal_focus` | Switch focus to another goal |
| `goal_archive` | Archive a goal by ID or the focused goal |

### User commands

| Command | Description |
|---------|-------------|
| `/goal-set <objective>` | Create and start a regular goal |
| `/sisyphus-set <objective>` | Create and start a Sisyphus goal |
| `/goals <topic>` | Start drafting discussion for a goal |
| `/sisyphus <topic>` | Start drafting discussion for a Sisyphus goal |
| `/goal-status` | Show focused goal state |
| `/goal-list` | List all open goals |
| `/goal-focus` | Choose which goal to focus (interactive picker) |
| `/goal-pause` | Pause the focused goal |
| `/goal-resume` | Resume a paused goal |
| `/goal-abort` | Abort and archive the focused goal |
| `/goal-clear` | Clear and archive the focused goal |
| `/goal-tweak [hint]` | Start drafting to revise the current goal |

### Keybindings

| Key | Action |
|-----|--------|
| `Ctrl+G` | Toggle goal list picker (normal mode) |

## Storage

Goals are stored in the maki state directory:

```
~/.local/state/maki/goals/
  active/          # Active goals (JSON files)
  archived/        # Archived goals (JSON files)
  focus.json       # Current focus state
```

## License

Same as maki (MIT).
