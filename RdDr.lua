-- RdDr.lua (Bootstrapper)
local BaseUrl = "https://raw.githubusercontent.com/rederadaniel/RdDr.lua/refs/heads/main/RdDr/"

local files = {
    "Main.lua",
    "TP.lua",
    "Automatic.lua",
    "Others.lua",
    "Harvest.lua",
    "Fish.lua",
    "Bug.lua",
    "Sell_N_Trade_Hub.lua",
    "Treasures.lua",
    "Fishing_and_Bugs_Spots.lua",
    "Watering.lua"
}

for _, file in ipairs(files) do
    local success, err = pcall(function()
        loadstring(game:HttpGet(BaseUrl .. file, true))()
    end)
    if not success then
        warn("[RdDr Loader] Failed to load " .. file .. ": " .. tostring(err))
    end
end