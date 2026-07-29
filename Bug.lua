local plAuto, plThread = false, nil
local plRemote = ReplicatedStorage:FindFirstChild("Remotes")
if plRemote then
	plRemote = plRemote:FindFirstChild("BugCatching")
	if plRemote then
		plRemote = plRemote:FindFirstChild("RequestCatch")
	end
end

-- Auto Bug Catch toggle button on the Bug Tab (Page4)
local abcBtn = Instance.new("TextButton")
abcBtn.Size = UDim2.new(0.9, 0, 0, 30)
abcBtn.Position = UDim2.new(0.05, 0, 0, 205)
abcBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
abcBtn.Text = "🐞 Auto Bug Catch: OFF [F]"
abcBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
abcBtn.Font = Enum.Font.SourceSansBold
abcBtn.TextSize = 13
abcBtn.BorderSizePixel = 0
abcBtn.Parent = Page4
Instance.new("UICorner", abcBtn).CornerRadius = UDim.new(0, 6)
applyButtonEffects(abcBtn, Color3.fromRGB(180, 50, 50), Color3.fromRGB(210, 70, 70))

local function abcRefresh()
	if plAuto then
		abcBtn.BackgroundColor3 = Color3.fromRGB(0, 160, 90)
		abcBtn.Text = "🐞 Auto Bug Catch: ON [F]"
	else
		abcBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
		abcBtn.Text = "🐞 Auto Bug Catch: OFF [F]"
	end
end

abcBtn.MouseButton1Click:Connect(function()
	plSet(not plAuto)
	abcRefresh()
end)

local function plPos(t)
	if not t then return nil end
	if t:IsA("PVInstance") then
		return t:GetPivot().Position
	elseif t:IsA("BasePart") then
		return t.Position
	elseif t:IsA("Model") then
		local p = t.PrimaryPart or t:FindFirstChildWhichIsA("BasePart", true)
		return p and p.Position
	end
end

local function plTP(t)
	local c = Player.Character
	if not c then return end
	local p = plPos(t)
	if p then
		c:PivotTo(CFrame.new(p + Vector3.new(0, 3, 0)))
	end
end

local function plCopy(t)
	local p = plPos(t)
	if p then
		local s = string.format("%.2f, %.2f, %.2f", p.X, p.Y, p.Z)
		if setclipboard then
			setclipboard(s)
		elseif Clipboard and Clipboard.set then
			Clipboard.set(s)
		end
	end
end

local function plGD(c, d)
	local a = c:GetAttribute(d)
	if a ~= nil then return tostring(a) end
	local o = c:FindFirstChild(d)
	return o and o:IsA("ValueBase") and tostring(o.Value) or nil
end

local function plAmt(t)
	if not t then return 0 end
	local n, s = string.match(t:lower(), "([%d%.]+)%s*([kmb]?)")
	if not n then return 0 end
	local v = tonumber(n) or 0
	if s == "k" then
		v = v * 1e3
	elseif s == "m" then
		v = v * 1e6
	elseif s == "b" then
		v = v * 1e9
	end
	return v
end

local function plCFD(c)
	local d, isFav, amt = {}, false, 0
	local cf = c:FindFirstChild("ContentFrame")
	if cf then
		local fb = cf:FindFirstChild("FavoriteButton")
		if fb and fb:IsA("GuiObject") then
			isFav = fb.Visible
			table.insert(d, "Favorite: " .. (isFav and "Yes" or "No"))
		else
			table.insert(d, "Favorite: No")
		end
		local al = cf:FindFirstChild("AmountLabel")
		if al and (al:IsA("TextLabel") or al:IsA("TextButton")) and al.Text ~= "" then
			table.insert(d, "Amount: " .. al.Text)
			amt = plAmt(al.Text)
		end
	end
	return d, isFav, amt
end

