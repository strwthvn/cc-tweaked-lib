-- dispatch.lua -- mining coordination dispatcher
-- Usage: dispatch

local registry = require("lib.registry")
local tasks    = require("lib.tasks")
local mined    = require("lib.mined_areas")
local protocol = require("lib.protocol")
local ui       = require("lib.ui")

-- ========== Constants ==========

-- Base coordinates (chest for dropping resources)
-- CONFIGURE FOR YOUR WORLD:
local BASE_POS = { x = 0, y = 64, z = 0 }

-- ========== Return queue ==========

local return_queue = {}    -- ordered list of turtle IDs waiting to return
local active_return = nil  -- turtle ID currently returning (or nil)

-- Forward declaration
local process_queue

--- Add turtle to return queue
local function queue_return(turtle_id, reason)
    -- Don't add if already in queue or actively returning
    if active_return == turtle_id then return end
    for _, id in ipairs(return_queue) do
        if id == turtle_id then return end
    end
    return_queue[#return_queue + 1] = turtle_id
    print("[Q] Turtle #" .. turtle_id .. " queued (" .. (reason or "?") .. "), pos " .. #return_queue)
    process_queue()
end

--- Process queue: grant return to first turtle if none active
process_queue = function()
    if active_return then return end
    if #return_queue == 0 then return end

    local tid = table.remove(return_queue, 1)
    active_return = tid

    -- Assign lane 0 (exclusive access, no collision possible)
    protocol.send(tid, "return_granted", { lane = 0 })
    print("[>] Turtle #" .. tid .. " granted return (queue: " .. #return_queue .. " left)")
end

--- Turtle finished returning
local function complete_return(turtle_id)
    if active_return == turtle_id then
        active_return = nil
        print("[<] Turtle #" .. turtle_id .. " return complete")
        process_queue()
    end
end

--- Recall all turtles with unique lanes (no queue, parallel return)
local function recall_all()
    local online = registry.get_online_ids()
    for i, tid in ipairs(online) do
        protocol.send(tid, "recall", { reason = "manual", lane = i - 1 })
    end
    print("[!] Recall all: " .. #online .. " turtles, each with unique lane")
end

--- Recall single turtle with dedicated lane
local function recall_one(tid)
    -- Give it lane 0 through the queue system
    queue_return(tid, "manual")
end

-- ========== Message handling ==========

local function handle_message(sender_id, msg)
    local t = msg.type
    local p = msg.payload or {}

    if t == "register" then
        registry.register(sender_id, p)
        protocol.send(sender_id, "register_ack", {
            base_pos = BASE_POS,
        })
        print("[+] Turtle #" .. sender_id .. " registered")

    elseif t == "heartbeat" then
        registry.update_heartbeat(sender_id, p)

    elseif t == "request_return" then
        queue_return(sender_id, p.reason)

    elseif t == "return_complete" then
        complete_return(sender_id)

    elseif t == "task_done" then
        local task_id = p.task_id
        if task_id then
            tasks.mark_turtle_done(task_id, sender_id)
            registry.clear_task(sender_id)
            local task = tasks.get(task_id)
            if task and task.status == "done" then
                mined.add_completed_task(task_id)
                print("[v] Task #" .. task_id .. " fully completed!")
            else
                print("[v] Turtle #" .. sender_id .. " finished its part of task #" .. task_id)
            end
        end

    elseif t == "ack" then
        -- Acknowledgements from turtles

    elseif t == "status_report" then
        local turtle_rec = registry.get(sender_id)
        if turtle_rec then
            if p.status == "lost" then
                print("[!] Turtle #" .. sender_id .. " LOST: " .. (p.detail or ""))
                -- Remove from queue if stuck
                if active_return == sender_id then
                    active_return = nil
                    process_queue()
                end
            end
        end
    end
end

-- ========== Main loops ==========

local function loop_network()
    while true do
        local id, msg = protocol.receive(1)
        if id and msg then
            handle_message(id, msg)
        end
        registry.check_timeouts(30)
    end
end

local function loop_ui()
    ui.set_base_pos(BASE_POS)
    ui.set_recall_functions(recall_all, recall_one)
    ui.loop()
end

-- ========== Entry point ==========

local function main()
    print("=== Mining Dispatcher v1.0 ===")
    print("ID: " .. os.getComputerID())
    print("Base: " .. BASE_POS.x .. ", " .. BASE_POS.y .. ", " .. BASE_POS.z)

    -- Open modem
    rednet.open("right")

    -- Load data
    registry.load()
    tasks.load()
    mined.load()

    print("Loaded turtles: " .. registry.count_all())
    print("Starting...")
    print()

    -- Start parallel loops
    parallel.waitForAny(loop_network, loop_ui)

    -- Save before exit
    registry.save()
    tasks.save()
    mined.save()

    print("Dispatcher stopped.")
end

main()
