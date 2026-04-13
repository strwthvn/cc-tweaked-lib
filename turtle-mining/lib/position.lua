-- position.lua -- position tracking and movement wrappers
-- Directions (Minecraft): 0=S(+Z), 1=W(-X), 2=N(-Z), 3=E(+X)

local position = {}

position.DIR_TO_STR = { [0] = "S", [1] = "W", [2] = "N", [3] = "E" }
position.STR_TO_DIR = { S = 0, W = 1, N = 2, E = 3 }

-- Forward movement deltas by facing
local FORWARD_DELTA = {
    [0] = { x = 0, z = 1 },  -- S
    [1] = { x = -1, z = 0 }, -- W
    [2] = { x = 0, z = -1 }, -- N
    [3] = { x = 1, z = 0 },  -- E
}

--- Create a new position state
function position.new(x, y, z, facing)
    return { x = x, y = y, z = z, facing = facing }
end

--- Copy position
function position.copy(state)
    return { x = state.x, y = state.y, z = state.z, facing = state.facing }
end

--- Manhattan distance
function position.distance(a, b)
    return math.abs(a.x - b.x) + math.abs(a.y - b.y) + math.abs(a.z - b.z)
end

--- String representation
function position.to_string(state)
    return string.format("%d, %d, %d %s", state.x, state.y, state.z,
        position.DIR_TO_STR[state.facing] or "?")
end

-- Movement wrappers: return true/false, update state
-- persist_fn is called after each successful movement

local _persist_fn = nil

function position.set_persist(fn)
    _persist_fn = fn
end

local function _save()
    if _persist_fn then _persist_fn() end
end

--- Try to move forward with retry (digs blocks, waits for gravel/sand)
function position.forward(state)
    for attempt = 1, 5 do
        local ok, err = turtle.forward()
        if ok then
            local d = FORWARD_DELTA[state.facing]
            state.x = state.x + d.x
            state.z = state.z + d.z
            _save()
            return true
        end
        turtle.dig()
        os.sleep(0.4)
    end
    return false, "blocked"
end

function position.back(state)
    local ok, err = turtle.back()
    if ok then
        local d = FORWARD_DELTA[state.facing]
        state.x = state.x - d.x
        state.z = state.z - d.z
        _save()
        return true
    end
    return false, err
end

function position.up(state)
    for attempt = 1, 5 do
        local ok, err = turtle.up()
        if ok then
            state.y = state.y + 1
            _save()
            return true
        end
        turtle.digUp()
        os.sleep(0.4)
    end
    return false, "blocked"
end

function position.down(state)
    for attempt = 1, 5 do
        local ok, err = turtle.down()
        if ok then
            state.y = state.y - 1
            _save()
            return true
        end
        turtle.digDown()
        os.sleep(0.4)
    end
    return false, "blocked"
end

function position.turnLeft(state)
    turtle.turnLeft()
    state.facing = (state.facing - 1 + 4) % 4 -- counterclockwise
    _save()
    return true
end

function position.turnRight(state)
    turtle.turnRight()
    state.facing = (state.facing + 1) % 4 -- clockwise
    _save()
    return true
end

--- Dig forward (no movement)
function position.dig()
    return turtle.dig()
end

function position.digUp()
    return turtle.digUp()
end

function position.digDown()
    return turtle.digDown()
end

return position
