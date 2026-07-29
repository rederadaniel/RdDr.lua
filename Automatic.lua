-- RdDr/Automatic.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PageAuto = _G.RDR_CreatePage("Automatic", "🛒 Automatic")

local buyRemote = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("Shops") and ReplicatedStorage.Remotes.Shops:FindFirstChild("BuyShopItem")

local raw = [[
Garden Seeds Shop|GardenSeedShop|CarrotSeed,StrawberrySeed
Cabbage Seeds Shop|CabbageSeedShop|CabbageSeed,PurpleCabbageSeed
Tropical Seeds Shop|TropicalSeedShop|CoconutSeed,BananaSeed
Magic Seeds Shop|MagicSeedShop|HeartGrassSeed,DangoRootSeed
Bug Nets Shop|MainBugShop|BasicNet,BlueNet
Brother Seeds Shop|BrotherSeedShop|RedCarrotSeed,YellowTomatoSeed
Mushroom Seed Shop|MushroomSeedShop|PinkJumboMushroomSeed,BlueJumboMushroomSeed
Mushroom Pet Shop|MushroomPetShop|RedMushroom,LuckyMushroom
Gear Shop|MainGearShop|WateringCan,RustySprinkler
Witch Potions Shop|WitchShop|PotionOfSpeed,PotionOfLeaping
Pet Shop|MainPetShop|BasicIncubator,CowEgg
]]

local shops = {}
for l in raw:gmatch("[^\n]+") do
    local n, i, t = l:match("([^|]+)|([^|]+)|(.+)")
    if n and i and t then
        table.insert(shops, {name = n, id = i, items = t:split(",")})
    end
end

local selectedItems = {}
for _, s in ipairs(shops) do
    selectedItems[s.id] = {}
    for _, item in ipairs(s.items) do selectedItems[s.id][item] = false end
end

local isAutoBuying = true

local function pcallPurchaseEngine(amt)
    amt = amt or 1
    if not buyRemote then return end
    for _, sData in ipairs(shops) do
        local sId = sData.id
        for _, item in ipairs(sData.items) do
            if selectedItems[sId] and selectedItems[sId][item] then
                buyRemote:FireServer(sId, item, amt)
                task.wait(0.12)
            end
        end
    end
end

task.spawn(function()
    while isAutoBuying do
        pcallPurchaseEngine(1)
        task.wait(1)
    end
end)