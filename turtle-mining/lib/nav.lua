-- nav.lua -- navigation to target coordinates

local position = require("lib.position")

local nav = {}

-- Safe Y level for horizontal travel (above most obstacles)
nav.SAFE_Y = 80

--- Turn to the desired facing (shortest path)
function nav.turn_to(state, target_facing)
    if state.facing == target_facing then return end
    local delta = (target_facing - state.facing + 4) % 4
    if delta == 1 then
        position.turnRight(state)
    elseif delta == 2 then
        position.turnRight(state)
        position.turnRight(state)
    elseif delta == 3 then
        position.turnLeft(state)
    end
end

--- Move forward n blocks (with digging)
local function move_forward_n(state, n)
    for i = 1, n do
        if not position.forward(state) then
            return false, i - 1
        end
    end
    return true, n
end

--- Navigate to point (x, y, z) -- direct path with digging
function nav.go_to(state, tx, ty, tz)
    -- 1. Align Y
    while state.y < ty do
        if not position.up(state) then return false, "cant_go_up" end
    end
    while state.y > ty do
        if not position.down(state) then return false, "cant_go_down" end
    end

    -- 2. Align X
    if state.x ~= tx then
        local face = tx > state.x and 3 or 1 -- E or W
        nav.turn_to(state, face)
        local dist = math.abs(tx - state.x)
        local ok, moved = move_forward_n(state, dist)
        if not ok then return false, "blocked_x" end
    end

    -- 3. Align Z
    if state.z ~= tz then
        local face = tz > state.z and 0 or 2 -- S or N
        nav.turn_to(state, face)
        local dist = math.abs(tz - state.z)
        local ok, moved = move_forward_n(state, dist)
        if not ok then return false, "blocked_z" end
    end

    return true
end

--- Safe navigation: go up to safe Y, travel horizontally, descend to target
--- Use this for long-distance travel (e.g. going home) to avoid lava/bedrock
function nav.go_to_safe(state, tx, ty, tz)
    local safe_y = math.max(nav.SAFE_Y, state.y, ty)

    -- 1. Go up to safe height
    while state.y < safe_y do
        if not position.up(state) then
            -- Can't go higher, try traveling at current height
            break
        end
    end

    -- 2. Horizontal travel at safe height
    if state.x ~= tx then
        local face = tx > state.x and 3 or 1
        nav.turn_to(state, face)
        local dist = math.abs(tx - state.x)
        local ok = move_forward_n(state, dist)
        if not ok then return false, "blocked_x" end
    end

    if state.z ~= tz then
        local face = tz > state.z and 0 or 2
        nav.turn_to(state, face)
        local dist = math.abs(tz - state.z)
        local ok = move_forward_n(state, dist)
        if not ok then return false, "blocked_z" end
    end

    -- 3. Descend to target Y
    while state.y > ty do
        if not position.down(state) then return false, "cant_go_down" end
    end

    return true
end

--- Check if current position matches target
function nav.arrived(state, tx, ty, tz)
    return state.x == tx and state.y == ty and state.z == tz
end

return nav
