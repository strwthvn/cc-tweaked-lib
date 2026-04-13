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
        -- Acknowledgements from turtles (can be logged)

    elseif t == "status_report" then
        local turtle = registry.get(sender_id)
        if turtle then
            if p.inventory_full then
                print("[!] Turtle #" .. sender_id .. ": inventory full")
            end
            if p.fuel_low then
                print("[!] Turtle #" .. sender_id .. ": fuel low")
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
        -- Check timeouts every cycle
        registry.check_timeouts(30)
    end
end

local function loop_ui()
    ui.set_base_pos(BASE_POS)
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
