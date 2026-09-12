--[[
  Steal An Egg - Panel v17 (GitHub loader)
  Load this ONLY. Core is loaded by HttpGet when you press Auto or ESP.
]]

local function resolveHiddenParent()
	if typeof(gethui) == "function" then
		local ok, h = pcall(gethui)
		if ok and h then return h, "gethui" end
	end
	if typeof(get_hidden_gui) == "function" then
		local ok, h = pcall(get_hidden_gui)
		if ok and h then return h, "get_hidden_gui" end
	end
	return nil, "none"
end

local function protectInstance(inst)
	pcall(function() if syn and syn.protect_gui then syn.protect_gui(inst) end end)
	pcall(function() if protect_gui then protect_gui(inst) end end)
	pcall(function() if protectgui then protectgui(inst) end end)
	pcall(function() if hidgui then hidgui(inst) end end)
end

local function mountGui(gui)
	protectInstance(gui)
	local parent, how = resolveHiddenParent()
	if parent then
		gui.Parent = parent
		return true, how
	end
	protectInstance(gui)
	local ok = pcall(function()
		gui.Parent = game:GetService("CoreGui")
	end)
	return ok, ok and "CoreGui+protect" or "FAIL"
end

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LP = Players.LocalPlayer

local BIOMES = {
	"Forest", "Lake", "Desert", "Jungle", "Snow", "Volcano",
	"Abyss Ocean", "Prehistoric", "Cosmic", "Cherry Blossom", "Titan Temple",
}

local selectedBiome = 1
local approachSpeed = 250
local escapeSpeed = 480
local statusLbl, biomeLbl, farmBtn, espBtn
local coreApi
local coreLoaded = false
local autoOn = false
local espOn = false
-- Unique filename + cb= busts GitHub raw CDN cache
local CORE_URL = "https://raw.githubusercontent.com/kimpler1/scim/main/StealAnEgg_v17_Core.lua?cb=17"

local function setStatus(t)
	if statusLbl then statusLbl.Text = tostring(t) end
end

local function setBiomeLabel()
	if biomeLbl then
		biomeLbl.Text = ("Zone [%d/%d]: %s"):format(selectedBiome, #BIOMES, BIOMES[selectedBiome])
	end
end

local function loadCore()
	if coreLoaded and coreApi then return true end
	setStatus("Loading core...")
	local ok, src = pcall(function()
		return game:HttpGet(CORE_URL)
	end)
	if not ok or typeof(src) ~= "string" or #src < 100 then
		setStatus("HttpGet failed: " .. tostring(src))
		return false
	end
	local fn, err = loadstring(src)
	if not fn then
		setStatus("Core compile error: " .. tostring(err))
		return false
	end
	local ran, api = pcall(fn)
	if not ran then
		setStatus("Core run error: " .. tostring(api))
		return false
	end
	if typeof(api) ~= "table" or typeof(api.startFarm) ~= "function" then
		setStatus("Core did not return API")
		return false
	end
	coreApi = api
	coreLoaded = true
	setStatus("Core OK")
	return true
end

local gui = Instance.new("ScreenGui")
gui.Name = "P_" .. tostring(math.random(10000, 99999))
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 999
gui.IgnoreGuiInset = true

local okMount, howMount = mountGui(gui)

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 300, 0, 355)
main.Position = UDim2.new(0.5, -150, 0.28, 0)
main.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -36, 0, 30)
title.BackgroundTransparency = 1
title.Text = "  SAE v17"
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextColor3 = Color3.new(1, 1, 1)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = main

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 30)
closeBtn.Position = UDim2.new(1, -30, 0, 0)
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.BackgroundColor3 = Color3.fromRGB(150, 35, 35)
closeBtn.BorderSizePixel = 0
closeBtn.Parent = main

do
	local dragging, dragStart, startPos, dragInput
	main.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = main.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	main.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input == dragInput then
			local d = input.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
end

local function mkBtn(y, h, text)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0.9, 0, 0, h)
	b.Position = UDim2.new(0.05, 0, 0, y)
	b.Text = text
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.TextColor3 = Color3.new(1, 1, 1)
	b.BackgroundColor3 = Color3.fromRGB(42, 42, 52)
	b.BorderSizePixel = 0
	b.Parent = main
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	return b
end

farmBtn = mkBtn(36, 36, "Auto: OFF")
espBtn = mkBtn(78, 36, "ESP: OFF")

biomeLbl = Instance.new("TextLabel")
biomeLbl.Size = UDim2.new(0.9, 0, 0, 22)
biomeLbl.Position = UDim2.new(0.05, 0, 0, 120)
biomeLbl.BackgroundTransparency = 1
biomeLbl.Font = Enum.Font.GothamBold
biomeLbl.TextSize = 13
biomeLbl.TextColor3 = Color3.fromRGB(255, 210, 90)
biomeLbl.TextXAlignment = Enum.TextXAlignment.Left
biomeLbl.Parent = main
setBiomeLabel()

local prevBiome = mkBtn(146, 32, "< Prev")
prevBiome.Size = UDim2.new(0.42, 0, 0, 32)
local nextBiome = mkBtn(146, 32, "Next >")
nextBiome.Size = UDim2.new(0.42, 0, 0, 32)
nextBiome.Position = UDim2.new(0.53, 0, 0, 146)

