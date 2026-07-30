		local speedVal, jumpVal = 16, 50
		flySpeed = 50
		noclipActive, flyActive, infJumpActive = false, false, false
		local function makeSlider(label, min, max, default, pos, callback)
			local L = Instance.new("TextLabel")
			L.Size = UDim2.new(0, 150, 0, 35)
			L.Position = pos
			L.Text = label .. ": " .. default
			L.TextColor3 = Color3.fromRGB(220, 220, 225)
			L.Font = Enum.Font.SourceSansBold
			L.TextSize = 14
			L.BackgroundTransparency = 1
			L.Parent = PageOthers
			local I = Instance.new("TextBox")
			I.Size = UDim2.new(0, 80, 0, 28)
			I.Position = pos + UDim2.new(0, 160, 0, 3)
			I.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
			I.Text = tostring(default)
			I.TextColor3 = Color3.fromRGB(255, 255, 255)
			I.Font = Enum.Font.SourceSansBold
			I.TextSize = 14
			I.Parent = PageOthers
			Instance.new("UICorner", I).CornerRadius = UDim.new(0, 4)
			I.FocusLost:Connect(function()
				local val = math.clamp(tonumber(I.Text) or default, min, max)
				I.Text = tostring(val)
				L.Text = label .. ": " .. val
				callback(val)
			end)
			return I, L
		end
		local setSpeedInput, speedLabel = makeSlider("Walkspeed Matrix", 16, 500, 16, UDim2.new(0, 10, 0, 15), function(v)
			speedVal = v
			local char = Player.Character
			if char and char:FindFirstChild("Humanoid") then char.Humanoid.WalkSpeed = v end
		end)
		local setJumpInput, jumpLabel = makeSlider("JumpPower Matrix", 16, 50000, 16, UDim2.new(0, 10, 0, 65), function(v)
			jumpVal = v
			local char = Player.Character
			if char and char:FindFirstChild("Humanoid") then
				char.Humanoid.UseJumpPower = true
				char.Humanoid.JumpPower = v
			end
		end)
		Player.CharacterAdded:Connect(function(newChar)
			local hum = newChar and newChar:WaitForChild("Humanoid", 5)
			if hum then
				if speedVal and speedVal ~= 16 then hum.WalkSpeed = speedVal end
				if jumpVal and jumpVal ~= 16 then
					hum.UseJumpPower = true
					hum.JumpPower = jumpVal
				end
			end
		end)
		syncAntiAfk = makeToggle("Anti-Idle Connection (Anti-AFK)", UDim2.new(0, 10, 0, 120), PageOthers, function(state)
			if state then
				_G.AntiAfkConnection = Player.Idled:Connect(function()
					pcall(function() VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame) end)
					task.wait(1)
					pcall(function() VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame) end)
				end)
			else
				if _G.AntiAfkConnection then _G.AntiAfkConnection:Disconnect() end
			end
		end)
	end
	do
		local syncNoclip = makeToggle("Phase State (No-Clip)", UDim2.new(0, 10, 0, 165), PageOthers, function(state) noclipActive = state end)
		RunService.Stepped:Connect(function()
			if noclipActive and Character then
				for _, part in ipairs(Character:GetDescendants()) do
					if part:IsA("BasePart") then part.CanCollide = false end
				end
			end
		end)
		local syncInfJump = makeToggle("Chain Lift (Infinite Jump)", UDim2.new(0, 10, 0, 210), PageOthers, function(state) infJumpActive = state end)
		UserInputService.JumpRequest:Connect(function()
			if infJumpActive and Character and Character:FindFirstChild("Humanoid") then
				Character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			end
		end)
		local syncFly = makeToggle("FLY HIGH", UDim2.new(0, 10, 0, 255), PageOthers, function(state)
			flyActive = state
			local hrp = Character:FindFirstChild("HumanoidRootPart")
			if not hrp or not flyActive then return end
			local bg = Instance.new("BodyGyro", hrp) bg.maxTorque = Vector3.new(4e5, 4e5, 4e5) bg.cframe = hrp.CFrame
			local bv = Instance.new("BodyVelocity", hrp) bv.maxForce = Vector3.new(4e5, 4e5, 4e5)
			task.spawn(function()
				local cam = workspace.CurrentCamera
				while flyActive and hrp and hrp.Parent do
					local dirVector = Vector3.new(0, 0, 0)
					if UserInputService:IsKeyDown(Enum.KeyCode.W) then dirVector = dirVector + cam.CFrame.LookVector end
					if UserInputService:IsKeyDown(Enum.KeyCode.S) then dirVector = dirVector - cam.CFrame.LookVector end
					if UserInputService:IsKeyDown(Enum.KeyCode.A) then dirVector = dirVector - cam.CFrame.RightVector end
					if UserInputService:IsKeyDown(Enum.KeyCode.D) then dirVector = dirVector + cam.CFrame.RightVector end
					if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dirVector = dirVector + Vector3.new(0, 1, 0) end
					bv.velocity = (dirVector.Magnitude > 0) and (dirVector.Unit * flySpeed) or Vector3.new(0, 0, 0)
					bg.cframe = cam.CFrame
					task.wait()
				end
				bg:Destroy() bv:Destroy()
			end)
		end)
		local originalStates = {}
		local hideSeedsActive = false
		local function processSeeds(instance, enable)
			if instance:IsA("BasePart") then
				if enable then
					if not originalStates[instance] then
						originalStates[instance] = { Size = instance.Size, Transparency = instance.Transparency }
					end
					pcall(function()
						instance.Size = Vector3.new(0, 0, 0)
						instance.Transparency = 1
					end)
				else
					if originalStates[instance] then
						pcall(function()
							instance.Size = originalStates[instance].Size
							instance.Transparency = originalStates[instance].Transparency
						end)
					end
				end
			end
			for _, child in ipairs(instance:GetChildren()) do processSeeds(child, enable) end
		end
		local function resolvePlotsFolder()
			local map = workspace:FindFirstChild("Map")
			local island = map and (map:FindFirstChild("MainIsland") or map)
			if island and island:FindFirstChild("PlayerGardens") then
				return island.PlayerGardens:FindFirstChild("Plots")
			end
			if island then return island:FindFirstChild("Plots") end
			if map then return map:FindFirstChild("Plots") end
			return workspace:FindFirstChild("Plots")
		end
		local function applySeedsToPlots(enable)
			local pf = resolvePlotsFolder()
			if not pf then return end
			for _, plot in ipairs(pf:GetChildren()) do
				local currentFolder = plot:FindFirstChild("PlantedSeeds")
				if currentFolder then
					for _, seed in ipairs(currentFolder:GetChildren()) do processSeeds(seed, enable) end
				end
			end
		end
		local syncHideSeeds = makeToggle("Render Seeds", UDim2.new(0, 10, 0, 300), PageOthers, function(state)
			hideSeedsActive = state
			applySeedsToPlots(state)
		end)
		task.spawn(function()
			while true do
				task.wait(1)
				if hideSeedsActive then applySeedsToPlots(true) end
			end
		end)

		local function evaluateAutomationDependencies()
			if _G.AutoChests or _G.AutoDigSites or _G.AutoMagicOrbs then
				if not noclipActive then syncNoclip(true) end
				if not flyActive then syncFly(true) end
			else
				if noclipActive then syncNoclip(false) end
				if flyActive then syncFly(false) end
			end
		end
