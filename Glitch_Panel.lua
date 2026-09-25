--[[
  Glitch — Steal An Egg UI (glass / sidebar)
  Tabs: Main | ESP | Player
  VER: V78
]]

local GLITCH_UI_VER = "V113"
local CORE_URL = "https://raw.githubusercontent.com/kimpler1/scim/main/Glitch_Core.lua?cb=v113"

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LP = Players.LocalPlayer

-- Only one Glitch core may control the character.  Users commonly run an
-- updated loader over an existing panel; without this handoff the old farm
-- loop keeps its former biome and can fight the new route at the same time.
local sessionEnv = _G
if typeof(getgenv) == "function" then
	local ok, env = pcall(getgenv)
	if ok and typeof(env) == "table" then sessionEnv = env end
end
local priorSession = sessionEnv.__SAE_GLITCH_SESSION
if typeof(priorSession) == "table" then
	local priorApi = priorSession.api
	if typeof(priorApi) == "table" then
		pcall(function() if priorApi.stopFarm then priorApi.stopFarm() end end)
		pcall(function() if priorApi.destroy then priorApi.destroy() end end)
	end
	pcall(function()
		if priorSession.gui and priorSession.gui.Parent then priorSession.gui:Destroy() end
	end)
end
local activeSession = {}
sessionEnv.__SAE_GLITCH_SESSION = activeSession

local ACCENT = Color3.fromRGB(120, 110, 255)
local ACCENT_SOFT = Color3.fromRGB(90, 80, 200)
local GLASS = Color3.fromRGB(28, 24, 48)
local GLASS2 = Color3.fromRGB(22, 20, 38)
local SIDE = Color3.fromRGB(18, 16, 32)
local TEXT = Color3.fromRGB(245, 245, 250)
local MUTED = Color3.fromRGB(160, 155, 185)
local ROW = Color3.fromRGB(36, 32, 58)

local BIOMES = {
	"Forest", "Lake", "Desert", "Jungle", "Snow", "Volcano",
	"Abyss Ocean", "Prehistoric", "Cosmic", "Cherry Blossom", "Titan Temple",
	"Angels / Demons",
}

local BIOME_LOCALES = {
	ru = {
		Forest = "Лес", Lake = "Озеро", Desert = "Пустыня", Jungle = "Джунгли", Snow = "Снег", Volcano = "Вулкан",
		["Abyss Ocean"] = "Океан Бездны", Prehistoric = "Доисторический", Cosmic = "Космос",
		["Cherry Blossom"] = "Цветущая сакура", ["Titan Temple"] = "Храм титанов", ["Angels / Demons"] = "Ангелы / Демоны",
	},
	de = {
		Forest = "Wald", Lake = "See", Desert = "Wüste", Jungle = "Dschungel", Snow = "Schnee", Volcano = "Vulkan",
		["Abyss Ocean"] = "Abgrund-Ozean", Prehistoric = "Prähistorisch", Cosmic = "Kosmisch",
		["Cherry Blossom"] = "Kirschblüte", ["Titan Temple"] = "Titanentempel", ["Angels / Demons"] = "Engel / Dämonen",
	},
	fr = {
		Forest = "Forêt", Lake = "Lac", Desert = "Désert", Jungle = "Jungle", Snow = "Neige", Volcano = "Volcan",
		["Abyss Ocean"] = "Océan des abysses", Prehistoric = "Préhistorique", Cosmic = "Cosmique",
		["Cherry Blossom"] = "Fleur de cerisier", ["Titan Temple"] = "Temple des titans", ["Angels / Demons"] = "Anges / Démons",
	},
	es = {
		Forest = "Bosque", Lake = "Lago", Desert = "Desierto", Jungle = "Jungla", Snow = "Nieve", Volcano = "Volcán",
		["Abyss Ocean"] = "Océano abisal", Prehistoric = "Prehistórico", Cosmic = "Cósmico",
		["Cherry Blossom"] = "Flor de cerezo", ["Titan Temple"] = "Templo de titanes", ["Angels / Demons"] = "Ángeles / Demonios",
	},
}

local selectedBiome = 1
local targetMode = "all"
local approachSpeed, escapeSpeed = 250, 480
local walkSpeedVal, flySpeedVal = 32, 60
local autoOn = false
local coreApi, coreLoaded = nil, false
local statusLbl, biomeLbl
local debugLines = {}
local pages = {}
local navBtns = {}
local currentPage = "General"
local currentLocale = "en"

local LANGUAGES = {
	{ code = "ru", name = "Русский" },
	{ code = "en", name = "English" },
	{ code = "de", name = "Deutsch" },
	{ code = "fr", name = "Français" },
	{ code = "es", name = "Español" },
}

