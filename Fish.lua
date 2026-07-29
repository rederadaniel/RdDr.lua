-- RdDr/Fish.lua
local PageFish = _G.RDR_CreatePage("FishTab", "🎣 Fish")
_G.AutoFishEnabled = false

task.spawn(function()
    while true do
        task.wait(1)
    end
end)