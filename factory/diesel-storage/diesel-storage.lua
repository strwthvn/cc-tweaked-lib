-- Diesel Storage Monitor
-- Live readout of all Create fluid tanks attached via wired modems.

local TANK_PATTERN  = "^create:fluid_tank"
local REFRESH       = 1            -- seconds between updates
local SECTION_BUCKETS = 16          -- 1 vertical section of a Create tank = 16 buckets
local MB_PER_BUCKET = 1000

local function findTanks()
    local tanks = {}
    for _, name in ipairs(peripheral.getNames()) do
        if name:match(TANK_PATTERN) then
            tanks[#tanks + 1] = name
        end
    end
    table.sort(tanks)
    return tanks
end

local function readTank(name)
    local p = peripheral.wrap(name)
    if not p or not p.tanks then
        return { error = "no fluid_storage" }
    end

    local ok, data = pcall(p.tanks)
    if not ok then return { error = tostring(data) } end

    local fluids = {}
    local total = 0
    local capacity = 0
    for _, t in pairs(data) do
        fluids[#fluids + 1] = {
            name   = t.name or "unknown",
            amount = t.amount or 0,
        }
        total = total + (t.amount or 0)
        capacity = capacity + (t.capacity or 0)
    end
    return { fluids = fluids, total = total, capacity = capacity }
end

local function shortFluid(id)
    -- "minecraft:water" -> "water", "create:honey" -> "honey"
    local short = id:match(":(.+)$") or id
    return short
end

local function fmt(n)
    -- 12345678 -> "12 345 678"
    local s = tostring(n)
    local out, count = "", 0
    for i = #s, 1, -1 do
        out = s:sub(i, i) .. out
        count = count + 1
        if count % 3 == 0 and i > 1 then out = " " .. out end
    end
    return out
end

local function bar(used, cap, width)
    if cap <= 0 then return string.rep("-", width) end
    local filled = math.floor((used / cap) * width + 0.5)
    if filled > width then filled = width end
    return string.rep("=", filled) .. string.rep("-", width - filled)
end

local function setColor(c)
    if term.isColor and term.isColor() then term.setTextColor(c) end
end

local function header()
    setColor(colors.yellow)
    print("=== Diesel Storage ===")
    setColor(colors.lightGray)
    print(os.date("%Y-%m-%d %H:%M:%S"))
    setColor(colors.white)
    print()
end

local function render(tanks)
    term.clear()
    term.setCursorPos(1, 1)
    header()

    if #tanks == 0 then
        setColor(colors.red)
        print("No Create fluid tanks found.")
        setColor(colors.lightGray)
        print("Connect tanks via wired modem and refresh.")
        setColor(colors.white)
        return
    end

    local w = term.getSize()
    local barWidth = math.max(10, w - 18)

    local grandTotal = 0
    local grandCap   = 0
    local sums = {}

    for _, name in ipairs(tanks) do
        local info = readTank(name)
        setColor(colors.cyan)
        write(name)
        setColor(colors.white)
        print()

        if info.error then
            setColor(colors.red)
            print("  err: " .. info.error)
            setColor(colors.white)
        elseif #info.fluids == 0 then
            setColor(colors.lightGray)
            print("  (empty)")
            setColor(colors.white)
        else
            for _, f in ipairs(info.fluids) do
                setColor(colors.lime)
                print(("  %-12s %s mB"):format(shortFluid(f.name), fmt(f.amount)))
                setColor(colors.white)
                sums[f.name] = (sums[f.name] or 0) + f.amount
            end
            if info.capacity > 0 then
                local pct = math.floor((info.total / info.capacity) * 100 + 0.5)
                print(("  [%s] %d%%"):format(bar(info.total, info.capacity, barWidth), pct))
            else
                print(("  total: %s mB"):format(fmt(info.total)))
            end
            grandTotal = grandTotal + info.total
            grandCap   = grandCap   + info.capacity
        end
        print()
    end

    setColor(colors.yellow)
    print("=== Total ===")
    setColor(colors.white)
    for fluid, amount in pairs(sums) do
        setColor(colors.lime)
        print(("  %-12s %s mB"):format(shortFluid(fluid), fmt(amount)))
        setColor(colors.white)
    end
    if grandCap > 0 then
        local pct = math.floor((grandTotal / grandCap) * 100 + 0.5)
        print(("  [%s] %d%%"):format(bar(grandTotal, grandCap, math.max(10, w - 18)), pct))
    else
        print(("  total: %s mB"):format(fmt(grandTotal)))
    end
end

local function loop()
    while true do
        local tanks = findTanks()
        local ok, err = pcall(render, tanks)
        if not ok then
            term.clear()
            term.setCursorPos(1, 1)
            setColor(colors.red)
            print("render error: " .. tostring(err))
            setColor(colors.white)
        end

        local timer = os.startTimer(REFRESH)
        while true do
            local ev, p1 = os.pullEvent()
            if ev == "timer" and p1 == timer then break end
            if ev == "peripheral" or ev == "peripheral_detach" then break end
            if ev == "key" and p1 == keys.q then return end
            if ev == "terminate" then return end
        end
    end
end

loop()
