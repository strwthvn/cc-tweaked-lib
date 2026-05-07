-- Diesel Storage Monitor (SCADA-style)
-- Live readout of all Create fluid tanks attached via wired modems.
-- 51x19 single-screen view, flicker-free, with rates and ETA.

local TANK_PATTERN = "^create:fluid_tank"
local REFRESH      = 1
local EMA_ALPHA    = 0.4
local STATE_FILE   = ".diesel-storage.state"

-- Capacity hints (used when tanks() does not return capacity).
local DEFAULT_CAPACITY = 0
local CAPACITY_BY_NAME = {
    -- ["create:fluid_tank_0"] = 256000,
}

-- ===== state =====

local prev = {}
local rate = {}
local prevTotal, rateTotal = nil, nil

-- Auto-learned capacity: max amount ever seen per tank, persisted on disk.
local maxSeen = {}
local maxSeenDirty = false

local function loadState()
    if not fs.exists(STATE_FILE) then return end
    local f = fs.open(STATE_FILE, "r")
    if not f then return end
    local data = f.readAll(); f.close()
    local ok, st = pcall(textutils.unserialize, data)
    if ok and type(st) == "table" then maxSeen = st end
end

local function saveState()
    if not maxSeenDirty then return end
    local f = fs.open(STATE_FILE, "w")
    if not f then return end
    f.write(textutils.serialize(maxSeen))
    f.close()
    maxSeenDirty = false
end

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

-- Returns capacity in mB, and a source tag: "real" | "manual" | "auto" | "none"
local function effectiveCapacity(name, info)
    if info.capacity and info.capacity > 0 then return info.capacity, "real"   end
    if CAPACITY_BY_NAME[name]              then return CAPACITY_BY_NAME[name], "manual" end
    if DEFAULT_CAPACITY > 0                then return DEFAULT_CAPACITY, "manual" end
    if maxSeen[name] and maxSeen[name] > 0 then return maxSeen[name], "auto"   end
    return 0, "none"
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

-- Combined arrow + rate in 6 chars: "▼ 1.2k", "▲   12", "=    0", "  --  "
local function trendRate(r)
    if not r then return "  --  ", colors.gray end
    local arrow, color
    if     r >  0.5 then arrow, color = "\30", colors.lime
    elseif r < -0.5 then arrow, color = "\31", colors.red
    else                 arrow, color = "=",   colors.gray end

    local abs = math.abs(r)
    local body
    if     abs < 1000    then body = string.format("%4d",   math.floor(abs + 0.5))
    elseif abs < 1000000 then body = string.format("%3.1fk", abs/1000)
    else                      body = string.format("%3.2fM", abs/1000000) end

    -- pad/truncate to total 6 chars: arrow(1) + space(1) + body(4)
    local out = arrow .. " " .. body
    if #out < 6 then out = out .. string.rep(" ", 6 - #out)
    elseif #out > 6 then out = out:sub(1, 6) end
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

-- ===== status colors =====

local function etaColor(amount, r)
    if not r or r >= -0.5 or amount <= 0 then return colors.gray end
    local s = amount / -r
    if s <  300 then return colors.red end
    if s < 1800 then return colors.orange end
    if s < 3600 then return colors.yellow end
    return colors.lime
end

local function fillColor(pct)
    if pct < 10 then return colors.red end
    if pct < 30 then return colors.orange end
    if pct < 60 then return colors.yellow end
    return colors.lime
end

-- ===== render buffer =====

-- Each segment: { fg, text [, bg] }
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

-- ===== layout primitives =====

