-- RdDr/Harvest.lua
local Players = game:GetService("Players")
local Player = Players.LocalPlayer

local PageHarvest = _G.RDR_CreatePage("Tab", "🌾 Harvest")
local autoHarvestActive = false

function _G.StartAutoHarvest()
    autoHarvestActive = true
    task.spawn(function()
        while autoHarvestActive do
            task.wait(1)
        end
    end)
end