# maki-goal-plugin

Long-running goal management plugin for [maki](https://github.com/gabvee/maki). Provides persistent objectives with lifecycle management, multi-goal support, Sisyphus mode (ordered sequential execution), intent drafting flows, a recursive task breakdown system, verification contracts, and a unified settings system.

Ported from [pi](https://pi.dev) plugins [pi-goal](https://github.com/capyup/pi-goal) and [pi-goal-x](https://github.com/tmonk/pi-goal-x).

## Features

- **Agent tools** for goal lifecycle: create, read, update (complete, pause, resume, abort, tweak), list, focus, archive
- **Task list system** with recursive subtasks and verification contracts
- **User commands** for interactive control: `/goal-set`, `/goal-list`, `/goal-pause`, `/goal-resume`, `/goal-abort`, `/goal-clear`, `/goal-tweak`, `/goal-tasks`, `/goal-settings`
- **Sisyphus mode** for ordered sequential execution without preflight steps
- **Intent drafting** via `/goals` and `/sisyphus` commands for goal definition before committing
- **Persistent storage** -- goals survive across maki sessions
- **Status line hint** showing the focused goal
- **Keybinding** -- `Ctrl+G` to toggle the goal list picker, `Ctrl+Shift+G` to show task list
- **Autocmds** -- refreshes goal state on turn end and session reset
- **Unified settings** -- per-goal completion auditing, deferred archival, immutable objectives
- **Verification contracts** -- per-goal and per-task acceptance criteria
- **Enhanced completion auditor** with per-goal toggle
- **Immutable objective enforcement** -- prevents accidental objective drift
- **Deferred archival** -- goals marked complete stay visible until explicitly archived

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
| `propose_task_list` | Propose a task breakdown for the focused goal |
| `complete_task` | Mark a task complete with optional evidence |
| `skip_task` | Mark a task skipped with a reason |

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
| `/goal-tasks` | Show task list for focused goal |
| `/goal-settings` | View and toggle plugin settings |

### Keybindings

| Key | Action |
|-----|--------|
| `Ctrl+G` | Toggle goal list picker (normal mode) |
| `Ctrl+Shift+G` | Show task list for focused goal (normal mode) |

## Storage

Goals are stored in the maki state directory:

```
~/.local/state/maki/goals/
  active/          # Active goals (JSON files)
  archived/        # Archived goals (JSON files)
  focus.json       # Current focus state
```

## Configuration

Plugin settings are stored in `~/.local/state/maki/goals/settings.json`. Fields:

| Field | Type | Description |
|-------|------|-------------|
| `completion_auditor_enabled` | boolean | Enable the completion auditor globally (default: `true`) |
| `deferred_archival` | boolean | Keep completed goals visible instead of auto-archiving (default: `true`) |
| `immutable_objectives` | boolean | Prevent goal objectives from being modified after creation (default: `true`) |

Use `/goal-settings` to view and toggle these values interactively.

## Task System

Goals can be broken down into ordered, hierarchical task lists. The agent uses `propose_task_list` to generate a task breakdown for the focused goal. Tasks support:

- **Recursive subtasks** -- any task can have its own nested subtasks, enabling deep decomposition
- **Verification contracts** -- each task can define acceptance criteria that must be satisfied before it is marked complete
- **Evidence** -- `complete_task` accepts optional evidence to justify completion

Tasks are managed through three agent tools:

| Tool | Description |
|------|-------------|
| `propose_task_list` | Propose a task breakdown for the focused goal |
| `complete_task` | Mark a task complete with optional evidence |
| `skip_task` | Mark a task skipped with a reason |

Users can view the current task list with `/goal-tasks` or `Ctrl+Shift+G`.

## Verification Contracts

Verification contracts define acceptance criteria at two levels:

- **Per-goal contracts** -- criteria the entire goal must satisfy before it can be marked complete
- **Per-task contracts** -- criteria each individual task must satisfy before it can be marked complete

Contracts are checked by the completion auditor when a goal or task is marked complete. If the auditor is enabled (globally via settings, or per-goal via `goal_update`), the agent must provide sufficient evidence that all contract criteria are met. This prevents premature or incomplete goal/task closure.

## License

Same as maki (MIT).
