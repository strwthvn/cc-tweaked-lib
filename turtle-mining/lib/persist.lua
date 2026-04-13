-- persist.lua -- save/load turtle state

local persist = {}

persist.FILE = "/mining_state.dat"

--- Save full state
function persist.save(state)
    local f = fs.open(persist.FILE, "w")
    f.write(textutils.serialize(state))
    f.close()
end

--- Load state (or nil if no file)
function persist.load()
    if not fs.exists(persist.FILE) then return nil end
    local f = fs.open(persist.FILE, "r")
    local data = textutils.unserialize(f.readAll())
    f.close()
    return data
end

--- Delete state file
function persist.clear()
    if fs.exists(persist.FILE) then
        fs.delete(persist.FILE)
    end
end

return persist
