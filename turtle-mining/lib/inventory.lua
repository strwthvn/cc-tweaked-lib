-- inventory.lua -- turtle inventory management

local inventory = {}

inventory.FULL_THRESHOLD = 14 -- 14+ filled slots = full

--- Check if inventory is full
function inventory.is_full()
    local count = 0
    for i = 1, 16 do
        if turtle.getItemCount(i) > 0 then
            count = count + 1
        end
    end
    return count >= inventory.FULL_THRESHOLD
end

--- Number of filled slots
function inventory.slots_used()
    local count = 0
    for i = 1, 16 do
        if turtle.getItemCount(i) > 0 then
            count = count + 1
        end
    end
    return count
end

--- Drop all inventory forward (in front of a chest), except fuel
function inventory.drop_all_forward()
    local old_slot = turtle.getSelectedSlot and turtle.getSelectedSlot() or 1
    for i = 1, 16 do
        if turtle.getItemCount(i) > 0 then
            turtle.select(i)
            if not turtle.refuel(0) then
                turtle.drop()
            end
        end
    end
    turtle.select(old_slot)
end

--- Drop all inventory down (above a chest)
function inventory.drop_all_down()
    local old_slot = turtle.getSelectedSlot and turtle.getSelectedSlot() or 1
    for i = 1, 16 do
        if turtle.getItemCount(i) > 0 then
            turtle.select(i)
            if not turtle.refuel(0) then
                turtle.dropDown()
            end
        end
    end
    turtle.select(old_slot)
end

return inventory
