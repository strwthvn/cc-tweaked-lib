-- Mining dispatcher installer
-- Usage: wget run https://raw.githubusercontent.com/strwthvn/cc-tweaked-lib/main/dispatch/install.lua

local base = "https://raw.githubusercontent.com/strwthvn/cc-tweaked-lib/main/dispatch/"

local files = {
    "dispatch.lua",
    "lib/protocol.lua",
    "lib/registry.lua",
    "lib/tasks.lua",
    "lib/ui.lua",
    "lib/mined_areas.lua",
}

print("=== Mining Dispatcher Installer ===")

fs.makeDir("lib")

for _, file in ipairs(files) do
    local url = base .. file
    print("Downloading " .. file .. "...")
    local ok, err = shell.run("wget", url, file)
    if not ok then
        print("ERROR: " .. file .. " - " .. tostring(err))
        return
    end
end

print("")
print("Done! Edit BASE_POS in dispatch.lua, then run: dispatch")
