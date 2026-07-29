local Players = game:GetService("Players") -- 
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Player = Players.LocalPlayer
local Character = Player.Character
local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
local PlayerGui = Player:WaitForChild("PlayerGui")
_G.RDR_RAN = true
local RDR_InvStateMod = nil
local RDR_ItemDisplay = nil
local function RDR_GetInvState()
	if RDR_InvStateMod then return RDR_InvStateMod end
	pcall(function()
		RDR_InvStateMod = require(Player:WaitForChild("PlayerScripts"):WaitForChild("Inventory"):WaitForChild("InventoryState"))
	end)
	return RDR_InvStateMod
end
local function RDR_GetItemDisplay()
	if RDR_ItemDisplay then return RDR_ItemDisplay end
	pcall(function()
		RDR_ItemDisplay = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ItemDisplayData"))
	end)
	return RDR_ItemDisplay
end

-- Background inventory resync: keeps InventoryById populated even when the
-- inventory GUI is closed by periodically requesting the server for updates.
local RDR_ResyncRemote = nil
local RDR_ResyncRunning = false
local RDR_RESYNC_INTERVAL = 5 -- seconds between resync requests
local RDR_InventoryListenersSetup = false

local function RDR_GetResyncRemote()
	if RDR_ResyncRemote then return RDR_ResyncRemote end
	pcall(function()
		-- Correct path: ReplicatedStorage.Remote (not Remotes)
		local remoteFolder = ReplicatedStorage:FindFirstChild("Remote")
		if remoteFolder then
			local mainInv = remoteFolder:FindFirstChild("MainInventory")
			if mainInv then
				RDR_ResyncRemote = mainInv:FindFirstChild("RequestInventoryResync")
			end
		end
	end)
	return RDR_ResyncRemote
end

-- Set up InventoryUpdate and InventoryDelta listeners so the server's
-- resync response actually populates InventoryState.InventoryById.
-- Without these, firing RequestInventoryResync does nothing because
-- the InventoryController (which normally sets these up) hasn't loaded yet.
local function RDR_SetupInventoryListeners()
	if RDR_InventoryListenersSetup then return end

	local remoteFolder = ReplicatedStorage:FindFirstChild("Remote")
	if not remoteFolder then return end
	local mainInv = remoteFolder:FindFirstChild("MainInventory")
	if not mainInv then return end

	local inventoryUpdate = mainInv:FindFirstChild("InventoryUpdate")
	local inventoryDelta = mainInv:FindFirstChild("InventoryDelta")

	if inventoryUpdate and inventoryUpdate:IsA("RemoteEvent") then
		inventoryUpdate.OnClientEvent:Connect(function(data)
			if type(data) ~= "table" then return end
			local state = RDR_GetInvState()
			if state and state.SetInventoryItems then
				state.SetInventoryItems(data.Items or {}, data.Version)
			end
		end)
		RDR_InventoryListenersSetup = true
	end

	if inventoryDelta and inventoryDelta:IsA("RemoteEvent") then
		inventoryDelta.OnClientEvent:Connect(function(data)
			if type(data) ~= "table" then return end
			local state = RDR_GetInvState()
			if state and state.ApplyDelta then
				state.ApplyDelta(data)
			end
		end)
	end
end

local function RDR_StartInventoryResync()
	if RDR_ResyncRunning then return end
	RDR_ResyncRunning = true

	-- Set up listeners first so we can receive the server's response
	RDR_SetupInventoryListeners()

	task.spawn(function()
		while RDR_ResyncRunning do
			local remote = RDR_GetResyncRemote()
			local state = RDR_GetInvState()
			if remote and state then
				local version = state.GetVersion and state.GetVersion() or nil
				pcall(function() remote:FireServer(version) end)
			end
			task.wait(RDR_RESYNC_INTERVAL)
		end
	end)
end

RDR_StartInventoryResync()
local function RDR_CountCritters(catName)
	local s = RDR_GetInvState()
	if not s or not s.InventoryById then
		-- Trigger a resync if inventory state is empty
		local remote = RDR_GetResyncRemote()
		if remote then
			pcall(function() remote:FireServer(nil) end)
		end
		return 0
	end
	local c = 0
	for _, it in pairs(s.InventoryById) do
		if type(it) == "table" then
			local cat = it.Category or (it.Metadata and it.Metadata.Category) or ""
			local itype = it.ItemType or (it.Metadata and it.Metadata.ItemType) or ""
			if cat == catName or itype == catName then c = c + 1 end
		end
	end
	return c
end
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local Player = Players.LocalPlayer
GuiService:SetGameplayPausedNotificationEnabled(false)
local function forceUnpause()
	if Player.GameplayPaused then
		print("Gameplay pause detected! Automatically removing...")
		Player:ClearRequirementForReplication() 
	end
