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

		local shops={} for l in raw:gmatch("[^\n]+") do local n,i,t=l:match("([^|]+)|([^|]+)|(.+)") table.insert(shops,{name=n,id=i,items=t:split(",")}) end
		local selectedItems = {}
		for _, s in ipairs(shops) do
			selectedItems[s.id] = {}
			for _, item in ipairs(s.items) do selectedItems[s.id][item] = false end
		end
		local ShopSelectFrame = Instance.new("ScrollingFrame")
		ShopSelectFrame.Size = UDim2.new(0, 140, 1, -115)
		ShopSelectFrame.Position = UDim2.new(0, 5, 0, 35)
		ShopSelectFrame.BackgroundTransparency = 1
		ShopSelectFrame.CanvasSize = UDim2.new(0, 0, 0, 360)
		ShopSelectFrame.ScrollBarThickness = 2
		ShopSelectFrame.Parent = PageAuto
		local ShopSelectLayout = Instance.new("UIListLayout")
		ShopSelectLayout.Padding = UDim.new(0, 4)
		ShopSelectLayout.Parent = ShopSelectFrame
		local ItemsDisplayFrame = Instance.new("Frame")
		ItemsDisplayFrame.Size = UDim2.new(1, -155, 1, -115)
		ItemsDisplayFrame.Position = UDim2.new(0, 150, 0, 35)
		ItemsDisplayFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
		ItemsDisplayFrame.Parent = PageAuto
		Instance.new("UICorner", ItemsDisplayFrame).CornerRadius = UDim.new(0, 6)
		AddNavInstructionText(PageAuto, "Select shop tab, check desired items, specify input amount, and toggle loop.", 5)
		local activeShopPage = nil
		local activeShopId = nil
		local checkUIReferences = {}
		local selectAllBtn = Instance.new("TextButton")
		selectAllBtn.Size = UDim2.new(0.66, -10, 0, 28)
		selectAllBtn.Position = UDim2.new(0, 165, 0, 50)
		selectAllBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 130)
		selectAllBtn.Text = "Select All (in current shop)"
		selectAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		selectAllBtn.Font = Enum.Font.SourceSansBold
		selectAllBtn.TextSize = 12
		selectAllBtn.Parent = ViewContainer
		Instance.new("UICorner", selectAllBtn).CornerRadius = UDim.new(0, 4)
		applyButtonEffects(selectAllBtn, Color3.fromRGB(60, 90, 130), Color3.fromRGB(80, 120, 170))
		PageAuto:GetPropertyChangedSignal("Visible"):Connect(function()
			selectAllBtn.Visible = PageAuto.Visible
		end)
		selectAllBtn.Visible = PageAuto.Visible
		local function refreshSelectAllLabel()
			local labelName = "current shop"
			local allOn = true
			local anyOn = false
			for _, sData in ipairs(shops) do
				if sData.id == activeShopId then
					labelName = sData.name
					for _, item in ipairs(sData.items) do
						if selectedItems[sData.id][item] then anyOn = true else allOn = false end
					end
					break
				end
			end
			if allOn and anyOn then
				selectAllBtn.Text = "✗ Deselect All (" .. labelName .. ")"
				selectAllBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 95)
			else
				selectAllBtn.Text = "Select All (" .. labelName .. ")"
				selectAllBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 130)
			end
		end
		refreshSelectAllLabel()
		for idx, sData in ipairs(shops) do
			local SPage = Instance.new("ScrollingFrame")
			SPage.Size = UDim2.new(1, -10, 1, -45)
			SPage.Position = UDim2.new(0, 5, 0, 38)
			SPage.BackgroundTransparency = 1
			SPage.CanvasSize = UDim2.new(0, 0, 0, #sData.items * 34)
			SPage.Visible = (idx == 1)
			SPage.ScrollBarThickness = 3
			SPage.Parent = ItemsDisplayFrame
			if idx == 1 then
				activeShopPage = SPage
				activeShopId = sData.id
				refreshSelectAllLabel()
			end
			local STab = Instance.new("TextButton")
			STab.Size = UDim2.new(1, -4, 0, 30)
			STab.BackgroundColor3 = (idx == 1) and Color3.fromRGB(0, 210, 255) or Color3.fromRGB(24, 24, 30)
			STab.Text = sData.name
			STab.TextColor3 = (idx == 1) and Color3.fromRGB(10, 10, 14) or Color3.fromRGB(200, 200, 205)
			STab.Font = Enum.Font.SourceSansBold
			STab.TextSize = 12
			STab.Parent = ShopSelectFrame
			Instance.new("UICorner", STab).CornerRadius = UDim.new(0, 4)
			STab.MouseButton1Click:Connect(function()
				if activeShopPage then activeShopPage.Visible = false end
				for _, child in ipairs(ShopSelectFrame:GetChildren()) do
					if child:IsA("TextButton") then
						child.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
						child.TextColor3 = Color3.fromRGB(200, 200, 205)
					end
				end
				STab.BackgroundColor3 = Color3.fromRGB(0, 210, 255)
				STab.TextColor3 = Color3.fromRGB(10, 10, 14)
				SPage.Visible = true
				activeShopPage = SPage
				activeShopId = sData.id
				refreshSelectAllLabel()
			end)
			local SLayout = Instance.new("UIListLayout")
			SLayout.Padding = UDim.new(0, 4)
			SLayout.Parent = SPage
			for _, item in ipairs(sData.items) do
				local Row = Instance.new("Frame")
				Row.Size = UDim2.new(1, -6, 0, 30)
				Row.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
				Row.Parent = SPage
				Instance.new("UICorner", Row).CornerRadius = UDim.new(0, 4)
				local Lbl = Instance.new("TextLabel")
				Lbl.Size = UDim2.new(1, -45, 1, 0)
				Lbl.Position = UDim2.new(0, 10, 0, 0)
				Lbl.Text = item
				Lbl.TextColor3 = Color3.fromRGB(210, 210, 215)
				Lbl.Font = Enum.Font.SourceSans
				Lbl.TextSize = 14
				Lbl.TextXAlignment = Enum.TextXAlignment.Left
				Lbl.BackgroundTransparency = 1
				Lbl.Parent = Row
				local Box = Instance.new("TextButton")
				Box.Size = UDim2.new(0, 20, 0, 20)
				Box.Position = UDim2.new(1, -28, 0.5, -10)
				Box.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
				Box.Text = ""
				Box.Parent = Row
				Instance.new("UICorner", Box).CornerRadius = UDim.new(0, 4)
				local function updateVisualState(val)
					selectedItems[sData.id][item] = val
					Box.BackgroundColor3 = val and Color3.fromRGB(0, 210, 255) or Color3.fromRGB(40, 40, 48)
					Box.Text = val and "✓" or ""
					Box.TextColor3 = val and Color3.fromRGB(10, 10, 14) or Color3.fromRGB(255, 255, 255)
				end
				Box.MouseButton1Click:Connect(function()
					updateVisualState(not selectedItems[sData.id][item])
					refreshSelectAllLabel()
				end)
				checkUIReferences[sData.id .. "_" .. item] = updateVisualState
			end
		end
		selectAllBtn.MouseButton1Click:Connect(function()
			local target = false
			for _, sData in ipairs(shops) do
				if sData.id == activeShopId then
					for _, item in ipairs(sData.items) do
						if not selectedItems[sData.id][item] then
							target = true
						end
					end
					break
				end
			end
			for _, sData in ipairs(shops) do
				if sData.id == activeShopId then
					for _, item in ipairs(sData.items) do
						local ref = checkUIReferences[sData.id .. "_" .. item]
						if ref then ref(target) end
					end
					break
				end
			end
			refreshSelectAllLabel()
		end)
		local CtrlBar = Instance.new("Frame")
		CtrlBar.Size = UDim2.new(1, -155, 0, 140)
		CtrlBar.Position = UDim2.new(0, 150, 1, -105)
		CtrlBar.BackgroundTransparency = 1
		CtrlBar.Parent = PageAuto
		local AmtInput = Instance.new("TextBox")
		AmtInput.Size = UDim2.new(0, 60, 0, 34)
		AmtInput.Position = UDim2.new(0, 5, 0, 15)
		AmtInput.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
		AmtInput.Text = "1"
		AmtInput.TextColor3 = Color3.fromRGB(255, 255, 255)
		AmtInput.Font = Enum.Font.SourceSansBold
		AmtInput.TextSize = 14
		AmtInput.Parent = CtrlBar
		Instance.new("UICorner", AmtInput).CornerRadius = UDim.new(0, 4)
		local SingleBuy = Instance.new("TextButton")
		SingleBuy.Size = UDim2.new(0, 120, 0, 34)
		SingleBuy.Position = UDim2.new(0, 75, 0, 15)
		SingleBuy.BackgroundColor3 = Color3.fromRGB(0, 210, 255)
		SingleBuy.Text = "Purchase Selected"
		SingleBuy.TextColor3 = Color3.fromRGB(10, 10, 14)
		SingleBuy.Font = Enum.Font.SourceSansBold
		SingleBuy.TextSize = 13
		SingleBuy.Parent = CtrlBar
		Instance.new("UICorner", SingleBuy).CornerRadius = UDim.new(0, 4)
		local LoopBuy = Instance.new("TextButton")
		LoopBuy.Size = UDim2.new(0, 140, 0, 34)
		LoopBuy.Position = UDim2.new(1, -145, 0, 15)
		LoopBuy.BackgroundColor3 = Color3.fromRGB(0, 200, 120)
		LoopBuy.Text = "Auto Loop [ON]"
		LoopBuy.TextColor3 = Color3.fromRGB(255, 255, 255)
		LoopBuy.Font = Enum.Font.SourceSansBold
		LoopBuy.TextSize = 13
		LoopBuy.Parent = CtrlBar
		Instance.new("UICorner", LoopBuy).CornerRadius = UDim.new(0, 4)
		local function pcallPurchaseEngine()
			local amt = tonumber(AmtInput.Text) or 1
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
		local function setAutoBuyState(state)
			isAutoBuying = state
			if isAutoBuying then
				LoopBuy.Text = "Auto Loop [ON]"
				LoopBuy.BackgroundColor3 = Color3.fromRGB(0, 200, 120)
				task.spawn(function()
					while isAutoBuying do
						pcallPurchaseEngine()
						task.wait(1)
					end
				end)
			else
				LoopBuy.Text = "Auto Loop [OFF]"
				LoopBuy.BackgroundColor3 = Color3.fromRGB(240, 70, 70)
			end
		end
		SingleBuy.MouseButton1Click:Connect(pcallPurchaseEngine)
		LoopBuy.MouseButton1Click:Connect(function() setAutoBuyState(not isAutoBuying) end)
		isAutoBuying = true
		task.spawn(function()
			while isAutoBuying do
				pcallPurchaseEngine()
				task.wait(1)
			end
		end)
		RDR_CONFIG_DATA.getShopSelections = function()
			local out = {}
			for shopId, items in pairs(selectedItems) do
				out[shopId] = {}
				for item, selected in pairs(items) do
					if selected then out[shopId][item] = true end
				end
			end
			return out
		end
		RDR_CONFIG_DATA.applyShopSelections = function(data)
			if not data then return end
			for _, sData in ipairs(shops) do
				for _, item in ipairs(sData.items) do
					local ref = checkUIReferences[sData.id .. "_" .. item]
					if ref then ref(false) end
				end
			end
			for shopId, items in pairs(data) do
				for item, selected in pairs(items) do
					if selected then
						local ref = checkUIReferences[shopId .. "_" .. item]
						if ref then ref(true) end
					end
				end
			end
			refreshSelectAllLabel()
		end
		RDR_CONFIG_DATA.getIsAutoBuying = function() return isAutoBuying end
		RDR_CONFIG_DATA.setIsAutoBuying = function(state) if isAutoBuying ~= state then setAutoBuyState(state) end end
