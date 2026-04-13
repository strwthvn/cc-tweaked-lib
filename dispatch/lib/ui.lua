-- ui.lua -- dispatcher terminal interface

local registry = require("lib.registry")
local tasks    = require("lib.tasks")
local mined    = require("lib.mined_areas")
local protocol = require("lib.protocol")

local ui = {}

local BASE_POS -- set externally

function ui.set_base_pos(pos)
    BASE_POS = pos
end

local function dir_str(facing)
    local dirs = { [0] = "S", [1] = "W", [2] = "N", [3] = "E" }
    return dirs[facing] or "?"
end

--- Print header
local function print_header()
    term.clear()
    term.setCursorPos(1, 1)
    print("=== Mining Dispatcher v1.0 ===")
    print("ID: " .. os.getComputerID() .. "  Online: " .. registry.count_online() .. "/" .. registry.count_all())
    print("Base: " .. BASE_POS.x .. ", " .. BASE_POS.y .. ", " .. BASE_POS.z)
    print(string.rep("-", 40))
end

--- Print help
local function cmd_help()
    print("Commands:")
    print("  list                    - list turtles")
    print("  status <id>             - detailed status")
    print("  cmd <id> <action>       - send command")
    print("  home [id|all]           - recall home")
    print("  repos <id> <x> <y> <z> [N|E|S|W]")
    print("                          - reset turtle position")
    print("  task <x1> <z1> <x2> <z2> <y> [sp] [bl]")
    print("                          - create mining task")
    print("  assign <task> [id|auto] [N|E|S|W]")
    print("                          - assign task")
    print("  tasks                   - list tasks")
    print("  areas                   - mining stats")
    print("  help                    - this help")
    print("  quit                    - exit")
end

--- List turtles
local function cmd_list()
    local all = registry.get_all()
    local count = 0
    for id, t in pairs(all) do
        count = count + 1
        local pos_str = t.pos and (t.pos.x .. "," .. t.pos.y .. "," .. t.pos.z .. " " .. dir_str(t.pos.facing)) or "?"
        local task_str = t.task_id and (" task#" .. t.task_id) or ""
        print(string.format("  #%d [%s] fuel:%s %s%s",
            id, t.status or "?", tostring(t.fuel or "?"), pos_str, task_str))
    end
    if count == 0 then
        print("  No registered turtles")
    end
end

--- Detailed turtle status
local function cmd_status(id)
    id = tonumber(id)
    if not id then print("Error: specify turtle ID") return end
    local t = registry.get(id)
    if not t then print("Turtle #" .. id .. " not found") return end

    print("Turtle #" .. id)
    print("  Status:   " .. (t.status or "?"))
    if t.pos then
        print("  Position: " .. t.pos.x .. ", " .. t.pos.y .. ", " .. t.pos.z .. " " .. dir_str(t.pos.facing))
    end
    print("  Fuel:     " .. tostring(t.fuel or "?"))
    print("  Task:     " .. (t.task_id and ("#" .. t.task_id) or "none"))
    print("  Slots:    " .. tostring(t.slots_used or "?") .. "/16")
end