local LOCALES = {
	ru = {
		General = "Общее", Main = "Главное", Player = "Игрок", Auto = "Авто", Language = "Язык",
		["More scripts for different places"] = "Больше скриптов на разные плейсы", ["Steal All Eggs"] = "Забрать все яйца",
		["Steal Best Egg"] = "Забрать лучшее яйцо", ["Recover Dropped Eggs"] = "Подобрать упавшие яйца",
		["Bat Aura"] = "Аура биты", ["ESP Players"] = "ESP игроков", ["ESP Eggs"] = "ESP яиц",
		Speed = "Скорость", ["Walk Speed"] = "Скорость ходьбы", Fly = "Полёт", ["Fly Speed"] = "Скорость полёта",
		["Infinite Jump"] = "Бесконечный прыжок", ["No Clip"] = "Без столкновений",
		["Auto Plant All Eggs"] = "Авто посадка всех яиц", ["Auto Hatch Eggs"] = "Авто вылупление яиц",
		["Auto Equip Best Pets"] = "Авто выбор лучших питомцев", ["Link copied"] = "Ссылка скопирована",
		["Link unavailable"] = "Ссылка недоступна",
	},
	de = {
		General = "Allgemein", Main = "Haupt", Player = "Spieler", Auto = "Auto", Language = "Sprache",
		["More scripts for different places"] = "Mehr Skripte für verschiedene Spiele", ["Steal All Eggs"] = "Alle Eier nehmen",
		["Steal Best Egg"] = "Bestes Ei nehmen", ["Recover Dropped Eggs"] = "Gefallene Eier holen",
		["Bat Aura"] = "Schläger-Aura", ["ESP Players"] = "ESP Spieler", ["ESP Eggs"] = "ESP Eier",
		Speed = "Tempo", ["Walk Speed"] = "Lauftempo", Fly = "Fliegen", ["Fly Speed"] = "Flugtempo",
		["Infinite Jump"] = "Unendlicher Sprung", ["No Clip"] = "Keine Kollision",
		["Auto Plant All Eggs"] = "Alle Eier automatisch pflanzen", ["Auto Hatch Eggs"] = "Eier automatisch ausbrüten",
		["Auto Equip Best Pets"] = "Beste Haustiere automatisch wählen", ["Link copied"] = "Link kopiert",
		["Link unavailable"] = "Link nicht verfügbar",
	},
	fr = {
		General = "Général", Main = "Principal", Player = "Joueur", Auto = "Auto", Language = "Langue",
		["More scripts for different places"] = "Plus de scripts pour différents jeux", ["Steal All Eggs"] = "Prendre tous les œufs",
		["Steal Best Egg"] = "Prendre le meilleur œuf", ["Recover Dropped Eggs"] = "Récupérer les œufs tombés",
		["Bat Aura"] = "Aura de batte", ["ESP Players"] = "ESP joueurs", ["ESP Eggs"] = "ESP œufs",
		Speed = "Vitesse", ["Walk Speed"] = "Vitesse de marche", Fly = "Vol", ["Fly Speed"] = "Vitesse de vol",
		["Infinite Jump"] = "Saut infini", ["No Clip"] = "Sans collision",
		["Auto Plant All Eggs"] = "Planter tous les œufs auto", ["Auto Hatch Eggs"] = "Faire éclore les œufs auto",
		["Auto Equip Best Pets"] = "Équiper les meilleurs animaux auto", ["Link copied"] = "Lien copié",
		["Link unavailable"] = "Lien indisponible",
	},
	es = {
		General = "General", Main = "Principal", Player = "Jugador", Auto = "Auto", Language = "Idioma",
		["More scripts for different places"] = "Más scripts para distintos juegos", ["Steal All Eggs"] = "Tomar todos los huevos",
		["Steal Best Egg"] = "Tomar el mejor huevo", ["Recover Dropped Eggs"] = "Recoger huevos caídos",
		["Bat Aura"] = "Aura de bate", ["ESP Players"] = "ESP jugadores", ["ESP Eggs"] = "ESP huevos",
		Speed = "Velocidad", ["Walk Speed"] = "Velocidad al caminar", Fly = "Volar", ["Fly Speed"] = "Velocidad de vuelo",
		["Infinite Jump"] = "Salto infinito", ["No Clip"] = "Sin colisión",
		["Auto Plant All Eggs"] = "Plantar todos los huevos auto", ["Auto Hatch Eggs"] = "Incubar huevos auto",
		["Auto Equip Best Pets"] = "Equipar mejores mascotas auto", ["Link copied"] = "Enlace copiado",
		["Link unavailable"] = "Enlace no disponible",
	},
}

local function localizedText(key)
	return (LOCALES[currentLocale] and LOCALES[currentLocale][key]) or key
end

local function localizedBiome(name)
	return (BIOME_LOCALES[currentLocale] and BIOME_LOCALES[currentLocale][name]) or name
end

local function markLocalized(inst, key)
	inst:SetAttribute("LangKey", key)
	inst.Text = localizedText(key)
	return inst
end

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
	return ok, ok and "CoreGui" or "FAIL"
end

local function setStatus(t)
	local text = tostring(t)
	table.insert(debugLines, text)
	while #debugLines > 3 do table.remove(debugLines, 1) end
	if statusLbl then statusLbl.Text = table.concat(debugLines, "\n") end
end

local function setBiomeLabel()
	if biomeLbl then
		biomeLbl.Text = ("%d/%d  ·  %s"):format(selectedBiome, #BIOMES, localizedBiome(BIOMES[selectedBiome]))
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
		setStatus("Compile: " .. tostring(err))
		return false
	end
	local ran, api = pcall(fn)
	if not ran or typeof(api) ~= "table" or typeof(api.startFarm) ~= "function" then
		setStatus("Core fail: " .. tostring(api))
		return false
	end
	coreApi = api
	coreLoaded = true
	activeSession.api = coreApi
	local cv = (coreApi.getVersion and coreApi.getVersion()) or "?"
	setStatus(("Core OK  UI %s  Core %s"):format(GLITCH_UI_VER, tostring(cv)))
	return true
end

local function pushConfig()
	if coreApi and coreApi.setConfig then
		coreApi.setConfig({
			biomeIndex = selectedBiome,
			biomes = BIOMES,
		approachSpeed = approachSpeed,
		escapeSpeed = escapeSpeed,
		targetMode = targetMode,
		status = setStatus,
		})
	end
end

local function corner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 10)
	c.Parent = p
	return c
