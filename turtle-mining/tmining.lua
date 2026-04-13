-- tmining.lua -- mining turtle program
-- Usage: tmining <x> <y> <z> <N|E|S|W>

local position  = require("lib.position")
local nav       = require("lib.nav")
local mining    = require("lib.mining")
local fuel      = require("lib.fuel")
local inventory = require("lib.inventory")
local persist   = require("lib.persist")
local protocol  = require("lib.protocol")

-- ========== Global state ==========

local state        -- position { x, y, z, facing }
local base_pos     -- base coordinates (from dispatcher)
local dispatch_id  -- dispatcher ID
local current_task -- current task
local tunnels      -- mined tunnels table { ["x,y,z"] = true }
local status       -- "idle" | "mining" | "returning" | "waiting_return" | "paused" | "stopped" | "lost"
local interrupt    -- nil | "stop" | "pause" | "go_home"
local work_pos     -- work position (for return after base trip)
local my_lane      -- assigned flight lane for safe navigation
local return_granted_flag = false -- set by network loop when return is granted

-- ========== Argument parsing ==========

local args = { ... }

local function print_usage()
    print("Usage: tmining <x> <y> <z> <N|E|S|W>")
    print("Example: tmining 1430 68 -600 N")
end

local function init_from_args()
    if #args < 4 then
        local saved = persist.load()
        if saved then
            state = saved.pos
            current_task = saved.task
            tunnels = saved.tunnels_mined or {}
            dispatch_id = saved.dispatch_id
            base_pos = saved.base_pos
            status = "idle"
            print("Restored from save: " .. position.to_string(state))
            return true
        end
        print_usage()
        return false
    end

    local x = tonumber(args[1])
    local y = tonumber(args[2])
    local z = tonumber(args[3])
    local dir = string.upper(args[4])

    if not x or not y or not z then
        print("Error: coordinates must be numbers")
        print_usage()
        return false
    end

    if not position.STR_TO_DIR[dir] then
        print("Error: direction must be N, E, S or W")
        print_usage()
        return false
    end

    state = position.new(x, y, z, position.STR_TO_DIR[dir])
    tunnels = {}
    status = "idle"
    print("Start: " .. position.to_string(state))
    return true
end

-- ========== State saving ==========

local function save_state()
    persist.save({
        version = 1,
        pos = state,
        task = current_task,
        tunnels_mined = tunnels,
        dispatch_id = dispatch_id,
        base_pos = base_pos,
    })
end

-- ========== Notify dispatcher ==========

local function notify_dispatch(msg_type, payload)
    if dispatch_id then
        protocol.send(dispatch_id, msg_type, payload)
    end
end

-- ========== Dispatcher registration ==========

local function register_with_dispatch()
    print("Searching for dispatcher...")
    for attempt = 1, 3 do
        protocol.broadcast("register", {
            pos = state,
            fuel = fuel.level(),
            slots_used = inventory.slots_used(),
        })

        local id, msg = protocol.receive(5)
        if id and msg.type == "register_ack" then
            dispatch_id = id
            base_pos = msg.payload.base_pos
            save_state()
            print("Dispatcher found: ID " .. id)
            print("Base: " .. base_pos.x .. ", " .. base_pos.y .. ", " .. base_pos.z)
            return true
        end
        print("  attempt " .. attempt .. "/3...")
    end
    print("Dispatcher not found. Working autonomously.")
    return false
end

-- ========== Incoming message handling ==========

local function handle_message(sender_id, msg)
    local t = msg.type
    local p = msg.payload or {}

    if t == "register_ack" then
        dispatch_id = sender_id
        base_pos = p.base_pos
        save_state()

    elseif t == "command" then
        local action = p.action
        if action == "stop" then
            interrupt = "stop"
            status = "stopped"
        elseif action == "pause" then
            interrupt = "pause"
            status = "paused"
        elseif action == "resume" then
            interrupt = nil
            status = current_task and "mining" or "idle"
        elseif action == "go_home" then
            my_lane = 0
            interrupt = "go_home"
            protocol.send(sender_id, "ack", {
                ref_type = "command", ok = true, msg = status,
            })
        elseif action == "report" then
            protocol.send(sender_id, "ack", {
                ref_type = "command", ok = true, msg = status,
            })
        elseif action == "repos" and p.args then
            state.x = p.args.x
            state.y = p.args.y
            state.z = p.args.z
            if p.args.facing then
                state.facing = p.args.facing
            end
            status = "idle"
            interrupt = nil
            current_task = nil
            save_state()
            print("Position reset to: " .. position.to_string(state))
            protocol.send(sender_id, "ack", {
                ref_type = "command", ok = true,
                msg = "repos ok: " .. position.to_string(state),
            })
        elseif action == "go_to" and p.args then
            interrupt = "stop"
            os.sleep(0.1)
            local ok, err = nav.go_to(state, p.args.x, p.args.y, p.args.z)
            save_state()
            protocol.send(sender_id, "ack", {
                ref_type = "command",
                ok = ok,
                msg = ok and "arrived" or ("stuck: " .. tostring(err) .. " at " .. position.to_string(state)),
            })
            if not ok then
                status = "lost"
            end
        end

    elseif t == "task_assign" then
        current_task = p
        status = "mining"
        interrupt = nil
        save_state()
        protocol.send(sender_id, "ack", {
            ref_type = "task_assign",
            ok = true,
            msg = "accepted",
        })

    elseif t == "return_granted" then
        -- Dispatcher granted us permission to return
        my_lane = p.lane or 0
        return_granted_flag = true
        print("Return granted, lane " .. my_lane)

    elseif t == "recall" then
        -- Only set flags, loop_mining handles the actual movement
        my_lane = p.lane or 0
        interrupt = "go_home"
    end
end