local function plFmt(c, attr, realName, isInv)
	local d = {}
	if isInv then
		for _, v in ipairs(plCFD(c)) do
			table.insert(d, v)
		end
	end
	local m = c.Name
	if not realName then
		m = plGD(c, "ItemName") or c.Name
		local cat = plGD(c, "Category")
		if cat then table.insert(d, "Category: " .. cat) end
	end
	if attr then
		for _, n in ipairs(attr) do
			if n ~= "ItemName" and n ~= "Category" and n ~= "Amount" then
				local v = plGD(c, n)
				if v then table.insert(d, n .. ": " .. v) end
			end
		end
	end
	return "• " .. m .. (#d > 0 and " [" .. table.concat(d, " | ") .. "]" or "")
end

local function plBFmt(c)
	local d = {}
	local z = plGD(c, "BugZoneId")
	if z then table.insert(d, "Zone: " .. z) end
	local b = plGD(c, "BugId")
	if b then table.insert(d, "ID: " .. b) end
	return "• " .. c.Name .. (#d > 0 and " [" .. table.concat(d, " | ") .. "]" or "")
end

local function plFire(bug)
	local id = plGD(bug, "BugId") or bug.Name
	if plRemote then plRemote:FireServer(id) end
end

local function plMini()
	local g = PlayerGui:FindFirstChild("BugMinigameGui")
	return g and g.Enabled and g:FindFirstChild("BugBoxContainer") and g.BugBoxContainer.Visible
end

RunService.Heartbeat:Connect(function()
	if not plAuto then return end
	plRefreshNet()
	if plNetTool and plNetTool.Parent then
		local h = plNetTool:FindFirstChild("Handle", true)
		if h then
			plNetCFrame = h:GetPivot()
			local af = workspace:FindFirstChild("ActiveBugVisuals")
			if af then
				for _, b in ipairs(af:GetDescendants()) do
					if b:IsA("BasePart") and b.Name == "BugHitbox" and b.Parent then
						b.CFrame = plNetCFrame
					end
				end
			end
		end
	end
	local ct = PlayerGui:FindFirstChild("BugMinigameGui")
	ct = ct and ct:FindFirstChild("BugBoxContainer")
	local cb = ct and ct:FindFirstChild("CatchBox")
	local bb = ct and ct:FindFirstChild("BugBox")
	if cb and bb then
		if cb.AbsolutePosition.X < bb.AbsolutePosition.X then
			VirtualUser:Button1Down(Vector2.new())
		else
			VirtualUser:Button1Up(Vector2.new())
		end
	else
		VirtualUser:Button1Up(Vector2.new())
	end
end)

local function plStart()
	if plThread then return end
	plThread = task.spawn(function()
		while plAuto do
			local af = workspace:FindFirstChild("ActiveBugVisuals")
			local bl = {}
			if af then
				for _, b in ipairs(af:GetDescendants()) do
					if b:IsA("BasePart") and b.Name == "BugHitbox" then
						table.insert(bl, { b, tonumber(plGD(b, "BugId")) or math.huge })
					end
				end
				table.sort(bl, function(a, b) return a[2] < b[2] end)
			end
			if #bl > 0 then
				for i = 1, #bl do
					if not plAuto then break end
					local t = bl[i][1]
					if t and t.Parent then
						plTP(t)
						task.wait(0.5)
						if plAuto and t and t.Parent then plFire(t) end
						task.wait(1)
						while plAuto and plMini() do task.wait(0.2) end
					end
				end
			else
				task.wait(0.5)
			end
		end
		plThread = nil
	end)
end

local lastBugCastExistingIds = {}
local bugWonThisSession = false
local bugCompleteFired = false
local bugLastCompleteFire = 0
local bugHolding = false
local bugDiagTick = 0

local y4 = AddSectionHeader(Page4, "Bug Catch Settings", 10)
y4 = AddNavInstructionText(Page4, "Teleports to bugs AND bug minigame. Shortcut: [F] ON, [Y] OFF.", y4)

local setInstantBug = makeToggle("Instant Bug Catch", UDim2.new(0, 10, 0, y4), Page4, function(state)
	isTPBugHunting = state
	if state then
		startAutoCatchRoutine()
	else
		VirtualUser:Button1Up(Vector2.new(0, 0))
	end
end)

local y4Mode = AddNavInstructionText(Page4, "Auto Mode — choose what happens when bug inventory is full. Click a button: ✅ = selected.", y4 + 103)
local bugModeButtons = {}
local bugModeInfo = {}
local bugModes = {
	{ key = "bugonly", label = "🐞 Bug Catch Only", clean = "Bug Catch Only", color = Color3.fromRGB(120, 90, 60), hover = Color3.fromRGB(160, 120, 80) },
}

for i, mode in ipairs(bugModes) do
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 150, 0, 28)
	btn.Position = UDim2.new(0, 10 + (i - 1) * 155, 0, y4Mode)
	btn.BackgroundColor3 = mode.color
	btn.Text = mode.label
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.SourceSansBold
	btn.TextSize = 12
	btn.Parent = Page4
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
	applyButtonEffects(btn, mode.color, mode.hover)
	bugModeButtons[mode.key] = btn
	bugModeInfo[mode.key] = { label = mode.label, clean = mode.clean }

	local function updateBugModeHighlight()
		for k, b in pairs(bugModeButtons) do
			if k == _G.BugAutoMode then
				b.BorderSizePixel = 3
				b.BorderColor3 = Color3.fromRGB(255, 255, 255)
				b.Text = "✅ " .. bugModeInfo[k].clean
			else
				b.BorderSizePixel = 0
				b.Text = bugModeInfo[k].label
			end
		end
	end

	updateBugModeHighlight()
	btn.MouseButton1Click:Connect(function()
		_G.BugAutoMode = mode.key
		updateBugModeHighlight()
		if showToast then
			showToast("🐞 Bug auto mode: " .. mode.label, mode.color, 2)
		end
	end)
end

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.Y then
		if isTPBugHunting and setInstantBug then
			setInstantBug(false)
			showToast("⏻ Instant Bug Catch OFF (Y)", Color3.fromRGB(255, 170, 90), 1.5)
		end
	elseif input.KeyCode == Enum.KeyCode.F then
		if not isTPBugHunting and setInstantBug then
			setInstantBug(true)
			showToast("🐞 Instant Bug Catch ON (F)", Color3.fromRGB(150, 230, 140), 1.5)
		end
	end
end)

