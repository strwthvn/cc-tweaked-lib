-- tasks.lua -- task manager and zone splitting

local tasks = {}

local FILE = "/tasks.dat"
local task_list = {} -- [id] = task
local next_id = 1

--- Load tasks
function tasks.load()
    if not fs.exists(FILE) then return end
    local f = fs.open(FILE, "r")
    local data = textutils.unserialize(f.readAll())
    f.close()
    if data then
        task_list = data.tasks or {}
        next_id = data.next_id or 1
    end
end

--- Save tasks
function tasks.save()
    local f = fs.open(FILE, "w")
    f.write(textutils.serialize({ tasks = task_list, next_id = next_id }))
    f.close()
end

--- Create a strip_mine task
---@param x1 number
---@param z1 number
---@param x2 number
---@param z2 number
---@param y number mining level
---@param spacing number branch spacing (default 3)
---@param branch_len number branch length (default 16)
---@return table task
function tasks.create_strip_mine(x1, z1, x2, z2, y, spacing, branch_len)
    local id = next_id
    next_id = next_id + 1

    local task = {
        id = id,
        type = "strip_mine",
        area = {
            x1 = math.min(x1, x2),
            z1 = math.min(z1, z2),
            x2 = math.max(x1, x2),
            z2 = math.max(z1, z2),
            y  = y,
        },
        branch_spacing = spacing or 3,
        branch_length  = branch_len or 16,
        assigned = {},     -- [turtle_id] = sub_params
        status = "pending", -- pending | active | done
        created_at = os.clock(),
    }

    task_list[id] = task
    tasks.save()
    return task
end

--- Split task zone into sub-areas for N turtles
--- direction: "N"|"S"|"E"|"W" -- main tunnel direction
---@param task table
---@param turtle_ids table list of turtle IDs
---@param direction string
---@return table[] sub_params -- array of { turtle_id, params }
function tasks.split_for_turtles(task, turtle_ids, direction)
    local n = #turtle_ids
    if n == 0 then return {} end

    direction = direction or "N"
    local is_ns = (direction == "N" or direction == "S")
    local a = task.area

    -- Split along axis perpendicular to main tunnel
    local split_min, split_max
    if is_ns then
        split_min = a.x1
        split_max = a.x2
    else
        split_min = a.z1
        split_max = a.z2
    end

    local total = split_max - split_min + 1
    local per_turtle = math.ceil(total / n)

    local result = {}
    for i, tid in ipairs(turtle_ids) do
        local s_start = split_min + (i - 1) * per_turtle
        local s_end   = math.min(s_start + per_turtle - 1, split_max)

        if s_start > split_max then break end

        local params
        if is_ns then
            params = {
                start = { x = s_start, z = a.z1 },
                end_  = { x = s_end,   z = a.z2 },
                y = a.y,
                branch_spacing = task.branch_spacing,
                branch_length  = task.branch_length,
                direction = direction,
            }
        else
            params = {
                start = { x = a.x1, z = s_start },
                end_  = { x = a.x2, z = s_end },
                y = a.y,
                branch_spacing = task.branch_spacing,
                branch_length  = task.branch_length,
                direction = direction,
            }
        end

        task.assigned[tid] = params
        result[#result + 1] = { turtle_id = tid, params = params }
    end

    task.status = "active"
    tasks.save()
    return result
end

--- Get task
function tasks.get(id)
    return task_list[id]
end

--- Get all tasks
function tasks.get_all()
    return task_list
end

--- Mark task done for a turtle
function tasks.mark_turtle_done(task_id, turtle_id)
    local task = task_list[task_id]
    if not task then return end
    task.assigned[turtle_id] = nil

    -- If all turtles finished -- task is done
    local has_assigned = false
    for _ in pairs(task.assigned) do
        has_assigned = true
        break
    end
    if not has_assigned then
        task.status = "done"
    end
    tasks.save()
end

return tasks
