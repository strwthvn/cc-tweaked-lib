-- Diesel Storage installer
-- Usage: wget run https://raw.githubusercontent.com/strwthvn/cc-tweaked-lib/main/factory/diesel-storage/install.lua

local base = "https://raw.githubusercontent.com/strwthvn/cc-tweaked-lib/main/factory/diesel-storage/"

local files = {
    "diesel-storage.lua",
}

print("=== Diesel Storage Installer ===")

for _, file in ipairs(files) do
    local url = base .. file
    print("Downloading " .. file .. "...")
    if fs.exists(file) then fs.delete(file) end
    local ok, err = shell.run("wget", url, file)
    if not ok then
        print("ERROR: " .. file .. " - " .. tostring(err))
        return
    end
end

-- Autostart
local startup = [[shell.run("diesel-storage")
]]
local f = fs.open("startup.lua", "w")
f.write(startup)
f.close()

print("")
print("Done! Will autostart on boot.")
print("Run now: diesel-storage")
