-- protocol.lua -- shared messaging protocol mining_v2

local protocol = {}

protocol.NAME = "mining_v2"

--- Build a message
---@param msg_type string
---@param payload table|nil
---@return table
function protocol.build(msg_type, payload)
    return {
        type    = msg_type,
        sender  = os.getComputerID(),
        ts      = os.clock(),
        payload = payload or {},
    }
end

--- Send a message to a specific recipient
---@param target_id number
---@param msg_type string
---@param payload table|nil
function protocol.send(target_id, msg_type, payload)
    local msg = protocol.build(msg_type, payload)
    rednet.send(target_id, msg, protocol.NAME)
end

--- Broadcast a message to all
---@param msg_type string
---@param payload table|nil
function protocol.broadcast(msg_type, payload)
    local msg = protocol.build(msg_type, payload)
    rednet.broadcast(msg, protocol.NAME)
end

--- Receive a message (with timeout)
---@param timeout number|nil
---@return number|nil sender_id
---@return table|nil message
function protocol.receive(timeout)
    local id, msg = rednet.receive(protocol.NAME, timeout)
    if id and type(msg) == "table" and msg.type then
        return id, msg
    end
    return nil, nil
end

return protocol