-- ========== Request return from dispatcher ==========

--- Request permission to return to base. Waits for grant.
--- Returns true + lane, or false if no dispatcher / timeout
local function request_return(reason)
    if not dispatch_id then
        -- No dispatcher, return immediately on lane 0
        return true, 0
    end

    -- Send request
    return_granted_flag = false
    notify_dispatch("request_return", {
        reason = reason,
        pos = state,
    })

    status = "waiting_return"
    print("Waiting for return permission (" .. reason .. ")...")

    -- Wait for grant (up to 60 seconds, keep listening)
    for wait = 1, 60 do
        -- Check if grant arrived (set by handle_message via loop_network)
        if return_granted_flag then
            return_granted_flag = false
            return true, my_lane or 0
        end
        os.sleep(1)
    end

    -- Timeout: return anyway on fallback lane based on ID
    print("Return permission timeout, going anyway")
    return true, os.getComputerID() % 10
end

-- ========== Return to base ==========

local function return_to_base(reason)
    if not base_pos then return false end
    local old_status = status
    work_pos = position.copy(state)

    -- Request permission (queued return for inventory/fuel)
    local granted, lane
    if reason == "recalled" then
        -- Already got lane from recall message
        lane = my_lane or 0
        granted = true
    else
        granted, lane = request_return(reason)
    end

    if not granted then
        status = old_status
        return false
    end

    status = "returning"
    print("Returning to base: " .. reason .. " (lane " .. lane .. ")")

    -- Use safe navigation with unique lane
    local ok, err = nav.go_to_safe(state, base_pos.x, base_pos.y, base_pos.z, lane)

    if not ok then
        print("STUCK at " .. position.to_string(state) .. ": " .. tostring(err))
        status = "lost"
        notify_dispatch("status_report", {
            status = "lost",
            detail = "stuck going home: " .. tostring(err),
            pos = state,
        })
        save_state()
        return false
    end

    if not nav.arrived(state, base_pos.x, base_pos.y, base_pos.z) then
        print("NAV ERROR: expected base but at " .. position.to_string(state))
        status = "lost"
        notify_dispatch("status_report", {
            status = "lost",
            detail = "position mismatch after nav",
            pos = state,
        })
        save_state()
        return false
    end

    print("Arrived at base")

    if reason == "inventory_full" then
        inventory.drop_all_forward()
    end
    fuel.try_refuel()

    -- Notify dispatcher that return is complete
    notify_dispatch("return_complete", {})

    -- Return to work
    if old_status == "mining" and work_pos and interrupt ~= "go_home" and interrupt ~= "stop" then
        print("Returning to work (lane " .. lane .. ")...")
        local ok2, err2 = nav.go_to_safe(state, work_pos.x, work_pos.y, work_pos.z, lane)
        if not ok2 then
            print("STUCK returning to work: " .. tostring(err2))
            status = "lost"
            notify_dispatch("status_report", {
                status = "lost",
                detail = "stuck returning to work: " .. tostring(err2),
                pos = state,
            })
            save_state()
            return false
        end
        status = "mining"
    else
        status = "idle"
    end
    save_state()
    return true
end

-- ========== Main loops ==========

local function loop_network()
    while true do
        local id, msg = protocol.receive(1)
        if id and msg then
            handle_message(id, msg)
        end
    end
end

local function loop_heartbeat()
    while true do
        if dispatch_id then
            protocol.send(dispatch_id, "heartbeat", {
                pos = state,
                fuel = fuel.level(),
                status = status,
                task_id = current_task and current_task.task_id or nil,
            })
        end
        os.sleep(5)
    end
end

local function loop_mining()
    while true do
        if status == "lost" then
            os.sleep(2)

        elseif interrupt == "go_home" then
            -- Handle go_home in ANY state (idle, mining, paused, stopped)
            interrupt = nil
            return_to_base("recalled")
            if status ~= "lost" then
                current_task = nil
                status = "idle"
                save_state()
            end

        elseif current_task and status == "mining" then
            local check_interrupt = function(s)
                if base_pos and fuel.is_low(s, base_pos) then
                    return_to_base("fuel_low")
                end
                if inventory.is_full() then
                    return_to_base("inventory_full")
                end
                return interrupt
            end

            local result
            local cb = {
                on_save = save_state,
                check_interrupt = check_interrupt,
                base_pos = base_pos,
            }
            if current_task.type == "cuboid" then
                result = mining.execute_cuboid(state, current_task.params, tunnels, cb)
            else
                result = mining.execute_strip_mine(state, current_task.params, tunnels, cb)
            end

            if result == "done" then
                notify_dispatch("task_done", {
                    task_id = current_task.task_id,
                })
                print("Task #" .. current_task.task_id .. " completed!")
                current_task = nil
                status = "idle"
                save_state()

            elseif result == "fuel_low" then
                return_to_base("fuel_low")

            elseif result == "inventory_full" then
                return_to_base("inventory_full")

            elseif result == "recalled" then
                return_to_base("recalled")
                if status ~= "lost" then
                    current_task = nil
                    status = "idle"
                    save_state()
                end

            elseif result == "stopped" then
                status = "stopped"
            end
        else
            os.sleep(1)
        end
    end
end

-- ========== Entry point ==========

local function main()
    print("=== Mining Turtle v1.0 ===")
    print("ID: " .. os.getComputerID())

    if not init_from_args() then return end

    -- Open modem
    rednet.open("right")

    -- Set persist function for position
    position.set_persist(save_state)

    -- Save initial state
    save_state()

    -- Register with dispatcher
    register_with_dispatch()

    print("Fuel: " .. tostring(fuel.level()))
    print("Waiting for commands...")

    -- Start parallel loops
    parallel.waitForAny(loop_network, loop_mining, loop_heartbeat)
end

main()
