-- fuel.lua -- fuel management

local position = require("lib.position")

local fuel = {}

fuel.RESERVE = 200 -- reserve for unexpected situations

--- Check if fuel is enough to reach base and back
---@param state table turtle position
---@param base_pos table base position
---@return boolean true if need to return
function fuel.is_low(state, base_pos)
    local level = turtle.getFuelLevel()
    if level == "unlimited" then return false end
    local dist = position.distance(state, base_pos)
    return level < dist + fuel.RESERVE
end

--- Try to refuel from inventory
---@return boolean true if refueled successfully
function fuel.try_refuel()
    local old_slot = turtle.getSelectedSlot and turtle.getSelectedSlot() or 1
    local refueled = false
    for slot = 1, 16 do
        turtle.select(slot)
        if turtle.refuel(0) then -- check without consuming
            turtle.refuel()      -- refuel all from this slot
            refueled = true
        end
    end
    turtle.select(old_slot)
    return refueled
end

--- Current fuel level
function fuel.level()
    return turtle.getFuelLevel()
end

return fuel
