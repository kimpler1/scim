--[[
  Bat Aura Probe — read-only action journal for Steal An Egg.
  Stop/close: getgenv().SAE_BAT_AURA_PROBE = false
]]

local CoreGui = game:GetService("CoreGui")
local ProximityPromptService = game:GetService("ProximityPromptService")
local PROBE_VER = "V63"

local ENV = (getgenv and getgenv()) or _G
ENV.SAE_BAT_AURA_PROBE = true

local uiParent = CoreGui
pcall(function()
	if gethui then uiParent = gethui() end
end)
local old = uiParent:FindFirstChild("SAE_BatAuraProbe")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "SAE_BatAuraProbe"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = uiParent

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(620, 320)
panel.Position = UDim2.new(0, 18, 1, -338)
panel.BackgroundColor3 = Color3.fromRGB(19, 17, 32)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -180, 0, 34)
title.Position = UDim2.fromOffset(12, 5)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 224, 128)
title.Text = "Bat Aura Probe " .. PROBE_VER .. " · журнал запущен"
title.Parent = panel

local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(1, -18, 0, 34)
hint.Position = UDim2.fromOffset(12, 34)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Gotham
hint.TextSize = 11
hint.TextWrapped = true
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.TextColor3 = Color3.fromRGB(190, 184, 210)
hint.Text = "Включи Bat Aura в другом скрипте рядом с игроком. Журнал пишет сетевые вызовы, Tool:Activate и ProximityPrompt; ★ — вероятный удар."
hint.Parent = panel

local logBox = Instance.new("TextLabel")
logBox.Size = UDim2.new(1, -22, 1, -118)
logBox.Position = UDim2.fromOffset(11, 66)
logBox.BackgroundColor3 = Color3.fromRGB(11, 10, 20)
logBox.BackgroundTransparency = 0.22
logBox.BorderSizePixel = 0
logBox.Font = Enum.Font.Code
logBox.TextSize = 12
logBox.TextXAlignment = Enum.TextXAlignment.Left
logBox.TextYAlignment = Enum.TextYAlignment.Top
logBox.TextColor3 = Color3.fromRGB(230, 228, 240)
logBox.TextWrapped = false
logBox.Text = "Нет вызовов."
logBox.Parent = panel
Instance.new("UICorner", logBox).CornerRadius = UDim.new(0, 8)

local lines, fullLines = {}, {}
local function render()
	logBox.Text = #lines > 0 and table.concat(lines, "\n") or "Нет событий. Включи Bat Aura в другом скрипте."
end

local function addLine(text)
	local stamped = string.format("[%s] %s", os.date("%H:%M:%S"), text)
	table.insert(lines, 1, stamped)
	table.insert(fullLines, stamped)
	while #lines > 15 do table.remove(lines) end
	while #fullLines > 300 do table.remove(fullLines, 1) end
	render()
	pcall(function() print("[BatAura Probe] " .. stamped) end)
end

local function valueText(value)
	local kind = typeof(value)
	if kind == "Instance" then return value:GetFullName() end
	if kind == "string" then return string.format("%q", value:sub(1, 80)) end
	if kind == "table" then return "{table}" end
	return tostring(value)
end

local function record(remote, method, args)
	if not ENV.SAE_BAT_AURA_PROBE then return end
	local parts = {}
	for i = 1, math.min(args.n, 4) do table.insert(parts, valueText(args[i])) end
	local path = remote:GetFullName()
	local candidate = path:lower():find("bat", 1, true) or path:lower():find("swing", 1, true)
		or path:lower():find("slap", 1, true) or path:lower():find("hit", 1, true)
	local prefix = candidate and "★ " or "· "
	addLine(string.format("%s%s  %s(%s)", prefix, path, method, table.concat(parts, ", ")))
	if candidate then title.Text = "Bat Aura Probe · найден вероятный вызов удара" end
end

local function button(text, x, callback)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(74, 26)
	b.Position = UDim2.new(1, x, 0, 8)
	b.BackgroundColor3 = Color3.fromRGB(72, 57, 145)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 11
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.Parent = panel
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
	b.MouseButton1Click:Connect(callback)
end

button("Copy", -166, function()
	local text = table.concat(fullLines, "\n")
	if setclipboard then
		setclipboard(text)
		title.Text = "Bat Aura Probe · журнал скопирован"
	else
		title.Text = "Bat Aura Probe · setclipboard недоступен в этом executor"
	end
end)
button("Close", -84, function()
	ENV.SAE_BAT_AURA_PROBE = false
	gui:Destroy()
end)

addLine("Probe loaded; hooks installing")

local function watchTool(tool)
	if not tool:IsA("Tool") then return end
	tool.Activated:Connect(function()
		if ENV.SAE_BAT_AURA_PROBE then addLine("Tool:Activate " .. tool:GetFullName()) end
	end)
end
local function watchContainer(container)
	if not container then return end
	for _, child in ipairs(container:GetChildren()) do watchTool(child) end
	container.ChildAdded:Connect(watchTool)
end
local player = game:GetService("Players").LocalPlayer
watchContainer(player:FindFirstChildOfClass("Backpack"))
player.CharacterAdded:Connect(watchContainer)
if player.Character then watchContainer(player.Character) end
ProximityPromptService.PromptTriggered:Connect(function(prompt, owner)
	if ENV.SAE_BAT_AURA_PROBE and owner == player then addLine("Prompt " .. prompt:GetFullName()) end
end)

if not (hookmetamethod and getnamecallmethod and newcclosure) then
	title.Text = "Bat Aura Probe · executor не поддерживает network hook"
	addLine("ERROR: hookmetamethod/getnamecallmethod/newcclosure unavailable")
	return
end

local previous
previous = hookmetamethod(game, "__namecall", newcclosure(function(remote, ...)
	local method = getnamecallmethod()
	if ENV.SAE_BAT_AURA_PROBE and (method == "FireServer" or method == "InvokeServer")
		and (remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction")) then
		record(remote, method, table.pack(...))
	end
	return previous(remote, ...)
end))

addLine("Network hook ready")