end

local function stroke(p, col, th)
	local s = Instance.new("UIStroke")
	s.Color = col or Color3.fromRGB(255, 255, 255)
	s.Thickness = th or 1
	s.Transparency = 0.78
	s.Parent = p
	return s
end

local function pad(p, l, t, r, b)
	local u = Instance.new("UIPadding")
	u.PaddingLeft = UDim.new(0, l or 0)
	u.PaddingTop = UDim.new(0, t or 0)
	u.PaddingRight = UDim.new(0, r or 0)
	u.PaddingBottom = UDim.new(0, b or 0)
	u.Parent = p
	return u
end

-- Screen
local gui = Instance.new("ScreenGui")
gui.Name = "Glitch_" .. tostring(math.random(10000, 99999))
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 999
gui.IgnoreGuiInset = true
activeSession.gui = gui
local okMount, howMount = mountGui(gui)

local function applyLanguage(code)
	currentLocale = code
	for _, inst in ipairs(gui:GetDescendants()) do
		local key = inst:GetAttribute("LangKey")
		if key and (inst:IsA("TextLabel") or inst:IsA("TextButton")) then
			inst.Text = localizedText(key)
		end
	end
	setBiomeLabel()
end

local win = Instance.new("Frame")
win.Name = "Window"
win.Size = UDim2.fromOffset(560, 380)
win.Position = UDim2.new(0.5, -280, 0.5, -190)
win.BackgroundColor3 = GLASS
win.BackgroundTransparency = 0.12
win.BorderSizePixel = 0
win.Active = true
win.ClipsDescendants = true
win.Parent = gui
corner(win, 22)
stroke(win, Color3.fromRGB(180, 170, 255), 1.2)

-- Header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 44)
header.BackgroundColor3 = SIDE
header.BackgroundTransparency = 0.15
header.BorderSizePixel = 0
header.Parent = win
corner(header, 22)

local brandDot = Instance.new("Frame")
brandDot.Size = UDim2.fromOffset(10, 10)
brandDot.Position = UDim2.fromOffset(16, 17)
brandDot.BackgroundColor3 = ACCENT
brandDot.BorderSizePixel = 0
brandDot.Parent = header
corner(brandDot, 5)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(34, 0)
title.Size = UDim2.new(0, 210, 1, 0)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextColor3 = TEXT
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Glitch  ·  Steal An Egg"
title.Parent = header

local versionDot = Instance.new("Frame")
versionDot.Size = UDim2.fromOffset(7, 7)
versionDot.Position = UDim2.fromOffset(248, 19)
versionDot.BackgroundColor3 = ACCENT
versionDot.BorderSizePixel = 0
versionDot.Parent = header
corner(versionDot, 4)

local version = Instance.new("TextLabel")
version.BackgroundTransparency = 1
version.Position = UDim2.fromOffset(261, 0)
version.Size = UDim2.fromOffset(48, 44)
version.Font = Enum.Font.GothamBold
version.TextSize = 12
version.TextColor3 = MUTED
version.TextXAlignment = Enum.TextXAlignment.Left
version.Text = GLITCH_UI_VER
version.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(28, 28)
closeBtn.Position = UDim2.new(1, -36, 0.5, -14)
closeBtn.BackgroundColor3 = Color3.fromRGB(160, 50, 70)
closeBtn.BackgroundTransparency = 0.2
closeBtn.Text = "×"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 18
closeBtn.TextColor3 = TEXT
closeBtn.BorderSizePixel = 0
closeBtn.Parent = header
corner(closeBtn, 8)

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.fromOffset(28, 28)
minBtn.Position = UDim2.new(1, -70, 0.5, -14)
minBtn.BackgroundColor3 = Color3.fromRGB(50, 48, 70)
minBtn.BackgroundTransparency = 0.2
minBtn.Text = "–"
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 18
minBtn.TextColor3 = TEXT
minBtn.BorderSizePixel = 0
minBtn.Parent = header
corner(minBtn, 8)

-- Drag
do
	local dragging, dragStart, startPos, dragInput
	header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = win.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	header.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input == dragInput then
			local d = input.Position - dragStart
			win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
end

-- Body
local body = Instance.new("Frame")
body.Size = UDim2.new(1, 0, 1, -48)
body.Position = UDim2.fromOffset(0, 48)
body.BackgroundTransparency = 1
body.Parent = win

local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 132, 1, 0)
sidebar.BackgroundColor3 = SIDE
sidebar.BackgroundTransparency = 0
sidebar.BorderSizePixel = 0
sidebar.Parent = body
corner(sidebar, 22)

-- Fill just the two inner corner cutouts, avoiding a second full-size layer.
for _, y in ipairs({ 0, -22 }) do
	local join = Instance.new("Frame")
	join.Size = UDim2.fromOffset(22, 22)
	join.Position = UDim2.new(1, -22, y == 0 and 0 or 1, y)
	join.BackgroundColor3 = SIDE
	join.BackgroundTransparency = 0
	join.BorderSizePixel = 0
	join.ZIndex = 0
	join.Parent = sidebar
