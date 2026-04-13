# CC:Tweaked Mining System

Coordinated mining system: dispatcher (computer) + mining turtles.

## Install

Delete old files first if updating:
```
delete tmining.lua
delete dispatch.lua
delete lib
```

### Turtle (mining turtle)
```
wget run https://raw.githubusercontent.com/strwthvn/cc-tweaked-lib/main/turtle-mining/install.lua
```
Run: `tmining <x> <y> <z> <N|E|S|W>`

### Computer (dispatcher)
```
wget run https://raw.githubusercontent.com/strwthvn/cc-tweaked-lib/main/dispatch/install.lua
```
Edit `BASE_POS` in `dispatch.lua`, then run: `dispatch`

## Dispatcher Commands

| Command | Description |
|---|---|
| `list` | List all turtles |
| `status <id>` | Detailed turtle status |
| `cmd <id> <action>` | Send command (stop/pause/resume/go_to) |
| `home [id\|all]` | Recall home |
| `repos <id> <x> <y> <z> [N\|E\|S\|W]` | Reset turtle position |
| `task <x1> <z1> <x2> <z2> <y> [spacing] [branch_len]` | Create strip mine task |
| `dig <x1> <y1> <z1> <x2> <y2> <z2>` | Create cuboid excavation |
| `assign <task_id> [id\|auto] [N\|E\|S\|W]` | Assign task to turtles |
| `tasks` | List all tasks |
| `areas` | Mining statistics |

## Requirements

- Wireless modem on RIGHT side (both turtle and computer)
- Chest at BASE_POS for item drops
- Fuel in chest or turtle inventory