end
Player:GetPropertyChangedSignal("GameplayPaused"):Connect(forceUnpause)
task.spawn(forceUnpause)
local function RDR_DisplayNameOf(item)
	local nm = item and item.ItemName
	local dd = nm and RDR_GetItemDisplay()
	if dd and nm and dd[nm] and dd[nm].DisplayName then return dd[nm].DisplayName end
	local meta = item and item.Metadata
	if meta and meta.DisplayName then return meta.DisplayName end
	return nm
end
local autoHarvestActive = false
local autoHarvestThread = nil
local sellWithHarvestActive = false
local sellWithHarvestThread = nil
local _sellInProgress = false
local instantFishEnabled = false
local isTPBugHunting = false
local fishTrackConnection = nil
local bugTrackConnection = nil
local safeModeActive = false
local SAFE_MODE_RADIUS = 60
local RDR_TOGGLES = {}
local RDR_CONFIG_DATA = {}
local function playerNearby(radius)
	radius = radius or SAFE_MODE_RADIUS
	local me = Player.Character
	local hrp = me and me:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	for _, p in ipairs(Players:GetPlayers()) do
		if p == Player then continue end
		local c = p.Character
		local ohrp = c and c:FindFirstChild("HumanoidRootPart")
		if ohrp and (ohrp.Position - hrp.Position).Magnitude <= radius then return true end
	end
	return false
end
local CoreGui = game:GetService("CoreGui") or PlayerGui
local existing = CoreGui and CoreGui:FindFirstChild("RdDr_PremiumGUI")
if existing then existing:Destroy() end
local existing2 = PlayerGui and PlayerGui:FindFirstChild("RdDr_PremiumGUI")
if existing2 then existing2:Destroy() end
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "RdDr_PremiumGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 100002
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Enabled = true
pcall(function() ScreenGui.Parent = PlayerGui end)
if not ScreenGui.Parent then ScreenGui.Parent = CoreGui end
local ToastHolder = Instance.new("Frame")
ToastHolder.Name = "RdDr_Toasts"
ToastHolder.Size = UDim2.new(0, 320, 1, 0)
ToastHolder.Position = UDim2.new(1, -340, 0, 0)
ToastHolder.BackgroundTransparency = 1
ToastHolder.BorderSizePixel = 0
ToastHolder.Parent = ScreenGui
ToastHolder.ZIndex = 10
local toastQueue = {}
local function showToast(text, color, life)
	color = color or Color3.fromRGB(0, 210, 255)
	life = life or 3
	local T = Instance.new("Frame")
	T.Size = UDim2.new(1, 0, 0, 44)
	T.BackgroundColor3 = Color3.fromRGB(12, 14, 20)
	T.BorderSizePixel = 0
	T.BackgroundTransparency = 0.08
	T.Parent = ToastHolder
	Instance.new("UICorner", T).CornerRadius = UDim.new(0, 8)
	local Accent = Instance.new("Frame")
	Accent.Size = UDim2.new(0, 4, 1, 0)
	Accent.BackgroundColor3 = color
	Accent.BorderSizePixel = 0
	Accent.Parent = T
	local Lbl = Instance.new("TextLabel")
	Lbl.Size = UDim2.new(1, -12, 0, 1)
	Lbl.Position = UDim2.new(0, 10, 0, 0)
	Lbl.Text = text
	Lbl.TextColor3 = Color3.fromRGB(240, 245, 255)
	Lbl.Font = Enum.Font.SourceSans
	Lbl.TextSize = 12
	Lbl.TextWrapped = true
	Lbl.TextXAlignment = Enum.TextXAlignment.Left
	Lbl.BackgroundTransparency = 1
	Lbl.Parent = T
	table.insert(toastQueue, T)
	local y = -10
	for i = #toastQueue, 1, -1 do
		local t = toastQueue[i]
		t.Position = UDim2.new(0, 0, 1, y)
		y = y - 50
	end
	task.spawn(function()
		task.wait(life)
		pcall(function()
			TweenService:Create(T, TweenInfo.new(0.5), {BackgroundTransparency = 1}):Play()
			TweenService:Create(Lbl, TweenInfo.new(0.5), {TextTransparency = 1}):Play()
			TweenService:Create(Accent, TweenInfo.new(0.5), {BackgroundTransparency = 1}):Play()
		end)
		task.wait(0.55)
		for i = #toastQueue, 1, -1 do if toastQueue[i] == T then table.remove(toastQueue, i) break end end
		T:Destroy()
	end)