local approachBox = Instance.new("TextBox")
approachBox.Size = UDim2.new(0.42, 0, 0, 30)
approachBox.Position = UDim2.new(0.05, 0, 0, 188)
approachBox.Text = tostring(approachSpeed)
approachBox.PlaceholderText = "Approach"
approachBox.ClearTextOnFocus = false
approachBox.Font = Enum.Font.Gotham
approachBox.TextSize = 13
approachBox.TextColor3 = Color3.new(1, 1, 1)
approachBox.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
approachBox.BorderSizePixel = 0
approachBox.Parent = main
Instance.new("UICorner", approachBox).CornerRadius = UDim.new(0, 6)

local escapeBox = Instance.new("TextBox")
escapeBox.Size = UDim2.new(0.42, 0, 0, 30)
escapeBox.Position = UDim2.new(0.53, 0, 0, 188)
escapeBox.Text = tostring(escapeSpeed)
escapeBox.PlaceholderText = "Escape"
escapeBox.ClearTextOnFocus = false
escapeBox.Font = Enum.Font.Gotham
escapeBox.TextSize = 13
escapeBox.TextColor3 = Color3.new(1, 1, 1)
escapeBox.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
escapeBox.BorderSizePixel = 0
escapeBox.Parent = main
Instance.new("UICorner", escapeBox).CornerRadius = UDim.new(0, 6)

local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(0.9, 0, 0, 18)
hint.Position = UDim2.new(0.05, 0, 0, 222)
hint.BackgroundTransparency = 1
hint.Text = "Approach | Escape  (v17 Best+fast 250/480)"
hint.Font = Enum.Font.Gotham
hint.TextSize = 11
hint.TextColor3 = Color3.fromRGB(140, 140, 150)
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.Parent = main

statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(0.9, 0, 0, 85)
statusLbl.Position = UDim2.new(0.05, 0, 0, 245)
statusLbl.BackgroundTransparency = 1
statusLbl.TextWrapped = true
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 12
statusLbl.TextColor3 = Color3.fromRGB(180, 180, 190)
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.TextYAlignment = Enum.TextYAlignment.Top
statusLbl.Parent = main
statusLbl.Text = ("v17 from Best Version. Fast grab+escape.\nmount=%s"):format(tostring(howMount))

if not okMount then
	statusLbl.Text = "UI mount FAIL"
end

local function pushConfig()
	if coreApi and coreApi.setConfig then
		coreApi.setConfig({
			biomeIndex = selectedBiome,
			biomes = BIOMES,
			approachSpeed = approachSpeed,
			escapeSpeed = escapeSpeed,
			status = setStatus,
		})
	end
end

farmBtn.MouseButton1Click:Connect(function()
	if not autoOn then
		if not loadCore() then return end
		pushConfig()
		autoOn = true
		farmBtn.Text = "Auto: ON"
		farmBtn.BackgroundColor3 = Color3.fromRGB(18, 125, 55)
		coreApi.startFarm()
	else
		autoOn = false
		farmBtn.Text = "Auto: OFF"
		farmBtn.BackgroundColor3 = Color3.fromRGB(42, 42, 52)
		if coreApi and coreApi.stopFarm then coreApi.stopFarm() end
		setStatus("Auto off")
	end
end)

espBtn.MouseButton1Click:Connect(function()
	if not loadCore() then return end
	pushConfig()
	espOn = not espOn
	espBtn.Text = espOn and "ESP: ON" or "ESP: OFF"
	espBtn.BackgroundColor3 = espOn and Color3.fromRGB(18, 125, 55) or Color3.fromRGB(42, 42, 52)
	if coreApi.setEsp then coreApi.setEsp(espOn) end
end)

prevBiome.MouseButton1Click:Connect(function()
	selectedBiome = selectedBiome <= 1 and #BIOMES or (selectedBiome - 1)
	setBiomeLabel()
	pushConfig()
end)

nextBiome.MouseButton1Click:Connect(function()
	selectedBiome = selectedBiome >= #BIOMES and 1 or (selectedBiome + 1)
	setBiomeLabel()
	pushConfig()
end)

approachBox.FocusLost:Connect(function()
	local n = tonumber(approachBox.Text)
	if n and n >= 50 and n <= 1000 then approachSpeed = n else approachBox.Text = tostring(approachSpeed) end
	pushConfig()
end)

escapeBox.FocusLost:Connect(function()
	local n = tonumber(escapeBox.Text)
	if n and n >= 50 and n <= 1000 then escapeSpeed = n else escapeBox.Text = tostring(escapeSpeed) end
	pushConfig()
end)

closeBtn.MouseButton1Click:Connect(function()
	autoOn = false
	if coreApi then
		pcall(function() if coreApi.stopFarm then coreApi.stopFarm() end end)
		pcall(function() if coreApi.setEsp then coreApi.setEsp(false) end end)
		pcall(function() if coreApi.destroy then coreApi.destroy() end end)
	end
	gui:Destroy()
end)
