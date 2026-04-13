-- control.lua — программа управления на компьютере
-- Отправляет команды черепахе #0 и ждёт ответ

local TURTLE_ID = 0
local PROTOCOL = "test"

rednet.open("right") -- сторона модема, поменяй если нужно
print("=== Контроль черепахи #" .. TURTLE_ID .. " ===")
print("Команды: forward, back, up, down, left, right, dig, place, status, quit")

while true do
    write("> ")
    local cmd = read()

    if cmd == "quit" then
        print("Выход.")
        break
    end

    rednet.send(TURTLE_ID, cmd, PROTOCOL)
    local id, reply = rednet.receive(PROTOCOL, 5)

    if reply then
        print("< " .. tostring(reply))
    else
        print("! Нет ответа (таймаут 5 сек)")
    end
end

rednet.close()
