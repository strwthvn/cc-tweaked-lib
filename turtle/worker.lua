-- worker.lua — программа на черепахе #0
-- Слушает команды от компьютера и выполняет

local PROTOCOL = "test"

rednet.open("right") -- сторона модема
print("=== Черепаха #" .. os.getComputerID() .. " готова ===")
print("Жду команды...")

local actions = {
    forward = turtle.forward,
    back    = turtle.back,
    up      = turtle.up,
    down    = turtle.down,
    left    = turtle.turnLeft,
    right   = turtle.turnRight,
    dig     = turtle.dig,
    place   = turtle.place,
}

while true do
    local id, cmd = rednet.receive(PROTOCOL)
    print("Команда от #" .. id .. ": " .. cmd)

    if cmd == "status" then
        local fuel = turtle.getFuelLevel()
        rednet.send(id, "fuel=" .. tostring(fuel), PROTOCOL)
    elseif actions[cmd] then
        local ok, err = actions[cmd]()
        if ok then
            rednet.send(id, "ok", PROTOCOL)
        else
            rednet.send(id, "fail: " .. tostring(err), PROTOCOL)
        end
    else
        rednet.send(id, "unknown: " .. cmd, PROTOCOL)
    end
end
