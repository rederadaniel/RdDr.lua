-- RdDr/TP.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Player = Players.LocalPlayer

local PageTP = _G.RDR_CreatePage("TP", "✈️ TP")

local islandList = {"SeaSaltHarbor", "PointNemo", "TropicalIsland", "MagicForest"}

local y2 = 10
for _, island in ipairs(islandList) do
    local IslandBtn = Instance.new("TextButton")
    IslandBtn.Size = UDim2.new(1, -20, 0, 36)
    IslandBtn.Position = UDim2.new(0, 10, 0, y2)
    IslandBtn.BackgroundColor3 = Color3.fromRGB(35, 45, 75)
    IslandBtn.Text = "Request Cross-Island Travel ➔ " .. island
    IslandBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    IslandBtn.Font = Enum.Font.SourceSansBold
    IslandBtn.TextSize = 13
    IslandBtn.Parent = PageTP
    Instance.new("UICorner", IslandBtn).CornerRadius = UDim.new(0, 5)
    y2 = y2 + 42

    IslandBtn.MouseButton1Click:Connect(function()
        pcall(function()
            ReplicatedStorage.Remotes.IslandTravel.RequestIslandTravel:InvokeServer(island)
        end)
    end)
end