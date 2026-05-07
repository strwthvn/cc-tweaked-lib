-- Diesel Storage Monitor
-- Live readout of all Create fluid tanks attached via wired modems.
-- Compact, flicker-free single-screen view.

local TANK_PATTERN = "^create:fluid_tank"
local REFRESH      = 1

-- ===== data =====

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
    if not p or not p.tanks then return { error = "no peripheral" } end

    local ok, data = pcall(p.tanks)
    if not ok then return { error = tostring(data) } end

    local fluids, total, capacity = {}, 0, 0
    for _, t in pairs(data) do
        fluids[#fluids + 1] = { name = t.name or "?", amount = t.amount or 0 }
        total    = total    + (t.amount   or 0)
        capacity = capacity + (t.capacity or 0)
    end
    return { fluids = fluids, total = total, capacity = capacity }
end

-- ===== formatting =====

local function shortFluid(id)
    return (id:match(":(.+)$") or id)
end

local function shortTank(id)
    -- "create:fluid_tank_0" -> "tank_0"
    return (id:match("([^:_]+_%d+)$") or id:match(":(.+)$") or id)
end

-- 12345 -> "12.3k", 1234567 -> "1.23M"
local function human(n)
    if n < 1000      then return tostring(n) end
    if n < 1000000   then return string.format("%.1fk", n/1000) end
    if n < 1000000000 then return string.format("%.2fM", n/1000000) end
    return string.format("%.2fG", n/1000000000)
end

local function bar(used, cap, width)
    if cap <= 0 then return string.rep(".", width) end
    local f = math.floor((used / cap) * width + 0.5)
    if f > width then f = width end
    if f < 0     then f = 0     end
    return string.rep("|", f) .. string.rep(".", width - f)
end

-- ===== render buffer =====

local Buf = {}
Buf.__index = Buf

local function newBuf(w, h)
    return setmetatable({ w = w, h = h, lines = {} }, Buf)
end

-- segs: { {color, text}, ... }
function Buf:add(segs) self.lines[#self.lines + 1] = segs end
function Buf:blank()    self.lines[#self.lines + 1] = {} end

local function isColor()
    return term.isColor and term.isColor()
end

function Buf:flush()
    for i = 1, self.h do
        term.setCursorPos(1, i)
        local segs = self.lines[i] or {}
        local used = 0
        for _, s in ipairs(segs) do
            local txt = s[2] or ""
            if used + #txt > self.w then txt = txt:sub(1, self.w - used) end
            if isColor() then term.setTextColor(s[1]) end
            term.write(txt)
            used = used + #txt
            if used >= self.w then break end
        end
        if used < self.w then
            if isColor() then term.setTextColor(colors.white) end
            term.write(string.rep(" ", self.w - used))
        end
    end
end

-- ===== layout =====

local function tankLine(idx, name, info, w)
    -- "1 tank_0  water  50% [||||......] 12.3k/64.0k"
    local id    = string.format("%d", idx)
    local label = shortTank(name)

    if info.error then
        return {
            { colors.lightGray, id .. " " },
            { colors.white,     string.format("%-12s ", label:sub(1, 12)) },
            { colors.red,       "err: " .. info.error },
        }
    end

    if #info.fluids == 0 then
        return {
            { colors.lightGray, id .. " " },
            { colors.white,     string.format("%-12s ", label:sub(1, 12)) },
            { colors.gray,      "(empty)" },
        }
    end

    -- multi-fluid: pick the dominant for the headline, list rest below
    local main = info.fluids[1]
    for _, f in ipairs(info.fluids) do
        if f.amount > main.amount then main = f end
    end

    local fluid = shortFluid(main.name)
    local pct, amt
    if info.capacity > 0 then
        pct = math.floor((info.total / info.capacity) * 100 + 0.5)
        amt = string.format("%s/%s", human(info.total), human(info.capacity))
    else
        pct = nil
        amt = human(info.total)
    end

    -- adapt bar width to terminal
    local fixed = #id + 1 + 13 + 9 + 5 + 1 + 1 + #amt + 1
    local bw = math.max(6, math.min(14, w - fixed))

    local pctStr = pct and string.format("%3d%%", pct) or "  ?%"
    local barStr = "[" .. bar(info.total, info.capacity, bw) .. "]"

    return {
        { colors.lightGray, id .. " " },
        { colors.white,     string.format("%-12s ", label:sub(1, 12)) },
        { colors.lime,      string.format("%-8s ", fluid:sub(1, 8)) },
        { colors.yellow,    pctStr .. " " },
        { colors.cyan,      barStr .. " " },
        { colors.white,     amt },
    }
end

local function build(tanks)
    local w, h = term.getSize()
    local buf = newBuf(w, h)

    -- header
    local title = "=== Diesel Storage ==="
    local clk = textutils.formatTime(os.time(), true)
    local pad = math.max(1, w - #title - #clk)
    buf:add({
        { colors.yellow,    title },
        { colors.white,     string.rep(" ", pad) },
        { colors.lightGray, clk },
    })

    if #tanks == 0 then
        buf:blank()
        buf:add({ { colors.red, "No Create fluid tanks found." } })
        buf:add({ { colors.lightGray, "Connect tanks via wired modem." } })
        return buf
    end

    -- tank lines
    local sums, grandTotal, grandCap = {}, 0, 0
    for i, name in ipairs(tanks) do
        local info = readTank(name)
        buf:add(tankLine(i, name, info, w))

        if not info.error then
            for _, f in ipairs(info.fluids) do
                sums[f.name] = (sums[f.name] or 0) + f.amount
            end
            grandTotal = grandTotal + info.total
            grandCap   = grandCap   + info.capacity
        end
    end

    -- separator
    buf:add({ { colors.gray, string.rep("-", w) } })

    -- totals
    local totalsLine = function(fluid, amount)
        local pct, amt
        if grandCap > 0 then
            pct = math.floor((amount / grandCap) * 100 + 0.5)
            amt = string.format("%s/%s", human(amount), human(grandCap))
        else
            amt = human(amount)
        end
        local fixed = 6 + 9 + 5 + 1 + 1 + #amt + 1
        local bw = math.max(6, math.min(14, w - fixed))
        local pctStr = pct and string.format("%3d%%", pct) or "  ?%"
        local barStr = "[" .. bar(amount, grandCap, bw) .. "]"
        return {
            { colors.yellow, "TOTAL " },
            { colors.lime,   string.format("%-8s ", shortFluid(fluid):sub(1, 8)) },
            { colors.yellow, pctStr .. " " },
            { colors.cyan,   barStr .. " " },
            { colors.white,  amt },
        }
    end

    -- sort fluids by amount desc
    local list = {}
    for f, a in pairs(sums) do list[#list + 1] = { f, a } end
    table.sort(list, function(a, b) return a[2] > b[2] end)

    for _, e in ipairs(list) do
        buf:add(totalsLine(e[1], e[2]))
    end

    return buf
end

-- ===== main loop =====

local function loop()
    term.clear()
    while true do
        local tanks = findTanks()
        local ok, bufOrErr = pcall(build, tanks)
        if ok then
            bufOrErr:flush()
        else
            term.setCursorPos(1, 1)
            if isColor() then term.setTextColor(colors.red) end
            term.write("render error: " .. tostring(bufOrErr))
        end

        local timer = os.startTimer(REFRESH)
        while true do
            local ev, p1 = os.pullEvent()
            if ev == "timer" and p1 == timer then break end
            if ev == "peripheral" or ev == "peripheral_detach" then break end
            if ev == "key" and p1 == keys.q then
                term.clear()
                term.setCursorPos(1, 1)
                return
            end
            if ev == "terminate" then return end
        end
    end
end

loop()
