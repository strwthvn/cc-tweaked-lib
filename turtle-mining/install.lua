-- Mining turtle installer
-- Usage: wget run https://raw.githubusercontent.com/strwthvn/cc-tweaked-lib/main/turtle-mining/install.lua

local base = "https://raw.githubusercontent.com/strwthvn/cc-tweaked-lib/main/turtle-mining/"

local files = {
    "tmining.lua",
    "lib/protocol.lua",
    "lib/position.lua",
    "lib/nav.lua",
    "lib/mining.lua",
    "lib/fuel.lua",
    "lib/inventory.lua",
    "lib/persist.lua",
}

print("=== Mining Turtle Installer ===")

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
print("Done! Run: tmining <x> <y> <z> <N|E|S|W>")
