local function attemptTrigger(prompt)
	if prompt.KeyboardKeyCode == Enum.KeyCode.E and prompt.Enabled then
		local originalHold = prompt.HoldDuration
		prompt.HoldDuration = 0
		if fireproximityprompt then
			fireproximityprompt(prompt)
		elseif fireproximitytrigger then
			fireproximitytrigger(prompt)
		end
		task.spawn(function()
			task.wait(0.8)
			if prompt and prompt.Parent then
				prompt.HoldDuration = originalHold
			end
		end)
	end
end

task.spawn(function()
	while true do
		task.wait(0.8)
		if _G.AutoChests or _G.AutoDigSites or _G.AutoMagicOrbs then
			VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
			task.wait(0.8)
			VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
			local rootPart = Character and Character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				for _, prompt in ipairs(workspace:GetDescendants()) do
					if prompt:IsA("ProximityPrompt") and prompt.Enabled then
						local parentPart = prompt.Parent
						if parentPart and (parentPart:IsA("BasePart") or parentPart:IsA("Model")) then
							local distance = (rootPart.Position - parentPart:GetPivot().Position).Magnitude
							if distance <= prompt.MaxActivationDistance then
								attemptTrigger(prompt)
							end
						end
					end
				end
			end
		end
	end
end)

local function tpAndHold(targetPosition, duration, toggleKey)
	local endTime = os.clock() + duration
	while os.clock() < endTime and _G[toggleKey] do
		local hrp = Character and Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.CFrame = typeof(targetPosition) == "CFrame" and targetPosition or targetPosition
		end
		task.wait(0.2)
	end
end

task.spawn(function()
	task.wait(1.5)
	if syncAntiAfk then pcall(function() syncAntiAfk(true) end) end
end)

local lastMaxNotify = 0
local lastMaxSell = 0
local isAutoSelling = false
local pausedForSell = false

task.spawn(function()
	while true do
		task.wait(0.5)
		pcall(function()
			local foundMax = false
			for _, gui in ipairs(PlayerGui:GetDescendants()) do
				if gui:IsA("TextLabel") and gui.Text and gui.Text:find("Max crops in inventory") then
					foundMax = true
					local now = os.clock()
					local onlyHarvOn = RDR_TOGGLES and RDR_TOGGLES["ONLY AUTO HARVEST"]
					local onlyHarv = onlyHarvOn and onlyHarvOn.get()
					local sellCropOn = RDR_TOGGLES and RDR_TOGGLES["SELL CROPS + AUTO HARVEST"]
					local sellCrop = sellCropOn and sellCropOn.get()
					if onlyHarv then
						if OnlyHarvFullLabel then OnlyHarvFullLabel.Visible = true end
						if HarvestStatusLabel then HarvestStatusLabel.Visible = false end
					end
					if now - lastMaxNotify > 1 then
						lastMaxNotify = now
						if onlyHarv then
							lastMaxSell = now
							if showToast then
								showToast("🍎 Max Inventory — harvest only (auto-sell disabled)!", Color3.fromRGB(255, 165, 60), 4)
							end
						elseif sellCrop and now - lastMaxSell > 1 and not isAutoSelling then
							lastMaxSell = now
							isAutoSelling = true
							autoHarvestActive = false
							if HarvestStatusLabel then HarvestStatusLabel.Visible = true; HarvestStatusLabel.Text = "⏸ Paused for auto-sell (9s)..." end
							if OnlyHarvFullLabel then OnlyHarvFullLabel.Visible = false end
							task.spawn(function()
								local hrp = Character and Character:FindFirstChild("HumanoidRootPart")
								if hrp then
									local old = hrp.CFrame
									hrp.CFrame = CFrame.new(1013.78, 41.01, -114.92)
									task.wait(1)
									executeSellAllCrops()
									task.wait(6)
								end
								local elapsed = os.clock() - lastMaxSell
								if elapsed < 9 then task.wait(9 - elapsed) end
								local harvSetter = RDR_TOGGLES and RDR_TOGGLES["SELL CROPS + AUTO HARVEST"]
								if harvSetter then
									harvSetter(true)
								else
									autoHarvestActive = true
								end
								if HarvestStatusLabel then HarvestStatusLabel.Text = "🌾 Auto-sell done — auto harvest ON" end
								if OnlyHarvFullLabel then OnlyHarvFullLabel.Visible = false end
								isAutoSelling = false
							end)
						end
					end
					break
				end
			end
			if not foundMax then
				if OnlyHarvFullLabel then OnlyHarvFullLabel.Visible = false end
				if HarvestStatusLabel then HarvestStatusLabel.Visible = true end
			end
		end)
	end
end)