end
local ToggleButton = Instance.new("ImageButton")
ToggleButton.Name = "RdDr_MinimizeButton"
ToggleButton.Size = UDim2.new(0, 75, 0, 75)
ToggleButton.Position = UDim2.new(0, 20, 0.3, 0)
ToggleButton.BackgroundColor3 = Color3.fromRGB(11, 11, 14)
ToggleButton.BorderSizePixel = 0
ToggleButton.Image = "rbxassetid://13580435133"
ToggleButton.Visible = true
ToggleButton.Active = true
ToggleButton.Draggable = true
ToggleButton.Parent = ScreenGui
Instance.new("UICorner", ToggleButton).CornerRadius = UDim.new(1, 0)
local ToggleStroke = Instance.new("UIStroke")
ToggleStroke.Color = Color3.fromRGB(0, 210, 255)
ToggleStroke.Thickness = 2.5
ToggleStroke.Parent = ToggleButton
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 760, 0, 500)
MainFrame.Position = UDim2.new(0.5, -380, 0.5, -250)
MainFrame.BackgroundColor3 = Color3.fromRGB(11, 11, 14)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 12)
ToggleButton.MouseButton1Click:Connect(function() MainFrame.Visible = not MainFrame.Visible end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.K then MainFrame.Visible = not MainFrame.Visible end
end)
local LaserBar = Instance.new("Frame")
LaserBar.Size = UDim2.new(1, 0, 0, 4)
LaserBar.BackgroundColor3 = Color3.fromRGB(0, 210, 255)
LaserBar.BorderSizePixel = 0
LaserBar.Parent = MainFrame
local guiOpacity = 0
local opacitySlider = nil
local function applyGuiOpacity(v)
	v = math.clamp(tonumber(v) or 0, 0, 1)
	guiOpacity = v
	MainFrame.BackgroundTransparency = v
	SidePanel.BackgroundTransparency = v
	ViewContainer.BackgroundTransparency = v
	LaserBar.BackgroundTransparency = v
end
local SidePanel = Instance.new("Frame")
SidePanel.Size = UDim2.new(0, 195, 1, -55)
SidePanel.Position = UDim2.new(0, 12, 0, 42)
SidePanel.BackgroundColor3 = Color3.fromRGB(16, 16, 21)
SidePanel.BorderSizePixel = 0
SidePanel.Parent = MainFrame
Instance.new("UICorner", SidePanel).CornerRadius = UDim.new(0, 10)
local LeftScrollNav = Instance.new("ScrollingFrame")
LeftScrollNav.Size = UDim2.new(1, 0, 1, 0)
LeftScrollNav.BackgroundTransparency = 1
LeftScrollNav.CanvasSize = UDim2.new(0, 0, 0, 0)
LeftScrollNav.AutomaticCanvasSize = Enum.AutomaticSize.Y
LeftScrollNav.ScrollingDirection = Enum.ScrollingDirection.Y
LeftScrollNav.ScrollBarThickness = 2
LeftScrollNav.Parent = SidePanel
local NavLayout = Instance.new("UIListLayout")
NavLayout.Padding = UDim.new(0, 5)
NavLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
NavLayout.Parent = LeftScrollNav
local ViewContainer = Instance.new("Frame")
ViewContainer.Size = UDim2.new(1, -230, 1, -55)
ViewContainer.Position = UDim2.new(0, 218, 0, 42)
ViewContainer.BackgroundColor3 = Color3.fromRGB(16, 16, 21)
ViewContainer.BorderSizePixel = 0
ViewContainer.Parent = MainFrame
Instance.new("UICorner", ViewContainer).CornerRadius = UDim.new(0, 10)
local Close = Instance.new("TextButton")
Close.Size = UDim2.new(0, 35, 0, 30)
Close.Position = UDim2.new(1, -40, 0, 6)
Close.Text = "✕"
Close.TextColor3 = Color3.fromRGB(240, 70, 70)
Close.Font = Enum.Font.SourceSansBold
Close.TextSize = 16
Close.BackgroundTransparency = 1
Close.Parent = MainFrame
local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 35, 0, 30)
MinBtn.Position = UDim2.new(1, -75, 0, 6)
MinBtn.Text = "—"
MinBtn.TextColor3 = Color3.fromRGB(200, 200, 205)
MinBtn.Font = Enum.Font.SourceSansBold
MinBtn.TextSize = 14
MinBtn.BackgroundTransparency = 1
MinBtn.Parent = MainFrame
MinBtn.MouseButton1Click:Connect(function() MainFrame.Visible = false end)
local function CleanupScriptState()
	autoHarvestActive = false
	instantFishEnabled = false
	isTPBugHunting = false
	autoPlantActive = false
	autoBuyActive = false
	autoHatchActive = false
	autoWaterNGActive = false
	autoWaterAllActive = false
	if fishTrackConnection then fishTrackConnection:Disconnect() fishTrackConnection = nil end
	if bugTrackConnection then bugTrackConnection:Disconnect() bugTrackConnection = nil end
	if autoHarvestThread then task.cancel(autoHarvestThread) autoHarvestThread = nil end
	if sellWithHarvestThread then task.cancel(sellWithHarvestThread) sellWithHarvestThread = nil end
	if autoPlantThread then task.cancel(autoPlantThread) autoPlantThread = nil end
	if autoBuyThread then task.cancel(autoBuyThread) autoBuyThread = nil end
	if autoHatchThread then task.cancel(autoHatchThread) autoHatchThread = nil end
	if autoWaterNGThread then task.cancel(autoWaterNGThread) autoWaterNGThread = nil end
	if autoWaterAllThread then task.cancel(autoWaterAllThread) autoWaterAllThread = nil end
	pcall(function() VirtualUser:Button1Up(Vector2.new(0, 0)) end)
	ScreenGui:Destroy()