--- Send command to a specific turtle
local function cmd_send(id, action, args_str)
    id = tonumber(id)
    if not id then print("Error: specify turtle ID") return end
    if not action then print("Error: specify action") return end

    local cmd_args = nil
    if action == "go_to" and args_str then
        local parts = {}
        for w in args_str:gmatch("%S+") do parts[#parts + 1] = tonumber(w) end
        if #parts >= 3 then
            cmd_args = { x = parts[1], y = parts[2], z = parts[3] }
        end
    end

    protocol.send(id, "command", { action = action, args = cmd_args })
    print("Command '" .. action .. "' sent to turtle #" .. id)
end

--- Reset turtle position (for lost turtles)
local function cmd_repos(args_list)
    if #args_list < 4 then
        print("Usage: repos <id> <x> <y> <z> [N|E|S|W]")
        return
    end
    local id = tonumber(args_list[1])
    local x  = tonumber(args_list[2])
    local y  = tonumber(args_list[3])
    local z  = tonumber(args_list[4])
    local dir_str_val = args_list[5]

    if not (id and x and y and z) then
        print("Error: ID and coordinates must be numbers")
        return
    end

    local facing = nil
    if dir_str_val then
        local dir_map = { N = 2, S = 0, E = 3, W = 1 }
        facing = dir_map[string.upper(dir_str_val)]
    end

    protocol.send(id, "command", {
        action = "repos",
        args = { x = x, y = y, z = z, facing = facing },
    })
    print("Position reset sent to turtle #" .. id .. ": " .. x .. "," .. y .. "," .. z)
end

--- Recall home
local function cmd_home(target)
    if target == "all" or not target then
        protocol.broadcast("recall", { reason = "manual" })
        print("Broadcast: all turtles returning home")
    else
        local id = tonumber(target)
        if id then
            protocol.send(id, "recall", { reason = "manual" })
            print("Turtle #" .. id .. " returning home")
        else
            print("Error: specify ID or 'all'")
        end
    end
end

--- Create task
local function cmd_task(args_list)
    if #args_list < 5 then
        print("Usage: task <x1> <z1> <x2> <z2> <y> [spacing] [branch_len]")
        return
    end
    local x1 = tonumber(args_list[1])
    local z1 = tonumber(args_list[2])
    local x2 = tonumber(args_list[3])
    local z2 = tonumber(args_list[4])
    local y  = tonumber(args_list[5])
    local sp = tonumber(args_list[6]) or 3
    local bl = tonumber(args_list[7]) or 16

    if not (x1 and z1 and x2 and z2 and y) then
        print("Error: all coordinates must be numbers")
        return
    end

    local task = tasks.create_strip_mine(x1, z1, x2, z2, y, sp, bl)
    print("Task #" .. task.id .. " created")
    print("  Zone: " .. task.area.x1 .. "," .. task.area.z1 .. " -> " .. task.area.x2 .. "," .. task.area.z2)
    print("  Level Y: " .. y .. "  Spacing: " .. sp .. "  Branch len: " .. bl)
end

--- Assign task to turtles
local function cmd_assign(args_list)
    if #args_list < 1 then
        print("Usage: assign <task_id> [turtle_id|auto] [N|E|S|W]")
        return
    end

    local task_id = tonumber(args_list[1])
    if not task_id then print("Error: task ID must be a number") return end

    local task = tasks.get(task_id)
    if not task then print("Task #" .. task_id .. " not found") return end

    local direction = "N" -- default
    local turtle_ids = {}

    local target = args_list[2] or "auto"

    -- Check if last arg is a direction
    local last_arg = args_list[#args_list]
    if last_arg and (last_arg == "N" or last_arg == "S" or last_arg == "E" or last_arg == "W") then
        direction = last_arg
        if #args_list > 2 then
            target = args_list[2]
        end
    end

    if target == "auto" then
        turtle_ids = registry.get_idle_ids()
        if #turtle_ids == 0 then
            print("No idle turtles available")
            return
        end
    else
        local tid = tonumber(target)
        if tid then
            turtle_ids = { tid }
        else
            print("Error: specify turtle ID or 'auto'")
            return
        end
    end

    local assignments = tasks.split_for_turtles(task, turtle_ids, direction)

    for _, a in ipairs(assignments) do
        protocol.send(a.turtle_id, "task_assign", {
            task_id = task_id,
            type = task.type,
            params = a.params,
        })
        registry.set_task(a.turtle_id, task_id)
        print("  Turtle #" .. a.turtle_id .. " assigned")
    end

    print("Task #" .. task_id .. " assigned to " .. #assignments .. " turtles, direction " .. direction)
end

--- List tasks
local function cmd_tasks()
    local all = tasks.get_all()
    local count = 0
    for id, t in pairs(all) do
        count = count + 1
        local assigned_count = 0
        for _ in pairs(t.assigned) do assigned_count = assigned_count + 1 end
        print(string.format("  #%d [%s] %s zone:%d,%d->%d,%d y:%d turtles:%d",
            id, t.status, t.type,
            t.area.x1, t.area.z1, t.area.x2, t.area.z2,
            t.area.y, assigned_count))
    end
    if count == 0 then
        print("  No tasks")
    end
end

--- Mining stats
local function cmd_areas()
    local stats = mined.get_stats()
    print("Mining stats:")
    print("  Completed tasks: " .. stats.tasks)
    print("  Recorded tunnels: " .. stats.tunnels)
end

--- Process input line
function ui.handle_input(line)
    local parts = {}
    for w in line:gmatch("%S+") do parts[#parts + 1] = w end
    if #parts == 0 then return true end

    local cmd = parts[1]:lower()

    if cmd == "help" then
        cmd_help()
    elseif cmd == "list" then
        cmd_list()
    elseif cmd == "status" then
        cmd_status(parts[2])
    elseif cmd == "cmd" then
        local rest = ""
        for i = 4, #parts do rest = rest .. " " .. parts[i] end
        cmd_send(parts[2], parts[3], rest:sub(2))
    elseif cmd == "repos" then
        local repos_args = {}
        for i = 2, #parts do repos_args[#repos_args + 1] = parts[i] end
        cmd_repos(repos_args)
    elseif cmd == "home" then
        cmd_home(parts[2])
    elseif cmd == "task" then
        local task_args = {}
        for i = 2, #parts do task_args[#task_args + 1] = parts[i] end
        cmd_task(task_args)
    elseif cmd == "assign" then
        local assign_args = {}
        for i = 2, #parts do assign_args[#assign_args + 1] = parts[i] end
        cmd_assign(assign_args)
    elseif cmd == "tasks" then
        cmd_tasks()
    elseif cmd == "areas" then
        cmd_areas()
    elseif cmd == "quit" or cmd == "exit" then
        return false
    else
        print("Unknown command. Type 'help' for help.")
    end

    return true
end

--- Main UI loop
function ui.loop()
    print_header()
    cmd_help()
    print()

    while true do
        write("> ")
        local line = read()
        if not line then break end
        local ok = ui.handle_input(line)
        if not ok then break end
    end
end

return ui
