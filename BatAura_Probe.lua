--[[
  Bat Aura Probe — read-only network diagnostics for Steal An Egg.
  Run this first, then enable Bat Aura in the other script.  It records
  RemoteEvent/RemoteFunction calls so the exact server action can be verified.
  Stop: getgenv().SAE_BAT_AURA_PROBE = false
]]

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")

local ENV = (getgenv and getgenv()) or _G
ENV.SAE_BAT_AURA_PROBE = true

local old = CoreGui:FindFirstChild("SAE_BatAuraProbe")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "SAE_BatAuraProbe"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = CoreGui

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(560, 260)
panel.Position = UDim2.new(0, 18, 1, -278)
panel.BackgroundColor3 = Color3.fromRGB(19, 17, 32)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -18, 0, 34)
title.Position = UDim2.fromOffset(12, 5)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 224, 128)
title.Text = "Bat Aura Probe · ожидание вызовов чужого скрипта"
title.Parent = panel

local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(1, -18, 0, 28)
hint.Position = UDim2.fromOffset(12, 34)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Gotham
hint.TextSize = 11
hint.TextWrapped = true
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.TextColor3 = Color3.fromRGB(190, 184, 210)
hint.Text = "Включи Bat Aura в другом скрипте рядом с игроком. Жёлтые строки — вероятные вызовы удара."
hint.Parent = panel

local logBox = Instance.new("TextLabel")
logBox.Size = UDim2.new(1, -22, 1, -78)
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

local lines = {}
local function render()
	logBox.Text = #lines > 0 and table.concat(lines, "\n") or "Нет вызовов."
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
	table.insert(lines, 1, string.format("%s%s  %s(%s)", prefix, path, method, table.concat(parts, ", ")))
	while #lines > 12 do table.remove(lines) end
	render()
	if candidate then title.Text = "Bat Aura Probe · найден вероятный вызов удара" end
end

if not (hookmetamethod and getnamecallmethod and newcclosure) then
	title.Text = "Bat Aura Probe · executor не поддерживает network hook"
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