-- Draw a horizontal bar as bg-painted spaces. Returns segments.
-- width: total cells; cap: capacity; used: filled amount; fc: fill color
local function barSegs(width, used, cap, fc)
    if width < 1 then return {} end
    if cap <= 0 then
        return { { colors.gray, string.rep(" ", width), colors.gray } }
    end
    local f = math.floor((used / cap) * width + 0.5)
    if f > width then f = width end
    if f < 0     then f = 0     end
    local segs = {}
    if f > 0          then segs[#segs+1] = { colors.white, string.rep(" ", f),         fc           } end
    if f < width      then segs[#segs+1] = { colors.white, string.rep(" ", width - f), colors.gray } end
    return segs
end

-- ===== rows =====

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
    -- "-- TOTAL ------------------------------"
    local prefix = "- " .. label .. " "
    local rest   = string.rep("-", math.max(1, w - #prefix))
    return {
        { colors.gray, prefix },
        { colors.gray, rest },
    }
end

-- Tank: 2 rows
-- Row 1:  "● 1 tank_0     diesel  193.0k  ▼ 1.2k  21m"
-- Row 2:  "   [████████░░░░░░░░░░░░░░░] ~72% / 256.0k"
local function tankRows(idx, name, info, w)
    local r1, r2

    local label = shortTank(name):sub(1, 10)
    local id    = string.format("%d", idx)

    if info.error then
        return { {
            { colors.red,       "\7 " },
            { colors.lightGray, id .. " " },
            { colors.white,     string.format("%-10s ", label) },
            { colors.red,       info.error },
        }, {} }
    end

    if #info.fluids == 0 then
        return { {
            { colors.gray,      "\7 " },
            { colors.lightGray, id .. " " },
            { colors.white,     string.format("%-10s ", label) },
            { colors.gray,      "(empty)" },
        }, {} }
    end

    local main = info.fluids[1]
    for _, f in ipairs(info.fluids) do
        if f.amount > main.amount then main = f end
    end

    local cap, capSrc = effectiveCapacity(name, info)
    local r   = rate[name]
    local trendStr, tcolor = trendRate(r)
    local ec       = etaColor(info.total, r)
    local dotColor = ec

    -- Row 1: ● id name  fluid  amount  ▼ rate  eta
    r1 = {
        { dotColor,         "\7 " },                                           -- 2
        { colors.lightGray, id .. " " },                                       -- 2
        { colors.white,     string.format("%-10s ", label) },                  -- 11
        { colors.lime,      string.format("%-7s ", shortFluid(main.name):sub(1, 7)) }, -- 8
        { colors.white,     string.format("%-7s ", human(info.total)) },       -- 8
        { tcolor,           trendStr .. " " },                                 -- 7
        { ec,               humanETA(info.total, r) },                         -- 5
    }

    -- Row 2: indent + bar + pct + capacity
    local pct
    local pctMark = (capSrc == "auto") and "~" or " "
    local pctStr, capStr
    if cap > 0 then
        pct = math.floor((info.total / cap) * 100 + 0.5)
        pctStr = string.format("%s%3d%%", pctMark, pct)
        capStr = " / " .. human(cap)
    else
        pctStr = "  --%"
        capStr = ""
    end

    local indent  = "   ["
    local close   = "] "
    local tail    = pctStr .. capStr
    local fixed   = #indent + #close + #tail
    local barW    = math.max(4, w - fixed)
    local fc      = cap > 0 and fillColor(pct) or colors.gray

    r2 = { { colors.white, indent } }
    for _, s in ipairs(barSegs(barW, info.total, cap, fc)) do
        r2[#r2 + 1] = s
    end
    r2[#r2 + 1] = { colors.white,     close }
    r2[#r2 + 1] = { fc,               pctStr }
    r2[#r2 + 1] = { colors.lightGray, capStr }

    return { r1, r2 }
end

local function totalRows(w, sums, grandTotal, grandCap, rateT, anyAuto)
    local list = {}
    for f, a in pairs(sums) do list[#list + 1] = { f, a } end
    table.sort(list, function(a, b) return a[2] > b[2] end)

    local rows = { sectionBar(w, "TOTAL") }

    for _, e in ipairs(list) do
        local fluid, amount = e[1], e[2]
        local pct, pctStr, capStr
        local pctMark = anyAuto and "~" or " "
        if grandCap > 0 then
            pct = math.floor((amount / grandCap) * 100 + 0.5)
            pctStr = string.format("%s%3d%%", pctMark, pct)
            capStr = " / " .. human(grandCap)
        else
            pctStr = "  --%"
            capStr = ""
        end

        local prefix = string.format(" %-7s [", shortFluid(fluid):sub(1, 7))
        local close  = "] "
        local tail   = pctStr .. capStr
        local fixed  = #prefix + #close + #tail
        local barW   = math.max(4, w - fixed)
        local fc     = grandCap > 0 and fillColor(pct) or colors.cyan

        local row = { { colors.lime, prefix } }
        for _, s in ipairs(barSegs(barW, amount, grandCap, fc)) do
            row[#row + 1] = s
        end
        row[#row + 1] = { colors.white,     close }
        row[#row + 1] = { fc,               pctStr }
        row[#row + 1] = { colors.lightGray, capStr }
        rows[#rows + 1] = row
    end

    -- summary: amount  trend  ETA
    local trendStr, tcolor = trendRate(rateT)
    local ec = etaColor(grandTotal, rateT)
    rows[#rows + 1] = {
        { colors.lightGray, " SYS " },
        { colors.white,     string.format("%-8s ", human(grandTotal)) },
        { tcolor,           trendStr .. " " },
        { colors.lightGray, "ETA " },
        { ec,               humanETA(grandTotal, rateT) },
    }

    return rows
end

-- ===== build =====

local function build(tanks)
    local w, h = term.getSize()
    local buf  = newBuf(w, h)

    buf:add(titleBar(w))

    if #tanks == 0 then
        buf:blank()
        buf:add({ { colors.red, " No Create fluid tanks found." } })
        buf:add({ { colors.lightGray, " Connect tanks via wired modem." } })
        return buf
    end

    local sums, grandTotal, grandCap = {}, 0, 0
    local anyAuto, anyManual, anyReal = false, false, false
    for i, name in ipairs(tanks) do
        local info = readTank(name)
        if not info.error then
            updateRate(name, info.total)
            -- auto-learn capacity
            if info.total > (maxSeen[name] or 0) then
                maxSeen[name] = info.total
                maxSeenDirty = true
            end
            for _, f in ipairs(info.fluids) do
                sums[f.name] = (sums[f.name] or 0) + f.amount
            end
            grandTotal = grandTotal + info.total
            local c, src = effectiveCapacity(name, info)
            grandCap = grandCap + c
            if     src == "auto"   then anyAuto   = true
            elseif src == "manual" then anyManual = true
            elseif src == "real"   then anyReal   = true end
        end
        for _, row in ipairs(tankRows(i, name, info, w)) do
            buf:add(row)
        end
    end

    updateTotalRate(grandTotal)

    for _, row in ipairs(totalRows(w, sums, grandTotal, grandCap, rateTotal, anyAuto)) do
        buf:add(row)
    end

    -- footer
    buf:add({ { colors.gray, string.rep("-", w) } })
    local hint = " q:quit  ~%=auto-learned"
    if anyAuto and not anyReal and not anyManual then
        hint = " q:quit  ~%=auto-learned (fill tanks to calibrate)"
    elseif not anyAuto then
        hint = " q:quit  refresh " .. REFRESH .. "s"
    end
    buf:add({ { colors.lightGray, hint } })

    return buf
end

-- ===== main loop =====

local function loop()
    loadState()
    term.clear()
    local lastSave = 0
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

        -- persist auto-learned capacity at most once per ~30 s
        if maxSeenDirty and (now() - lastSave) > 30 then
            saveState()
            lastSave = now()
        end

        local timer = os.startTimer(REFRESH)
        while true do
            local ev, p1 = os.pullEvent()
            if ev == "timer" and p1 == timer then break end
            if ev == "peripheral" or ev == "peripheral_detach" then break end
            if ev == "key" and p1 == keys.q then
                saveState()
                if isColor() then
                    term.setBackgroundColor(colors.black)
                    term.setTextColor(colors.white)
                end
                term.clear()
                term.setCursorPos(1, 1)
                return
            end
            if ev == "terminate" then saveState(); return end
        end
    end
end

loop()