end
Close.MouseButton1Click:Connect(CleanupScriptState)
local BUILD_OK, BUILD_ERR = pcall(function()
	local RARITY_ORDER={"Common","Uncommon","Rare","Epic","Legendary","Mythical","Ethereal"}
	local HubTitle = Instance.new("TextLabel")
	HubTitle.Size = UDim2.new(0, 250, 0, 35)
	HubTitle.Position = UDim2.new(0, 18, 0, 5)
	HubTitle.Text = "RdDr Premium Framework"
	HubTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	HubTitle.Font = Enum.Font.SourceSansBold
	HubTitle.TextSize = 18
	HubTitle.TextXAlignment = Enum.TextXAlignment.Left
	HubTitle.BackgroundTransparency = 1
	HubTitle.Parent = MainFrame
	local function applyButtonEffects(btn, defaultColor, hoverColor)
		btn.MouseEnter:Connect(function() TweenService:Create(btn, TweenInfo.new(0.25), {BackgroundColor3 = hoverColor}):Play() end)
		btn.MouseLeave:Connect(function() TweenService:Create(btn, TweenInfo.new(0.25), {BackgroundColor3 = defaultColor}):Play() end)
	end
	local pages = {}
	local function createPage(name, labelTag)
		local F = Instance.new("ScrollingFrame")
		F.Size = UDim2.new(1, -20, 1, -20)
		F.Position = UDim2.new(0, 10, 0, 10)
		F.BackgroundTransparency = 1
		F.CanvasSize = UDim2.new(0, 0, 0, 950)
		F.ScrollBarThickness = 4
		F.ScrollBarImageColor3 = Color3.fromRGB(0, 210, 255)
		F.Visible = false
		F.Parent = ViewContainer
		pages[name] = F
		local TabBtn = Instance.new("TextButton")
		TabBtn.Size = UDim2.new(0, 175, 0, 36)
		TabBtn.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
		TabBtn.Text = "  " .. labelTag
		TabBtn.TextColor3 = Color3.fromRGB(160, 165, 175)
		TabBtn.Font = Enum.Font.SourceSansBold
		TabBtn.TextSize = 13
		TabBtn.TextXAlignment = Enum.TextXAlignment.Left
		TabBtn.Parent = LeftScrollNav
		Instance.new("UICorner", TabBtn).CornerRadius = UDim.new(0, 6)
		local LineAccent = Instance.new("Frame")
		LineAccent.Size = UDim2.new(0, 4, 1, 0)
		LineAccent.BackgroundColor3 = Color3.fromRGB(0, 210, 255)
		LineAccent.BorderSizePixel = 0
		LineAccent.Visible = false
		LineAccent.Parent = TabBtn
		TabBtn.MouseButton1Click:Connect(function()
			for _, p in pairs(pages) do p.Visible = false end
			for _, btn in ipairs(LeftScrollNav:GetChildren()) do
				if btn:IsA("TextButton") then
					btn.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
					btn.TextColor3 = Color3.fromRGB(160, 165, 175)
					if btn:FindFirstChild("Frame") then btn.Frame.Visible = false end
				end
			end
			TabBtn.BackgroundColor3 = Color3.fromRGB(28, 30, 40)
			TabBtn.TextColor3 = Color3.fromRGB(0, 210, 255)
			LineAccent.Visible = true
			F.Visible = true
		end)
		return F
	end
	local function AddNavInstructionText(parent, text, yoffset)
		local Ins = Instance.new("TextLabel")
		Ins.Size = UDim2.new(1, -20, 0, 25)
		Ins.Position = UDim2.new(0, 10, 0, yoffset)
		Ins.Text = "ℹ️ " .. text
		Ins.TextColor3 = Color3.fromRGB(170, 175, 190)
		Ins.Font = Enum.Font.SourceSansItalic
		Ins.TextSize = 13
		Ins.TextXAlignment = Enum.TextXAlignment.Left
		Ins.BackgroundTransparency = 1
		Ins.Parent = parent
		return yoffset + 30
	end
	local function AddSectionHeader(parent, text, yoffset)
		local H = Instance.new("TextLabel")
		H.Size = UDim2.new(1, -20, 0, 30)
		H.Position = UDim2.new(0, 10, 0, yoffset)
		H.Text = text:upper()
		H.TextColor3 = Color3.fromRGB(0, 210, 255)
		H.Font = Enum.Font.SourceSansBold
		H.TextSize = 13
		H.TextXAlignment = Enum.TextXAlignment.Left
		H.BackgroundTransparency = 1
		H.Parent = parent
		return yoffset + 35
	end
	local function createTeleportButton(parent, label, cframeTarget, ypos)
		local B = Instance.new("TextButton")
		B.Size = UDim2.new(1, -20, 0, 36)
		B.Position = UDim2.new(0, 10, 0, ypos)
		B.BackgroundColor3 = Color3.fromRGB(26, 28, 38)
		B.Text = "Teleport to: " .. label
		B.TextColor3 = Color3.fromRGB(235, 235, 240)
		B.Font = Enum.Font.SourceSansBold
		B.TextSize = 13
		B.Parent = parent
		Instance.new("UICorner", B).CornerRadius = UDim.new(0, 5)
		applyButtonEffects(B, Color3.fromRGB(26, 28, 38), Color3.fromRGB(36, 40, 55))
		B.MouseButton1Click:Connect(function()
			local char = Player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.CFrame = cframeTarget
			elseif Character and Character:FindFirstChild("HumanoidRootPart") then
				Character.HumanoidRootPart.CFrame = cframeTarget
			end
		end)
		return ypos + 42
	end
	local function makeToggle(label, pos, parentPage, callback)
		local TBtn = Instance.new("TextButton")
		TBtn.Size = UDim2.new(0, 190, 0, 36)
		TBtn.Position = pos
		TBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
		TBtn.Text = label .. " [OFF]"
		TBtn.TextColor3 = Color3.fromRGB(200, 200, 205)
		TBtn.Font = Enum.Font.SourceSansBold
		TBtn.TextSize = 12
		TBtn.Parent = parentPage
		Instance.new("UICorner", TBtn).CornerRadius = UDim.new(0, 4)
		local state = false
		TBtn.MouseButton1Click:Connect(function()
			state = not state
			local targetColor = state and Color3.fromRGB(0, 210, 255) or Color3.fromRGB(40, 40, 50)
			local targetTxtColor = state and Color3.fromRGB(10, 10, 14) or Color3.fromRGB(200, 200, 205)
			TweenService:Create(TBtn, TweenInfo.new(0.2), {BackgroundColor3 = targetColor, TextColor3 = targetTxtColor}):Play()
			TBtn.Text = label .. (state and " [ON]" or " [OFF]")
			callback(state)
		end)
		local setter = setmetatable({}, {__call=function(_,e) state=e TBtn.BackgroundColor3=state and Color3.fromRGB(0,210,255) or Color3.fromRGB(40,40,50) TBtn.TextColor3=state and Color3.fromRGB(10,10,14) or Color3.fromRGB(200,200,205) TBtn.Text=label..(state and " [ON]" or " [OFF]") callback(state) end})
		setter.get = function() return state end
		RDR_TOGGLES[label] = setter
		return setter
	end
	local function saveRDRConfig(profile)
		local fname = profile and ("RdDrConfig_" .. tostring(profile) .. ".json") or "RdDrConfig.json"
		local cfg = { version = 1, toggles = {}, lists = {} }
		for label, setter in pairs(RDR_TOGGLES) do
			local ok, v = pcall(setter.get)
			cfg.toggles[label] = ok and v or false
		end
		if RDR_CONFIG_DATA and RDR_CONFIG_DATA.getLists then
			local ok, d = pcall(RDR_CONFIG_DATA.getLists)
			if ok and d then cfg.lists = d end
		end
		local json = HttpService:JSONEncode(cfg)
		local saved = false
		pcall(function()
			if writefile and isfile then
				pcall(function() writefile(fname, json) end)
				saved = true
			end
		end)
		if not saved then _G["RDR_CFG" .. (profile and ("_" .. tostring(profile)) or "")] = json end
		return saved and "file" or "memory"
	end
	local function loadRDRConfig(profile)
		local fname = profile and ("RdDrConfig_" .. tostring(profile) .. ".json") or "RdDrConfig.json"
		local json = nil
		pcall(function()
			if readfile and isfile and isfile(fname) then
				json = readfile(fname)
			end
		end)
		local memKey = "RDR_CFG" .. (profile and ("_" .. tostring(profile)) or "")
		if not json and _G[memKey] then json = _G[memKey] end
		if not json then return false, "no saved config" end
		local cfg = HttpService:JSONEncode(json)
		if cfg.toggles then
			for label, v in pairs(cfg.toggles) do
				local setter = RDR_TOGGLES[label]
				if setter then pcall(setter, v) end
			end
		end
		if cfg.lists and RDR_CONFIG_DATA and RDR_CONFIG_DATA.applyLists then
			pcall(RDR_CONFIG_DATA.applyLists, cfg.lists)
		end
		return true
	end
	local function createAmtInputBox(pos, default, parent, callback)
		local Box = Instance.new("TextBox")
		Box.Size = UDim2.new(0, 50, 0, 36)
		Box.Position = pos
		Box.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
		Box.Text = tostring(default)
		Box.TextColor3 = Color3.fromRGB(255, 255, 255)
		Box.Font = Enum.Font.SourceSansBold
		Box.TextSize = 14
		Box.Parent = parent
		Instance.new("UICorner", Box).CornerRadius = UDim.new(0, 4)
		Box.FocusLost:Connect(function()
			local val = tonumber(Box.Text) or default
			Box.Text = tostring(val)
			callback(val)
		end)
		return Box
	end
	local function createOpacitySlider(pos, parent, callback)
		local trackW = 200
		local knobW = 18
		local trackX = pos.X.Offset
		local trackY = pos.Y.Offset
		local Track = Instance.new("Frame")
		Track.Size = UDim2.new(0, trackW, 0, 6)
		Track.Position = pos
		Track.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
		Track.BorderSizePixel = 0
		Track.Parent = parent
		Instance.new("UICorner", Track).CornerRadius = UDim.new(1, 0)
		local Knob = Instance.new("TextButton")
		Knob.Size = UDim2.new(0, knobW, 0, knobW)
		Knob.Position = UDim2.new(0, trackX, 0, trackY - (knobW - 6) / 2)
		Knob.BackgroundColor3 = Color3.fromRGB(0, 210, 255)
		Knob.BorderSizePixel = 0
		Knob.Text = ""
		Knob.AutoButtonColor = false
		Knob.Draggable = true
		Knob.Parent = parent
		Instance.new("UICorner", Knob).CornerRadius = UDim.new(1, 0)
		local function setFrac(frac)
			frac = math.clamp(frac, 0, 1)
			Knob.Position = UDim2.new(0, trackX + frac * (trackW - knobW), 0, trackY - (knobW - 6) / 2)
			callback(frac)
		end
		Knob:GetPropertyChangedSignal("Position"):Connect(function()
			local x = math.clamp(Knob.Position.X.Offset, trackX, trackX + trackW - knobW)
			setFrac((x - trackX) / (trackW - knobW))
		end)
		return { Track = Track, Knob = Knob, Set = setFrac }
	end
	local function createActionButton(label, pos, size, parent, callback)
		local B = Instance.new("TextButton")
		B.Size = size or UDim2.new(0, 130, 0, 36)
		B.Position = pos
		B.BackgroundColor3 = Color3.fromRGB(0, 160, 120)
		B.Text = label
		B.TextColor3 = Color3.fromRGB(255, 255, 255)
		B.Font = Enum.Font.SourceSansBold
		B.TextSize = 12
		B.Parent = parent
		Instance.new("UICorner", B).CornerRadius = UDim.new(0, 4)
		applyButtonEffects(B, Color3.fromRGB(0, 160, 120), Color3.fromRGB(0, 200, 150))
		B.MouseButton1Click:Connect(callback)
		return B
	end
	local function getHRP()
		local char = Player.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			return char.HumanoidRootPart
		end
		return nil
	end

	local function getFruitPosition(inst)
		if not inst then return nil end
		local prim = inst:FindFirstChild("prim")
		if prim and prim:IsA("BasePart") then
			return prim.Position
		end
		local ok, pivot = pcall(function() return inst:GetPivot() end)
		if ok and pivot then return pivot.Position end
		local part = inst:FindFirstChildWhichIsA("BasePart", true)
		if part then return part.Position end
		return nil
	end

	local NAME_KEYS = {"displayname","name","creaturename","fishname","bugname","speciesname","itemname","title","label","creature","fish","bug","species","creatureid","speciesid","itemid","reward","resultname","variant","kind","fishtype","bugtype","creaturetype","typename"}
	local function looksLikeNameKey(k)
		k = string.lower(tostring(k))
		for _, nk in ipairs(NAME_KEYS) do
			if string.find(k, nk) then return true end
		end
		return false
	end
	local function deepFindName(data, seen)
		if typeof(data) ~= "table" then return nil end
		seen = seen or {}
		if seen[data] then return nil end
		seen[data] = true
		for k, v in pairs(data) do
			if typeof(v) == "string" and v ~= "" and looksLikeNameKey(k) then
				return v
			end
		end
		for k, v in pairs(data) do
			if typeof(v) == "table" and not seen[v] then
				local found = deepFindName(v, seen)
				if found then return found end
			end
		end
		return nil
	end

	local UUID_PATTERN = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
	local function deepFindId(data, seen)
		if typeof(data) == "string" then
			if data:match(UUID_PATTERN) then return data end
			return nil
		end
		if typeof(data) ~= "table" then return nil end
		seen = seen or {}
		if seen[data] then return nil end
		seen[data] = true
		for k, v in pairs(data) do
			if typeof(k) == "string" then
				local lk = string.lower(k)
				if lk:find("itemid") or lk:find("itemuid") or lk:find("inventoryitemid") or lk:find("inventoryid") then
					if typeof(v) == "string" and v ~= "" then return v end
				end
			end
			local r = deepFindId(v, seen)
			if r then return r end
		end
		return nil
	end

	-- === RARITY DATA (Fish + Bugs) ===
	local FISH_RARITY = {
		Ethereal = {
			shadow_devil_whale_shark = { DisplayName = "Shadow Devil Whale Shark" },
		},
		Mythical = {
			angelic_whale_shark = { DisplayName = "Angelic Whale Shark" },
		},
		Legendary = {
			moonlight_jellyfish = { DisplayName = "Moonlight Jellyfish" }, golden_monkfish = { DisplayName = "Golden Monkfish" },
		},
		Epic = {
			narwhal = { DisplayName = "Narwhal" }, golden_pangasius = { DisplayName = "Golden Pangasius" },
		},
		Rare = {
			electric_eel = { DisplayName = "Electric Eel" }, black_manta_ray = { DisplayName = "Black Manta Ray" },
		},
		Uncommon = {
			atlantic_sturgeon = { DisplayName = "Atlantic Sturgeon" }, white_sturgeon = { DisplayName = "White Sturgeon" },
		},
		Common = {
			goldfish = { DisplayName = "Goldfish" }, bluegill = { DisplayName = "Bluegill" },
		},
	}
	local BUG_RARITY = {
		Ethereal = {
			crimson_centipede = { DisplayName = "Crimson Centipede" },
		},
		Mythical = {
			golden_stick_bug = { DisplayName = "Golden Stick Bug" },
		},
		Legendary = {
			crystal_beetle_amethyst = { DisplayName = "Amethyst Crystal Beetle" }, blue_crab = { DisplayName = "Blue Crab" },
		},
		Epic = {
			black_scorpion = { DisplayName = "Black Scorpion" }, emerald_butterfly = { DisplayName = "Emerald Butterfly" },
		},
		Rare = {
			crystal_beetle_amber = { DisplayName = "Amber Crystal Beetle" }, blue_butterfly = { DisplayName = "Blue Butterfly" },
		},
		Uncommon = {
			bee = { DisplayName = "Bee" }, cricket = { DisplayName = "Cricket" },
		},
		Common = {
			ant = { DisplayName = "Ant" }, fire_ant = { DisplayName = "Fire Ant" },
		},
	}
	local RARITY_BY_NAME = {}
	local function indexRarities(tbl)
		for rarity, list in pairs(tbl) do
			for internal, info in pairs(list) do
				RARITY_BY_NAME[string.lower(tostring(internal))] = rarity
				if info and info.DisplayName then
					RARITY_BY_NAME[string.lower(tostring(info.DisplayName))] = rarity
				end
			end
		end
	end
	indexRarities(FISH_RARITY)
	indexRarities(BUG_RARITY)
	local function getRarity(name)
		if not name then return nil end
		return RARITY_BY_NAME[string.lower(tostring(name))]
	end
	local function getInventoryItemsFrame()
		local lp = game:GetService("Players").LocalPlayer
		local pg = lp and lp:FindFirstChild("PlayerGui")
		local inv = pg and pg:FindFirstChild("InventoryGui")
		local main = inv and inv:FindFirstChild("MainFrame")
		return main and main:FindFirstChild("ItemsFrame")
	end
	local function getAttrCI(inst, key)
		key = string.lower(tostring(key))
		local ok, attrs = pcall(function() return inst:GetAttributes() end)
		if not ok or not attrs then return nil end
		for k, v in pairs(attrs) do
			if string.lower(tostring(k)) == key then return v end
		end
		return nil
	end
	local function snapshotInventoryIds()
		local ids = {}
		local frame = getInventoryItemsFrame()
		if not frame then return ids end
		for _, item in ipairs(frame:GetChildren()) do
			if item:IsA("GuiObject") then
				local _, iid, vid = readItemAttrs(item)
				local eid = vid or iid
				if eid then ids[tostring(eid)] = true end
			end
		end
		return ids
	end
	local function normName(s)
		if not s then return "" end
		return string.lower(tostring(s)):gsub("[%s_%-]", "")
	end
	local function readItemAttrs(inst)
		if not inst then return nil, nil, nil, nil, nil end
		local itemName = getAttrCI(inst, "itemname") or getAttrCI(inst, "name")
		local itemId   = getAttrCI(inst, "itemid")
		local invId    = getAttrCI(inst, "inventoryitemid")
		local weight   = getAttrCI(inst, "weightgrams")
		local category = getAttrCI(inst, "category")
		return itemName, itemId, invId, weight, category
	end
	local recentInventoryItems = {}
	local function recordInventoryItem(inst)
		if not inst or not inst:IsA("GuiObject") then return end
		local function tryRecord()
			local nm, iid, vid, weight, cat = readItemAttrs(inst)
			if not (vid or iid) then return false end
			for i = #recentInventoryItems, 1, -1 do
				if recentInventoryItems[i] and recentInventoryItems[i].inst == inst then
					table.remove(recentInventoryItems, i)
					break
				end
			end
			table.insert(recentInventoryItems, { inst = inst, name = nm, itemid = iid, invid = vid, weight = weight, category = cat, t = os.clock() })
			if #recentInventoryItems > 60 then table.remove(recentInventoryItems, 1) end
			return true
		end
		if not tryRecord() then
			local conn
			conn = inst.AttributeChanged:Connect(function(attr)
				if not attr then return end
				local a = string.lower(tostring(attr))
				if a == "itemid" or a == "inventoryitemid" or a == "itemuid" then
					if tryRecord() and conn then conn:Disconnect() end
				end
			end)
		end
	end
	local function findRecentItemId(name, excludeIds)
		local ln = name and normName(name)
		for i = #recentInventoryItems, 1, -1 do
			local r = recentInventoryItems[i]
			if not r then continue end
			if (not ln) or (r.name and normName(r.name) == ln) then
				local id = r.invid or r.itemid
				if id and not (excludeIds and excludeIds[tostring(id)]) then
					return id, r
				end
			end
		end
		return nil
	end
	local function hookInventoryCapture()
		local frame = getInventoryItemsFrame()
		if not frame then return false end
		for _, c in ipairs(frame:GetChildren()) do recordInventoryItem(c) end
		frame.ChildAdded:Connect(recordInventoryItem)
		return true
	end
	if not hookInventoryCapture() then
		task.spawn(function()
			for _ = 1, 40 do
				task.wait(0.5)
				if hookInventoryCapture() then break end
			end
		end)
	end
	local function findInventoryItem(name, excludeIds)
		local frame = getInventoryItemsFrame()
		if not frame or not name then return nil end
		local ln = normName(name)
		local items = {}
		local function collect(container, depth)
			if depth > 3 then return end
			local children = container:GetChildren()
			for i = #children, 1, -1 do
				local item = children[i]
				if item:IsA("GuiObject") then
					table.insert(items, item)
					collect(item, depth + 1)
				end
			end
		end
		collect(frame, 0)
		for _, item in ipairs(items) do
			if excludeIds then
				local _, iid, vid = readItemAttrs(item)
				local eid = vid or iid
				if eid and excludeIds[tostring(eid)] then continue end
			end
			local nm, iid, vid = readItemAttrs(item)
			local candidates = { nm, iid, vid, item.Name }
			for _, c in ipairs(candidates) do
				if c and normName(c) == ln then return item end
			end
		end
		return nil
	end
	local function resolveIds(name, data, excludeIds)
		local itemId = deepFindId(data)
		if not itemId and name then
			itemId = findRecentItemId(name, excludeIds)
		end
		if not itemId and name then
			local itemGui = findInventoryItem(name, excludeIds)
			if itemGui then
				local _, iid, vid = readItemAttrs(itemGui)
				itemId = vid or iid
			end
		end
		return itemId
	end
end)
