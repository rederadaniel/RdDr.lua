local fishSellBtn = Instance.new("TextButton")
		fishSellBtn.Size = UDim2.new(0, 170, 0, 30)
		fishSellBtn.Position = UDim2.new(0, 10, 0, 595)
		fishSellBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 100)
		fishSellBtn.Text = "💰 Sell All Fish"
		fishSellBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		fishSellBtn.Font = Enum.Font.SourceSansBold
		fishSellBtn.TextSize = 13
		fishSellBtn.Visible = false
		fishSellBtn.Parent = Page3
		Instance.new("UICorner", fishSellBtn).CornerRadius = UDim.new(0, 5)
		applyButtonEffects(fishSellBtn, Color3.fromRGB(0, 140, 100), Color3.fromRGB(0, 180, 120))
		local fishTradeBtn = Instance.new("TextButton")
		fishTradeBtn.Size = UDim2.new(0, 170, 0, 30)
		fishTradeBtn.Position = UDim2.new(0, 190, 0, 595)
		fishTradeBtn.BackgroundColor3 = Color3.fromRGB(80, 100, 200)
		fishTradeBtn.Text = "🔄 Trade All Fish"
		fishTradeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		fishTradeBtn.Font = Enum.Font.SourceSansBold
		fishTradeBtn.TextSize = 13
		fishTradeBtn.Visible = false
		fishTradeBtn.Parent = Page3
		Instance.new("UICorner", fishTradeBtn).CornerRadius = UDim.new(0, 5)
		applyButtonEffects(fishTradeBtn, Color3.fromRGB(80, 100, 200), Color3.fromRGB(110, 130, 240))
		local isFishBusy = false
		fishSellBtn.MouseButton1Click:Connect(function()
			if isFishBusy then return end
			isFishBusy = true
			fishSellBtn.Visible = false
			fishTradeBtn.Visible = false
			task.spawn(function()
				local hrp = Character and Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					local old = hrp.CFrame
					hrp.CFrame = CFrame.new(-1409.36, 37.78, -2562.63)
					task.wait(0.5) executeSellAllFish() task.wait(5) executeSellAllFish() hrp.CFrame = old
				end
				if showToast then showToast("🐟 Fish sold!", Color3.fromRGB(120, 220, 130), 3) end
				isFishBusy = false
			end)
		end)
		fishTradeBtn.MouseButton1Click:Connect(function()
			if isFishBusy then return end
			isFishBusy = true
			fishSellBtn.Visible = false
			fishTradeBtn.Visible = false
			task.spawn(function()
				local hrp = Character and Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					local old = hrp.CFrame
					hrp.CFrame = CFrame.new(-1088.27, 37.39, -80.23)
					task.wait(0.5)
					pcall(function() VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game) end) task.wait(0.1)
					pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)
					executeTradeAllFish() task.wait(5)
					pcall(function() VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game) end) task.wait(0.1)
					pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)
					executeTradeAllFish() hrp.CFrame = old
				end
				if showToast then showToast("🔄 Fish traded!", Color3.fromRGB(110, 130, 240), 3) end
				isFishBusy = false
			end)
		end)
		_G.FishAutoMode = _G.FishAutoMode or "fishonly"
		local lastFishMaxNotify = 0
		local lastFishMaxSell = 0
		local isFishAutoSelling = false
		task.spawn(function()
			while true do
				task.wait(1)
				pcall(function()
					local lastCatch = _G.RDR_LastFishCatch or -1e9
					local fishCount = RDR_CountCritters("CaughtFish")
					local full = (fishCount > 0) and (lastCatch > 0) and ((os.clock() - lastCatch) > 15)
					if full then
						local now = os.clock()
						if now - lastFishMaxNotify > 3 then
							lastFishMaxNotify = now
						end
						if _G.AutoFishEnabled and _G.FishAutoMode ~= "fishonly" and (now - lastFishMaxSell) > 3 and not isFishAutoSelling then
							lastFishMaxSell = now
							isFishAutoSelling = true
							fishSellBtn.Visible = false
							fishTradeBtn.Visible = false
							task.spawn(function()
								local fishSetter = RDR_TOGGLES and RDR_TOGGLES["Auto Fish (Hands-Free)"]
								if fishSetter then fishSetter(false) end
								local modeLabel = _G.FishAutoMode == "trade" and "auto-trade" or "auto-sell"
								if showToast then showToast("🐟 Pausing auto-fish for " .. modeLabel .. " (9s)...", Color3.fromRGB(255, 170, 90), 3) end
								local hrp = Character and Character:FindFirstChild("HumanoidRootPart")
								local oldCF = hrp and hrp.CFrame
								if _G.FishAutoMode == "trade" then
									if hrp then
										hrp.CFrame = CFrame.new(-1088.27, 37.39, -80.23)
										task.wait(1)
										pcall(function() VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game) end) task.wait(0.1)
										pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)
										executeTradeAllFish() task.wait(5)
										pcall(function() VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game) end) task.wait(0.1)
										pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)
										executeTradeAllFish() hrp.CFrame = oldCF
									end
								else
									if hrp then
										hrp.CFrame = CFrame.new(-1409.36, 37.78, -2562.63)
										task.wait(1)
										executeSellAllFish()
										task.wait(7.6)
										hrp.CFrame = oldCF
									end
								end
								local elapsed = os.clock() - lastFishMaxSell
								if elapsed < 8 then task.wait(8 - elapsed) end
								_G.RDR_LastFishCatch = os.clock()
								if fishSetter then fishSetter(true) end
								if showToast then showToast("🐟 " .. modeLabel .. " done — auto fish resumed!", Color3.fromRGB(120, 220, 130), 3) end
								isFishAutoSelling = false
							end)
						end
					else
						if not isFishAutoSelling then fishSellBtn.Visible = false fishTradeBtn.Visible = false end
					end
				end)
			end
		end)
		local FishCastRemote = nil
		task.spawn(function()
			local ok, r = pcall(function()
				return ReplicatedStorage:WaitForChild("Fishing", 5):WaitForChild("Remotes", 5):WaitForChild("RequestCast", 5)
			end)
			if ok then FishCastRemote = r end
		end)
		local FishCancelRemote = nil
		task.spawn(function()
			local ok, r = pcall(function()
				return ReplicatedStorage:WaitForChild("Fishing", 5):WaitForChild("Remotes", 5):WaitForChild("CancelCast", 5)
			end)
			if ok then FishCancelRemote = r end
		end)
		local fishSessionId = nil
		local lastCastExistingIds = {}
		local combinedFishEnabled = false
		local fishBypassEnabled = false
		local fishWonThisSession = false
		local fishHandsFreeThread = nil
		local fishTrackConnection = nil
		local fishLastCompleteFire = 0
		local fishHolding = false
		local autoCastEnabled = false
		local autoHoldEnabled = false
		local function fishActive()
			return combinedFishEnabled or fishBypassEnabled or autoHoldEnabled
		end
		local function findCatchBox(container, targetBox)
			local named = container:FindFirstChild("CatchBox", true)
			if named and named:IsA("GuiObject") then
				return named
			end
			local containerW = container.AbsoluteSize.X
			local containerH = container.AbsoluteSize.Y
			local candidates = {}
			local function recurse(p, depth)
				if depth > 4 then return end
				for _, child in ipairs(p:GetChildren()) do
					local isBox = child:IsA("Frame") or child:IsA("ImageLabel") or child:IsA("ImageButton") or child:IsA("TextLabel")
					if isBox and child ~= targetBox then
						if child.AbsoluteSize.Y >= containerH * 0.20 and child.AbsoluteSize.X <= containerW * 0.95 then
							table.insert(candidates, child)
						end
					end
					recurse(child, depth + 1)
				end
			end
			recurse(container, 0)
			local best, bestW = nil, -1
			for _, c in ipairs(candidates) do
				if c.AbsoluteSize.X > bestW then
					bestW = c.AbsoluteSize.X
					best = c
				end
			end
			return best
		end
		local function getMiniGameRemote(category)
			local catLower = string.lower(category)
			local function findRemoteEvent(parent)
				local found
				local function recurse(p, depth)
					if depth > 5 then return end
					for _, c in ipairs(p:GetChildren()) do
						if c:IsA("RemoteEvent") and string.find(string.lower(c.Name), "minigame") then
							found = c
							return true
						end
						if recurse(c, depth + 1) then return true end
					end
					return false
				end
				recurse(parent, 0)
				return found
			end
			local candidates = {}
			local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
			if Remotes then
				local guess1 = Remotes:FindFirstChild(category)
				if guess1 then table.insert(candidates, guess1) end
			end
			local guess2 = ReplicatedStorage:FindFirstChild(category)
			if guess2 then table.insert(candidates, guess2) end
			for _, c in ipairs(ReplicatedStorage:GetChildren()) do
				if c ~= Remotes and c ~= guess2 and string.find(string.lower(c.Name), catLower) then
					table.insert(candidates, c)
				end
			end
			for _, cand in ipairs(candidates) do
				local r = findRemoteEvent(cand)
				if r then
					print("[RdDr] MiniGame remote for '" .. category .. "' -> " .. r:GetFullName())
					return r
				end
			end
			warn("[RdDr] Could NOT locate a MiniGame RemoteEvent for category '" .. category .. "'. Bypass Auto Win will not work for it.")
			return nil
		end
		local y3 = AddSectionHeader(Page3, "Fish Catch Settings", 10)
		y3 = AddNavInstructionText(Page3, "Auto Fish: fishing minigame AND auto-casts when idle.", y3)
		y3 = AddNavInstructionText(Page3, "Press [Y] to shut Auto Fish + Instant Bug off. Press [F] to turn Instant Bug Catch ON.", y3)
		local function ensureFishLogic()
			if fishTrackConnection then return end
			fishTrackConnection = RunService.Heartbeat:Connect(function()
				if not fishActive() then
					if fishHolding then VirtualUser:Button1Up(Vector2.new(0, 0)); fishHolding = false end
					return
				end
				local gui = PlayerGui:FindFirstChild("FishingMinigameGui")
				local container = gui and gui:FindFirstChild("FishingBoxContainer")
				if not container or fishWonThisSession then
					if fishHolding then VirtualUser:Button1Up(Vector2.new(0, 0)); fishHolding = false end
					return
				end
				local fishBox = container:FindFirstChild("FishBox")
				local catchBox = findCatchBox(container, fishBox)
				if catchBox and fishBox then
					local shouldHold = catchBox.AbsolutePosition.X < fishBox.AbsolutePosition.X
					if shouldHold and not fishHolding then
						VirtualUser:Button1Down(Vector2.new(0, 0)); fishHolding = true
					elseif not shouldHold and fishHolding then
						VirtualUser:Button1Up(Vector2.new(0, 0)); fishHolding = false
					end
				else
					if fishHolding then VirtualUser:Button1Up(Vector2.new(0, 0)); fishHolding = false end
					local diag = (not fishBox and "FishBox missing" or "") .. (not catchBox and (fishBox and " | CatchBox missing" or "") or "")
					if diag ~= "" and (tick() - (fishDiagTick or 0)) > 2 then
						fishDiagTick = tick()
						warn("[RdDr][Fish] minigame active but " .. diag .. " — tracking cannot aim. Container children: "
							.. table.concat((function() local t={} for _,c in ipairs(container:GetChildren()) do table.insert(t,c.Name) end return t end)(), ", "))
					end
				end
				local now = tick()
				if now - fishLastCompleteFire > 1.0 and fishMiniGameRemote then
					fishLastCompleteFire = now
					local ok, err = pcall(function()
						fishMiniGameRemote:FireServer("Complete", tostring(fishSessionId), {result = "Caught", reason = "ProgressComplete", elapsed = 0})
					end)
					if not ok then warn("[RdDr][Fish] backup Complete failed: " .. tostring(err)) end
				end
			end)
		end
		local function fishHandsFreeLoop()
			while (combinedFishEnabled or fishBypassEnabled or autoCastEnabled) do
				if safeModeActive and playerNearby(SAFE_MODE_RADIUS) then task.wait(0.5) continue end
				local inMini = PlayerGui:FindFirstChild("FishingMinigameGui") ~= nil
				if not inMini and FishCastRemote then
					pcall(function() FishCastRemote:FireServer(1) end)
					local waited = 0
					while (combinedFishEnabled or fishBypassEnabled or autoCastEnabled) and not PlayerGui:FindFirstChild("FishingMinigameGui") and waited < 8 do
						task.wait(0.2)
						waited = waited + 0.2
					end
				end
				task.wait(0.5)
			end
		end
		local setAutoFish = makeToggle("Auto Fish (Hands-Free)", UDim2.new(0, 10, 0, y3), Page3, function(state)
			combinedFishEnabled = state
			_G.AutoFishEnabled = state
			ensureFishLogic()
			if state then
				if fishHandsFreeThread then task.cancel(fishHandsFreeThread) end
				fishHandsFreeThread = task.spawn(fishHandsFreeLoop)
			else
				if fishHandsFreeThread then task.cancel(fishHandsFreeThread) fishHandsFreeThread = nil end
			end
		end)
		local setBypassWin = makeToggle("Bypass Auto Win (Fish)", UDim2.new(0, 10, 0, y3 + 25), Page3, function(state)
			fishBypassEnabled = state
			if state then
				ensureFishLogic()
			end
		end)
		local y3Mode = AddNavInstructionText(Page3, "Auto Mode — choose what happens when fish inventory is full. Click a button: ✅ = selected.", y3 + 103)
		local fishModeButtons = {}
		local fishModeInfo = {}
		local fishModes = {
			{key = "sell",   label = "💰 Sell + Fish",  clean = "Sell + Fish",  color = Color3.fromRGB(0, 140, 100),   hover = Color3.fromRGB(0, 180, 120)},
			{key = "trade",  label = "🔄 Trade + Fish", clean = "Trade + Fish", color = Color3.fromRGB(80, 100, 200),   hover = Color3.fromRGB(110, 130, 240)},
			{key = "fishonly", label = "🎣 Fish Only",  clean = "Fish Only",    color = Color3.fromRGB(120, 90, 60),    hover = Color3.fromRGB(160, 120, 80)},
		}
		for i, mode in ipairs(fishModes) do
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(0, 120, 0, 28)
			btn.Position = UDim2.new(0, 10 + (i - 1) * 125, 0, y3Mode)
			btn.BackgroundColor3 = mode.color
			btn.Text = mode.label
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
			btn.Font = Enum.Font.SourceSansBold
			btn.TextSize = 12
			btn.Parent = Page3
			Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
			applyButtonEffects(btn, mode.color, mode.hover)
			fishModeButtons[mode.key] = btn
			fishModeInfo[mode.key] = {label = mode.label, clean = mode.clean}
			local function updateFishModeHighlight()
				for k, b in pairs(fishModeButtons) do
					if k == _G.FishAutoMode then
						b.BorderSizePixel = 3
						b.BorderColor3 = Color3.fromRGB(255, 255, 255)
						b.Text = "✅ " .. fishModeInfo[k].clean
					else
						b.BorderSizePixel = 0
						b.Text = fishModeInfo[k].label
					end
				end
			end
			updateFishModeHighlight()
			btn.MouseButton1Click:Connect(function()
				_G.FishAutoMode = mode.key
				updateFishModeHighlight()
				if showToast then
					showToast("🐟 Fish auto mode: " .. mode.label, mode.color, 2)
				end
			end)
		end
		UserInputService.InputBegan:Connect(function(input, gpe)
			if gpe then return end
			if UserInputService:GetFocusedTextBox() then return end
			if input.KeyCode == Enum.KeyCode.Y then
				if combinedFishEnabled and setAutoFish then setAutoFish(false) end
				if fishBypassEnabled and setBypassWin then setBypassWin(false) end
				showToast("⏻ Auto Fish OFF (Y)", Color3.fromRGB(255, 170, 90), 1.5)
			end
		end)
		local fishCaughtCounts = {}
		local predictRowMap = {}
		local predictRowInfo = {}
		local predictOrder = 0
		bumpFishCount = function(nm)
			if not nm then return end
			local ln = normName(nm)
			fishCaughtCounts[ln] = (fishCaughtCounts[ln] or 0) + 1
			local row = predictRowMap[ln]
			if row and row.Parent then
				local info = predictRowInfo[ln]
				row.Text = "   " .. (info and info.display or nm) .. "  — Stock: " .. fishCaughtCounts[ln]
			end
		end
		local fishMiniGameRemote
		do
			Page5.CanvasSize = UDim2.new(0, 0, 0, predY + 900)
			local fishCatchCount = 0
			local currentFishName = nil
			local FishStatusLabel = Instance.new("TextLabel")
			FishStatusLabel.Size = UDim2.new(1, -20, 0, 54)
			FishStatusLabel.Position = UDim2.new(0, 10, 0, y3 + 45)
			FishStatusLabel.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
			FishStatusLabel.Text = "Status: Idle    |    Last: —    |    Total: 0"
			FishStatusLabel.TextColor3 = Color3.fromRGB(235, 235, 240)
			FishStatusLabel.Font = Enum.Font.SourceSans
			FishStatusLabel.TextSize = 13
			FishStatusLabel.TextWrapped = true
			FishStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
			FishStatusLabel.Parent = Page3
			Instance.new("UICorner", FishStatusLabel).CornerRadius = UDim.new(0, 6)
			local function updateFishStatus(text)
				FishStatusLabel.Text = text
			end
			-- Fish MiniGame Remote Event Connection
			fishMiniGameRemote = getMiniGameRemote("Fishing")
			if fishMiniGameRemote then
				fishMiniGameRemote.OnClientEvent:Connect(function(action, data)
					if action == "Start" then
						if typeof(data) == "table" and data.sessionId then
							fishSessionId = tostring(data.sessionId)
							fishWonThisSession = false
							fishCatchCount = fishCatchCount + 1
							currentFishName = nil
							updateFishStatus("Status: Fishing (Session: " .. fishSessionId .. ")    |    Last: —    |    Total: " .. tostring(fishCatchCount))
						end
					elseif action == "Win" then
						if typeof(data) == "table" and data.sessionId then
							local winSession = tostring(data.sessionId)
							if winSession == fishSessionId then
								fishWonThisSession = true
								fishLastCompleteFire = 0
								updateFishStatus("Status: Fish Caught!    |    Last: " .. (currentFishName or "Unknown") .. "    |    Total: " .. tostring(fishCatchCount))
								if currentFishName then
									pcall(function() LogCatch(tostring(currentFishName), "Fish", nil) end)
									pcall(function() bumpFishCount(currentFishName) end)
								end
								fishSessionId = nil
							end
						else
							fishWonThisSession = true
							fishLastCompleteFire = 0
							updateFishStatus("Status: Fish Caught!    |    Last: " .. (currentFishName or "Unknown") .. "    |    Total: " .. tostring(fishCatchCount))
							fishSessionId = nil
						end
					elseif action == "Failed" then
						local failSession = data
						if typeof(failSession) == "table" and failSession.sessionId then
							failSession = tostring(failSession.sessionId)
						end
						if fishSessionId then
							fishWonThisSession = false
							updateFishStatus("Status: Failed    |    Last: —    |    Total: " .. tostring(fishCatchCount))
						end
						fishSessionId = nil
					elseif action == "Cancel" then
						fishSessionId = nil
						fishWonThisSession = false
					end
				end)
			else
				warn("[RdDr] Fish MiniGame remote not found — bypass auto-win and logging will not work.")
			end
