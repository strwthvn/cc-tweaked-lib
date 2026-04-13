-- mining.lua -- strip-mining algorithm

local position  = require("lib.position")
local nav       = require("lib.nav")
local fuel      = require("lib.fuel")
local inventory = require("lib.inventory")

local mining = {}

--- Dig forward 1x2 (two blocks high) and advance
local function dig_forward_2high(state)
    position.dig()
    position.digUp()
    return position.forward(state)
end

--- Dig a branch of given length, then return back
local function dig_branch(state, length, tunnels)
    for i = 1, length do
        if not dig_forward_2high(state) then break end
        local key = state.x .. "," .. state.y .. "," .. state.z
        tunnels[key] = true
    end
    -- Turn 180 and go back
    position.turnRight(state)
    position.turnRight(state)
    for i = 1, length do
        position.forward(state)
    end
    -- Turn back to original direction
    position.turnRight(state)
    position.turnRight(state)
end

--- Execute a strip-mine task
--- task_params: { start={x,z}, end_={x,z}, y, branch_spacing, branch_length, direction }
--- callbacks: { on_save, check_interrupt, base_pos }
function mining.execute_strip_mine(state, task_params, tunnels, callbacks)
    local p = task_params
    local spacing = p.branch_spacing or 3
    local branch_len = p.branch_length or 16
    local y = p.y or 11

    -- Determine main tunnel axis and direction
    local dir_map = { N = 2, S = 0, E = 3, W = 1 }
    local main_facing = dir_map[p.direction] or 2 -- default north

    -- Determine perpendicular axis for tunnel placement
    local is_ns = (p.direction == "N" or p.direction == "S")

    local tunnel_start, tunnel_end
    if is_ns then
        -- Main tunnel along Z, tunnels placed along X
        tunnel_start = math.min(p.start.x, p.end_.x)
        tunnel_end = math.max(p.start.x, p.end_.x)
    else
        -- Main tunnel along X, tunnels placed along Z
        tunnel_start = math.min(p.start.z, p.end_.z)
        tunnel_end = math.max(p.start.z, p.end_.z)
    end

    -- Main tunnel length
    local main_length
    if is_ns then
        main_length = math.abs(p.start.z - p.end_.z)
    else
        main_length = math.abs(p.start.x - p.end_.x)
    end

    -- Iterate over tunnel positions
    for t_pos = tunnel_start, tunnel_end, spacing do
        -- Starting position of this tunnel
        local sx, sz
        if is_ns then
            sx = t_pos
            sz = (p.direction == "N") and math.max(p.start.z, p.end_.z) or math.min(p.start.z, p.end_.z)
        else
            sz = t_pos
            sx = (p.direction == "W") and math.max(p.start.x, p.end_.x) or math.min(p.start.x, p.end_.x)
        end

        local tunnel_key = sx .. "," .. y .. "," .. sz
        if tunnels[tunnel_key] then
            -- Tunnel already mined, skip
        else
            -- Navigate to tunnel start
            nav.go_to(state, sx, y, sz)
            nav.turn_to(state, main_facing)

            -- Dig main tunnel
            local branch_counter = 0
            for step = 1, main_length do
                -- Check for interrupts (commands, fuel, inventory)
                if callbacks.check_interrupt then
                    local action = callbacks.check_interrupt(state)
                    if action == "stop" then return "stopped" end
                    if action == "pause" then
                        while true do
                            os.sleep(1)
                            local a = callbacks.check_interrupt(state)
                            if a ~= "pause" then break end
                        end
                    end
                    if action == "go_home" then return "recalled" end
                end

                -- Check fuel and inventory
                if callbacks.base_pos then
                    if fuel.is_low(state, callbacks.base_pos) then
                        return "fuel_low"
                    end
                    if inventory.is_full() then
                        return "inventory_full"
                    end
                end

                if not dig_forward_2high(state) then
                    break -- impassable block
                end

                local key = state.x .. "," .. state.y .. "," .. state.z
                tunnels[key] = true

                branch_counter = branch_counter + 1
                if branch_counter >= spacing then
                    branch_counter = 0
                    -- Branch left
                    position.turnLeft(state)
                    dig_branch(state, branch_len, tunnels)
                    -- Branch right
                    position.turnRight(state)
                    dig_branch(state, branch_len, tunnels)
                    -- Restore main tunnel direction
                    position.turnLeft(state)
                end

                if callbacks.on_save then callbacks.on_save() end
            end

            -- Mark tunnel as completed
            tunnels[tunnel_key] = true
            if callbacks.on_save then callbacks.on_save() end
        end
    end

    return "done"
end

return mining
