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
		local cfg = HttpService:JSONDecode(json)
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
		if not frame then return ids end -- FIXED: Return empty table instead of proceeding with nil frame
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
		if not s then return "" end -- FIXED: Null check added
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
				if recentInventoryItems[i] and recentInventoryItems[i].inst == inst then -- FIXED: Added nil check
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
				if not attr then return end -- FIXED: Null check added
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
			if not r then continue end -- FIXED: Added nil check
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
		local itemid, invid, weight, category
		local recentId, recentItem = findRecentItemId(name, excludeIds)
		if recentId then
			invid = recentItem.invid or recentId
			itemid = recentItem.itemid or recentId
			weight = recentItem.weight
			category = recentItem.category
			return itemid, invid, weight, category
		end
		if typeof(data) == "table" then
			invid = data.InventoryItemId or data.inventoryitemid or data.inventoryId or data.itemuid
			itemid = data.ItemId or data.itemid or data.itemuid or data.id
			weight = data.WeightGrams or data.weight
			category = data.Category or data.category
		end
		if not itemid and not invid then
			local ok, invItem = pcall(function() return findInventoryItem(name, excludeIds) end)
			if ok and invItem then
				local nm, iid, vid, wt, cat = readItemAttrs(invItem)
				itemid = iid
				invid = vid
				weight = wt
				category = cat
			end
		end
		if (not itemid and not invid) and typeof(data) == "table" then
			local ids = collectAllIds(data)
			local byKey = {}
			for _, kv in ipairs(ids) do byKey[string.lower(tostring(kv[1]))] = kv[2] end
			invid = invid or byKey["inventoryitemid"] or byKey["inventoryid"] or byKey["itemuid"]
			itemid = itemid or byKey["itemid"]
			weight = weight or byKey["weightgrams"] or byKey["weight"]
			category = category or byKey["category"]
			if not itemid and not invid and #ids > 0 then invid = ids[1][2] end
		end
		return itemid, invid, weight, category
	end
	local function findInventoryItemId(name, winData, excludeIds)
		local itemid, invid = resolveIds(name, winData, excludeIds)
		return invid or itemid or nil
	end
	local autoFavoriteEnabled = false
	local autoFavSpecificEnabled = false
	local favEthereal = true
	local favMythical = true
	local favCustomNames = {}
	local favManualSet = {}
	local function nameInCustomList(name)
		if #favCustomNames == 0 or not name then return false end
		local ln = normName(name)
		for _, cn in ipairs(favCustomNames) do
			if cn == ln then return true end
		end
		return false
	end
	local function shouldFavorite(name)
		if not name then return false end
		local rarity = getRarity(name)
		if autoFavoriteEnabled then
			if favEthereal and rarity == "Ethereal" then return true end
			if favMythical and rarity == "Mythical" then return true end
		end
		if autoFavSpecificEnabled and nameInCustomList(name) then return true end
		return false
	end
	local InventoryAction = nil
	local deleteCatch  -- forward declaration for auto-delete
	task.spawn(function()
		local ok, remotes = pcall(function() return ReplicatedStorage:WaitForChild("Remotes", 6) end)
		if not ok or not remotes then return end
		local mainInv = remotes:FindFirstChild("MainInventory") or remotes:FindFirstChild("Inventory")
		if not mainInv then return end
		InventoryAction = mainInv:FindFirstChild("InventoryAction")
	end)
	local function collectAllIds(data)
		local out = {}
		if typeof(data) ~= "table" then return out end
		local seen = {}
		local function scan(d, depth)
			if typeof(d) ~= "table" or depth > 6 or seen[d] then return end
			seen[d] = true
			for k, v in pairs(d) do
				if typeof(v) == "string" and v:match(UUID_PATTERN) then
					table.insert(out, {tostring(k), v})
				elseif typeof(v) == "table" then
					scan(v, depth + 1)
				end
			end
		end
		scan(data, 0)
		return out
	end
	local favoritedIds = {}
	local function findInventoryFrameById(itemId)
		itemId = tostring(itemId)
		local frame = getInventoryItemsFrame()
		if not frame then return nil end
		local function search(c, depth)
			if depth > 3 then return nil end
			for _, item in ipairs(c:GetChildren()) do
				if item:IsA("GuiObject") then
					local _, iid, vid = readItemAttrs(item)
					local eid = tostring(vid or iid)
					if eid ~= "" and eid == itemId then return item end
					local r = search(item, depth + 1)
					if r then return r end
				end
			end
			return nil
		end
		return search(frame, 0)
	end
	local function favoriteItem(itemId, frame)
		if not InventoryAction or not itemId then return false end
		itemId = tostring(itemId)
		local frm = frame or findInventoryFrameById(itemId)
		if frm then
			local fb = frm:FindFirstChild("FavoriteButton", true)
			if fb and fb:IsA("GuiObject") and fb.Visible then
				favoritedIds[itemId] = true
				return false
			end
		end
		if favoritedIds[itemId] then return false end
		local ok, err = pcall(function()
			InventoryAction:FireServer({ Action = "ToggleFavorite", ItemId = itemId })
		end)
		if ok then
			favoritedIds[itemId] = true
			return true
		end
		warn("[RdDr][Fav] ToggleFavorite failed for " .. itemId .. ": " .. tostring(err))
		return false
	end
	local function favoriteCatch(name, kind, winData, excludeIds)
		if not name or (not autoFavoriteEnabled and not autoFavSpecificEnabled) then return end
		kind = kind or "Fish"
		local function favoriteAllMatchingName()
			local frame = getInventoryItemsFrame()
			if not frame or not name then return 0, 0 end
			local ln = normName(name)
			local seen = {}
			local matched, faved = 0, 0
			local function collect(c, depth)
				if depth > 3 then return end
				local children = c:GetChildren()
				for i = #children, 1, -1 do
					local item = children[i]
					if item:IsA("GuiObject") then
						local nm, iid, vid = readItemAttrs(item)
						if nm and normName(nm) == ln then
							matched = matched + 1
							local id = vid or iid
							if id and not seen[tostring(id)] then
								seen[tostring(id)] = true
								local did = favoriteItem(tostring(id), item)
								faved = faved + (did and 1 or 0)
							end
						end
						collect(item, depth + 1)
					end
				end
			end
			collect(frame, 0)
			return matched, faved
		end
		local tries = 0
		local function attempt()
			tries = tries + 1
			local matched = favoriteAllMatchingName()
			if matched == 0 then
				local recentId = findRecentItemId(name, excludeIds)
				if recentId then
					local did = favoriteItem(tostring(recentId))
				end
			end
			if tries < 8 and matched == 0 then task.delay(0.5, attempt) end
		end
		task.delay(1.0, attempt)
	end
	local Page1 = createPage("Main", "🏠 Main")
	local PageTP = createPage("TP", "✈️ TP")
	local PageAuto = createPage("Automatic", "🛒 Automatic")
	local PageOthers = createPage("Others", "🚀 Others")
	local Page2 = createPage("Tab", "🌾 Harvest")
	local Page3 = createPage("FishTab", "🎣 Fish")
	local Page4 = createPage("BugHunt", "🐞 Bug")
	local PageSellHub = createPage("SellTab", "💰 Sell & Trade Hub")
	local PageTreasure = createPage("TreasureTab", "💎 Treasures")
	local Page10 = createPage("FishTPTab", "🗺️ Fishing and Bugs Spots")
	local Page6 = createPage("WaterTab", "💧 Watering")
	local _sellAllCropsFn
	local onlyFishingMode, y2, flySpeed, noclipActive, flyActive, infJumpActive, syncAntiAfk
	do 
		local buyRemote = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("Shops") and ReplicatedStorage.Remotes.Shops:FindFirstChild("BuyShopItem")
		local sellActionRemote = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("Sell") and ReplicatedStorage.Remotes.Sell:FindFirstChild("SellAction")
		local tradeActionRemote = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("Exchanges") and ReplicatedStorage.Remotes.Exchanges:FindFirstChild("RewardExchangeAction")
		InventoryAction = (ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("MainInventory") and ReplicatedStorage.Remotes.MainInventory:FindFirstChild("InventoryAction")) or InventoryAction
		local islandList = {"SeaSaltHarbor", "PointNemo", "TropicalIsland", "MagicForest"}
		local sellCropsAmt, sellFishAmt, tradeFishAmt, sellPetsAmt, sellBugsAmt = 1, 1, 1, 1, 1
		local autoSellFishActive, autoTradeFishActive, autoSellPetsActive = false, false, false
		local isAutoBuying = false
		onlyFishingMode = false
		_G.AutoChests = false
		_G.AutoDigSites = false
		_G.AutoMagicOrbs = false
		local mainScanNavLabel
		local y0 = AddSectionHeader(Page1, "Welcome to RdDr Premium", 10)
		y0 = AddNavInstructionText(Page1, "Use the tabs on the left to open each feature.", y0)
		y0 = AddNavInstructionText(Page1, "🌾 Harvest - auto harvest all ready crops if not ready stop wait a minite", y0)
		y0 = AddNavInstructionText(Page1, "🎣 Fish - fishing catching minigame", y0)
		y0 = AddNavInstructionText(Page1, "🐞 Bug - bug catching minigame", y0)
		mainScanNavLabel = Instance.new("TextLabel")
		mainScanNavLabel.Size = UDim2.new(1, -20, 0, 25)
		mainScanNavLabel.Position = UDim2.new(0, 10, 0, y0)
		mainScanNavLabel.Text = "ℹ️ Scan Inventory: [ON] — Fish & Bug catch logs are scanning your inventory."
		mainScanNavLabel.TextColor3 = Color3.fromRGB(0, 210, 255)
		mainScanNavLabel.Font = Enum.Font.SourceSansItalic
		mainScanNavLabel.TextSize = 13
		mainScanNavLabel.TextXAlignment = Enum.TextXAlignment.Left
		mainScanNavLabel.BackgroundTransparency = 1
		mainScanNavLabel.Parent = Page1
		y0 = y0 + 30
		Page1.Visible = true
		local MASTER_LOG = {}
		local MASTER_LOG_MAX = 1e9
		local SUPPRESS_MASTER = false

		-- Rarity -> display color for catch-log lines.
		local RARITY_COLOR = {
			Common = Color3.fromRGB(200, 205, 215),
			Uncommon = Color3.fromRGB(120, 220, 130),
			Rare = Color3.fromRGB(90, 160, 255),
			Epic = Color3.fromRGB(190, 110, 255),
			Legendary = Color3.fromRGB(255, 200, 60),
			Mythical = Color3.fromRGB(255, 110, 200),
			Ethereal = Color3.fromRGB(120, 240, 255),
		}
		local function rarityColor(rarity)
			return RARITY_COLOR[rarity] or Color3.fromRGB(160, 200, 230)
		end

		local function makeCatchLog(parent, title, ypos, height, accent, logName, opts)
			opts = opts or {}
			local includeSearch = (opts.search ~= false)
			local Header = Instance.new("TextLabel")
			Header.Size = UDim2.new(1, -20, 0, 24)
			Header.Position = UDim2.new(0, 10, 0, ypos)
			Header.Text = title
			Header.TextColor3 = accent
			Header.Font = Enum.Font.SourceSansBold
			Header.TextSize = 13
			Header.TextXAlignment = Enum.TextXAlignment.Left
			Header.BackgroundTransparency = 1
			Header.Parent = parent

			-- Totals + rarity breakdown (Ethereal … Common) shown at the top of every log.
			local RARITY_ORDER_STATS = {"Ethereal", "Mythical", "Legendary", "Epic", "Rare", "Uncommon", "Common"}
			local statTotal = 0
			local statRarity = {Ethereal = 0, Mythical = 0, Legendary = 0, Epic = 0, Rare = 0, Uncommon = 0, Common = 0}
			local StatsLabel = Instance.new("TextLabel")
			StatsLabel.Size = UDim2.new(1, -20, 0, 16)
			StatsLabel.Position = UDim2.new(0, 10, 0, ypos + 24)
			StatsLabel.Text = "Total: 0"
			StatsLabel.TextColor3 = Color3.fromRGB(235, 235, 240)
			StatsLabel.Font = Enum.Font.SourceSans
			StatsLabel.TextSize = 11
			StatsLabel.TextXAlignment = Enum.TextXAlignment.Left
			StatsLabel.BackgroundTransparency = 1
			StatsLabel.Parent = parent
			local function updateStats()
				local parts = {"Total: " .. statTotal}
				for _, r in ipairs(RARITY_ORDER_STATS) do
					if statRarity[r] > 0 then table.insert(parts, r .. ": " .. statRarity[r]) end
				end
				StatsLabel.Text = table.concat(parts, "   ")
			end

			local frameY = ypos + 28
			local frameH = height
			local SearchBox
			if includeSearch then
				SearchBox = Instance.new("TextBox")
				SearchBox.Size = UDim2.new(1, -20, 0, 26)
				SearchBox.Position = UDim2.new(0, 10, 0, ypos + 44)
				SearchBox.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
				SearchBox.PlaceholderText = "🔎 Search… (filter this log)"
				SearchBox.Text = ""
				SearchBox.TextColor3 = Color3.fromRGB(235, 235, 240)
				SearchBox.Font = Enum.Font.SourceSans
				SearchBox.TextSize = 12
				SearchBox.ClearTextOnFocus = false
				SearchBox.Parent = parent
				Instance.new("UICorner", SearchBox).CornerRadius = UDim.new(0, 5)
				frameY = ypos + 74
				frameH = height - 46
			else
				frameY = ypos + 44
				frameH = height - 16
			end

			local Frame = Instance.new("ScrollingFrame")
			Frame.Size = UDim2.new(1, -20, 0, frameH)
			Frame.Position = UDim2.new(0, 10, 0, frameY)
			Frame.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
			Frame.BorderSizePixel = 0
			Frame.ScrollBarThickness = 4
			Frame.ScrollBarImageColor3 = Color3.fromRGB(0, 210, 255)
			Frame.CanvasSize = UDim2.new(0, 0, 0, 0)
			Frame.Parent = parent
			Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 6)

			local Layout = Instance.new("UIListLayout")
			Layout.SortOrder = Enum.SortOrder.LayoutOrder
			Layout.Padding = UDim.new(0, 2)
			Layout.Parent = Frame

			local order = 0
			local entries = {}
			local allEntries = {}
			local currentFilter = ""
			local function matchesFilter(text)
				if currentFilter == "" then return true end
				return string.find(string.lower(tostring(text)), currentFilter, 1, true) ~= nil
			end
			local function applyFilter(query)
				currentFilter = string.lower(query or "")
				for _, e in ipairs(allEntries) do
					if e and e.Parent then e.Visible = matchesFilter(e.Text) end
				end
			end
			local function add(text, color, key, rarity)
				order = order + 1
				if key and entries[key] and entries[key].Parent then
					entries[key].Text = text
					entries[key].TextColor3 = color
					entries[key].Visible = matchesFilter(text)
					for i = #MASTER_LOG, 1, -1 do
						local m = MASTER_LOG[i]
						if m.logName == logName and m.key == key then m.text = text m.color = color break end
					end
					return entries[key]
				end
				local e = Instance.new("TextLabel")
				e.Size = UDim2.new(1, -10, 0, 34)
				e.BackgroundTransparency = 1
				e.Text = text
				e.TextColor3 = color
				e.Font = Enum.Font.SourceSans
				e.TextSize = 11
				e.TextWrapped = true
				e.TextXAlignment = Enum.TextXAlignment.Left
				e.LayoutOrder = order
				e.Visible = matchesFilter(text)
				e.Parent = Frame
				table.insert(allEntries, e)
				if key then entries[key] = e end
				Frame.CanvasSize = UDim2.new(0, 0, 0, Layout.AbsoluteContentSize.Y + 8)
				if not SUPPRESS_MASTER then
					table.insert(MASTER_LOG, { logName = logName, text = text, color = color, key = key, rarity = rarity })
					if #MASTER_LOG > MASTER_LOG_MAX then table.remove(MASTER_LOG, 1) end
				end
				statTotal = statTotal + 1
				if rarity and statRarity[rarity] ~= nil then statRarity[rarity] = statRarity[rarity] + 1 end
				updateStats()
				return e
			end
			local function clear()
				for _, c in ipairs(Frame:GetChildren()) do
					if c:IsA("TextLabel") then c:Destroy() end
				end
				entries = {}
				allEntries = {}
				order = 0
				statTotal = 0
				statRarity = {Ethereal = 0, Mythical = 0, Legendary = 0, Epic = 0, Rare = 0, Uncommon = 0, Common = 0}
				updateStats()
				Frame.CanvasSize = UDim2.new(0, 0, 0, 0)
			end
			if includeSearch and SearchBox then
				SearchBox:GetPropertyChangedSignal("Text"):Connect(function() applyFilter(SearchBox.Text) end)
			end
			return { frame = Frame, add = add, clear = clear, applyFilter = applyFilter, search = includeSearch and SearchBox or nil }
		end

		local yLog = y0 + 5
		local CombinedLog = makeCatchLog(Page1, "📋 Catch Log — Fish + Bugs (type in search to filter)", yLog, 170, Color3.fromRGB(0, 210, 255), "Combined")
		local FishLog = makeCatchLog(Page3, "Fish Catch Log", 275, 240, Color3.fromRGB(120, 200, 255), "Fish")
		local BugLog = makeCatchLog(Page4, "Bug Catch Log", 245, 240, Color3.fromRGB(150, 230, 140), "Bug")
		Page3.CanvasSize = UDim2.new(0, 0, 0, 520)
		Page4.CanvasSize = UDim2.new(0, 0, 0, 520)

		local HarvestLog

		local function addClearButton(parent, ypos, label, log)
			local b = Instance.new("TextButton")
			b.Size = UDim2.new(0, 170, 0, 24)
			b.Position = UDim2.new(0, 10, 0, ypos)
			b.BackgroundColor3 = Color3.fromRGB(120, 40, 40)
			b.Text = label
			b.TextColor3 = Color3.fromRGB(255, 255, 255)
			b.Font = Enum.Font.SourceSansBold
			b.TextSize = 12
			b.Parent = parent
			Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
			applyButtonEffects(b, Color3.fromRGB(120, 40, 40), Color3.fromRGB(160, 60, 60))
			b.MouseButton1Click:Connect(function()
				if log and log.clear then log.clear() end
			end)
			return b
		end

		local ClearAllBtn = Instance.new("TextButton")
		ClearAllBtn.Size = UDim2.new(0.20, 0, 0, 24)
		ClearAllBtn.Position = UDim2.new(0.56, 0, 0, yLog)
		ClearAllBtn.BackgroundColor3 = Color3.fromRGB(120, 40, 40)
		ClearAllBtn.Text = "🗑 Clear All Logs"
		ClearAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		ClearAllBtn.Font = Enum.Font.SourceSansBold
		ClearAllBtn.TextSize = 12
		ClearAllBtn.Parent = Page1
		Instance.new("UICorner", ClearAllBtn).CornerRadius = UDim.new(0, 5)
		applyButtonEffects(ClearAllBtn, Color3.fromRGB(120, 40, 40), Color3.fromRGB(160, 60, 60))
		ClearAllBtn.MouseButton1Click:Connect(function()
			pcall(function()
				CombinedLog.clear()
				FishLog.clear()
				BugLog.clear()
				if HarvestLog then HarvestLog.clear() end
			end)
		end)

		local ViewAllBtn = Instance.new("TextButton")
		ViewAllBtn.Size = UDim2.new(0.20, 0, 0, 24)
		ViewAllBtn.Position = UDim2.new(0.78, 0, 0, yLog)
		ViewAllBtn.BackgroundColor3 = Color3.fromRGB(40, 90, 120)
		ViewAllBtn.Text = "📜 View All Logs"
		ViewAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		ViewAllBtn.Font = Enum.Font.SourceSansBold
		ViewAllBtn.TextSize = 12
		ViewAllBtn.Parent = Page1
		Instance.new("UICorner", ViewAllBtn).CornerRadius = UDim.new(0, 5)
		applyButtonEffects(ViewAllBtn, Color3.fromRGB(40, 90, 120), Color3.fromRGB(60, 120, 160))
		ViewAllBtn.MouseButton1Click:Connect(function()
			pcall(function()
				CombinedLog.clear()
				FishLog.clear()
				BugLog.clear()
				if HarvestLog then HarvestLog.clear() end
				SUPPRESS_MASTER = true
				for _, m in ipairs(MASTER_LOG) do
					if m.logName == "Combined" then CombinedLog.add(m.text, m.color, m.key, m.rarity)
					elseif m.logName == "Fish" then FishLog.add(m.text, m.color, m.key, m.rarity)
					elseif m.logName == "Bug" then BugLog.add(m.text, m.color, m.key, m.rarity)
					elseif m.logName == "Harvest" then if HarvestLog then HarvestLog.add(m.text, m.color, m.key, m.rarity) end end
				end
				SUPPRESS_MASTER = false
			end)
		end)

		addClearButton(Page3, 565, "🗑 Clear Fish Log", FishLog)
		Page3.CanvasSize = UDim2.new(0, 0, 0, 670)
		addClearButton(Page4, 567, "🗑 Clear Bug Log", BugLog)
		Page4.CanvasSize = UDim2.new(0, 0, 0, 670)

		-- ===== Scan Inventory Toggle (Fish + Bug Catch Logs) =====
		local catchScanEnabled = true
		local scanToggleBtns = {}

		local function updateScanToggleVisuals()
			for _, btn in ipairs(scanToggleBtns) do
				if catchScanEnabled then
					btn.BackgroundColor3 = Color3.fromRGB(0, 210, 255)
					btn.TextColor3 = Color3.fromRGB(10, 10, 14)
					btn.Text = "Scan Inventory [ON]"
				else
					btn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
					btn.TextColor3 = Color3.fromRGB(200, 200, 205)
					btn.Text = "Scan Inventory [OFF]"
				end
			end
			if mainScanNavLabel then
				if catchScanEnabled then
					mainScanNavLabel.Text = "ℹ️ Scan Inventory: [ON] — Fish & Bug catch logs are scanning your inventory."
					mainScanNavLabel.TextColor3 = Color3.fromRGB(0, 210, 255)
				else
					mainScanNavLabel.Text = "ℹ️ Scan Inventory: [OFF] — Fish & Bug catch logs are NOT scanning your inventory."
					mainScanNavLabel.TextColor3 = Color3.fromRGB(200, 100, 100)
				end
			end
		end

		local function createScanToggleButton(parent, ypos)
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(0, 190, 0, 36)
			btn.Position = UDim2.new(0, 10, 0, ypos)
			btn.BackgroundColor3 = Color3.fromRGB(0, 210, 255)
			btn.Text = "Scan Inventory [ON]"
			btn.TextColor3 = Color3.fromRGB(10, 10, 14)
			btn.Font = Enum.Font.SourceSansBold
			btn.TextSize = 12
			btn.Parent = parent
			Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
			-- Custom hover effects that respect toggle state (do NOT use applyButtonEffects
			-- because its MouseLeave closure would always revert to the ON color)
			btn.MouseEnter:Connect(function()
				if catchScanEnabled then
					TweenService:Create(btn, TweenInfo.new(0.25), {BackgroundColor3 = Color3.fromRGB(0, 230, 255)}):Play()
				else
					TweenService:Create(btn, TweenInfo.new(0.25), {BackgroundColor3 = Color3.fromRGB(60, 60, 70)}):Play()
				end
			end)
			btn.MouseLeave:Connect(function()
				if catchScanEnabled then
					TweenService:Create(btn, TweenInfo.new(0.25), {BackgroundColor3 = Color3.fromRGB(0, 210, 255)}):Play()
				else
					TweenService:Create(btn, TweenInfo.new(0.25), {BackgroundColor3 = Color3.fromRGB(40, 40, 50)}):Play()
				end
			end)
			btn.MouseButton1Click:Connect(function()
				catchScanEnabled = not catchScanEnabled
				updateScanToggleVisuals()
			end)
			table.insert(scanToggleBtns, btn)
			return btn
		end

		-- Fish Catch Log (Page3): scan toggle + nav instructions
		createScanToggleButton(Page3, 595)
		AddNavInstructionText(Page3, "Scan Inventory (Fish+Bug): When ON, automatically scans your inventory for new fish/bug catches and logs them here.", 635)
		AddNavInstructionText(Page3, "Turn this OFF to stop inventory scanning. This controls scanning for BOTH Fish and Bug catch logs.", 665)
		Page3.CanvasSize = UDim2.new(0, 0, 0, 730)

		-- Bug Catch Log (Page4): scan toggle + nav instructions
		createScanToggleButton(Page4, 597)
		AddNavInstructionText(Page4, "Scan Inventory (Fish+Bug): When ON, automatically scans your inventory for new fish/bug catches and logs them here.", 637)
		AddNavInstructionText(Page4, "Turn this OFF to stop inventory scanning. This controls scanning for BOTH Fish and Bug catch logs.", 667)
		Page4.CanvasSize = UDim2.new(0, 0, 0, 730)

		local catchSeq = 0

		-- Direct source for all Fish/Bug catch logs:
		-- PlayerGui.InventoryGui.MainFrame.ItemsFrame
		-- Each item is read from its own Attributes:
		-- ItemName, WeightGrams, ItemId, InventoryItemId, Category
		local catchSeen = {}
		local catchLogKeys = {}

		local function catchKindFromCategory(category)
			local c = string.lower(tostring(category or ""))
			if c == "fish" or c == "caughtfish" or string.find(c, "fish", 1, true) then
				return "Fish"
			end
			if c == "bug" or c == "bugs" or c == "caughtbugs" or string.find(c, "bug", 1, true) then
				return "Bug"
			end
			return nil
		end

		local function scanCatchItemsFrame(targetName, targetId)
			local frame = getInventoryItemsFrame()
			if not frame then return nil end

			local wantedName = targetName and normName(targetName) or nil
			local wantedId = targetId and tostring(targetId) or nil

			local function scan(container, depth)
				if not container or depth > 6 then return nil end
				for _, item in ipairs(container:GetChildren()) do
					if item:IsA("GuiObject") then
						local itemName, itemId, inventoryItemId, weightGrams, category = readItemAttrs(item)
						local id1 = itemId and tostring(itemId) or nil
						local id2 = inventoryItemId and tostring(inventoryItemId) or nil

						local idMatch = wantedId and (id1 == wantedId or id2 == wantedId)
						local nameMatch = wantedName and itemName and normName(itemName) == wantedName

						if idMatch or nameMatch then
							return {
								instance = item,
								ItemName = itemName or item.Name,
								ItemId = itemId,
								InventoryItemId = inventoryItemId,
								WeightGrams = weightGrams,
								Category = category,
							}
						end

						local found = scan(item, depth + 1)
						if found then return found end
					end
				end
			end

			return scan(frame, 0)
		end

		local function getGameWeightGrams(item)
			if typeof(item) ~= "table" then return nil end
			local w = tonumber(item.WeightGrams)
			if w and w > 0 then
				return math.max(1, math.floor(w + 0.5))
			end
			local md = item.Metadata
			if typeof(md) == "table" then
				w = tonumber(md.WeightGrams)
				if w and w > 0 then
					return math.max(1, math.floor(w + 0.5))
				end
			end
			return nil
		end

		-- The actual InventoryGui card visibly renders values like:
		-- "Ant [0.15 KG]". Use that display as a final fallback when the
		-- inventory state has not exposed WeightGrams yet.
		local function getGuiWeightGrams(guiItem)
			if not guiItem then return nil end

			local direct = tonumber(getAttrCI(guiItem, "WeightGrams"))
			if direct and direct > 0 then
				return math.max(1, math.floor(direct + 0.5))
			end

			local foundKg
			local function scanText(root, depth)
				if not root or depth > 6 or foundKg then return end

				if root:IsA("TextLabel") or root:IsA("TextButton") or root:IsA("TextBox") then
					local s = tostring(root.Text or "")
					local kg = s:match("([%d%.]+)%s*[Kk][Gg]")
					if kg then
						local n = tonumber(kg)
						if n and n > 0 then
							foundKg = n * 1000
							return
						end
					end
				end

				for _, child in ipairs(root:GetChildren()) do
					scanText(child, depth + 1)
					if foundKg then return end
				end
			end

			scanText(guiItem, 0)
			if foundKg then
				return math.max(1, math.floor(foundKg + 0.5))
			end

			return nil
		end

		local function resolveCatchWeightGrams(name, kind, preferredId, guiItem, guiWeight)
			local direct = tonumber(guiWeight)
			if direct and direct > 0 then
				return math.max(1, math.floor(direct + 0.5))
			end

			local guiGrams = getGuiWeightGrams(guiItem)
			if guiGrams then return guiGrams end

			local wanted = preferredId and tostring(preferredId) or nil
			local wantedName = name and normName(name) or ""
			local state
			pcall(function() state = RDR_GetInvState() end)
			local inv = state and state.InventoryById

			-- If inventory state is empty/stale, request a resync now
			if not inv or not next(inv) then
				local remote = RDR_GetResyncRemote()
				if remote then
					pcall(function() remote:FireServer(state and state.GetVersion and state.GetVersion() or nil) end)
				end
			end

			if type(inv) == "table" then
				if wanted and type(inv[wanted]) == "table" then
					local w = getGameWeightGrams(inv[wanted])
					if w then return w end
				end

				for _, entry in pairs(inv) do
					if type(entry) == "table" then
						local ids = {
							entry.InventoryItemId, entry.ItemId, entry.ItemUid,
							entry.ItemUID, entry.Uid, entry.UID, entry.Id
						}
						local idMatch = false
						if wanted then
							for _, id in ipairs(ids) do
								if id ~= nil and tostring(id) == wanted then
									idMatch = true
									break
								end
							end
						end

						local md = type(entry.Metadata) == "table" and entry.Metadata or nil
						local entryName = entry.ItemName or (md and md.ItemName) or RDR_DisplayNameOf(entry)
						local cat = entry.Category or (md and md.Category)
						local kindMatch =
							(kind == "Fish" and (cat == "Fish" or cat == "CaughtFish"))
							or
							(kind == "Bug" and (cat == "Bug" or cat == "Bugs" or cat == "CaughtBugs"))

						if idMatch or (wantedName ~= "" and entryName and normName(entryName) == wantedName and (not cat or kindMatch)) then
							local w = getGameWeightGrams(entry)
							if w then return w end
						end
					end
				end
			end

			for i = #recentInventoryItems, 1, -1 do
				local recent = recentInventoryItems[i]
				if recent then
					local rid = recent.invid or recent.itemid
					local idMatch = wanted and rid and tostring(rid) == wanted
					local nameMatch = wantedName ~= "" and recent.name and normName(recent.name) == wantedName
					if idMatch or nameMatch then
						local w = tonumber(recent.weight)
						if w and w > 0 then return math.max(1, math.floor(w + 0.5)) end
					end
				end
			end

			return nil
		end

		local function formatCatchWeight(grams)
			local g = tonumber(grams)
			if not g or g <= 0 then return "…" end
			g = math.max(1, math.floor(g + 0.5))
			return string.format("%dg / %.2f KG", g, g / 1000)
		end

		local function addCatchLog(line, color, key, rarity, kind)
			if CombinedLog and CombinedLog.add then
				CombinedLog.add(line, color, key, rarity)
			end
			if kind == "Bug" then
				if BugLog and BugLog.add then BugLog.add(line, color, key, rarity) end
			else
				if FishLog and FishLog.add then FishLog.add(line, color, key, rarity) end
			end
		end

		local function LogCatch(name, kind, data)
			if not name or name == "" then return end
			kind = kind == "Bug" and "Bug" or "Fish"

			local rarity = getRarity(name) or "?"
			local color = rarityColor(rarity)
			local fav = shouldFavorite(name) and "Yes" or "No"
			local icon = kind == "Bug" and "🐞 " or "🐟 "

			local preferredId
			if typeof(data) == "table" then
				preferredId = data.InventoryItemId or data.inventoryitemid or data.InventoryId or data.ItemId or data.itemid
			end

			local tries = 0
			local function attempt()
				tries = tries + 1

				local gui = scanCatchItemsFrame(name, preferredId)
				local itemId = gui and gui.ItemId
				local inventoryItemId = gui and gui.InventoryItemId
				local category = gui and gui.Category
				local itemName = gui and gui.ItemName or tostring(name)
				local guiWeight = gui and gui.WeightGrams

				-- Only log Fish/Bug inventory entries. Category from ItemsFrame is authoritative.
				local guiKind = catchKindFromCategory(category)
				if guiKind then kind = guiKind end

				local displayId = inventoryItemId or itemId or preferredId
				local weightGrams = resolveCatchWeightGrams(itemName, kind, displayId, gui and gui.instance, guiWeight)

				-- If the GUI exists but has not finished receiving attributes yet, retry.
				-- Do not permanently record "…" while the inventory card is
				-- still loading its weight. Wait for the real value first.
				if gui and displayId and category ~= nil and weightGrams then
					local seenKey = tostring(displayId)
					if not catchSeen[seenKey] then
						catchSeen[seenKey] = true
						catchSeq = catchSeq + 1
						local key = kind .. "|" .. tostring(itemName) .. "#" .. tostring(catchSeq)

						local weightStr = formatCatchWeight(weightGrams)
						local itemStr = itemId ~= nil and tostring(itemId) or "…"
						local invStr = inventoryItemId ~= nil and tostring(inventoryItemId) or "…"
						local catStr = tostring(category)

						local line = string.format(
							"%s%s [%s] | Weight: %s | ID: %s | Category: %s | Fav: %s",
							icon, tostring(itemName), tostring(rarity), weightStr, itemStr, catStr, fav
						)

						addCatchLog(line, color, key, rarity, kind)
					end
					return true
				end

				if tries < 12 then
					task.delay(0.35, attempt)
				end
			end

			task.spawn(attempt)
		end

		local function startCatchLogger()
			local ready = false

			local function processGuiItem(item, logEnabled)
				if not item or not item:IsA("GuiObject") then return end

				local itemName, itemId, inventoryItemId, weightGrams, category = readItemAttrs(item)
				if not itemName or tostring(itemName) == "" then return end
				local kind = catchKindFromCategory(category)
				if not kind then return end

				local uniqueId = inventoryItemId or itemId
				if not uniqueId then return end
				local seenKey = tostring(uniqueId)
				if catchSeen[seenKey] then return end

				-- During startup, remember existing Fish/Bug inventory entries
				-- without sending them into the three catch logs.
				if not logEnabled then
					catchSeen[seenKey] = true
					return
				end

				LogCatch(tostring(itemName), kind, {
					ItemId = itemId,
					InventoryItemId = inventoryItemId,
					WeightGrams = weightGrams,
					Category = category,
				})

				pcall(function()
					favoriteCatch(tostring(itemName), kind, {
						ItemId = itemId,
						InventoryItemId = inventoryItemId,
						WeightGrams = weightGrams,
						Category = category,
					})
				end)

				pcall(function()
					if deleteCatch then
						deleteCatch(tostring(itemName), kind, {
							ItemId = itemId,
							InventoryItemId = inventoryItemId,
							WeightGrams = weightGrams,
							Category = category,
						})
					end
				end)

				if kind == "Bug" then
					_G.RDR_LastBugCatch = os.clock()
				else
					_G.RDR_LastFishCatch = os.clock()
				end
			end

			local function scanFrame(logEnabled)
				local current = getInventoryItemsFrame()
				if not current then return end

				local function scan(container, depth)
					if not container or depth > 6 then return end
					for _, child in ipairs(container:GetChildren()) do
						if child:IsA("GuiObject") then
							processGuiItem(child, logEnabled)
							scan(child, depth + 1)
						end
					end
				end
				scan(current, 0)
			end

			-- Mark existing Fish/Bugs so startup inventory is not falsely logged.
			scanFrame(false)
			task.delay(2, function() ready = true end)

			task.spawn(function()
				while true do
					task.wait(0.35)
					if catchScanEnabled then scanFrame(ready) end
				end
			end)

			task.spawn(function()
				while true do
					local current = getInventoryItemsFrame()
					if current then
						current.DescendantAdded:Connect(function(inst)
							if not catchScanEnabled then return end
							task.defer(function()
								processGuiItem(inst, ready)
							end)
						end)
						break
					end
					task.wait(1)
				end
			end)
		end
		startCatchLogger()
		do
			local yFav = yLog + 213
			local FavHeader = Instance.new("TextLabel")
			FavHeader.Size = UDim2.new(1, -20, 0, 30)
			FavHeader.Position = UDim2.new(0, 10, 0, yFav)
			FavHeader.Text = "⭐ AUTO FAVORITE (FISH + BUGS)"
			FavHeader.TextColor3 = Color3.fromRGB(0, 210, 255)
			FavHeader.Font = Enum.Font.SourceSansBold
			FavHeader.TextSize = 13
			FavHeader.TextXAlignment = Enum.TextXAlignment.Left
			FavHeader.BackgroundTransparency = 1
			FavHeader.Parent = Page1
			makeToggle("⭐ Auto Favorite Specific Names (typed list)", UDim2.new(0, 10, 0, yFav + 35), Page1, function(state)
				autoFavSpecificEnabled = state
			end)
			local ALL_KNOWN_NAMES = {}
			for _, tbl in ipairs({FISH_RARITY, BUG_RARITY}) do
				for _, list in pairs(tbl) do
					for internal, info in pairs(list) do
						if info then
							ALL_KNOWN_NAMES[normName(internal)] = internal
						end
					end
				end
			end
			local function isKnownName(name)
				return name and ALL_KNOWN_NAMES[normName(name)] ~= nil
			end
			local function getDisplayName(name)
				return ALL_KNOWN_NAMES[normName(name)]
			end
			local ManualRowY = yFav + 112
			local ManualHelp = Instance.new("TextLabel")
			ManualHelp.Size = UDim2.new(1, -20, 0, 16)
			ManualHelp.Position = UDim2.new(0, 10, 0, yFav + 90)
			ManualHelp.Text = "📝 Enter the EXACT fish/bug internal name (case-insensitive), e.g. 'shadow_devil_whale_shark'. Click the button to favorite/unfavorite it."
			ManualHelp.TextColor3 = Color3.fromRGB(150, 200, 230)
			ManualHelp.Font = Enum.Font.SourceSansItalic
			ManualHelp.TextSize = 11
			ManualHelp.TextWrapped = true
			ManualHelp.TextXAlignment = Enum.TextXAlignment.Left
			ManualHelp.BackgroundTransparency = 1
			ManualHelp.Parent = Page1
			local ManualNameBox = Instance.new("TextBox")
			ManualNameBox.Size = UDim2.new(0, 300, 0, 30)
			ManualNameBox.Position = UDim2.new(0, 10, 0, ManualRowY)
			ManualNameBox.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
			ManualNameBox.PlaceholderText = "Type exact name — e.g. shadow_devil_whale_shark"
			ManualNameBox.Text = ""
			ManualNameBox.TextColor3 = Color3.fromRGB(235, 235, 240)
			ManualNameBox.Font = Enum.Font.SourceSans
			ManualNameBox.TextSize = 12
			ManualNameBox.ClearTextOnFocus = false
			ManualNameBox.Parent = Page1
			Instance.new("UICorner", ManualNameBox).CornerRadius = UDim.new(0, 5)
			local ManualFavBtn = Instance.new("TextButton")
			ManualFavBtn.Size = UDim2.new(0, 215, 0, 30)
			ManualFavBtn.Position = UDim2.new(0, 318, 0, ManualRowY)
			ManualFavBtn.BackgroundColor3 = Color3.fromRGB(40, 110, 80)
			ManualFavBtn.Text = "＋ Toggle Favorite"
			ManualFavBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			ManualFavBtn.Font = Enum.Font.SourceSansBold
			ManualFavBtn.TextSize = 12
			ManualFavBtn.Parent = Page1
			Instance.new("UICorner", ManualFavBtn).CornerRadius = UDim.new(0, 5)
			applyButtonEffects(ManualFavBtn, Color3.fromRGB(40, 110, 80), Color3.fromRGB(55, 150, 105))
			local ManualFavStatus = Instance.new("TextLabel")
			ManualFavStatus.Size = UDim2.new(1, -20, 0, 20)
			ManualFavStatus.Position = UDim2.new(0, 10, 0, ManualRowY + 34)
			ManualFavStatus.Text = "Type a fish/bug name above, then click '＋ Toggle Favorite'."
			ManualFavStatus.TextColor3 = Color3.fromRGB(150, 155, 170)
			ManualFavStatus.Font = Enum.Font.SourceSansItalic
			ManualFavStatus.TextSize = 11
			ManualFavStatus.TextXAlignment = Enum.TextXAlignment.Left
			ManualFavStatus.BackgroundTransparency = 1
			ManualFavStatus.Parent = Page1
			local autoDeleteEnabled = false
			local autoDeleteNames = {}
			local function nameInDeleteList(name)
				if #autoDeleteNames == 0 or not name then return false end
				local ln = normName(name)
				for _, cn in ipairs(autoDeleteNames) do
					if cn == ln then return true end
				end
				return false
			end
			do
				local RARITY_COLOR = {
					Common = Color3.fromRGB(190, 190, 195),
					Uncommon = Color3.fromRGB(95, 210, 110),
					Rare = Color3.fromRGB(90, 160, 255),
					Epic = Color3.fromRGB(185, 105, 255),
					Legendary = Color3.fromRGB(255, 185, 70),
					Mythical = Color3.fromRGB(255, 95, 200),
					Ethereal = Color3.fromRGB(110, 235, 255),
				}
				local nameToRarity = {}
				for _, rarity in ipairs(RARITY_ORDER) do
					local fl = FISH_RARITY[rarity]
					if fl then for internal, info in pairs(fl) do if info then nameToRarity[internal] = rarity end end end
					local bl = BUG_RARITY[rarity]
					if bl then for internal, info in pairs(bl) do if info then nameToRarity[internal] = rarity end end end
				end
				local FavNameLabel = Instance.new("TextLabel")
				FavNameLabel.Size = UDim2.new(1, -20, 0, 18)
				FavNameLabel.Position = UDim2.new(0, 10, 0, ManualRowY + 58)
				FavNameLabel.Text = "Favorite Specific Names (click to toggle, multi-select):"
				FavNameLabel.TextColor3 = Color3.fromRGB(200, 205, 215)
				FavNameLabel.Font = Enum.Font.SourceSans
				FavNameLabel.TextSize = 12
				FavNameLabel.TextXAlignment = Enum.TextXAlignment.Left
				FavNameLabel.BackgroundTransparency = 1
				FavNameLabel.Parent = Page1
				local FavNameSearch = Instance.new("TextBox")
				FavNameSearch.Size = UDim2.new(1, -20, 0, 26)
				FavNameSearch.Position = UDim2.new(0, 10, 0, ManualRowY + 80)
				FavNameSearch.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
				FavNameSearch.PlaceholderText = "🔎 Search names…"
				FavNameSearch.Text = ""
				FavNameSearch.TextColor3 = Color3.fromRGB(235, 235, 240)
				FavNameSearch.Font = Enum.Font.SourceSans
				FavNameSearch.TextSize = 12
				FavNameSearch.ClearTextOnFocus = false
				FavNameSearch.Parent = Page1
				Instance.new("UICorner", FavNameSearch).CornerRadius = UDim.new(0, 5)
				local FavNameScroll = Instance.new("ScrollingFrame")
				FavNameScroll.Size = UDim2.new(1, -20, 0, 250)
				FavNameScroll.Position = UDim2.new(0, 10, 0, ManualRowY + 110)
				FavNameScroll.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
				FavNameScroll.BorderSizePixel = 0
				FavNameScroll.ScrollBarThickness = 4
				FavNameScroll.ScrollBarImageColor3 = Color3.fromRGB(0, 210, 255)
				FavNameScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
				FavNameScroll.Parent = Page1
				local favRows = {}
				local favRowMap = {}
				local favNameFilter = ""
				local function applyFavFilter(query)
					favNameFilter = string.lower(query or "")
					for _, r in ipairs(favRows) do
						if r and r.Parent then
							r.Visible = (favNameFilter == "" or string.find(string.lower(r.Text), favNameFilter, 1, true) ~= nil)
						end
					end
				end
				FavNameSearch:GetPropertyChangedSignal("Text"):Connect(function() applyFavFilter(FavNameSearch.Text) end)
				local function isNameInFavList(ln)
					for _, v in ipairs(favCustomNames) do if v == ln then return true end end
					return false
				end
				local function refreshManualBtn()
					local nm = ManualNameBox.Text
					if nm == "" then
						ManualFavBtn.BackgroundColor3 = Color3.fromRGB(40, 110, 80)
						ManualFavBtn.Text = "＋ Toggle Favorite"
					elseif isKnownName(nm) then
						local inList = isNameInFavList(normName(nm))
						ManualFavBtn.BackgroundColor3 = inList and Color3.fromRGB(0, 150, 105) or Color3.fromRGB(40, 110, 80)
						ManualFavBtn.Text = inList and ("★ " .. getDisplayName(nm) .. "  (click to remove)") or ("＋ Add " .. getDisplayName(nm) .. " to Favorites")
					else
						ManualFavBtn.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
						ManualFavBtn.Text = "❓ Name not found"
					end
				end
				ManualNameBox:GetPropertyChangedSignal("Text"):Connect(refreshManualBtn)
				local function attemptLiveFavorite(nm)
					local invItem = findInventoryItem(nm)
					if not invItem then return nil end
					local id = getAttrCI(invItem, "inventoryitemid") or getAttrCI(invItem, "itemid")
					if id then favoriteItem(id) return true end
					return false
				end
				ManualFavBtn.MouseButton1Click:Connect(function()
					local nm = ManualNameBox.Text
					if nm == "" then
						ManualFavStatus.Text = "Type a fish/bug name first (e.g. 'shadow_devil_whale_shark')."
						return
					end
					local display = getDisplayName(nm) or nm
					local lived = attemptLiveFavorite(nm)
					if lived == true then
						ManualFavStatus.Text = "⭐ Toggled favorite for '" .. display .. "' (live item)."
						return
					end
					if isKnownName(nm) then
						local ln = normName(nm)
						local inList = false
						for i = #favCustomNames, 1, -1 do
							if favCustomNames[i] == ln then table.remove(favCustomNames, i) inList = true break end
						end
						if not inList then table.insert(favCustomNames, ln) favManualSet[ln] = true else favManualSet[ln] = nil end
						local row = favRowMap[ln]
						if row and row.Parent then
							row.BackgroundColor3 = inList and Color3.fromRGB(30, 30, 38) or Color3.fromRGB(0, 130, 95)
						end
						refreshManualBtn()
						ManualFavStatus.Text = "Added '" .. display .. "' to favorite watch-list (not owned yet to toggle)."
					else
						ManualFavStatus.Text = "❓ '" .. nm .. "' is not a known fish/bug name. Example: 'shadow_devil_whale_shark'."
					end
				end)
				Instance.new("UICorner", FavNameScroll).CornerRadius = UDim.new(0, 6)
				local FavNameLayout = Instance.new("UIListLayout")
				FavNameLayout.SortOrder = Enum.SortOrder.LayoutOrder
				FavNameLayout.Padding = UDim.new(0, 2)
				FavNameLayout.Parent = FavNameScroll
				local favOrder = 0
				local function addFavHeader(text, color)
					favOrder = favOrder + 1
					local h = Instance.new("TextLabel")
					h.Size = UDim2.new(1, -8, 0, 22)
					h.BackgroundColor3 = color
					h.Text = "  " .. text
					h.TextColor3 = Color3.fromRGB(255, 255, 255)
					h.Font = Enum.Font.SourceSansBold
					h.TextSize = 12
					h.TextXAlignment = Enum.TextXAlignment.Left
					h.LayoutOrder = favOrder
					h.Parent = FavNameScroll
					Instance.new("UICorner", h).CornerRadius = UDim.new(0, 3)
				end
				local function addFavRow(nm)
					favOrder = favOrder + 1
					local row = Instance.new("TextButton")
					row.Size = UDim2.new(1, -8, 0, 22)
					row.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
					local favRarity = nameToRarity[nm]
					local favRarityColor = favRarity and RARITY_COLOR[favRarity] or Color3.fromRGB(210, 210, 215)
					row.Text = "   " .. (favRarity and ("[" .. favRarity .. "] ") or "") .. nm
					row.TextColor3 = favRarityColor
					row.Font = Enum.Font.SourceSans
					row.TextSize = 12
					row.TextXAlignment = Enum.TextXAlignment.Left
					row.LayoutOrder = favOrder
					row.Parent = FavNameScroll
					Instance.new("UICorner", row).CornerRadius = UDim.new(0, 3)
					local ln = normName(nm)
					local selected = isNameInFavList(ln)
					row.BackgroundColor3 = selected and Color3.fromRGB(0, 130, 95) or Color3.fromRGB(30, 30, 38)
					row.Visible = (favNameFilter == "" or string.find(string.lower(row.Text), favNameFilter, 1, true) ~= nil)
					table.insert(favRows, row)
					favRowMap[ln] = row
					row.MouseButton1Click:Connect(function()
						selected = not selected
						row.BackgroundColor3 = selected and Color3.fromRGB(0, 130, 95) or Color3.fromRGB(30, 30, 38)
						if selected then
							favManualSet[ln] = true
							if not isNameInFavList(ln) then table.insert(favCustomNames, ln) end
						else
							favManualSet[ln] = nil
							for j = #favCustomNames, 1, -1 do
								if favCustomNames[j] == ln then table.remove(favCustomNames, j) end
							end
						end
						local lived = attemptLiveFavorite(nm)
						if lived == true then
							ManualFavStatus.Text = "⭐ Toggled favorite for '" .. nm .. "' (live item)."
						elseif lived == false then
							ManualFavStatus.Text = "'" .. nm .. "' is not currently owned — tracked in favorite list only."
						end
						if normName(ManualNameBox.Text) == ln then refreshManualBtn() end
					end)
				end
				for _, rarity in ipairs(RARITY_ORDER) do
					local list = FISH_RARITY[rarity]
					if list then
						addFavHeader("FISH — " .. rarity:upper(), Color3.fromRGB(20, 90, 150))
						for internal, info in pairs(list) do
							if info then addFavRow(internal) end
						end
					end
				end
				for _, rarity in ipairs(RARITY_ORDER) do
					local list = BUG_RARITY[rarity]
					if list then
						addFavHeader("BUG — " .. rarity:upper(), Color3.fromRGB(150, 90, 20))
						for internal, info in pairs(list) do
							if info then addFavRow(internal) end
						end
					end
				end
				local function setFavSelected(ln, on)
					ln = normName(ln)
					if not on and favManualSet[ln] then
						local row = favRowMap[ln]
						if row and row.Parent then row.BackgroundColor3 = Color3.fromRGB(0, 130, 95) end
						return
					end
					local inList = false
					for _, v in ipairs(favCustomNames) do if v == ln then inList = true break end end
					if on and not inList then
						table.insert(favCustomNames, ln)
					elseif not on and inList then
						for j = #favCustomNames, 1, -1 do if favCustomNames[j] == ln then table.remove(favCustomNames, j) break end end
					end
					local row = favRowMap[ln]
					if row and row.Parent then
						row.BackgroundColor3 = on and Color3.fromRGB(0, 130, 95) or Color3.fromRGB(30, 30, 38)
					end
				end
				local function favNamesForSelector(key)
					local out = {}
					if key == "Fish" then
						for r, _ in pairs(FISH_RARITY) do
							local l = FISH_RARITY[r]
							if l then for internal, info in pairs(l) do if info then table.insert(out, internal) end end end
						end
					elseif key == "Bugs" then
						for r, _ in pairs(BUG_RARITY) do
							local l = BUG_RARITY[r]
							if l then for internal, info in pairs(l) do if info then table.insert(out, internal) end end end
						end
					else
						for _, tbl in ipairs({FISH_RARITY, BUG_RARITY}) do
							local l = tbl[key]
							if l then for internal, info in pairs(l) do if info then table.insert(out, internal) end end end
						end
					end
					return out
				end
				local favRarityActive = {}
				local function favNameCovered(name, exceptKey)
					local ln = normName(name)
					for k, on in pairs(favRarityActive) do
						if on and k ~= exceptKey then
							for _, n in ipairs(favNamesForSelector(k)) do
								if normName(n) == ln then return true end
							end
						end
					end
					return false
				end
				local function applyFavSelector(key, turnOn)
					favRarityActive[key] = turnOn
					for _, n in ipairs(favNamesForSelector(key)) do
						if turnOn then
							setFavSelected(n, true)
						elseif not favNameCovered(n, key) then
							setFavSelected(n, false)
						end
					end
				end
				local SelAllY = ManualRowY + 365
				local SelAllLabel = Instance.new("TextLabel")
				SelAllLabel.Size = UDim2.new(1, -20, 0, 18)
				SelAllLabel.Position = UDim2.new(0, 10, 0, SelAllY)
				SelAllLabel.Text = "⚡ Select ALL by rarity (click to toggle, multi-select):"
				SelAllLabel.TextColor3 = Color3.fromRGB(200, 205, 215)
				SelAllLabel.Font = Enum.Font.SourceSans
				SelAllLabel.TextSize = 12
				SelAllLabel.TextXAlignment = Enum.TextXAlignment.Left
				SelAllLabel.BackgroundTransparency = 1
				SelAllLabel.Parent = Page1
				local SelAllFrame = Instance.new("Frame")
				SelAllFrame.Size = UDim2.new(1, -20, 0, 150)
				SelAllFrame.Position = UDim2.new(0, 10, 0, SelAllY + 20)
				SelAllFrame.BackgroundTransparency = 1
				SelAllFrame.Parent = Page1
				local SelGrid = Instance.new("UIGridLayout")
				SelGrid.CellSize = UDim2.new(0, 170, 0, 30)
				SelGrid.CellPadding = UDim2.new(0, 6, 0, 6)
				SelGrid.SortOrder = Enum.SortOrder.LayoutOrder
				SelGrid.Parent = SelAllFrame
				local selBtnResets = {}
				local function makeSelBtn(text, cb, activeColor)
					activeColor = activeColor or Color3.fromRGB(0, 130, 95)
					local b = Instance.new("TextButton")
					b.Size = UDim2.new(0, 170, 0, 30)
					local defaultColor = Color3.fromRGB(40, 90, 120)
					local hoverColor = Color3.fromRGB(60, 120, 160)
					b.BackgroundColor3 = defaultColor
					b.Text = text
					b.TextColor3 = Color3.fromRGB(255, 255, 255)
					b.Font = Enum.Font.SourceSansBold
					b.TextSize = 11
					b.Parent = SelAllFrame
					Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
					local active = false
					b.MouseEnter:Connect(function() b.BackgroundColor3 = active and activeColor or hoverColor end)
					b.MouseLeave:Connect(function() b.BackgroundColor3 = active and activeColor or defaultColor end)
					b.MouseButton1Click:Connect(function()
						active = not active
						b.BackgroundColor3 = active and activeColor or defaultColor
						cb(active)
					end)
					table.insert(selBtnResets, function()
						active = false
						b.BackgroundColor3 = defaultColor
					end)
					return b
				end
				for _, rarity in ipairs(RARITY_ORDER) do
					makeSelBtn("✦ All " .. rarity, function(on) applyFavSelector(rarity, on) end)
				end
				makeSelBtn("🐟 All Fish", function(on) applyFavSelector("Fish", on) end)
				makeSelBtn("🐞 All Bugs", function(on) applyFavSelector("Bugs", on) end)
				autoDeleteEnabled = false
				autoDeleteNames = {}
				local yDel = SelAllY + 20 + 160
				local DelHeader = Instance.new("TextLabel")
				DelHeader.Size = UDim2.new(1, -20, 0, 30)
				DelHeader.Position = UDim2.new(0, 10, 0, yDel)
				DelHeader.Text = "🗑 AUTO DELETE SPECIFIC NAMES (deletes the caught item on catch)"
				DelHeader.TextColor3 = Color3.fromRGB(255, 120, 120)
				DelHeader.Font = Enum.Font.SourceSansBold
				DelHeader.TextSize = 13
				DelHeader.TextXAlignment = Enum.TextXAlignment.Left
				DelHeader.BackgroundTransparency = 1
				DelHeader.Parent = Page1
				local tDel = makeToggle("Auto Delete Specific Names", UDim2.new(0, 10, 0, yDel + 35), Page1, function(state)
					autoDeleteEnabled = state
				end)
				local DelNameBox = Instance.new("TextBox")
				DelNameBox.Size = UDim2.new(0, 300, 0, 30)
				DelNameBox.Position = UDim2.new(0, 10, 0, yDel + 77)
				DelNameBox.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
				DelNameBox.PlaceholderText = "Type exact name to auto-delete (e.g. Common Minnow)"
				DelNameBox.Text = ""
				DelNameBox.TextColor3 = Color3.fromRGB(235, 235, 240)
				DelNameBox.Font = Enum.Font.SourceSans
				DelNameBox.TextSize = 12
				DelNameBox.ClearTextOnFocus = false
				DelNameBox.Parent = Page1
				Instance.new("UICorner", DelNameBox).CornerRadius = UDim.new(0, 5)
				local DelAddBtn = Instance.new("TextButton")
				DelAddBtn.Size = UDim2.new(0, 180, 0, 30)
				DelAddBtn.Position = UDim2.new(0, 318, 0, yDel + 77)
				DelAddBtn.BackgroundColor3 = Color3.fromRGB(120, 50, 50)
				DelAddBtn.Text = "＋ Add to Delete List"
				DelAddBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
				DelAddBtn.Font = Enum.Font.SourceSansBold
				DelAddBtn.TextSize = 12
				DelAddBtn.Parent = Page1
				Instance.new("UICorner", DelAddBtn).CornerRadius = UDim.new(0, 5)
				applyButtonEffects(DelAddBtn, Color3.fromRGB(120, 50, 50), Color3.fromRGB(160, 70, 70))
				local DelStatus = Instance.new("TextLabel")
				DelStatus.Size = UDim2.new(1, -20, 0, 18)
				DelStatus.Position = UDim2.new(0, 10, 0, yDel + 111)
				DelStatus.Text = "Type a fish/bug name, then '＋ Add to Delete List'."
				DelStatus.TextColor3 = Color3.fromRGB(150, 155, 170)
				DelStatus.Font = Enum.Font.SourceSansItalic
				DelStatus.TextSize = 11
				DelStatus.TextXAlignment = Enum.TextXAlignment.Left
				DelStatus.BackgroundTransparency = 1
				DelStatus.Parent = Page1
				local DelListLabel = Instance.new("TextLabel")
				DelListLabel.Size = UDim2.new(1, -20, 0, 18)
				DelListLabel.Position = UDim2.new(0, 10, 0, yDel + 133)
				DelListLabel.Text = "Auto-Delete Names (click to toggle):"
				DelListLabel.TextColor3 = Color3.fromRGB(200, 205, 215)
				DelListLabel.Font = Enum.Font.SourceSans
				DelListLabel.TextSize = 12
				DelListLabel.TextXAlignment = Enum.TextXAlignment.Left
				DelListLabel.BackgroundTransparency = 1
				DelListLabel.Parent = Page1
				local DelScroll = Instance.new("ScrollingFrame")
				DelScroll.Size = UDim2.new(1, -20, 0, 220)
				DelScroll.Position = UDim2.new(0, 10, 0, yDel + 155)
				DelScroll.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
				DelScroll.BorderSizePixel = 0
				DelScroll.ScrollBarThickness = 4
				DelScroll.ScrollBarImageColor3 = Color3.fromRGB(0, 210, 255)
				DelScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
				DelScroll.Parent = Page1
				Instance.new("UICorner", DelScroll).CornerRadius = UDim.new(0, 6)
				local DelLayout = Instance.new("UIListLayout")
				DelLayout.SortOrder = Enum.SortOrder.LayoutOrder
				DelLayout.Padding = UDim.new(0, 2)
				DelLayout.Parent = DelScroll
				local delRows = {}
				local delRowMap = {}
				local function setDelSelected(ln, on)
					ln = normName(ln)
					local inList = false
					for _, v in ipairs(autoDeleteNames) do if v == ln then inList = true break end end
					if on and not inList then
						table.insert(autoDeleteNames, ln)
					elseif not on and inList then
						for j = #autoDeleteNames, 1, -1 do if autoDeleteNames[j] == ln then table.remove(autoDeleteNames, j) break end end
					end
					local row = delRowMap[ln]
					if row and row.Parent then
						row.BackgroundColor3 = on and Color3.fromRGB(140, 50, 50) or Color3.fromRGB(30, 30, 38)
					end
				end
				local function addDelRow(nm)
					local row = Instance.new("TextButton")
					row.Size = UDim2.new(1, -8, 0, 22)
					row.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
					local delRarity = nameToRarity[nm]
					local delRarityColor = delRarity and RARITY_COLOR[delRarity] or Color3.fromRGB(180, 180, 185)
					row.Text = "   " .. (delRarity and ("[" .. delRarity .. "] ") or "") .. nm
					row.TextColor3 = delRarityColor
					row.Font = Enum.Font.SourceSans
					row.TextSize = 12
					row.TextXAlignment = Enum.TextXAlignment.Left
					row.LayoutOrder = #delRows + 1
					row.Parent = DelScroll
					Instance.new("UICorner", row).CornerRadius = UDim.new(0, 3)
					local ln = normName(nm)
					local selected = nameInDeleteList(nm)
					row.BackgroundColor3 = selected and Color3.fromRGB(140, 50, 50) or Color3.fromRGB(30, 30, 38)
					table.insert(delRows, row)
					delRowMap[ln] = row
					row.MouseButton1Click:Connect(function()
						selected = not selected
						row.BackgroundColor3 = selected and Color3.fromRGB(140, 50, 50) or Color3.fromRGB(30, 30, 38)
						setDelSelected(ln, selected)
					end)
				end
				for _, rarity in ipairs(RARITY_ORDER) do
					local fl = FISH_RARITY[rarity]
					if fl then
						for internal, info in pairs(fl) do if info then addDelRow(internal) end end
					end
					local bl = BUG_RARITY[rarity]
					if bl then
						for internal, info in pairs(bl) do if info then addDelRow(internal) end end
					end
				end
				local delRarityActive = {}
				local function delNamesForSelector(key)
					local out = {}
					if key == "Fish" then
						for r, _ in pairs(FISH_RARITY) do
							local l = FISH_RARITY[r]
							if l then for internal, info in pairs(l) do if info then table.insert(out, internal) end end end
						end
					elseif key == "Bugs" then
						for r, _ in pairs(BUG_RARITY) do
							local l = BUG_RARITY[r]
							if l then for internal, info in pairs(l) do if info then table.insert(out, internal) end end end
						end
					else
						for _, tbl in ipairs({FISH_RARITY, BUG_RARITY}) do
							local l = tbl[key]
							if l then for internal, info in pairs(l) do if info then table.insert(out, internal) end end end
						end
					end
					return out
				end
				local function delNameCovered(name, exceptKey)
					local ln = normName(name)
					for k, on in pairs(delRarityActive) do
						if on and k ~= exceptKey then
							for _, n in ipairs(delNamesForSelector(k)) do
								if normName(n) == ln then return true end
							end
						end
					end
					return false
				end
				local function applyDelSelector(key, turnOn)
					delRarityActive[key] = turnOn
					for _, n in ipairs(delNamesForSelector(key)) do
						if turnOn then
							setDelSelected(n, true)
						elseif not delNameCovered(n, key) then
							setDelSelected(n, false)
						end
					end
				end
				local DelSelY = yDel + 385
				local DelSelLabel = Instance.new("TextLabel")
				DelSelLabel.Size = UDim2.new(1, -20, 0, 18)
				DelSelLabel.Position = UDim2.new(0, 10, 0, DelSelY)
				DelSelLabel.Text = "⚡ Select ALL by rarity (click to toggle, multi-select, auto-deletes):"
				DelSelLabel.TextColor3 = Color3.fromRGB(200, 205, 215)
				DelSelLabel.Font = Enum.Font.SourceSans
				DelSelLabel.TextSize = 12
				DelSelLabel.TextXAlignment = Enum.TextXAlignment.Left
				DelSelLabel.BackgroundTransparency = 1
				DelSelLabel.Parent = Page1
				local DelSelFrame = Instance.new("Frame")
				DelSelFrame.Size = UDim2.new(1, -20, 0, 110)
				DelSelFrame.Position = UDim2.new(0, 10, 0, DelSelY + 20)
				DelSelFrame.BackgroundTransparency = 1
				DelSelFrame.Parent = Page1
				local DelSelGrid = Instance.new("UIGridLayout")
				DelSelGrid.CellSize = UDim2.new(0, 170, 0, 30)
				DelSelGrid.CellPadding = UDim2.new(0, 6, 0, 6)
				DelSelGrid.SortOrder = Enum.SortOrder.LayoutOrder
				DelSelGrid.Parent = DelSelFrame
				local delBtnResets = {}
				local function makeDelSelBtn(text, cb)
					local b = Instance.new("TextButton")
					b.Size = UDim2.new(0, 170, 0, 30)
					local defaultColor = Color3.fromRGB(120, 60, 60)
					local hoverColor = Color3.fromRGB(160, 80, 80)
					local activeColor = Color3.fromRGB(190, 60, 60)
					b.BackgroundColor3 = defaultColor
					b.Text = text
					b.TextColor3 = Color3.fromRGB(255, 255, 255)
					b.Font = Enum.Font.SourceSansBold
					b.TextSize = 11
					b.Parent = DelSelFrame
					Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
					local active = false
					b.MouseEnter:Connect(function() b.BackgroundColor3 = active and activeColor or hoverColor end)
					b.MouseLeave:Connect(function() b.BackgroundColor3 = active and activeColor or defaultColor end)
					b.MouseButton1Click:Connect(function()
						active = not active
						b.BackgroundColor3 = active and activeColor or defaultColor
						cb(active)
					end)
					table.insert(delBtnResets, function()
						active = false
						b.BackgroundColor3 = defaultColor
					end)
					return b
				end
				for _, rarity in ipairs(RARITY_ORDER) do
					makeDelSelBtn("🗑 All " .. rarity, function(on) applyDelSelector(rarity, on) end)
				end
				makeDelSelBtn("🐟 All Fish", function(on) applyDelSelector("Fish", on) end)
				makeDelSelBtn("🐞 All Bugs", function(on) applyDelSelector("Bugs", on) end)
				Page1.CanvasSize = UDim2.new(0, 0, 0, math.max(950, DelSelY + 140))
				DelAddBtn.MouseButton1Click:Connect(function()
					local nm = DelNameBox.Text
					if nm == "" then
						DelStatus.Text = "Type a name first."
						return
					end
					local ln = normName(nm)
					local display = getDisplayName(nm) or nm
					if isKnownName(nm) then
						setDelSelected(ln, true)
						DelStatus.Text = "Added '" .. display .. "' to auto-delete list."
					else
						DelStatus.Text = "❓ '" .. nm .. "' is not a known fish/bug name."
					end
				end)
				local ResetY = DelSelY + 201.3
				local ResetBtn = Instance.new("TextButton")
				ResetBtn.Size = UDim2.new(0, 340, 0, 32)
				ResetBtn.Position = UDim2.new(0, 10, 0, ResetY)
				ResetBtn.BackgroundColor3 = Color3.fromRGB(90, 60, 120)
				ResetBtn.Text = "🔄 Reset Auto-Delete & Favorite Lists"
				ResetBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
				ResetBtn.Font = Enum.Font.SourceSansBold
				ResetBtn.TextSize = 13
				ResetBtn.Parent = Page1
				Instance.new("UICorner", ResetBtn).CornerRadius = UDim.new(0, 5)
				applyButtonEffects(ResetBtn, Color3.fromRGB(90, 60, 120), Color3.fromRGB(125, 85, 165))
				ResetBtn.MouseButton1Click:Connect(function()
					autoDeleteNames = {}
					favCustomNames = {}
					favManualSet = {}
					for _, fn in ipairs(selBtnResets) do pcall(fn) end
					for _, fn in ipairs(delBtnResets) do pcall(fn) end
					favRarityActive = {}
					delRarityActive = {}
					for _, r in ipairs(favRows) do if r and r.Parent then r.BackgroundColor3 = Color3.fromRGB(30, 30, 38) end end
					for _, r in ipairs(delRows) do if r and r.Parent then r.BackgroundColor3 = Color3.fromRGB(30, 30, 38) end end
					DelStatus.Text = "Lists reset — all auto-delete & favorite names cleared."
				end)
				RDR_CONFIG_DATA.reset = function()
					autoDeleteNames = {}
					favCustomNames = {}
					favManualSet = {}
					for _, fn in ipairs(selBtnResets) do pcall(fn) end
					for _, fn in ipairs(delBtnResets) do pcall(fn) end
					favRarityActive = {}
					delRarityActive = {}
					for _, r in ipairs(favRows) do if r and r.Parent then r.BackgroundColor3 = Color3.fromRGB(30, 30, 38) end end
					for _, r in ipairs(delRows) do if r and r.Parent then r.BackgroundColor3 = Color3.fromRGB(30, 30, 38) end end
				end
				RDR_CONFIG_DATA.getLists = function()
					local ms = {}
					for k, v in pairs(favManualSet) do ms[k] = v end
					local shopSel = {}
					if RDR_CONFIG_DATA.getShopSelections then
						local ok, sd = pcall(RDR_CONFIG_DATA.getShopSelections)
						if ok and sd then shopSel = sd end
					end
					return {
						favCustomNames = table.clone(favCustomNames),
						autoDeleteNames = table.clone(autoDeleteNames),
						favManualSet = ms,
						favRarityActive = table.clone(favRarityActive),
						delRarityActive = table.clone(delRarityActive),
						shopSelections = shopSel,
						catchScanEnabled = catchScanEnabled,
						isAutoBuying = RDR_CONFIG_DATA.getIsAutoBuying and RDR_CONFIG_DATA.getIsAutoBuying() or nil,
					}
				end
				RDR_CONFIG_DATA.applyLists = function(d)
					if not d then return end
					pcall(RDR_CONFIG_DATA.reset)
					for k, on in pairs(d.favRarityActive or {}) do if on then pcall(applyFavSelector, k, true) end end
					for k, on in pairs(d.delRarityActive or {}) do if on then pcall(applyDelSelector, k, true) end end
					for _, n in ipairs(d.favCustomNames or {}) do
						if not pcall(function() return favNameCovered(n) end) or not favNameCovered(n) then pcall(setFavSelected, n, true) end
					end
					for _, n in ipairs(d.autoDeleteNames or {}) do
						if not pcall(function() return delNameCovered(n) end) or not delNameCovered(n) then pcall(setDelSelected, n, true) end
					end
					if d.shopSelections and RDR_CONFIG_DATA.applyShopSelections then
						pcall(RDR_CONFIG_DATA.applyShopSelections, d.shopSelections)
					end
					if d.catchScanEnabled ~= nil then
						catchScanEnabled = d.catchScanEnabled
						updateScanToggleVisuals()
					end
					if d.isAutoBuying ~= nil and RDR_CONFIG_DATA.setIsAutoBuying then
						pcall(RDR_CONFIG_DATA.setIsAutoBuying, d.isAutoBuying)
					end
				end
				local CfgY = DelSelY + 200
				local function makeCfgBtn(label, x, color)
					local B = Instance.new("TextButton")
					B.Size = UDim2.new(0, 165, 0, 32)
					B.Position = UDim2.new(0, x, 0, CfgY)
					B.BackgroundColor3 = color
					B.Text = label
					B.TextColor3 = Color3.fromRGB(255, 255, 255)
					B.Font = Enum.Font.SourceSansBold
					B.TextSize = 13
					B.Parent = Page1
					Instance.new("UICorner", B).CornerRadius = UDim.new(0, 5)
					if applyButtonEffects then pcall(applyButtonEffects, B, color, color) end
					return B
				end
				makeToggle("🛡 Safe Mode (pause near players)", UDim2.new(0, 10, 0, CfgY + 40), Page1, function(state)
					safeModeActive = state
				end)
				local ProfLabel = Instance.new("TextLabel")
				ProfLabel.Size = UDim2.new(1, -20, 0, 18)
				ProfLabel.Position = UDim2.new(0, 10, 0, CfgY + 160)
				ProfLabel.Text = "Config profile name:"
				ProfLabel.TextColor3 = Color3.fromRGB(170, 175, 190)
				ProfLabel.Font = Enum.Font.SourceSans
				ProfLabel.TextSize = 11
				ProfLabel.TextXAlignment = Enum.TextXAlignment.Left
				ProfLabel.BackgroundTransparency = 1
				ProfLabel.Parent = Page1
				local ProfBox = Instance.new("TextBox")
				ProfBox.Size = UDim2.new(1, -20, 0, 26)
				ProfBox.Position = UDim2.new(0, 10, 0, CfgY + 178)
				ProfBox.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
				ProfBox.PlaceholderText = "e.g. farm"
				ProfBox.Text = ""
				ProfBox.TextColor3 = Color3.fromRGB(235, 235, 240)
				ProfBox.Font = Enum.Font.SourceSans
				ProfBox.TextSize = 12
				ProfBox.ClearTextOnFocus = false
				ProfBox.Parent = Page1
				Instance.new("UICorner", ProfBox).CornerRadius = UDim.new(0, 4)
				createActionButton("💾 Save Profile", UDim2.new(0, 10, 0, CfgY + 210), UDim2.new(0, 175, 0, 32), Page1, function()
					local name = ProfBox.Text:match("^%s*(.-)%s*$")
					if name == "" then DelStatus.Text = "Profile name required." return end
					local where = saveRDRConfig(name)
					DelStatus.Text = "Profile '" .. name .. "' saved (" .. where .. ")."
				end)
				createActionButton("📂 Load Profile", UDim2.new(0, 200, 0, CfgY + 210), UDim2.new(0, 175, 0, 32), Page1, function()
					local name = ProfBox.Text:match("^%s*(.-)%s*$")
					if name == "" then DelStatus.Text = "Profile name required." return end
					local ok, msg = loadRDRConfig(name)
					DelStatus.Text = ok and ("Profile '" .. name .. "' loaded.") or ("Load failed: " .. tostring(msg))
					if ok and autoClaimDaily then task.spawn(claimDaily) end
				end)
				local antiAfkActive = false
				local antiAfkThread = nil
				local antiAfkInterval = 30
				local function antiAfkLoop()
					while antiAfkActive do
						task.wait(antiAfkInterval)
						if not antiAfkActive then break end
						pcall(function()
							VirtualUser:CaptureController()
							VirtualUser:Button1Down(Vector2.new(0, 0))
							VirtualUser:Button1Up(Vector2.new(0, 0))
						end)
						showToast("⚡ Anti-AFK ping", Color3.fromRGB(0, 210, 255), 1)
					end
				end
				makeToggle("⚡ Anti-AFK (prevent idle kick)", UDim2.new(0, 10, 0, CfgY + 254), Page1, function(state)
					antiAfkActive = state
					if state then
						if antiAfkThread then task.cancel(antiAfkThread) end
						antiAfkThread = task.spawn(antiAfkLoop)
					else
						antiAfkActive = false
						if antiAfkThread then task.cancel(antiAfkThread) antiAfkThread = nil end
					end
				end)
				local AfkIntLbl = Instance.new("TextLabel")
				AfkIntLbl.Size = UDim2.new(0, 120, 0, 32)
				AfkIntLbl.Position = UDim2.new(0, 210, 0, CfgY + 254)
				AfkIntLbl.Text = "Ping every (s):"
				AfkIntLbl.TextColor3 = Color3.fromRGB(200, 205, 215)
				AfkIntLbl.Font = Enum.Font.SourceSans
				AfkIntLbl.TextSize = 12
				AfkIntLbl.TextXAlignment = Enum.TextXAlignment.Left
				AfkIntLbl.BackgroundTransparency = 1
				AfkIntLbl.Parent = Page1
				createAmtInputBox(UDim2.new(0, 330, 0, CfgY + 254), 30, Page1, function(v) antiAfkInterval = math.clamp(math.floor(v), 5, 300) end)
				local PROMO_CODES = {"RELEASEDAY", "HAPPYBIRTHDAYGQ", "FISHQUEST", "BIGSPOON", "MAGICFOREST", "ORB", "CABBAGE", "FOX", "ROCKET"}
				local PROMO_DESCRIPTIONS = {
					RELEASEDAY = "x5 Premium Flower Pack",
					HAPPYBIRTHDAYGQ = "x1 Birthday Cow",
					FISHQUEST = "x1 Bottle of Fishing",
					BIGSPOON = "x3 Retrievers",
					MAGICFOREST = "x1 Neptune Sprinkler",
					ORB = "x3 Scythe",
					CABBAGE = "x1 Premium Cabbage Pack",
					FOX = "x1 Fox Egg",
					ROCKET = "x1 Permanent Lock",
				}
				local CodeLog
				local autoRedeemCodes = false
				local autoRedeemThread = nil
				local function redeemCodes()
					local rem = ReplicatedStorage:FindFirstChild("RedeemCode", true)
					if not rem then
						showToast("⚠ Code remote not found", Color3.fromRGB(255, 120, 120), 3)
						return
					end
					for _, code in ipairs(PROMO_CODES) do
						local ok = pcall(function()
							if typeof(rem.InvokeServer) == "function" then rem:InvokeServer(code) else rem:FireServer(code) end
						end)
						if CodeLog then
							local description = PROMO_DESCRIPTIONS[code] or "Description unavailable"
							CodeLog.add("🎟 " .. (ok and "Redeemed" or "Failed") .. ": " .. code .. " — " .. description, ok and Color3.fromRGB(150, 255, 180) or Color3.fromRGB(255, 160, 160))
						end
					end
					showToast("🎟 Tried " .. #PROMO_CODES .. " codes", Color3.fromRGB(200, 200, 255), 2)
				end
				local function autoRedeemLoop()
					while autoRedeemCodes do
						redeemCodes()
						local cooldown = 0
						while autoRedeemCodes and cooldown < 30 do
							task.wait(1)
							cooldown = cooldown + 1
						end
					end
				end
				createActionButton("🎟 Redeem Now", UDim2.new(0, 10, 0, CfgY + 344), UDim2.new(0, 175, 0, 32), Page1, function()
					task.spawn(redeemCodes)
				end)
				do
					local clY = CfgY + 380
					local clAccent = Color3.fromRGB(200, 200, 255)
					local CLHeader = Instance.new("TextLabel")
					CLHeader.Size = UDim2.new(1, -20, 0, 22)
					CLHeader.Position = UDim2.new(0, 10, 0, clY)
					CLHeader.Text = "🎟 Code Log — Enter a code below"
					CLHeader.TextColor3 = clAccent
					CLHeader.Font = Enum.Font.SourceSansBold
					CLHeader.TextSize = 13
					CLHeader.TextXAlignment = Enum.TextXAlignment.Left
					CLHeader.BackgroundTransparency = 1
					CLHeader.Parent = Page1
					local CodeInput = Instance.new("TextBox")
					CodeInput.Size = UDim2.new(0, 245, 0, 30)
					CodeInput.Position = UDim2.new(0, 10, 0, clY + 24)
					CodeInput.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
					CodeInput.PlaceholderText = "Enter code here..."
					CodeInput.Text = ""
					CodeInput.TextColor3 = Color3.fromRGB(235, 235, 240)
					CodeInput.Font = Enum.Font.SourceSans
					CodeInput.TextSize = 13
					CodeInput.ClearTextOnFocus = false
					CodeInput.Parent = Page1
					Instance.new("UICorner", CodeInput).CornerRadius = UDim.new(0, 5)
					local SubmitBtn = Instance.new("TextButton")
					SubmitBtn.Size = UDim2.new(0, 85, 0, 30)
					SubmitBtn.Position = UDim2.new(0, 260, 0, clY + 24)
					SubmitBtn.BackgroundColor3 = Color3.fromRGB(80, 60, 140)
					SubmitBtn.Text = "Submit"
					SubmitBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
					SubmitBtn.Font = Enum.Font.SourceSansBold
					SubmitBtn.TextSize = 13
					SubmitBtn.Parent = Page1
					Instance.new("UICorner", SubmitBtn).CornerRadius = UDim.new(0, 5)
					applyButtonEffects(SubmitBtn, Color3.fromRGB(80, 60, 140), Color3.fromRGB(110, 85, 170))
					local CLFrame = Instance.new("ScrollingFrame")
					CLFrame.Size = UDim2.new(1, -20, 0, 88)
					CLFrame.Position = UDim2.new(0, 10, 0, clY + 60)
					CLFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
					CLFrame.BorderSizePixel = 0
					CLFrame.ScrollBarThickness = 4
					CLFrame.ScrollBarImageColor3 = clAccent
					CLFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
					CLFrame.Parent = Page1
					Instance.new("UICorner", CLFrame).CornerRadius = UDim.new(0, 6)
					local CLLayout = Instance.new("UIListLayout")
					CLLayout.SortOrder = Enum.SortOrder.LayoutOrder
					CLLayout.Padding = UDim.new(0, 2)
					CLLayout.Parent = CLFrame
					local clOrder = 0
					local function clAdd(text, color)
						clOrder = clOrder + 1
						local e = Instance.new("TextLabel")
						e.Size = UDim2.new(1, -10, 0, 28)
						e.BackgroundTransparency = 1
						e.Text = text
						e.TextColor3 = color or Color3.fromRGB(235, 235, 240)
						e.Font = Enum.Font.SourceSans
						e.TextSize = 11
						e.TextWrapped = true
						e.TextXAlignment = Enum.TextXAlignment.Left
						e.LayoutOrder = clOrder
						e.Parent = CLFrame
						CLFrame.CanvasSize = UDim2.new(0, 0, 0, CLLayout.AbsoluteContentSize.Y + 8)
						return e
					end
					local function clClear()
						for _, c in ipairs(CLFrame:GetChildren()) do
							if c:IsA("TextLabel") then c:Destroy() end
						end
						clOrder = 0
						CLFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
					end
					CodeLog = { frame = CLFrame, add = clAdd, clear = clClear }
					clAdd("📋 Available codes:", clAccent)
					for _, code in ipairs(PROMO_CODES) do
						local desc = PROMO_DESCRIPTIONS[code] or "Unknown"
						clAdd("  • " .. code .. " — " .. desc, Color3.fromRGB(180, 180, 200))
					end
					local function submitCode()
						local code = CodeInput.Text:match("^%s*(.-)%s*$")
						if code == "" then
							showToast("⚠ Enter a code first", Color3.fromRGB(255, 170, 90), 2)
							return
						end
						local rem = ReplicatedStorage:FindFirstChild("RedeemCode", true)
						if not rem then
							clAdd("✗ Code remote not found", Color3.fromRGB(255, 120, 120))
							return
						end
						local ok = pcall(function()
							if typeof(rem.InvokeServer) == "function" then rem:InvokeServer(code) else rem:FireServer(code) end
						end)
						clAdd((ok and "✓" or "✗") .. " " .. code .. " — " .. (ok and "Redeemed" or "Failed"), ok and Color3.fromRGB(150, 255, 180) or Color3.fromRGB(255, 160, 160))
						showToast("🎟 Tried: " .. code, clAccent, 2)
						CodeInput.Text = ""
					end
					SubmitBtn.MouseButton1Click:Connect(function()
						task.spawn(submitCode)
					end)
					CodeInput.FocusLost:Connect(function(enterPressed)
						if enterPressed then
							task.spawn(submitCode)
						end
					end)
				end
				local codeInstr = Instance.new("TextLabel")
				codeInstr.Size = UDim2.new(1, -20, 0, 36)
				codeInstr.Position = UDim2.new(0, 10, 0, CfgY + 532)
				codeInstr.Text = "📝 How to use: Type a code in the box above → press Submit or hit Enter. Click 'Redeem Now' to auto-redeem all known codes."
				codeInstr.TextColor3 = Color3.fromRGB(150, 150, 160)
				codeInstr.Font = Enum.Font.SourceSans
				codeInstr.TextSize = 11
				codeInstr.TextWrapped = true
				codeInstr.TextXAlignment = Enum.TextXAlignment.Left
				codeInstr.BackgroundTransparency = 1
				codeInstr.Parent = Page1
				local plCat, sg
				local function _buildBugLog()
					local plAuto,plThread=false,nil
					local plRemote=ReplicatedStorage:FindFirstChild("Remotes")
					if plRemote then plRemote=plRemote:FindFirstChild("BugCatching")
						if plRemote then plRemote=plRemote:FindFirstChild("RequestCatch") end end
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
					abcBtn.MouseButton1Click:Connect(function() plSet(not plAuto) abcRefresh() end)
					local function plPos(t)
						if not t then return nil end
						if t:IsA("PVInstance") then return t:GetPivot().Position
						elseif t:IsA("BasePart") then return t.Position
						elseif t:IsA("Model") then local p=t.PrimaryPart or t:FindFirstChildWhichIsA("BasePart",true) return p and p.Position end
					end
					local function plTP(t)
						local c=Player.Character if not c then return end
						local p=plPos(t) if p then c:PivotTo(CFrame.new(p+Vector3.new(0,3,0))) end
					end
					local function plCopy(t)
						local p=plPos(t)
						if p then local s=string.format("%.2f, %.2f, %.2f",p.X,p.Y,p.Z)
							if setclipboard then setclipboard(s) elseif Clipboard and Clipboard.set then Clipboard.set(s) end end
					end
					local function plGD(c,d)
						local a=c:GetAttribute(d) if a~=nil then return tostring(a) end
						local o=c:FindFirstChild(d) return o and o:IsA("ValueBase") and tostring(o.Value) or nil
					end
					local function plAmt(t)
						if not t then return 0 end
						local n,s=string.match(t:lower(),"([%d%.]+)%s*([kmb]?)") if not n then return 0 end
						local v=tonumber(n) or 0
						if s=="k" then v=v*1e3 elseif s=="m" then v=v*1e6 elseif s=="b" then v=v*1e9 end return v
					end
					local function plCFD(c)
						local d,isFav,amt={},false,0
						local cf=c:FindFirstChild("ContentFrame")
						if cf then
							local fb=cf:FindFirstChild("FavoriteButton")
							if fb and fb:IsA("GuiObject") then isFav=fb.Visible; table.insert(d,"Favorite: "..(isFav and "Yes" or "No"))
							else table.insert(d,"Favorite: No") end
							local al=cf:FindFirstChild("AmountLabel")
							if al and (al:IsA("TextLabel") or al:IsA("TextButton")) and al.Text~="" then
								table.insert(d,"Amount: "..al.Text) amt=plAmt(al.Text) end
						end return d,isFav,amt
					end
					local function plFmt(c,attr,realName,isInv)
						local d={}
						if isInv then for _,v in ipairs(plCFD(c)) do table.insert(d,v) end end
						local m=c.Name
						if not realName then m=plGD(c,"ItemName") or c.Name
							local cat=plGD(c,"Category") if cat then table.insert(d,"Category: "..cat) end end
						if attr then for _,n in ipairs(attr) do
								if n~="ItemName" and n~="Category" and n~="Amount" then
									local v=plGD(c,n) if v then table.insert(d,n..": "..v) end end end end
						return "• "..m..(#d>0 and " ["..table.concat(d," | ").."]" or "")
					end
					local function plBFmt(c)
						local d={} local z=plGD(c,"BugZoneId") if z then table.insert(d,"Zone: "..z) end
						local b=plGD(c,"BugId") if b then table.insert(d,"ID: "..b) end
						return "• "..c.Name..(#d>0 and " ["..table.concat(d," | ").."]" or "")
					end
					local function plFire(bug) local id=plGD(bug,"BugId") or bug.Name if plRemote then plRemote:FireServer(id) end end
					local function plMini() local g=PlayerGui:FindFirstChild("BugMinigameGui")
						return g and g.Enabled and g:FindFirstChild("BugBoxContainer") and g.BugBoxContainer.Visible end
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
						local ct=PlayerGui:FindFirstChild("BugMinigameGui")
						ct=ct and ct:FindFirstChild("BugBoxContainer")
						local cb=ct and ct:FindFirstChild("CatchBox") local bb=ct and ct:FindFirstChild("BugBox")
						if cb and bb then if cb.AbsolutePosition.X<bb.AbsolutePosition.X then VirtualUser:Button1Down(Vector2.new())
							else VirtualUser:Button1Up(Vector2.new()) end else VirtualUser:Button1Up(Vector2.new()) end
					end)
					local function plStart()
						if plThread then return end plThread=task.spawn(function()
							while plAuto do
								local af=workspace:FindFirstChild("ActiveBugVisuals") local bl={}
								if af then for _,b in ipairs(af:GetDescendants()) do
										if b:IsA("BasePart") and b.Name == "BugHitbox" then
											table.insert(bl,{b,tonumber(plGD(b,"BugId")) or math.huge}) end end
									table.sort(bl,function(a,b) return a[2]<b[2] end) end
								if #bl>0 then for i=1,#bl do if not plAuto then break end local t=bl[i][1]
										if t and t.Parent then plTP(t) task.wait(0.5)
											if plAuto and t and t.Parent then plFire(t) end task.wait(1)
											while plAuto and plMini() do task.wait(0.2) end end end
								else task.wait(0.5) end end plThread=nil
						end)
					end
					sg=Instance.new("ScreenGui") sg.Name="MasterLogGui" sg.ResetOnSpawn=false sg.Parent=PlayerGui sg.Enabled=false
					local mf=Instance.new("Frame") mf.Name="MainMasterLogFrame" mf.Size=UDim2.new(0,540,0,660)
					mf.Position=UDim2.new(0.35,0,0.15,0) mf.BackgroundColor3=Color3.fromRGB(25,25,30)
					mf.BorderSizePixel=0 mf.Active=true mf.Draggable=true mf.Parent=sg
					Instance.new("UICorner",mf).CornerRadius=UDim.new(0,8)
					local tbf=Instance.new("Frame") tbf.Size=UDim2.new(1,0,0,40)
					tbf.BackgroundColor3=Color3.fromRGB(35,35,42) tbf.BorderSizePixel=0 tbf.Parent=mf
					Instance.new("UICorner",tbf).CornerRadius=UDim.new(0,8)
					local tl=Instance.new("TextLabel") tl.Size=UDim2.new(1,-270,0,40)
					tl.Position=UDim2.new(0,12,0,0) tl.BackgroundTransparency=1
					tl.Text="📋 ALL-IN-ONE MASTER LOG" tl.TextColor3=Color3.fromRGB(0,210,255)
					tl.TextXAlignment=Enum.TextXAlignment.Left tl.Font=Enum.Font.SourceSansBold tl.TextSize=16 tl.Parent=tbf
					local ctb=Instance.new("TextButton") ctb.Size=UDim2.new(0,200,0,26)
					ctb.Position=UDim2.new(1,-250,0,7) ctb.BackgroundColor3=Color3.fromRGB(180,50,50)
					ctb.Text="Auto Catch: OFF [F/Y]" ctb.TextColor3=Color3.fromRGB(255,255,255)
					ctb.Font=Enum.Font.SourceSansBold ctb.TextSize=12 ctb.BorderSizePixel=0 ctb.Parent=tbf
					Instance.new("UICorner",ctb).CornerRadius=UDim.new(0,5)
					local plClose=Instance.new("TextButton") plClose.Size=UDim2.new(0,30,0,26)
					plClose.Position=UDim2.new(1,-34,0,7) plClose.BackgroundColor3=Color3.fromRGB(180,50,50)
					plClose.Text="✕" plClose.TextColor3=Color3.fromRGB(255,255,255)
					plClose.Font=Enum.Font.SourceSansBold plClose.TextSize=14 plClose.BorderSizePixel=0 plClose.Parent=tbf
					Instance.new("UICorner",plClose).CornerRadius=UDim.new(0,5)
					plClose.MouseButton1Click:Connect(function() sg.Enabled=false end)
					local function plSet(on)
						plAuto=on
						if on then ctb.BackgroundColor3=Color3.fromRGB(0,160,90) ctb.Text="Auto Catch: ON [F/Y]" plStart()
						else ctb.BackgroundColor3=Color3.fromRGB(180,50,50) ctb.Text="Auto Catch: OFF [F/Y]" end
						if abcRefresh then abcRefresh() end
					end
					ctb.MouseButton1Click:Connect(function() plSet(not plAuto) end)
					UserInputService.InputBegan:Connect(function(i,gp)
						if not gp and i.UserInputType==Enum.UserInputType.Keyboard then
							if i.KeyCode==Enum.KeyCode.F then plSet(true)
							elseif i.KeyCode==Enum.KeyCode.Y then plSet(false) end if abcRefresh then abcRefresh() end end end)
					local sf=Instance.new("ScrollingFrame") sf.Size=UDim2.new(1,-16,1,-48)
					sf.Position=UDim2.new(0,8,0,44) sf.BackgroundTransparency=1 sf.BorderSizePixel=0
					sf.ScrollBarThickness=4 sf.ScrollBarImageColor3=Color3.fromRGB(0,210,255)
					sf.CanvasSize=UDim2.new(0,0,0,0) sf.AutomaticCanvasSize=Enum.AutomaticSize.Y sf.Parent=mf
					local sfl=Instance.new("UIListLayout") sfl.SortOrder=Enum.SortOrder.LayoutOrder
					sfl.Padding=UDim.new(0,6) sfl.Parent=sf
					plCat=function(cfg)
						local title,cont,hideTP,hasTN,hasSO,hasFF,isInv,attr,accent,hasCatch=
							cfg.Title,cfg.Path,cfg.HideTP,cfg.HasToggleName,cfg.HasSortOption,
						cfg.HasFavFilterOption,cfg.IsInventory,cfg.Attributes,
						cfg.Accent or Color3.fromRGB(85,170,255),cfg.HasCatch
						local realName,sMode,fMode=false,"Name","All"
						local cf=Instance.new("Frame") cf.Size=UDim2.new(1,-6,0,30)
						cf.BackgroundColor3=Color3.fromRGB(32,32,38) cf.BorderSizePixel=0
						cf.AutomaticSize=Enum.AutomaticSize.Y cf.Parent=sf
						Instance.new("UICorner",cf).CornerRadius=UDim.new(0,6)
						local ct=Instance.new("TextLabel") ct.Size=UDim2.new(1,-310,0,25)
						ct.Position=UDim2.new(0,10,0,0) ct.BackgroundTransparency=1
						ct.Text="  "..title.." (0)" ct.TextColor3=accent
						ct.TextXAlignment=Enum.TextXAlignment.Left ct.Font=Enum.Font.SourceSansBold
						ct.TextSize=13 ct.Parent=cf
						local ilf=Instance.new("Frame") ilf.Size=UDim2.new(1,0,0,0)
						ilf.Position=UDim2.new(0,0,0,25) ilf.BackgroundTransparency=1
						ilf.AutomaticSize=Enum.AutomaticSize.Y ilf.Parent=cf
						local ill=Instance.new("UIListLayout") ill.SortOrder=Enum.SortOrder.LayoutOrder
						ill.Padding=UDim.new(0,2) ill.Parent=ilf
						if not cont then ct.Text="  "..title.." (NOT FOUND)"
							ct.TextColor3=Color3.fromRGB(220,80,80) return end
						local tracked={}
						local function upC() local n=0 for _,d in pairs(tracked) do
								if d.f.Visible then n=n+1 end end ct.Text=string.format("  %s (%d)",title,n) end
						local function sortF()
							local l={} for c,d in pairs(tracked) do table.insert(l,{c,d}) end
							table.sort(l,function(a,b)
								local na=(plGD(a[1],"ItemName") or a[1].Name):lower()
								local nb=(plGD(b[1],"ItemName") or b[1].Name):lower()
								if sMode=="Amount" then local _,_,amA=plCFD(a[1]) local _,_,amB=plCFD(b[1])
									if amA~=amB then return amA>amB end end return na<nb end)
							for i,e in ipairs(l) do e[2].f.LayoutOrder=i
								if isInv and fMode~="All" then local _,isF=plCFD(e[1])
									if fMode=="No" then e[2].f.Visible=not isF
									elseif fMode=="Yes" then e[2].f.Visible=isF end
								else e[2].f.Visible=true end end upC()
						end
						local function refresh() for c,d in pairs(tracked) do
								if d.l then d.l.Text=hasCatch and plBFmt(c) or plFmt(c,attr,realName,isInv) end end sortF() end
						if hasFF then
							local sa=Instance.new("TextButton") sa.Size=UDim2.new(0,60,0,18)
							sa.Position=UDim2.new(1,-295,0,4) sa.BackgroundColor3=Color3.fromRGB(0,140,90)
							sa.Text="Show All" sa.TextColor3=Color3.fromRGB(255,255,255)
							sa.Font=Enum.Font.SourceSansBold sa.TextSize=11 sa.BorderSizePixel=0 sa.Parent=cf
							Instance.new("UICorner",sa).CornerRadius=UDim.new(0,4)
							local fb=Instance.new("TextButton") fb.Size=UDim2.new(0,80,0,18)
							fb.Position=UDim2.new(1,-230,0,4) fb.BackgroundColor3=Color3.fromRGB(50,50,65)
							fb.Text="Favorite: No" fb.TextColor3=Color3.fromRGB(220,220,220)
							fb.Font=Enum.Font.SourceSansBold fb.TextSize=11 fb.BorderSizePixel=0 fb.Parent=cf
							Instance.new("UICorner",fb).CornerRadius=UDim.new(0,4)
							sa.MouseButton1Click:Connect(function() fMode="All"
								sa.BackgroundColor3=Color3.fromRGB(0,140,90) fb.BackgroundColor3=Color3.fromRGB(50,50,65) sortF() end)
							fb.MouseButton1Click:Connect(function() fMode=fMode=="No" and "Yes" or "No"
								fb.Text="Favorite: "..fMode fb.BackgroundColor3=Color3.fromRGB(80,70,120)
								sa.BackgroundColor3=Color3.fromRGB(50,50,65) sortF() end)
						end
						if hasSO then
							local sb=Instance.new("TextButton") sb.Size=UDim2.new(0,70,0,18)
							sb.Position=UDim2.new(1,-145,0,4) sb.BackgroundColor3=Color3.fromRGB(50,50,65)
							sb.Text="Sort: Name" sb.TextColor3=Color3.fromRGB(220,220,220)
							sb.Font=Enum.Font.SourceSansBold sb.TextSize=11 sb.BorderSizePixel=0 sb.Parent=cf
							Instance.new("UICorner",sb).CornerRadius=UDim.new(0,4)
							sb.MouseButton1Click:Connect(function() sMode=sMode=="Name" and "Amount" or "Name"
								sb.Text="Sort: "..sMode sortF() end)
						end
						if hasTN then
							local tg=Instance.new("TextButton") tg.Size=UDim2.new(0,65,0,18)
							tg.Position=UDim2.new(1,-70,0,4) tg.BackgroundColor3=Color3.fromRGB(60,60,75)
							tg.Text="Real Name" tg.TextColor3=Color3.fromRGB(200,200,200)
							tg.Font=Enum.Font.SourceSansBold tg.TextSize=11 tg.BorderSizePixel=0 tg.Parent=cf
							Instance.new("UICorner",tg).CornerRadius=UDim.new(0,4)
							tg.MouseButton1Click:Connect(function() realName=not realName
								if realName then tg.BackgroundColor3=Color3.fromRGB(0,150,100) tg.Text="Attributes"
								else tg.BackgroundColor3=Color3.fromRGB(60,60,75) tg.Text="Real Name" end refresh() end)
						end
						local function addRow(child)
							if title == "ACTIVE BUGS LOG" and child.Name ~= "BugHitbox" then return end
							if tracked[child] then return end
							local rf=Instance.new("Frame") rf.Name=child.Name
							rf.Size=UDim2.new(1,-8,0,22) rf.BackgroundColor3=Color3.fromRGB(28,28,34)
							rf.BorderSizePixel=0 rf.Parent=ilf
							Instance.new("UICorner",rf).CornerRadius=UDim.new(0,4)
							local lbl=Instance.new("TextLabel")
							lbl.Size=UDim2.new(1,hideTP and -10 or (hasCatch and -125 or -75),1,0)
							lbl.Position=UDim2.new(0,10,0,0) lbl.BackgroundTransparency=1
							lbl.Text=hasCatch and plBFmt(child) or plFmt(child,attr,realName,isInv)
							lbl.TextColor3=Color3.fromRGB(235,235,240)
							lbl.TextXAlignment=Enum.TextXAlignment.Left lbl.Font=Enum.Font.SourceSans
							lbl.TextSize=12 lbl.TextTruncate=Enum.TextTruncate.AtEnd lbl.Parent=rf
							local conns={}
							local function upd()
								lbl.Text=hasCatch and plBFmt(child) or plFmt(child,attr,realName,isInv) sortF() end
							table.insert(conns,child.AttributeChanged:Connect(upd))
							table.insert(conns,child.ChildAdded:Connect(upd))
							table.insert(conns,child.ChildRemoved:Connect(upd))
							if isInv then local cf2=child:FindFirstChild("ContentFrame")
								if cf2 then local fb2=cf2:FindFirstChild("FavoriteButton")
									if fb2 then table.insert(conns,fb2:GetPropertyChangedSignal("Visible"):Connect(upd)) end
									local al2=cf2:FindFirstChild("AmountLabel")
									if al2 then table.insert(conns,al2:GetPropertyChangedSignal("Text"):Connect(upd)) end
								else table.insert(conns,child.ChildAdded:Connect(function(nc)
										if nc.Name=="ContentFrame" then local fb3=nc:FindFirstChild("FavoriteButton")
											if fb3 then table.insert(conns,fb3:GetPropertyChangedSignal("Visible"):Connect(upd)) end
											local al3=nc:FindFirstChild("AmountLabel")
											if al3 then table.insert(conns,al3:GetPropertyChangedSignal("Text"):Connect(upd)) end upd() end end)) end
							end
							if hasCatch then
								local cb=Instance.new("TextButton") cb.Size=UDim2.new(0,45,0,18)
								cb.Position=UDim2.new(1,-116,0,2) cb.BackgroundColor3=Color3.fromRGB(180,100,0)
								cb.Text="Catch" cb.TextColor3=Color3.fromRGB(255,255,255)
								cb.Font=Enum.Font.SourceSansBold cb.TextSize=11 cb.BorderSizePixel=0 cb.Parent=rf
								Instance.new("UICorner",cb).CornerRadius=UDim.new(0,4)
								applyButtonEffects(cb,Color3.fromRGB(180,100,0),Color3.fromRGB(210,130,20))
								cb.MouseButton1Click:Connect(function()
									task.spawn(function() plTP(child) task.wait(0.5) plFire(child) end) end)
							end
							if not hideTP then
								local cp=Instance.new("TextButton") cp.Size=UDim2.new(0,26,0,18)
								cp.Position=UDim2.new(1,-66,0,2) cp.BackgroundColor3=Color3.fromRGB(70,70,90)
								cp.Text="📋" cp.TextColor3=Color3.fromRGB(255,255,255)
								cp.Font=Enum.Font.SourceSansBold cp.TextSize=11 cp.BorderSizePixel=0 cp.Parent=rf
								Instance.new("UICorner",cp).CornerRadius=UDim.new(0,4)
								applyButtonEffects(cp,Color3.fromRGB(70,70,90),Color3.fromRGB(90,90,110))
								cp.MouseButton1Click:Connect(function() plCopy(child) end)
								local tp=Instance.new("TextButton") tp.Size=UDim2.new(0,35,0,18)
								tp.Position=UDim2.new(1,-38,0,2) tp.BackgroundColor3=Color3.fromRGB(0,120,215)
								tp.Text="TP" tp.TextColor3=Color3.fromRGB(255,255,255)
								tp.Font=Enum.Font.SourceSansBold tp.TextSize=12 tp.BorderSizePixel=0 tp.Parent=rf
								Instance.new("UICorner",tp).CornerRadius=UDim.new(0,4)
								applyButtonEffects(tp,Color3.fromRGB(0,120,215),Color3.fromRGB(0,150,240))
								tp.MouseButton1Click:Connect(function() plTP(child) end)
							end
							tracked[child]={f=rf,l=lbl,c=conns} sortF()
						end
						local function remRow(child)
							if tracked[child] then for _,c in ipairs(tracked[child].c) do c:Disconnect() end
								tracked[child].f:Destroy() tracked[child]=nil sortF() end
						end
						if title == "ACTIVE BUGS LOG" then
							for _,c in ipairs(cont:GetDescendants()) do addRow(c) end
							cont.DescendantAdded:Connect(addRow) cont.DescendantRemoving:Connect(remRow)
						else
							for _,c in ipairs(cont:GetChildren()) do addRow(c) end
							cont.ChildAdded:Connect(addRow) cont.ChildRemoved:Connect(remRow)
						end
					end
				end
				_buildBugLog()
				do
					local PL_CFG={
						{Title="ACTIVE BUGS LOG",Path=workspace:FindFirstChild("ActiveBugVisuals"),HasCatch=true,Accent=Color3.fromRGB(255,170,85)},
						{Title="ARTIFACTS LOG",Path=workspace:FindFirstChild("Artifacts"),Accent=Color3.fromRGB(255,170,60)},
						{Title="HAT LOG",Path=workspace:FindFirstChild("Hats"),Attributes={"HatColor_prim"},Accent=Color3.fromRGB(255,120,200)},
						{Title="MAGIC ORBS LOG",Path=workspace:FindFirstChild("MagicOrbs"),Accent=Color3.fromRGB(120,200,255)},
						{Title="PET WORLD PETS LOG",Path=workspace:FindFirstChild("PetWorldPets"),Accent=Color3.fromRGB(180,140,255)},
						{Title="TREASURE CHEST LOG",Path=workspace:FindFirstChild("TreasureChests"),Accent=Color3.fromRGB(255,200,60)},
						{Title="TREASURE DIG SITES LOG",Path=workspace:FindFirstChild("TreasureDigSites"),Accent=Color3.fromRGB(200,160,100)},
						{Title="INVENTORY ITEMFRAME LOG",Path=(function() local ig=PlayerGui:FindFirstChild("InventoryGui")
							return ig and ig:FindFirstChild("MainFrame") and ig.MainFrame:FindFirstChild("ItemsFrame") end)(),
						HideTP=true,HasToggleName=true,HasSortOption=true,HasFavFilterOption=true,IsInventory=true,
						Attributes={"Category","ItemName","Amount"},Accent=Color3.fromRGB(100,230,130)}
					}
					for _,cfg in ipairs(PL_CFG) do plCat(cfg) end
					local plOpenBtn=Instance.new("TextButton") plOpenBtn.Size=UDim2.new(0,280,0,32)
					plOpenBtn.Position=UDim2.new(0,10,0,CfgY+640) plOpenBtn.BackgroundColor3=Color3.fromRGB(35,35,42)
					plOpenBtn.Text="📋 Open Master Log Panel" plOpenBtn.TextColor3=Color3.fromRGB(0,210,255)
					plOpenBtn.Font=Enum.Font.SourceSansBold plOpenBtn.TextSize=13 plOpenBtn.BorderSizePixel=0 plOpenBtn.Parent=Page1
					Instance.new("UICorner",plOpenBtn).CornerRadius=UDim.new(0,6)
					applyButtonEffects(plOpenBtn,Color3.fromRGB(35,35,42),Color3.fromRGB(50,50,60))
					plOpenBtn.MouseButton1Click:Connect(function() sg.Enabled=true end)
				end
				local OpLbl = Instance.new("TextLabel")
				OpLbl.Size = UDim2.new(0, 120, 0, 24)
				OpLbl.Position = UDim2.new(0, 10, 0, CfgY + 606)
				OpLbl.Text = "GUI Opacity:"
				OpLbl.TextColor3 = Color3.fromRGB(200, 205, 215)
				OpLbl.Font = Enum.Font.SourceSans
				OpLbl.TextSize = 12
				OpLbl.TextXAlignment = Enum.TextXAlignment.Left
				OpLbl.BackgroundTransparency = 1
				OpLbl.Parent = Page1
				opacitySlider = createOpacitySlider(UDim2.new(0, 130, 0, CfgY + 606), Page1, function(frac)
					applyGuiOpacity(frac)
				end)
				Page1.CanvasSize = UDim2.new(0, 0, 0, CfgY + 905)
			end -- close Favorite/Delete do-block
			deleteCatch = function(name, kind, data, excludeIds)
				if not name or not autoDeleteEnabled then return end
				local function deleteAllMatchingName()
					if not name then return 0 end
					local ln = normName(name)
					local seen = {}
					local deleted = 0
					-- Try GUI first (if inventory is open)
					local frame = getInventoryItemsFrame()
					if frame then
						local function collect(c, depth)
							if depth > 3 then return end
							local children = c:GetChildren()
							for i = #children, 1, -1 do
								local item = children[i]
								if item:IsA("GuiObject") then
									local nm, iid, vid = readItemAttrs(item)
									if nm and normName(nm) == ln then
										local id = vid or iid
										if id and not seen[tostring(id)] then
											seen[tostring(id)] = true
											if InventoryAction then
												pcall(function()
													InventoryAction:FireServer({ Action = "DeleteItemStack", ItemId = tostring(id) })
												end)
												deleted = deleted + 1
												pcall(function()
													LogCatch("🗑 " .. name .. " [DELETED] -> " .. tostring(id), kind, data)
												end)
											end
										end
									end
									collect(item, depth + 1)
								end
							end
						end
						collect(frame, 0)
					end
					-- Also check inventory state (works without GUI)
					local state = RDR_GetInvState()
					if state and state.InventoryById then
						for _, entry in pairs(state.InventoryById) do
							if type(entry) == "table" then
								local entryName = entry.ItemName or (entry.Metadata and entry.Metadata.ItemName) or RDR_DisplayNameOf(entry)
								if entryName and normName(entryName) == ln then
									local id = entry.InventoryItemId or entry.ItemId or entry.ItemUid or entry.Uid or entry.UID or entry.Id
									if id and not seen[tostring(id)] then
										seen[tostring(id)] = true
										if InventoryAction then
											pcall(function()
												InventoryAction:FireServer({ Action = "DeleteItemStack", ItemId = tostring(id) })
											end)
											deleted = deleted + 1
											pcall(function()
												LogCatch("🗑 " .. name .. " [DELETED] -> " .. tostring(id), kind, data)
											end)
										end
									end
								end
							end
						end
					end
					return deleted
				end
				local tries = 0
				local function attempt()
					tries = tries + 1
					local n = deleteAllMatchingName()
					if n == 0 then
						local recentId = findRecentItemId(name, excludeIds)
						if recentId and InventoryAction then
							pcall(function()
								InventoryAction:FireServer({ Action = "DeleteItemStack", ItemId = tostring(recentId) })
							end)
							pcall(function()
								LogCatch("🗑 " .. name .. " [DELETED] -> " .. tostring(recentId), kind, data)
							end)
						end
					end
					if tries < 8 and n == 0 then task.delay(0.5, attempt) end
				end
				task.delay(1.0, attempt)
			end
			-- Background inventory scanner: deletes matching items from inventory state
			-- even when the inventory GUI is not open.
			task.spawn(function()
				while true do
					task.wait(2)
					if autoDeleteEnabled and #autoDeleteNames > 0 then
						local state = RDR_GetInvState()
						if state and state.InventoryById then
							for _, entry in pairs(state.InventoryById) do
								if type(entry) == "table" then
									local entryName = entry.ItemName or (entry.Metadata and entry.Metadata.ItemName) or RDR_DisplayNameOf(entry)
									if entryName and nameInDeleteList(entryName) then
										local cat = entry.Category or (entry.Metadata and entry.Metadata.Category) or ""
										local itemKind = (cat == "Bug" or cat == "Bugs" or cat == "CaughtBugs") and "Bug" or "Fish"
										local id = entry.InventoryItemId or entry.ItemId or entry.ItemUid or entry.Uid or entry.UID or entry.Id
										if id and InventoryAction then
											pcall(function()
												InventoryAction:FireServer({ Action = "DeleteItemStack", ItemId = tostring(id) })
											end)
											pcall(function()
												LogCatch("🗑 " .. tostring(entryName) .. " [BG-DELETED] -> " .. tostring(id), itemKind, entry)
											end)
										end
									end
								end
							end
						end
					end
				end
			end)
		end