local function ensureBugLogic()
	if bugWinConn then return end
	bugWinConn = RunService.Heartbeat:Connect(function()
		VirtualUser:Button1Up(Vector2.new(0, 0))
		return
	end)
end

-- Minigame Tracker Loop
local function runBugTracker()
	if bugTrackConnection then return end
	bugTrackConnection = RunService.Heartbeat:Connect(function()
		if not isTPBugHunting then return end
		local Container = PlayerGui:FindFirstChild("BugMinigameGui") and PlayerGui:FindFirstChild("BugMinigameGui"):FindFirstChild("BugBoxContainer")
		local catchBox = Container and Container:FindFirstChild("CatchBox")
		local bugBox = Container and Container:FindFirstChild("BugBox")

		if catchBox and bugBox then
			if catchBox.AbsolutePosition.X < bugBox.AbsolutePosition.X then
				VirtualUser:Button1Down(Vector2.new(0, 0))
			else
				VirtualUser:Button1Up(Vector2.new(0, 0))
			end
		else
			VirtualUser:Button1Up(Vector2.new(0, 0))
		end
	end)
end

runBugTracker()

local bugCatchCount = 0
local currentBugName = nil
local BugStatusLabel = Instance.new("TextLabel")
BugStatusLabel.Size = UDim2.new(1, -20, 0, 54)
BugStatusLabel.Position = UDim2.new(0, 10, 0, y4 + 45)
BugStatusLabel.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
BugStatusLabel.Text = "Status: Idle    |    Last: —    |    Total: 0"
BugStatusLabel.TextColor3 = Color3.fromRGB(235, 235, 240)
BugStatusLabel.Font = Enum.Font.SourceSans
BugStatusLabel.TextSize = 13
BugStatusLabel.TextWrapped = true
BugStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
BugStatusLabel.Parent = Page4
Instance.new("UICorner", BugStatusLabel).CornerRadius = UDim.new(0, 6)

local function updateBugStatus(text)
	BugStatusLabel.Text = text
end