local HarvestRemote = nil
task.spawn(function()
	local ok, r = pcall(function()
		return ReplicatedStorage:WaitForChild("Remotes", 8):WaitForChild("Farming", 8):WaitForChild("HarvestCrop", 8)
	end)
	if ok then HarvestRemote = r end
end)

local CROP_RARITY = {}
pcall(function()
	local mod = ReplicatedStorage:WaitForChild("Modules", 5):WaitForChild("ItemDisplayDataCategories", 5):WaitForChild("HarvestedCrops", 5)
	local data = require(mod)
	for internal, info in pairs(data) do
		if info and info.DisplayName then
			CROP_RARITY[string.lower(tostring(internal))] = info.Rarity
			CROP_RARITY[string.lower(tostring(info.DisplayName))] = info.Rarity
		end
	end
end)

local function getCropRarity(name)
	if not name then return nil end
	return CROP_RARITY[string.lower(tostring(name))]
end

local y2 = AddSectionHeader(Page2, "Auto Harvest All Crops", 10)
y2 = AddNavInstructionText(Page2, "Checks each fruit's CanHarvest flag; teleports onto and fires the Harvest proximity prompt of every READY ", y2)
y2 = AddNavInstructionText(Page2, "fruit (skips any not ready). ", y2)

local OnlyHarvFullLabel = Instance.new("TextLabel")
OnlyHarvFullLabel.Size = UDim2.new(1, -20, 0, 30)
OnlyHarvFullLabel.Position = UDim2.new(0, 10, 0, y2 + 90)
OnlyHarvFullLabel.BackgroundColor3 = Color3.fromRGB(70, 35, 12)
OnlyHarvFullLabel.Text = "🍎 Inventory FULL — harvest only, NOT auto-selling"
OnlyHarvFullLabel.TextColor3 = Color3.fromRGB(255, 195, 120)
OnlyHarvFullLabel.Font = Enum.Font.SourceSansBold
OnlyHarvFullLabel.TextSize = 13
OnlyHarvFullLabel.TextXAlignment = Enum.TextXAlignment.Left
OnlyHarvFullLabel.Visible = false
OnlyHarvFullLabel.Parent = Page2
Instance.new("UICorner", OnlyHarvFullLabel).CornerRadius = UDim.new(0, 6)

-- MAX SPEED PROXIMITY ENGINE
local function firePromptFast(prompt)
	if not prompt then return end
	pcall(function()
		if fireproximityprompt then
			fireproximityprompt(prompt)
		else
			prompt.HoldDuration = 0
			prompt:InputHoldBegin()
			prompt:InputHoldEnd()
		end
	end)
end

local cachedPlotsFolder = nil
local function getPlotsFolder()
	if cachedPlotsFolder and cachedPlotsFolder.Parent then return cachedPlotsFolder end
	local map = workspace:FindFirstChild("Map")
	local island = map and (map:FindFirstChild("MainIsland") or map)
	if island and island:FindFirstChild("PlayerGardens") then cachedPlotsFolder = island.PlayerGardens:FindFirstChild("Plots") end
	if not cachedPlotsFolder and island then cachedPlotsFolder = island:FindFirstChild("Plots") end
	if not cachedPlotsFolder and map then cachedPlotsFolder = map:FindFirstChild("Plots") end
	if not cachedPlotsFolder then cachedPlotsFolder = workspace:FindFirstChild("Plots") end
	return cachedPlotsFolder
end

local function getMyPlots()
	local f = getPlotsFolder(); if not f then return {} end
	local id = Player.UserId; local out = {}
	for _, p in ipairs(f:GetChildren()) do
		local o = p:GetAttribute("Owner") or p:GetAttribute("OwnerUserId")
		if o == id then table.insert(out, p) end
	end
	return out
end

local function getCropFruits(crop)
	local sc = crop:FindFirstChild("ServerConfiguration")
	return (sc and sc:FindFirstChild("Fruits")) or crop:FindFirstChild("Fruits")
end

local onlyFishingMode = false
local harvestedTotal = 0

