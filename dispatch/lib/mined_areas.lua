-- mined_areas.lua -- mined zones tracker

local mined = {}

local FILE = "/mined_areas.dat"
local data = {
    tunnels = {},         -- ["x,y,z"] = true
    completed_tasks = {}, -- [task_id] = true
}

--- Load
function mined.load()
    if not fs.exists(FILE) then return end
    local f = fs.open(FILE, "r")
    local d = textutils.unserialize(f.readAll())
    f.close()
    if d then data = d end
end

--- Save
function mined.save()
    local f = fs.open(FILE, "w")
    f.write(textutils.serialize(data))
    f.close()
end

--- Add completed task
function mined.add_completed_task(task_id)
    data.completed_tasks[task_id] = true
    mined.save()
end

--- Check if task is done
function mined.is_task_done(task_id)
    return data.completed_tasks[task_id] == true
end

--- Count completed tasks
function mined.count_tasks()
    local n = 0
    for _ in pairs(data.completed_tasks) do n = n + 1 end
    return n
end

--- Count recorded tunnels
function mined.count_tunnels()
    local n = 0
    for _ in pairs(data.tunnels) do n = n + 1 end
    return n
end

--- Get stats for display
function mined.get_stats()
    return {
        tunnels = mined.count_tunnels(),
        tasks = mined.count_tasks(),
    }
end

return mined
