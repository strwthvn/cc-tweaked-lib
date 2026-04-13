-- mining.lua -- strip-mining and cuboid excavation algorithms

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

--- Check interrupts and resources, return action or nil
local function check_all(state, callbacks)
    if callbacks.check_interrupt then
        local action = callbacks.check_interrupt(state)
        if action == "stop" then return "stop" end
        if action == "pause" then
            while true do
                os.sleep(1)
                local a = callbacks.check_interrupt(state)
                if a ~= "pause" then break end
            end
        end
        if action == "go_home" then return "go_home" end
    end
    if callbacks.base_pos then
        if fuel.is_low(state, callbacks.base_pos) then
            return "fuel_low"
        end
        if inventory.is_full() then
            return "inventory_full"
        end
    end
    return nil
end

--- Dig a branch of given length, then return back
--- Returns the number of blocks actually dug
local function dig_branch(state, length, tunnels)
    local dug = 0
    for i = 1, length do
        if not dig_forward_2high(state) then break end
        local key = state.x .. "," .. state.y .. "," .. state.z
        tunnels[key] = true
        dug = dug + 1
    end
    -- Turn 180 and go back
    position.turnRight(state)
    position.turnRight(state)
    for i = 1, dug do
        if not position.forward(state) then
            -- Path back blocked unexpectedly, try digging
            position.dig()
            if not position.forward(state) then
                break -- truly stuck, position is desynced
            end
        end
    end
    -- Turn back to original direction
    position.turnRight(state)
    position.turnRight(state)
    return dug
end

--- Execute a strip-mine task
--- task_params: { start={x,z}, end_={x,z}, y, branch_spacing, branch_length, direction }
--- callbacks: { on_save, check_interrupt, base_pos }
function mining.execute_strip_mine(state, task_params, tunnels, callbacks)
    local p = task_params
    local spacing = p.branch_spacing or 3
    local branch_len = p.branch_length or 16
    local y = p.y or 11

    local dir_map = { N = 2, S = 0, E = 3, W = 1 }
    local main_facing = dir_map[p.direction] or 2

    local is_ns = (p.direction == "N" or p.direction == "S")

    local tunnel_start, tunnel_end
    if is_ns then
        tunnel_start = math.min(p.start.x, p.end_.x)
        tunnel_end = math.max(p.start.x, p.end_.x)
    else
        tunnel_start = math.min(p.start.z, p.end_.z)
        tunnel_end = math.max(p.start.z, p.end_.z)
    end

    local main_length
    if is_ns then
        main_length = math.abs(p.start.z - p.end_.z)
    else
        main_length = math.abs(p.start.x - p.end_.x)
    end

    for t_pos = tunnel_start, tunnel_end, spacing do
        local sx, sz
        if is_ns then
            sx = t_pos
            sz = (p.direction == "N") and math.max(p.start.z, p.end_.z) or math.min(p.start.z, p.end_.z)
        else
            sz = t_pos
            sx = (p.direction == "W") and math.max(p.start.x, p.end_.x) or math.min(p.start.x, p.end_.x)
        end

        local tunnel_key = sx .. "," .. y .. "," .. sz
        if not tunnels[tunnel_key] then
            local ok, err = nav.go_to(state, sx, y, sz)
            if not ok then return "stuck" end
            nav.turn_to(state, main_facing)

            local branch_counter = 0
            for step = 1, main_length do
                local action = check_all(state, callbacks)
                if action == "stop" then return "stopped" end
                if action == "go_home" then return "recalled" end
                if action == "fuel_low" then return "fuel_low" end
                if action == "inventory_full" then return "inventory_full" end

                if not dig_forward_2high(state) then
                    break
                end

                local key = state.x .. "," .. state.y .. "," .. state.z
                tunnels[key] = true

                branch_counter = branch_counter + 1
                if branch_counter >= spacing then
                    branch_counter = 0

                    -- Branch left (perpendicular)
                    position.turnLeft(state)
                    dig_branch(state, branch_len, tunnels)
                    position.turnRight(state) -- restore main facing

                    -- Branch right (perpendicular)
                    position.turnRight(state)
                    dig_branch(state, branch_len, tunnels)
                    position.turnLeft(state) -- restore main facing
                end

                if callbacks.on_save then callbacks.on_save() end
            end

            tunnels[tunnel_key] = true
            if callbacks.on_save then callbacks.on_save() end
        end
    end

    return "done"
end

--- Execute cuboid excavation (dig everything between two corners)
--- params: { x1, y1, z1, x2, y2, z2 } (normalized: x1<=x2, y1<=y2, z1<=z2)
--- callbacks: { on_save, check_interrupt, base_pos }
function mining.execute_cuboid(state, params, tunnels, callbacks)
    local x1, y1, z1 = params.x1, params.y1, params.z1
    local x2, y2, z2 = params.x2, params.y2, params.z2

    local z_forward = true -- alternates per X row for serpentine

    for y = y2, y1, -1 do
        -- Reset serpentine for each layer
        z_forward = true

        for x = x1, x2 do
            local action = check_all(state, callbacks)
            if action == "stop" then return "stopped" end
            if action == "go_home" then return "recalled" end
            if action == "fuel_low" then return "fuel_low" end
            if action == "inventory_full" then return "inventory_full" end

            -- Navigate to start of this row
            local rz_start = z_forward and z1 or z2
            local rz_face  = z_forward and 0 or 2 -- S(+Z) or N(-Z)

            local ok, err = nav.go_to(state, x, y, rz_start)
            if not ok then
                -- Try going up and retrying
                position.up(state)
                ok, err = nav.go_to(state, x, y, rz_start)
                if not ok then return "stuck" end
            end

            -- Dig along Z row
            nav.turn_to(state, rz_face)
            local row_len = math.abs(z2 - z1)

            -- Dig at starting position
            position.digUp()
            position.digDown()
            tunnels[state.x .. "," .. state.y .. "," .. state.z] = true

            for step = 1, row_len do
                position.dig()
                position.digUp()
                position.digDown()
                if not position.forward(state) then break end
                tunnels[state.x .. "," .. state.y .. "," .. state.z] = true
            end

            z_forward = not z_forward
            if callbacks.on_save then callbacks.on_save() end
        end
    end

    return "done"
end

return mining