end

local sideScroll = Instance.new("ScrollingFrame")
sideScroll.Size = UDim2.new(1, 0, 1, -8)
sideScroll.Position = UDim2.fromOffset(0, 8)
sideScroll.BackgroundTransparency = 1
sideScroll.BorderSizePixel = 0
sideScroll.ScrollBarThickness = 2
sideScroll.CanvasSize = UDim2.fromOffset(0, 260)
sideScroll.Parent = sidebar
pad(sideScroll, 10, 4, 10, 8)

local sideList = Instance.new("UIListLayout")
sideList.Padding = UDim.new(0, 4)
sideList.Parent = sideScroll

local content = Instance.new("Frame")
content.Size = UDim2.new(1, -132, 1, 0)
content.Position = UDim2.fromOffset(132, 0)
content.BackgroundColor3 = GLASS2
content.BackgroundTransparency = 0.25
content.BorderSizePixel = 0
content.ClipsDescendants = true
content.Parent = body
corner(content, 22)

-- Mirror the two small join pieces at the content's inner edge.
for _, y in ipairs({ 0, -22 }) do
	local join = Instance.new("Frame")
	join.Size = UDim2.fromOffset(22, 22)
	join.Position = UDim2.new(0, 0, y == 0 and 0 or 1, y)
	join.BackgroundColor3 = GLASS2
	join.BackgroundTransparency = 0.25
	join.BorderSizePixel = 0
	join.ZIndex = 0
	join.Parent = content
end

local function makePage(name)
	local f = Instance.new("ScrollingFrame")
	f.Name = name
	-- Keep the scrollbar inside the rounded content edge at every scroll point.
	f.Size = UDim2.new(1, -10, 1, -16)
	f.Position = UDim2.fromOffset(0, 8)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.ScrollBarThickness = 3
	f.ScrollBarImageColor3 = ACCENT
	f.CanvasSize = UDim2.fromOffset(0, 420)
	f.Visible = false
	f.Parent = content
	pad(f, 16, 14, 12, 14)
	local list = Instance.new("UIListLayout")
	-- One clear, consistent gap between every row on every page.
	list.Padding = UDim.new(0, 10)
	list.Parent = f
	pages[name] = f
	return f
end

local function sectionLabel(parent, text)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 18)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = 11
	l.TextColor3 = MUTED
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = string.upper(text)
	l.Parent = parent
	return l
end

local function navItem(text, pageName, isHeader)
	if isHeader then
		local h = Instance.new("TextLabel")
		h.Size = UDim2.new(1, 0, 0, 20)
		h.BackgroundTransparency = 1
		h.Font = Enum.Font.GothamBold
		h.TextSize = 11
		h.TextColor3 = MUTED
		h.TextXAlignment = Enum.TextXAlignment.Left
		h.Text = text
		h.Parent = sideScroll
		return h
	end
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 34)
	b.BackgroundColor3 = ROW
	b.BackgroundTransparency = 1
	b.Text = ""
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.TextColor3 = TEXT
	b.TextXAlignment = Enum.TextXAlignment.Left
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Parent = sideScroll
	corner(b, 8)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(17, 0)
	label.Size = UDim2.new(1, -23, 1, 0)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = TEXT
	label.TextXAlignment = Enum.TextXAlignment.Left
	markLocalized(label, text)
	label.Parent = b
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 3, 0, 16)
	bar.Position = UDim2.new(0, 4, 0.5, -8)
	bar.BackgroundColor3 = ACCENT
	bar:SetAttribute("ThemeAccent", true)
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar.Parent = b
	corner(bar, 2)
	navBtns[pageName] = { btn = b, bar = bar }
	b.MouseButton1Click:Connect(function()
		currentPage = pageName
		for name, pg in pairs(pages) do
			pg.Visible = name == pageName
		end
		for name, pack in pairs(navBtns) do
			local on = name == pageName
			pack.bar.Visible = on
			pack.btn.BackgroundTransparency = on and 0.35 or 1
			pack.btn.BackgroundColor3 = on and Color3.fromRGB(55, 48, 95) or ROW
		end
	end)
	return b
end

local function glassRow(parent, height)
	local r = Instance.new("Frame")
	r.Size = UDim2.new(1, 0, 0, height or 48)
	r.BackgroundColor3 = ROW
	r:SetAttribute("ThemeRow", true)
	-- Keep the original darker glass treatment for function rows.
	r.BackgroundTransparency = 0.10
	r.BorderSizePixel = 0
	r.Parent = parent
	corner(r, 12)
	stroke(r, Color3.fromRGB(200, 190, 255), 1)
	return r
end

-- Visually groups controls that configure the same feature while preserving
-- the page's normal vertical layout.
local function controlGroup(parent, height)
	local group = Instance.new("Frame")
	group.Size = UDim2.new(1, 0, 0, height)
	group.BackgroundColor3 = Color3.fromRGB(46, 40, 76)
	group:SetAttribute("ThemeGroup", true)
	-- Group containers are outline-only; the page background shows through.
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.Parent = parent
	corner(group, 14)
	stroke(group, Color3.fromRGB(150, 140, 225), 1)
	pad(group, 8, 8, 8, 8)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 7)
	layout.Parent = group
	return group
end

