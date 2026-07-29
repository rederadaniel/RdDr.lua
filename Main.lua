-- RdDr/Main.lua
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

local Player = Players.LocalPlayer
local Character = Player.Character
local PlayerGui = Player:WaitForChild("PlayerGui")

_G.RDR_RAN = true
_G.RDR_TOGGLES = _G.RDR_TOGGLES or {}
_G.RDR_CONFIG_DATA = _G.RDR_CONFIG_DATA or {}

local RDR_InvStateMod = nil
local RDR_ItemDisplay = nil

function _G.RDR_GetInvState()
    if RDR_InvStateMod then return RDR_InvStateMod end
    pcall(function()
        RDR_InvStateMod = require(Player:WaitForChild("PlayerScripts"):WaitForChild("Inventory"):WaitForChild("InventoryState"))
    end)
    return RDR_InvStateMod
end

function _G.RDR_GetItemDisplay()
    if RDR_ItemDisplay then return RDR_ItemDisplay end
    pcall(function()
        RDR_ItemDisplay = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ItemDisplayData"))
    end)
    return RDR_ItemDisplay
end

local RDR_ResyncRemote = nil
local RDR_ResyncRunning = false
local RDR_RESYNC_INTERVAL = 5
local RDR_InventoryListenersSetup = false

local function RDR_GetResyncRemote()
    if RDR_ResyncRemote then return RDR_ResyncRemote end
    pcall(function()
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
            local state = _G.RDR_GetInvState()
            if state and state.SetInventoryItems then
                state.SetInventoryItems(data.Items or {}, data.Version)
            end
        end)
        RDR_InventoryListenersSetup = true
    end

    if inventoryDelta and inventoryDelta:IsA("RemoteEvent") then
        inventoryDelta.OnClientEvent:Connect(function(data)
            if type(data) ~= "table" then return end
            local state = _G.RDR_GetInvState()
            if state and state.ApplyDelta then
                state.ApplyDelta(data)
            end
        end)
    end
end

local function RDR_StartInventoryResync()
    if RDR_ResyncRunning then return end
    RDR_ResyncRunning = true
    RDR_SetupInventoryListeners()

    task.spawn(function()
        while RDR_ResyncRunning do
            local remote = RDR_GetResyncRemote()
            local state = _G.RDR_GetInvState()
            if remote and state then
                local version = state.GetVersion and state.GetVersion() or nil
                pcall(function() remote:FireServer(version) end)
            end
            task.wait(RDR_RESYNC_INTERVAL)
        end
    end)
end

RDR_StartInventoryResync()

function _G.RDR_CountCritters(catName)
    local s = _G.RDR_GetInvState()
    if not s or not s.InventoryById then
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

GuiService:SetGameplayPausedNotificationEnabled(false)
local function forceUnpause()
    if Player.GameplayPaused then
        Player:ClearRequirementForReplication() 
    end
end
Player:GetPropertyChangedSignal("GameplayPaused"):Connect(forceUnpause)
task.spawn(forceUnpause)

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
_G.RDR_ScreenGui = ScreenGui

local ToastHolder = Instance.new("Frame")
ToastHolder.Name = "RdDr_Toasts"
ToastHolder.Size = UDim2.new(0, 320, 1, 0)
ToastHolder.Position = UDim2.new(1, -340, 0, 0)
ToastHolder.BackgroundTransparency = 1
ToastHolder.BorderSizePixel = 0
ToastHolder.Parent = ScreenGui

local toastQueue = {}
function _G.showToast(text, color, life)
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

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 760, 0, 500)
MainFrame.Position = UDim2.new(0.5, -380, 0.5, -250)
MainFrame.BackgroundColor3 = Color3.fromRGB(11, 11, 14)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 12)
_G.RDR_MainFrame = MainFrame

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
LeftScrollNav.AutomaticCanvasSize = Enum.AutomaticSize.Y
LeftScrollNav.ScrollingDirection = Enum.ScrollingDirection.Y
LeftScrollNav.ScrollBarThickness = 2
LeftScrollNav.Parent = SidePanel
_G.RDR_LeftScrollNav = LeftScrollNav

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
_G.RDR_ViewContainer = ViewContainer

_G.RDR_Pages = {}
function _G.RDR_CreatePage(name, labelTag)
    local F = Instance.new("ScrollingFrame")
    F.Size = UDim2.new(1, -20, 1, -20)
    F.Position = UDim2.new(0, 10, 0, 10)
    F.BackgroundTransparency = 1
    F.CanvasSize = UDim2.new(0, 0, 0, 950)
    F.ScrollBarThickness = 4
    F.ScrollBarImageColor3 = Color3.fromRGB(0, 210, 255)
    F.Visible = false
    F.Parent = ViewContainer
    _G.RDR_Pages[name] = F

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
        for _, p in pairs(_G.RDR_Pages) do p.Visible = false end
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

local Page1 = _G.RDR_CreatePage("Main", "🏠 Main")
Page1.Visible = true