-- HIGH EFFICIENCY HARVEST LOOP (NO LAG + INSTANT DISPATCH)
local function autoHarvestLoop()
	local harvestedThisRun = 0
	local lastUIUpdate = 0

	while autoHarvestActive do
		if _sellInProgress or (safeModeActive and playerNearby(SAFE_MODE_RADIUS)) then
			task.wait(0.2)
			continue
		end

		if not onlyFishingMode then
			local myPlots = getMyPlots()
			if #myPlots == 0 then 
				task.wait(0.3) 
				continue 
			end

			for _, plot in ipairs(myPlots) do
				if not autoHarvestActive then break end
				local plantedSeeds = plot:FindFirstChild("PlantedSeeds")
				if not plantedSeeds then continue end

				for _, crop in ipairs(plantedSeeds:GetChildren()) do
					if not autoHarvestActive then break end
					local fruitsFolder = getCropFruits(crop)
					if not fruitsFolder then continue end

					for _, fruit in ipairs(fruitsFolder:GetChildren()) do
						if not autoHarvestActive then break end

						local canHarvest = false
						local ch = fruit:FindFirstChild("CanHarvest")
						if ch and ch:IsA("BoolValue") then
							canHarvest = ch.Value
						else
							local gp = fruit:FindFirstChild("GrowthPercentage")
							canHarvest = (gp and typeof(gp.Value) == "number" and gp.Value >= 100)
						end

						local prompt = nil
						if fruit:IsA("ProximityPrompt") then
							prompt = fruit
							canHarvest = true
						else
							prompt = fruit:FindFirstChildWhichIsA("ProximityPrompt", true)
							if prompt then canHarvest = true end
						end

						local fav = fruit:FindFirstChild("Favorited")
						local locked = fruit:FindFirstChild("PermanentLocked")
						local isFav = (fav and fav.Value) or fruit:GetAttribute("Favorited") == true
						local isLocked = (locked and locked.Value) or fruit:GetAttribute("PermanentLocked") == true

						if canHarvest and not isFav and not isLocked then
							-- Pivot character once per crop zone if out of range
							local hrp = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
							if hrp and (hrp.Position - crop:GetPivot().Position).Magnitude > 14 then
								pcall(function() hrp.CFrame = crop:GetPivot() + Vector3.new(0, 3, 0) end)
								task.wait(0.045)
							end

							-- Instant Trigger Execution (Concurrently Spammed)
							if HarvestRemote then
								pcall(function() HarvestRemote:FireServer(crop.Name, fruit.Name) end)
							end
							if prompt then
								firePromptFast(prompt)
							end

							-- DECOUPLED VERIFICATION THREAD (Never blocks execution loop, handles latency)
							task.spawn(function()
								local startTrack = os.clock()
								local nameString = fruit:GetAttribute("ItemName") or fruit:GetAttribute("ItemId") or fruit.Name
								local cropName = crop.Name

								while os.clock() - startTrack < 1.5 do
									if not fruit or not fruit:IsDescendantOf(workspace) or (prompt and not prompt:IsDescendantOf(workspace)) then
										harvestedThisRun = harvestedThisRun + 1
										break
									end
									task.wait(0.05)
								end
							end)
						end
					end
				end
			end

			-- Throttled UI label refresh rate
			if os.clock() - lastUIUpdate > 0.25 then
				lastUIUpdate = os.clock()
				if HarvestStatusLabel then
					HarvestStatusLabel.Text = "Harvesting... crops: " .. harvestedThisRun .. "  |  🌾 Session: " .. harvestedTotal
				end
			end
		end

		task.wait(0.02)
	end
end

makeToggle("ONLY AUTO HARVEST", UDim2.new(0, 10, 0, y2), Page2, function(enabled)
	if enabled then
		if OnlyHarvFullLabel then OnlyHarvFullLabel.Visible = false end
		if HarvestStatusLabel then HarvestStatusLabel.Visible = true end
		local nc = RDR_TOGGLES and RDR_TOGGLES["Phase State (No-Clip)"]
		local fl = RDR_TOGGLES and RDR_TOGGLES["FLY HIGH"]
		if nc and not nc.get() then nc(true) end
		if fl and not fl.get() then fl(true) end
		autoHarvestActive = true
		task.spawn(autoHarvestLoop)
	else
		autoHarvestActive = false
		if OnlyHarvFullLabel then OnlyHarvFullLabel.Visible = false end
		if HarvestStatusLabel then HarvestStatusLabel.Visible = true end
		local ncOff = RDR_TOGGLES and RDR_TOGGLES["Phase State (No-Clip)"]
		local flOff = RDR_TOGGLES and RDR_TOGGLES["FLY HIGH"]
		if ncOff and ncOff.get() then ncOff(false) end
		if flOff and flOff.get() then flOff(false) end
	end
end)