local function makeToggle(parent, labelText, default, callback)
	local row = glassRow(parent, 32)
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Position = UDim2.fromOffset(14, 0)
	lbl.Size = UDim2.new(1, -78, 1, 0)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 12
	lbl.TextColor3 = TEXT
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	markLocalized(lbl, labelText)
	lbl.Parent = row

	local track = Instance.new("TextButton")
	track.Size = UDim2.fromOffset(42, 22)
	track.Position = UDim2.new(1, -54, 0.5, -11)
	track.BackgroundColor3 = Color3.fromRGB(55, 52, 75)
	track:SetAttribute("ThemeToggle", true)
	track.Text = ""
	track.BorderSizePixel = 0
	track.AutoButtonColor = false
	track.Parent = row
	corner(track, 11)

	local knob = Instance.new("Frame")
	knob.Size = UDim2.fromOffset(16, 16)
	knob.Position = UDim2.fromOffset(3, 3)
	knob.BackgroundColor3 = TEXT
	knob.BorderSizePixel = 0
	knob.Parent = track
	corner(knob, 8)

	local on = default and true or false
	local function paint()
		track.BackgroundColor3 = on and ACCENT or Color3.fromRGB(55, 52, 75)
		TweenService:Create(knob, TweenInfo.new(0.15), {
			Position = on and UDim2.fromOffset(23, 3) or UDim2.fromOffset(3, 3),
		}):Play()
	end
	paint()
	track.MouseButton1Click:Connect(function()
		on = not on
		paint()
		if callback then callback(on) end
	end)
	return {
		set = function(v)
			on = v and true or false
			paint()
		end,
		get = function()
			return on
		end,
	}
end

local function makeSlider(parent, labelText, minV, maxV, default, callback)
	local row = glassRow(parent, 42)
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Position = UDim2.fromOffset(14, 1)
	lbl.Size = UDim2.new(1, -80, 0, 20)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 12
	lbl.TextColor3 = TEXT
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	markLocalized(lbl, labelText)
	lbl.Parent = row

	local valLbl = Instance.new("TextLabel")
	valLbl.BackgroundTransparency = 1
	valLbl.Position = UDim2.new(1, -70, 0, 1)
	valLbl.Size = UDim2.fromOffset(56, 20)
	valLbl.Font = Enum.Font.GothamBold
	valLbl.TextSize = 12
	valLbl.TextColor3 = ACCENT
	valLbl:SetAttribute("ThemeAccentText", true)
	valLbl.TextXAlignment = Enum.TextXAlignment.Right
	valLbl.Text = tostring(default)
	valLbl.Parent = row

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, -28, 0, 6)
	bar.Position = UDim2.fromOffset(14, 29)
	bar.BackgroundColor3 = Color3.fromRGB(45, 42, 65)
	bar.BorderSizePixel = 0
	bar.Parent = row
	corner(bar, 3)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new((default - minV) / (maxV - minV), 0, 1, 0)
	fill.BackgroundColor3 = ACCENT
	fill:SetAttribute("ThemeAccent", true)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	corner(fill, 3)

	local knob = Instance.new("Frame")
	knob.Size = UDim2.fromOffset(14, 14)
	knob.Position = UDim2.new((default - minV) / (maxV - minV), -7, 0.5, -7)
	knob.BackgroundColor3 = TEXT
	knob.BorderSizePixel = 0
	knob.Parent = bar
	corner(knob, 7)

	local value = default
	local dragging = false

	local function setFromX(x)
		local rel = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
		value = math.floor(minV + rel * (maxV - minV) + 0.5)
		fill.Size = UDim2.new(rel, 0, 1, 0)
		knob.Position = UDim2.new(rel, -7, 0.5, -7)
		valLbl.Text = tostring(value)
		if callback then callback(value) end
	end

	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	return {
		get = function()
			return value
		end,
	}
end

local function makeNumRow(parent, leftText, rightText, leftDef, rightDef, onLeft, onRight)
	local row = glassRow(parent, 52)
	local a = Instance.new("TextBox")
	a.Size = UDim2.new(0.42, 0, 0, 32)
	a.Position = UDim2.new(0.05, 0, 0.5, -16)
	a.Text = tostring(leftDef)
	a.PlaceholderText = leftText
	a.ClearTextOnFocus = false
	a.Font = Enum.Font.Gotham
	a.TextSize = 13
	a.TextColor3 = TEXT
	a.BackgroundColor3 = Color3.fromRGB(30, 28, 48)
	a.BorderSizePixel = 0
	a.Parent = row
	corner(a, 8)

	local b = Instance.new("TextBox")
	b.Size = UDim2.new(0.42, 0, 0, 32)
	b.Position = UDim2.new(0.53, 0, 0.5, -16)
	b.Text = tostring(rightDef)
	b.PlaceholderText = rightText
	b.ClearTextOnFocus = false
	b.Font = Enum.Font.Gotham
	b.TextSize = 13
	b.TextColor3 = TEXT
	b.BackgroundColor3 = Color3.fromRGB(30, 28, 48)
	b.BorderSizePixel = 0
	b.Parent = row
	corner(b, 8)

	a.FocusLost:Connect(function()
		local n = tonumber(a.Text)
		if n and onLeft then onLeft(n, a) end
	end)
	b.FocusLost:Connect(function()
		local n = tonumber(b.Text)
		if n and onRight then onRight(n, b) end
	end)
	return a, b
end

