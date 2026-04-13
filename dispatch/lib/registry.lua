-- registry.lua -- turtle registry

local registry = {}

local FILE = "/registry.dat"
local turtles = {} -- [id] = { id, pos, fuel, status, task_id, last_seen, slots_used }

--- Load registry from file
function registry.load()
    if not fs.exists(FILE) then return end
    local f = fs.open(FILE, "r")
    local data = textutils.unserialize(f.readAll())
    f.close()
    if data then
        turtles = data
        -- All loaded turtles are offline until heartbeat
        for id, t in pairs(turtles) do
            t.status = "offline"
        end
    end
end

--- Save registry
function registry.save()
    local f = fs.open(FILE, "w")
    f.write(textutils.serialize(turtles))
    f.close()
end

--- Register/update a turtle
function registry.register(id, payload)
    turtles[id] = {
        id        = id,
        pos       = payload.pos,
        fuel      = payload.fuel,
        status    = "idle",
        task_id   = nil,
        last_seen = os.clock(),
        slots_used = payload.slots_used or 0,
    }
    registry.save()
end

--- Update from heartbeat
function registry.update_heartbeat(id, payload)
    if not turtles[id] then
        registry.register(id, payload)
        return
    end
    local t = turtles[id]
    t.pos       = payload.pos
    t.fuel      = payload.fuel
    t.status    = payload.status or t.status
    t.task_id   = payload.task_id
    t.last_seen = os.clock()
end

--- Mark turtle offline if no heartbeat for too long
function registry.check_timeouts(timeout)
    timeout = timeout or 30
    local now = os.clock()
    for id, t in pairs(turtles) do
        if t.status ~= "offline" and (now - t.last_seen) > timeout then
            t.status = "offline"
        end
    end
end

--- Get turtle record
function registry.get(id)
    return turtles[id]
end

--- Get all records
function registry.get_all()
    return turtles
end

--- Get list of idle turtle IDs
function registry.get_idle_ids()
    local ids = {}
    for id, t in pairs(turtles) do
        if t.status == "idle" then
            ids[#ids + 1] = id
        end
    end
    return ids
end

--- Get list of all online turtle IDs
function registry.get_online_ids()
    local ids = {}
    for id, t in pairs(turtles) do
        if t.status ~= "offline" then
            ids[#ids + 1] = id
        end
    end
    return ids
end

--- Count online turtles
function registry.count_online()
    local n = 0
    for id, t in pairs(turtles) do
        if t.status ~= "offline" then n = n + 1 end
    end
    return n
end

--- Count all turtles
function registry.count_all()
    local n = 0
    for _ in pairs(turtles) do n = n + 1 end
    return n
end

--- Set task for turtle
function registry.set_task(id, task_id)
    if turtles[id] then
        turtles[id].task_id = task_id
        turtles[id].status = "mining"
        registry.save()
    end
end

--- Clear task for turtle
function registry.clear_task(id)
    if turtles[id] then
        turtles[id].task_id = nil
        turtles[id].status = "idle"
        registry.save()
    end
end

return registry
