-- Diesel Storage Monitor (stats-only)
-- Live readout of all Create fluid tanks attached via wired modems.
-- 51x19 single-screen view, flicker-free.

local TANK_PATTERN = "^create:fluid_tank"
local REFRESH      = 1
local EMA_ALPHA    = 0.4

-- Capacity per tank in mB. Override per-tank via CAPACITY_BY_NAME.
local DEFAULT_CAPACITY = 360000
local CAPACITY_BY_NAME = {
    -- ["create:fluid_tank_0"] = 360000,
}

-- ===== state =====

local prev = {}
local rate = {}
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

    local fluids, total = {}, 0
    for _, t in pairs(data) do
        fluids[#fluids + 1] = { name = t.name or "?", amount = t.amount or 0 }
        total = total + (t.amount or 0)
    end
    return { fluids = fluids, total = total }
end

local function capacityOf(name)
    return CAPACITY_BY_NAME[name] or DEFAULT_CAPACITY
end

-- ===== formatting =====

local function shortFluid(id) return (id:match(":(.+)$") or id) end
local function shortTank(id)
    return (id:match("([^:_]+_%d+)$") or id:match(":(.+)$") or id)
end

local function human(n)
    n = n or 0
    if n < 1000        then return tostring(math.floor(n)) end
    if n < 1000000     then return string.format("%.1fk", n/1000) end
    if n < 1000000000  then return string.format("%.2fM", n/1000000) end
    return string.format("%.2fG", n/1000000000)
end

-- 7 chars wide: "▼-1.2k ", "▲   12", "=    0", " --    "
local function trendRate(r)
    if not r then return " --    ", colors.gray end
    local arrow, color
    if     r >  0.5 then arrow, color = "\30", colors.lime
    elseif r < -0.5 then arrow, color = "\31", colors.red
    else                 arrow, color = "=",   colors.gray end

    local sign = (r > 0.5) and "+" or (r < -0.5 and "-" or " ")
    local abs  = math.abs(r)
    local body
    if     abs < 1000    then body = string.format("%4d",   math.floor(abs + 0.5))
    elseif abs < 1000000 then body = string.format("%3.1fk", abs/1000)
    else                      body = string.format("%3.2fM", abs/1000000) end

    local out = arrow .. sign .. body
    if #out < 7 then out = out .. string.rep(" ", 7 - #out) end
    if #out > 7 then out = out:sub(1, 7) end
    return out, color
end

-- 5 chars wide
local function humanETA(amount, r)
    if not r or r >= -0.5 then return "  -- " end
    if amount <= 0 then return "  0m " end
    local s = amount / -r
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

local function etaColor(amount, r)
    if not r or r >= -0.5 or amount <= 0 then return colors.gray end
    local s = amount / -r
    if s <  300 then return colors.red end
    if s < 1800 then return colors.orange end
    if s < 3600 then return colors.yellow end
    return colors.lime
end

local function pctColor(pct)
    if pct < 10 then return colors.red end
    if pct < 30 then return colors.orange end
    if pct < 60 then return colors.yellow end
    return colors.lime
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
            if isColor() then
                term.setTextColor(s[1] or colors.white)
                term.setBackgroundColor(s[3] or colors.black)
            end
            term.write(txt)
            used = used + #txt
            if used >= self.w then break end
        end
        if used < self.w then
            if isColor() then
                term.setTextColor(colors.white)
                term.setBackgroundColor(colors.black)
            end
            term.write(string.rep(" ", self.w - used))
        end
    end
    if isColor() then
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
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

-- ===== rows =====

-- Yellow stripe with title
local function titleBar(w)
    local title = " DIESEL STORAGE"
    local clk   = textutils.formatTime(os.time(), true) .. " "
    local mid   = string.rep(" ", math.max(1, w - #title - #clk))
    return {
        { colors.black, title, colors.yellow },
        { colors.black, mid,   colors.yellow },
        { colors.black, clk,   colors.yellow },
    }
end

local function sectionBar(w, label)
    local prefix = " --- " .. label .. " "
    local rest   = string.rep("-", math.max(1, w - #prefix))
    return {
        { colors.gray, prefix },
        { colors.gray, rest },
    }
end

-- "  #1  tank_0    diesel    193.0k/360.0k  53%  ▼-1.2k  21m "
local function tankRow(idx, name, info)
    local label = shortTank(name):sub(1, 7)
    local id    = "#" .. tostring(idx)

    if info.error then
        return {
            { colors.red,       "  " .. id },
            { colors.white,     " " .. string.format("%-8s", label) },
            { colors.red,       "  " .. info.error },
        }
    end

    if #info.fluids == 0 then
        return {
            { colors.gray,      "  " .. id },
            { colors.white,     " " .. string.format("%-8s", label) },
            { colors.gray,      "  (empty)" },
        }
    end

    local main = info.fluids[1]
    for _, f in ipairs(info.fluids) do
        if f.amount > main.amount then main = f end
    end

    local cap   = capacityOf(name)
    local pct   = math.floor((info.total / cap) * 100 + 0.5)
    local r     = rate[name]
    local trStr, trCol = trendRate(r)
    local etaCol = etaColor(info.total, r)
    local pcCol  = pctColor(pct)

    local amtStr = string.format("%s/%s", human(info.total), human(cap))

    return {
        { colors.lightGray, "  " .. id },                             --   #1
        { colors.white,     " " .. string.format("%-8s",  label) },   --   tank_0__
        { colors.lime,      string.format("%-7s", shortFluid(main.name):sub(1, 7)) }, -- diesel_
        { colors.white,     " " .. string.format("%-13s", amtStr) },  --   193.0k/360.0k
        { pcCol,            string.format(" %3d%% ", pct) },          --    53%_
        { trCol,            trStr },                                  --   ▼-1.2k_
        { etaCol,           " " .. humanETA(info.total, r) },         --   21m
    }
end

local function totalRows(sums, grandTotal, grandCap, rateT)
    local list = {}
    for f, a in pairs(sums) do list[#list + 1] = { f, a } end
    table.sort(list, function(a, b) return a[2] > b[2] end)

    local rows = {}
    for _, e in ipairs(list) do
        local fluid, amount = e[1], e[2]
        local pct  = grandCap > 0 and math.floor((amount / grandCap) * 100 + 0.5) or 0
        local pcCol = pctColor(pct)
        local trStr, trCol = trendRate(rateT)
        local etaCol = etaColor(grandTotal, rateT)

        local amtStr = grandCap > 0
            and string.format("%s/%s", human(amount), human(grandCap))
            or  human(amount)

        rows[#rows + 1] = {
            { colors.yellow,    "  TOTAL " },
            { colors.lime,      string.format("%-7s", shortFluid(fluid):sub(1, 7)) },
            { colors.white,     " " .. string.format("%-13s", amtStr) },
            { pcCol,            string.format(" %3d%% ", pct) },
            { trCol,            trStr },
            { etaCol,           " " .. humanETA(grandTotal, rateT) },
        }
    end
    return rows
end

-- ===== build =====

local function build(tanks)
    local w, h = term.getSize()
    local buf  = newBuf(w, h)

    buf:add(titleBar(w))
    buf:blank()

    if #tanks == 0 then
        buf:add({ { colors.red,       "  No Create fluid tanks found." } })
        buf:add({ { colors.lightGray, "  Connect tanks via wired modem." } })
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
            grandCap   = grandCap + capacityOf(name)
        end
        buf:add(tankRow(i, name, info))
    end

    updateTotalRate(grandTotal)

    buf:blank()
    buf:add(sectionBar(w, "TOTAL"))
    buf:blank()

    for _, row in ipairs(totalRows(sums, grandTotal, grandCap, rateTotal)) do
        buf:add(row)
    end

    -- footer
    while #buf.lines < h - 1 do buf:blank() end
    buf:add({ { colors.gray, " q:quit  refresh " .. REFRESH .. "s" } })

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
                if isColor() then
                    term.setBackgroundColor(colors.black)
                    term.setTextColor(colors.white)
                end
                term.clear()
                term.setCursorPos(1, 1)
                return
            end
            if ev == "terminate" then return end
        end
    end
end

loop()