local function makeActionButton(parent, text, callback)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 0, 30)
	button.BackgroundColor3 = ACCENT_SOFT
	button.BackgroundTransparency = 0.22
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.TextSize = 12
	button.TextColor3 = TEXT
	markLocalized(button, text)
	button.Parent = parent
	button:SetAttribute("ThemeAction", true)
	corner(button, 9)
	button.MouseButton1Click:Connect(function()
		if callback then callback(button) end
	end)
	return button
end

local function showLinkToast(button, message)
	local oldToast = button:FindFirstChild("LinkToast")
	if oldToast then oldToast:Destroy() end
	button.ClipsDescendants = false
	local toast = Instance.new("TextLabel")
	toast.Name = "LinkToast"
	toast.Size = UDim2.new(1, 0, 0, 20)
	toast.Position = UDim2.new(0, 0, 1, -14)
	toast.BackgroundColor3 = Color3.fromRGB(46, 42, 72)
	toast.BackgroundTransparency = 0.28
	toast.BorderSizePixel = 0
	toast.Font = Enum.Font.GothamBold
	toast.TextSize = 10
	toast.TextColor3 = TEXT
	toast.Text = message
	toast.ZIndex = button.ZIndex + 2
	toast.Parent = button
	corner(toast, 7)
	TweenService:Create(toast, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 0, 1, 3),
	}):Play()
	task.delay(2, function()
		if not toast.Parent then return end
		local retreat = TweenService:Create(toast, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0, 0, 1, -14),
		})
		retreat:Play()
		retreat.Completed:Wait()
		if toast.Parent then toast:Destroy() end
	end)
end

local function openOrCopyLink(url, button)
	local copied = false
	if typeof(setclipboard) == "function" then
		copied = pcall(setclipboard, url)
	elseif typeof(toclipboard) == "function" then
		copied = pcall(toclipboard, url)
	end
	local opened = false
	if typeof(open_url) == "function" then
		opened = pcall(open_url, url)
	elseif typeof(launch_url) == "function" then
		opened = pcall(launch_url, url)
	end
	showLinkToast(button, copied and localizedText("Link copied") or localizedText("Link unavailable"))
end

-- Pages
local generalPage = makePage("General")
local mainPage = makePage("Main")
local espPage = makePage("ESP")
local playerPage = makePage("Player")
local autoPage = makePage("Auto")

navItem("General", "General")
navItem("Main", "Main")
navItem("Player", "Player")
navItem("Auto", "Auto")
navItem("ESP", "ESP")

-- GENERAL
local languageRow = glassRow(generalPage, 32)
-- The pop-up belongs above every later page row while it is open.
languageRow.ZIndex = 30
local languageLabel = Instance.new("TextLabel")
languageLabel.BackgroundTransparency = 1
languageLabel.Position = UDim2.fromOffset(14, 0)
languageLabel.Size = UDim2.new(0, 104, 1, 0)
languageLabel.Font = Enum.Font.GothamBold
languageLabel.TextSize = 12
languageLabel.TextColor3 = TEXT
languageLabel.TextXAlignment = Enum.TextXAlignment.Left
markLocalized(languageLabel, "Language")
languageLabel.ZIndex = 31
languageLabel.Parent = languageRow

local languageSelect = Instance.new("TextButton")
languageSelect.Size = UDim2.fromOffset(156, 24)
languageSelect.Position = UDim2.new(1, -166, 0.5, -12)
languageSelect.BackgroundColor3 = Color3.fromRGB(20, 18, 34)
languageSelect.BackgroundTransparency = 0
languageSelect.BorderSizePixel = 0
languageSelect.Font = Enum.Font.GothamBold
languageSelect.TextSize = 11
languageSelect.TextColor3 = TEXT
languageSelect.Text = "English"
languageSelect.ZIndex = 31
languageSelect.AutoButtonColor = false
languageSelect.Parent = languageRow
corner(languageSelect, 7)

local languageMenu = Instance.new("Frame")
languageMenu.Size = UDim2.fromOffset(156, 138)
languageMenu.Position = UDim2.new(1, -166, 1, 5)
languageMenu.BackgroundColor3 = Color3.fromRGB(37, 33, 60)
languageMenu.BackgroundTransparency = 0.12
languageMenu.BorderSizePixel = 0
languageMenu.Visible = false
languageMenu.ZIndex = 32
languageMenu.Active = true
languageMenu.Parent = languageRow
corner(languageMenu, 9)
stroke(languageMenu, Color3.fromRGB(180, 170, 255), 1)
pad(languageMenu, 5, 5, 5, 5)
local menuList = Instance.new("UIListLayout")
menuList.Padding = UDim.new(0, 3)
menuList.Parent = languageMenu
for _, language in ipairs(LANGUAGES) do
	local option = Instance.new("TextButton")
	option.Size = UDim2.new(1, 0, 0, 23)
	option.BackgroundColor3 = ROW
	option.BackgroundTransparency = 1
	option.BorderSizePixel = 0
	option.Font = Enum.Font.GothamBold
	option.TextSize = 11
	option.TextColor3 = TEXT
	option.Text = language.name
	option.ZIndex = 33
	option.Parent = languageMenu
	corner(option, 6)
	option.MouseButton1Click:Connect(function()
		applyLanguage(language.code)
		languageSelect.Text = language.name
		languageMenu.Visible = false
		setStatus("Language · " .. language.name)
	end)
