-- RdDr/Bug.lua
local PageBug = _G.RDR_CreatePage("BugHunt", "🐞 Bug")
local plAuto = false

local abcBtn = Instance.new("TextButton")
abcBtn.Size = UDim2.new(0.9, 0, 0, 30)
abcBtn.Position = UDim2.new(0.05, 0, 0, 205)
abcBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
abcBtn.Text = "🐞 Auto Bug Catch: OFF [F]"
abcBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
abcBtn.Font = Enum.Font.SourceSansBold
abcBtn.TextSize = 13
abcBtn.Parent = PageBug
Instance.new("UICorner", abcBtn).CornerRadius = UDim.new(0, 6)