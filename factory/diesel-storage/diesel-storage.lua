-- Diesel Storage Monitor
-- Live readout of all Create fluid tanks attached via wired modems.
-- Compact, flicker-free, with per-tank and total flow rates (mB/s).

local TANK_PATTERN = "^create:fluid_tank"
local REFRESH      = 1            -- seconds between updates
local EMA_ALPHA    = 0.4          -- 0..1, higher = более чувствительно, ниже = плавнее

-- Если CC:T не возвращает capacity, пропиши вручную (mB) — будет показан %.
-- Можно общий через DEFAULT_CAPACITY, можно индивидуальный через CAPACITY_BY_NAME.
local DEFAULT_CAPACITY  = 0       -- 0 = выключено
local CAPACITY_BY_NAME  = {
    -- ["create:fluid_tank_0"] = 256000,
    -- ["create:fluid_tank_1"] = 256000,
}

-- ===== state =====

local prev = {}        -- [tankName] = { amount=N, t=seconds }
local rate = {}        -- [tankName] = mB/s (smoothed)
local prevTotal, rateTotal = nil, nil

-- ===== data =====

local function findTanks()
    local tanks = {}
    for _, name in ipairs(peripheral.getNames()) do
        if name:match(TANK_PATTERN) then tanks[#tanks + 1] = name end
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

local function effectiveCapacity(name, info)
    if info.capacity and info.capacity > 0 then return info.capacity end
    if CAPACITY_BY_NAME[name] then return CAPACITY_BY_NAME[name] end
    if DEFAULT_CAPACITY > 0 then return DEFAULT_CAPACITY end
    return 0
end

-- ===== formatting =====

local function shortFluid(id) return (id:match(":(.+)$") or id) end
local function shortTank(id)
    return (id:match("([^:_]+_%d+)$") or id:match(":(.+)$") or id)
end

-- 12345 -> "12.3k", 1234567 -> "1.23M"
local function human(n)
    n = n or 0
    if n < 1000        then return tostring(n) end
    if n < 1000000     then return string.format("%.1fk", n/1000) end
    if n < 1000000000  then return string.format("%.2fM", n/1000000) end
    return string.format("%.2fG", n/1000000000)
end

-- "+12 mB/s", "-1.2k mB/s", "  0    mB/s"  (6 chars)
local function humanRate(r)
    if not r then return "  --  " end
    local abs  = math.abs(r)
    local sign = r > 0.5 and "+" or (r < -0.5 and "-" or " ")
    local body
    if abs < 1000        then body = string.format("%4d", math.floor(abs + 0.5))
    elseif abs < 1000000 then body = string.format("%4.1fk", abs/1000)
    else                      body = string.format("%4.2fM", abs/1000000) end
    return string.format("%-6s", sign .. body)
end

-- ETA до опустошения: округление до минут/часов/дней
-- amount mB, rate mB/s (отрицательный = расход)
local function humanETA(amount, rate)
    if not rate or rate >= -0.5 then return "  -- " end
    if amount <= 0 then return "  0m " end
    local s = amount / -rate
    if s < 60     then return " <1m " end
    if s < 3600   then return string.format("%4dm", math.floor(s/60 + 0.5)) end
    if s < 86400  then
        local h = math.floor(s/3600)
        local m = math.floor((s % 3600)/60 + 0.5)
        if m == 0 then return string.format("%4dh", h) end
        if h < 10 then return string.format("%dh%02dm", h, m) end
        return string.format("%4dh", h)
    end
    local d = math.floor(s/86400)
    local h = math.floor((s % 86400)/3600 + 0.5)
    if h == 0 or d >= 10 then return string.format("%4dd", d) end
    return string.format("%dd%02dh", d, h)
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

function Buf:add(segs) self.lines[#self.lines + 1] = segs end
function Buf:blank()    self.lines[#self.lines + 1] = {} end

local function isColor() return term.isColor and term.isColor() end

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

-- ===== rate tracker =====

local function now() return os.epoch("utc") / 1000 end

local function updateRate(name, total)
    local t = now()
    local p = prev[name]
    if p then
        local dt = t - p.t
        if dt > 0.05 then
            local instant = (total - p.amount) / dt
            local r = rate[name]
            rate[name] = r and (EMA_ALPHA * instant + (1 - EMA_ALPHA) * r) or instant
        end
    end
    prev[name] = { amount = total, t = t }
end

local function updateTotalRate(total)
    local t = now()
    if prevTotal then
        local dt = t - prevTotal.t
        if dt > 0.05 then
            local instant = (total - prevTotal.amount) / dt
            rateTotal = rateTotal
                and (EMA_ALPHA * instant + (1 - EMA_ALPHA) * rateTotal)
                or instant
        end
    end
    prevTotal = { amount = total, t = t }
end

-- ===== layout =====

local function tankLine(idx, name, info, w)
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

    local main = info.fluids[1]
    for _, f in ipairs(info.fluids) do
        if f.amount > main.amount then main = f end
    end

    local cap = effectiveCapacity(name, info)
    local r   = rate[name]

    local segs = {
        { colors.lightGray, id .. " " },
        { colors.white,     string.format("%-12s ", label:sub(1, 12)) },
        { colors.lime,      string.format("%-8s ",  shortFluid(main.name):sub(1, 8)) },
    }

    if cap > 0 then
        local pct = math.floor((info.total / cap) * 100 + 0.5)
        local fixed = #id + 1 + 13 + 9 + 5 + 1 + 1 + 11 + 1 + 9
        local bw = math.max(4, math.min(12, w - fixed))
        segs[#segs + 1] = { colors.yellow, string.format("%3d%% ", pct) }
        segs[#segs + 1] = { colors.cyan,   "[" .. bar(info.total, cap, bw) .. "] " }
        segs[#segs + 1] = { colors.white,  string.format("%9s ", human(info.total) .. "/" .. human(cap)) }
    else
        segs[#segs + 1] = { colors.white,  string.format("%9s ", human(info.total)) }
    end

    local rcolor = colors.gray
    if r and r >  0.5 then rcolor = colors.lime end
    if r and r < -0.5 then rcolor = colors.red  end
    segs[#segs + 1] = { rcolor, humanRate(r) .. " " }

    -- ETA: красный если опустошение скоро (< 5 мин), оранжевый < 30 мин, жёлтый иначе
    local eta = humanETA(info.total, r)
    local ecolor = colors.gray
    if r and r < -0.5 and info.total > 0 then
        local s = info.total / -r
        if     s < 300  then ecolor = colors.red
        elseif s < 1800 then ecolor = colors.orange
        else                 ecolor = colors.yellow end
    end
    segs[#segs + 1] = { ecolor, eta }

    return segs
end

local function build(tanks)
    local w, h = term.getSize()
    local buf  = newBuf(w, h)

    local title = "=== Diesel Storage ==="
    local clk   = textutils.formatTime(os.time(), true)
    local pad   = math.max(1, w - #title - #clk)
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

    local sums, grandTotal, grandCap = {}, 0, 0
    for i, name in ipairs(tanks) do
        local info = readTank(name)
        if not info.error then
            updateRate(name, info.total)
            for _, f in ipairs(info.fluids) do
                sums[f.name] = (sums[f.name] or 0) + f.amount
            end
            grandTotal = grandTotal + info.total
            grandCap   = grandCap + effectiveCapacity(name, info)
        end
        buf:add(tankLine(i, name, info, w))
    end

    updateTotalRate(grandTotal)

    buf:add({ { colors.gray, string.rep("-", w) } })

    -- totals
    local list = {}
    for f, a in pairs(sums) do list[#list + 1] = { f, a } end
    table.sort(list, function(a, b) return a[2] > b[2] end)

    for _, e in ipairs(list) do
        local fluid, amount = e[1], e[2]
        local segs = {
            { colors.yellow, "TOTAL " },
            { colors.lime,   string.format("%-8s ", shortFluid(fluid):sub(1, 8)) },
        }
        if grandCap > 0 then
            local pct = math.floor((amount / grandCap) * 100 + 0.5)
            local fixed = 6 + 9 + 5 + 1 + 1 + 11 + 1 + 9
            local bw = math.max(4, math.min(14, w - fixed))
            segs[#segs + 1] = { colors.yellow, string.format("%3d%% ", pct) }
            segs[#segs + 1] = { colors.cyan,   "[" .. bar(amount, grandCap, bw) .. "] " }
            segs[#segs + 1] = { colors.white,  string.format("%9s ", human(amount) .. "/" .. human(grandCap)) }
        else
            segs[#segs + 1] = { colors.white,  string.format("%9s ", human(amount)) }
        end

        local rcolor = colors.gray
        if rateTotal and rateTotal >  0.5 then rcolor = colors.lime end
        if rateTotal and rateTotal < -0.5 then rcolor = colors.red  end
        segs[#segs + 1] = { rcolor, humanRate(rateTotal) .. " " }

        local eta = humanETA(amount, rateTotal)
        local ecolor = colors.gray
        if rateTotal and rateTotal < -0.5 and amount > 0 then
            local s = amount / -rateTotal
            if     s < 300  then ecolor = colors.red
            elseif s < 1800 then ecolor = colors.orange
            else                 ecolor = colors.yellow end
        end
        segs[#segs + 1] = { ecolor, eta }

        buf:add(segs)
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