end
languageSelect.MouseButton1Click:Connect(function()
	languageMenu.Visible = not languageMenu.Visible
end)

local linksRow = Instance.new("Frame")
linksRow.Size = UDim2.new(1, 0, 0, 52)
linksRow.BackgroundTransparency = 1
linksRow.Parent = generalPage

local moreButton = Instance.new("TextButton")
moreButton.Size = UDim2.new(1, 0, 1, 0)
moreButton.BackgroundColor3 = Color3.fromRGB(39, 35, 65)
moreButton.BackgroundTransparency = 0.38
moreButton.BorderSizePixel = 0
moreButton.AutoButtonColor = false
moreButton.Text = ""
moreButton.Parent = linksRow
corner(moreButton, 12)
stroke(moreButton, Color3.fromRGB(160, 150, 235), 1)
local moreAccent = Instance.new("Frame")
moreAccent.Size = UDim2.fromOffset(3, 30)
moreAccent.Position = UDim2.new(0, 15, 0.5, -15)
moreAccent.BackgroundColor3 = ACCENT
moreAccent.BackgroundTransparency = 0.12
moreAccent.BorderSizePixel = 0
moreAccent.Parent = moreButton
corner(moreAccent, 2)
local moreLabel = Instance.new("TextLabel")
moreLabel.BackgroundTransparency = 1
moreLabel.Position = UDim2.fromOffset(31, 0)
moreLabel.Size = UDim2.new(1, -78, 1, 0)
moreLabel.Font = Enum.Font.GothamBold
moreLabel.TextSize = 12
moreLabel.TextColor3 = TEXT
moreLabel.TextXAlignment = Enum.TextXAlignment.Left
markLocalized(moreLabel, "More scripts for different places")
moreLabel.Parent = moreButton
local moreArrow = Instance.new("TextLabel")
moreArrow.BackgroundTransparency = 1
moreArrow.Position = UDim2.new(1, -38, 0, 0)
moreArrow.Size = UDim2.fromOffset(24, 52)
moreArrow.Font = Enum.Font.GothamBold
moreArrow.TextSize = 17
moreArrow.TextColor3 = MUTED
moreArrow.Text = "→"
moreArrow.Parent = moreButton
moreButton.MouseButton1Click:Connect(function()
	openOrCopyLink("https://t.me/robloxskriptandsoft", moreButton)
end)

local eggTargetGroup = controlGroup(mainPage, 132)
local zoneRow = glassRow(eggTargetGroup, 34)
biomeLbl = Instance.new("TextLabel")
biomeLbl.BackgroundTransparency = 1
biomeLbl.Position = UDim2.fromOffset(40, 0)
biomeLbl.Size = UDim2.new(1, -80, 1, 0)
biomeLbl.Font = Enum.Font.GothamBold
biomeLbl.TextSize = 12
biomeLbl.TextColor3 = Color3.fromRGB(255, 210, 110)
biomeLbl.TextXAlignment = Enum.TextXAlignment.Center
biomeLbl.Parent = zoneRow
setBiomeLabel()

local prevB = Instance.new("TextButton")
prevB.Size = UDim2.fromOffset(26, 26)
prevB.Position = UDim2.new(0, 5, 0.5, -13)
prevB.Text = "←"
prevB.Font = Enum.Font.GothamBold
prevB.TextSize = 14
prevB.TextColor3 = TEXT
prevB.BackgroundColor3 = Color3.fromRGB(45, 42, 70)
prevB.BorderSizePixel = 0
prevB.Parent = zoneRow
corner(prevB, 8)

local nextB = Instance.new("TextButton")
nextB.Size = UDim2.fromOffset(26, 26)
nextB.Position = UDim2.new(1, -31, 0.5, -13)
nextB.Text = "→"
nextB.Font = Enum.Font.GothamBold
nextB.TextSize = 14
nextB.TextColor3 = TEXT
nextB.BackgroundColor3 = Color3.fromRGB(45, 42, 70)
nextB.BorderSizePixel = 0
nextB.Parent = zoneRow
corner(nextB, 8)

local allEggsToggle, bestEggToggle, droppedEggsToggle, carrierToggle
allEggsToggle = makeToggle(eggTargetGroup, "Steal All Eggs", false, function(on)
	if not loadCore() then
		allEggsToggle.set(false)
		return
	end
	if on then
		targetMode = "all"
		if bestEggToggle then bestEggToggle.set(false) end
		if droppedEggsToggle then droppedEggsToggle.set(false) end
		if carrierToggle then carrierToggle.set(false) end
	end
	pushConfig()
	autoOn = on
	if on then
		coreApi.startFarm()
	elseif targetMode == "all" then
		coreApi.stopFarm()
		setStatus("Auto off")
	end
end)

bestEggToggle = makeToggle(eggTargetGroup, "Steal Best Egg", false, function(on)
	if not loadCore() then
		bestEggToggle.set(false)
		return
	end
	if on then
		targetMode = "best"
		if allEggsToggle then allEggsToggle.set(false) end
		if droppedEggsToggle then droppedEggsToggle.set(false) end
		if carrierToggle then carrierToggle.set(false) end
	end
	pushConfig()
	autoOn = on
	if on then
		coreApi.startFarm()
	elseif targetMode == "best" then
		coreApi.stopFarm()
		setStatus("Auto off")
	end
end)

