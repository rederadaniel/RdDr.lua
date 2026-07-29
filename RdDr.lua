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
    local url = BaseUrl .. file
    local success, result = pcall(function()
        local code = game:HttpGet(url, true)
        local func, err = loadstring(code)
        if not func then
            error("Syntax error in " .. file .. ": " .. tostring(err))
        end
        return func()
    end)
    
    if not success then
        warn("[RdDr Loader] Failed to load " .. file .. ": " .. tostring(result))
    end
end