droppedEggsToggle = makeToggle(mainPage, "Recover Dropped Eggs", false, function(on)
	if not loadCore() then
		droppedEggsToggle.set(false)
		return
	end
	if on then
		targetMode = "dropped"
		if allEggsToggle then allEggsToggle.set(false) end
		if bestEggToggle then bestEggToggle.set(false) end
		if carrierToggle then carrierToggle.set(false) end
	end
	pushConfig()
	autoOn = on
	if on then
		coreApi.startFarm()
	elseif targetMode == "dropped" then
		coreApi.stopFarm()
		setStatus("Auto off")
	end
end)

carrierToggle = makeToggle(mainPage, "Bat Aura", false, function(on)
	if not loadCore() then
		carrierToggle.set(false)
		return
	end
	if on then
		targetMode = "carrier"
		if allEggsToggle then allEggsToggle.set(false) end
		if bestEggToggle then bestEggToggle.set(false) end
		if droppedEggsToggle then droppedEggsToggle.set(false) end
	end
	pushConfig()
	autoOn = on
	if on then
		coreApi.startFarm()
	elseif targetMode == "carrier" then
		coreApi.stopFarm()
		setStatus("Bat aura off")
	end
end)

prevB.MouseButton1Click:Connect(function()
	selectedBiome = selectedBiome <= 1 and #BIOMES or (selectedBiome - 1)
	setBiomeLabel()
	pushConfig()
end)
nextB.MouseButton1Click:Connect(function()
	selectedBiome = selectedBiome >= #BIOMES and 1 or (selectedBiome + 1)
	setBiomeLabel()
	pushConfig()
end)

-- ESP
makeToggle(espPage, "ESP Players", false, function(on)
	if not loadCore() then return end
	pushConfig()
	if coreApi.setEspPlayers then coreApi.setEspPlayers(on) end
end)
makeToggle(espPage, "ESP Eggs", false, function(on)
	if not loadCore() then return end
	pushConfig()
	if coreApi.setEspEggs then coreApi.setEspEggs(on) end
end)
-- PLAYER
local walkToggle
local speedGroup = controlGroup(playerPage, 106)
walkToggle = makeToggle(speedGroup, "Speed", false, function(on)
	if not loadCore() then
		walkToggle.set(false)
		return
	end
	if coreApi.setWalkSpeed then coreApi.setWalkSpeed(on, walkSpeedVal) end
end)
makeSlider(speedGroup, "Walk Speed", 16, 500, walkSpeedVal, function(v)
	walkSpeedVal = v
	-- dragging slider implies you want it on (Boblo-style always apply while enabled)
	if not walkToggle.get() then
		walkToggle.set(true)
	end
	if not loadCore() then return end
	if coreApi.setWalkSpeed then coreApi.setWalkSpeed(true, walkSpeedVal) end
end)

local flyToggle
local flyGroup = controlGroup(playerPage, 106)
flyToggle = makeToggle(flyGroup, "Fly", false, function(on)
	if not loadCore() then
		flyToggle.set(false)
		return
	end
	if coreApi.setFly then coreApi.setFly(on, flySpeedVal) end
end)
makeSlider(flyGroup, "Fly Speed", 20, 500, flySpeedVal, function(v)
	flySpeedVal = v
	if flyToggle.get() and coreApi and coreApi.setFly then
		coreApi.setFly(true, flySpeedVal)
	end
end)

local infiniteJumpToggle
infiniteJumpToggle = makeToggle(playerPage, "Infinite Jump", false, function(on)
	if not loadCore() then
		infiniteJumpToggle.set(false)
		return
	end
	if coreApi.setInfiniteJump then coreApi.setInfiniteJump(on) end
end)

local noClipToggle
noClipToggle = makeToggle(playerPage, "No Clip", false, function(on)
	if not loadCore() then
		noClipToggle.set(false)
		return
	end
	if coreApi.setNoClip then coreApi.setNoClip(on) end
end)

-- AUTO
local function autoActionToggle(label, action)
	local toggle
	toggle = makeToggle(autoPage, label, false, function(on)
		if not loadCore() then toggle.set(false); return end
		local ok = coreApi.setAutoAction and coreApi.setAutoAction(action, on)
		if on and not ok then toggle.set(false) end
	end)
end

autoActionToggle("Auto Plant All Eggs", "plant")
autoActionToggle("Auto Hatch Eggs", "hatch")
autoActionToggle("Auto Equip Best Pets", "equip")

-- default page
generalPage.Visible = true
if navBtns.General then
	navBtns.General.bar.Visible = true
	navBtns.General.btn.BackgroundTransparency = 0.35
	navBtns.General.btn.BackgroundColor3 = Color3.fromRGB(55, 48, 95)
end

local minimized = false
minBtn.MouseButton1Click:Connect(function()
	minimized = not minimized
	body.Visible = not minimized
	win.Size = minimized and UDim2.fromOffset(560, 44) or UDim2.fromOffset(560, 380)
end)

closeBtn.MouseButton1Click:Connect(function()
	autoOn = false
	if coreApi then
		pcall(function()
			if coreApi.stopFarm then coreApi.stopFarm() end
		end)
		pcall(function()
			if coreApi.destroy then coreApi.destroy() end
		end)
	end
	gui:Destroy()
	if sessionEnv.__SAE_GLITCH_SESSION == activeSession then
		sessionEnv.__SAE_GLITCH_SESSION = nil
	end
end)

if not okMount then
	setStatus("UI mount FAIL")
end
