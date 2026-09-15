--[[
  Glitch — Steal An Egg UI (glass / sidebar)
  Tabs: Main | ESP | Player | General
  VER: V29
]]

local GLITCH_UI_VER = "V29"
local CORE_URL = "https://raw.githubusercontent.com/kimpler1/scim/main/Glitch_Core.lua?cb=v29"

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LP = Players.LocalPlayer

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
}

local selectedBiome = 1
local approachSpeed, escapeSpeed = 250, 480
local walkSpeedVal, flySpeedVal = 32, 60
local autoOn = false
local coreApi, coreLoaded = nil, false
local statusLbl, biomeLbl
local pages = {}
local navBtns = {}
local currentPage = "Main"

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
	if statusLbl then statusLbl.Text = tostring(t) end
end

local locale = "en"
local LANG_ORDER = { "en", "ru", "zh", "de", "fr", "es" }
local LANG_LABEL = {
	en = "English", ru = "Русский", zh = "中文",
	de = "Deutsch", fr = "Français", es = "Español",
}
local I18N = {
	en = {
		features = "Features", main = "Main", esp = "ESP", player = "Player", general = "General",
		autofarm = "Autofarm", auto_steal = "Auto Steal Egg",
		zone = "Zone", approach_escape = "Approach  ·  Escape", approach = "Approach", escape = "Escape",
		prev = "< Prev", next = "Next >", world_esp = "World ESP", players = "Players", eggs = "Eggs",
		beasts = "Beasts / Night",
		esp_hint = "Beasts: MonsterParasite + zone guards + night/boss models.",
		movement = "Movement", walk_speed = "Walk Speed", walk_value = "Walk Speed value",
		fly = "Fly (WASD + Space/Ctrl)", fly_speed = "Fly Speed",
		fly_hint = "V29 = V25 farm/WS/Fly. Languages in General.",
		language = "Language", lang_hint = "UI language only. Biome names stay in-game.",
		subtitle = "glass ui  ·  quest farm  ·  %s",
		status_boot = "Glitch %s\nmount=%s\nload core → version in status",
	},
	ru = {
		features = "Функции", main = "Основное", esp = "ESP", player = "Игрок", general = "Общее",
		autofarm = "Автофарм", auto_steal = "Авто кража яиц",
		zone = "Зона", approach_escape = "Подход  ·  Уход", approach = "Подход", escape = "Уход",
		prev = "< Назад", next = "Далее >", world_esp = "Мир ESP", players = "Игроки", eggs = "Яйца",
		beasts = "Монстры / Ночь",
		esp_hint = "Монстры: паразит + гарды + ночь/боссы.",
		movement = "Движение", walk_speed = "Скорость ходьбы", walk_value = "Значение скорости",
		fly = "Полёт (WASD + Space/Ctrl)", fly_speed = "Скорость полёта",
		fly_hint = "V29 = V25 автофарм/WS/Fly. Языки во вкладке Общее.",
		language = "Язык", lang_hint = "Только язык интерфейса. Биомы как в игре.",
		subtitle = "glass ui  ·  quest farm  ·  %s",
		status_boot = "Glitch %s\nmount=%s\nзагрузка core → версия в статусе",
	},
	zh = {
		features = "功能", main = "主页", esp = "ESP", player = "玩家", general = "通用",
		autofarm = "自动挂机", auto_steal = "自动偷蛋",
		zone = "区域", approach_escape = "接近  ·  撤离", approach = "接近", escape = "撤离",
		prev = "< 上一个", next = "下一个 >", world_esp = "世界 ESP", players = "玩家", eggs = "蛋",
		beasts = "野兽 / 夜晚", esp_hint = "野兽：寄生虫 + 守卫 + 夜晚/Boss。",
		movement = "移动", walk_speed = "步行速度", walk_value = "速度数值",
		fly = "飞行 (WASD + Space/Ctrl)", fly_speed = "飞行速度",
		fly_hint = "V29 = V25 挂机/步行/飞行。语言在通用。",
		language = "语言", lang_hint = "仅界面语言。生物群系名保持游戏原文。",
		subtitle = "glass ui  ·  quest farm  ·  %s",
		status_boot = "Glitch %s\nmount=%s\n加载 core → 状态栏版本",
	},
	de = {
		features = "Funktionen", main = "Haupt", esp = "ESP", player = "Spieler", general = "Allgemein",
		autofarm = "Autofarm", auto_steal = "Auto Eier stehlen",
		zone = "Zone", approach_escape = "Anflug  ·  Flucht", approach = "Anflug", escape = "Flucht",
		prev = "< Zurück", next = "Weiter >", world_esp = "Welt ESP", players = "Spieler", eggs = "Eier",
		beasts = "Bestien / Nacht", esp_hint = "Bestien: Parasit + Wachen + Nacht/Bosse.",
		movement = "Bewegung", walk_speed = "Laufgeschwindigkeit", walk_value = "Geschwindigkeitswert",
		fly = "Flug (WASD + Space/Ctrl)", fly_speed = "Fluggeschwindigkeit",
		fly_hint = "V29 = V25 Farm/WS/Fly. Sprachen unter Allgemein.",
		language = "Sprache", lang_hint = "Nur UI-Sprache. Biom-Namen wie im Spiel.",
		subtitle = "glass ui  ·  quest farm  ·  %s",
		status_boot = "Glitch %s\nmount=%s\nCore laden → Version im Status",
	},
	fr = {
		features = "Fonctions", main = "Principal", esp = "ESP", player = "Joueur", general = "Général",
		autofarm = "Autofarm", auto_steal = "Vol auto d'œufs",
		zone = "Zone", approach_escape = "Approche  ·  Fuite", approach = "Approche", escape = "Fuite",
		prev = "< Préc.", next = "Suiv. >", world_esp = "Monde ESP", players = "Joueurs", eggs = "Œufs",
		beasts = "Bêtes / Nuit", esp_hint = "Bêtes : parasite + gardes + nuit/boss.",
		movement = "Mouvement", walk_speed = "Vitesse de marche", walk_value = "Valeur de vitesse",
		fly = "Vol (WASD + Space/Ctrl)", fly_speed = "Vitesse de vol",
		fly_hint = "V29 = V25 farm/WS/Fly. Langues dans Général.",
		language = "Langue", lang_hint = "Langue UI uniquement. Biomes inchangés.",
		subtitle = "glass ui  ·  quest farm  ·  %s",
		status_boot = "Glitch %s\nmount=%s\ncharger core → version dans le statut",
	},
	es = {
		features = "Funciones", main = "Principal", esp = "ESP", player = "Jugador", general = "General",
		autofarm = "Autofarm", auto_steal = "Robo auto de huevos",
		zone = "Zona", approach_escape = "Acercar  ·  Escapar", approach = "Acercar", escape = "Escapar",
		prev = "< Ant.", next = "Sig. >", world_esp = "Mundo ESP", players = "Jugadores", eggs = "Huevos",
		beasts = "Bestias / Noche", esp_hint = "Bestias: parásito + guardias + noche/jefes.",
		movement = "Movimiento", walk_speed = "Velocidad al caminar", walk_value = "Valor de velocidad",
		fly = "Vuelo (WASD + Space/Ctrl)", fly_speed = "Velocidad de vuelo",
		fly_hint = "V29 = V25 farm/WS/Fly. Idiomas en General.",
		language = "Idioma", lang_hint = "Solo idioma de la UI. Biomas como en el juego.",
		subtitle = "glass ui  ·  quest farm  ·  %s",
		status_boot = "Glitch %s\nmount=%s\ncargar core → versión en el estado",
	},
}

local function tr(key)
	local pack = I18N[locale] or I18N.en
	return pack[key] or I18N.en[key] or key
end

local function setBiomeLabel()
	if biomeLbl then
		biomeLbl.Text = ("%s [%d/%d]: %s"):format(tr("zone"), selectedBiome, #BIOMES, BIOMES[selectedBiome])
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
local okMount, howMount = mountGui(gui)

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
corner(win, 14)
stroke(win, Color3.fromRGB(180, 170, 255), 1.2)

-- Header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 44)
header.BackgroundColor3 = SIDE
header.BackgroundTransparency = 0.15
header.BorderSizePixel = 0
header.Parent = win

local brandDot = Instance.new("Frame")
brandDot.Size = UDim2.fromOffset(10, 10)
brandDot.Position = UDim2.fromOffset(16, 17)
brandDot.BackgroundColor3 = ACCENT
brandDot.BorderSizePixel = 0
brandDot.Parent = header
corner(brandDot, 5)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(34, 4)
title.Size = UDim2.new(0, 280, 0, 22)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextColor3 = TEXT
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Glitch  ·  Steal An Egg"
title.Parent = header

local sub = Instance.new("TextLabel")
sub.BackgroundTransparency = 1
sub.Position = UDim2.fromOffset(34, 22)
sub.Size = UDim2.new(0, 280, 0, 16)
sub.Font = Enum.Font.Gotham
sub.TextSize = 11
sub.TextColor3 = MUTED
sub.TextXAlignment = Enum.TextXAlignment.Left
sub.Text = ("glass ui  ·  quest farm  ·  %s"):format(GLITCH_UI_VER)
sub.Parent = header

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
body.Size = UDim2.new(1, 0, 1, -44)
body.Position = UDim2.fromOffset(0, 44)
body.BackgroundTransparency = 1
body.Parent = win

local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 132, 1, 0)
sidebar.BackgroundColor3 = SIDE
sidebar.BackgroundTransparency = 0.08
sidebar.BorderSizePixel = 0
sidebar.Parent = body

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
content.BackgroundTransparency = 0.35
content.BorderSizePixel = 0
content.ClipsDescendants = true
content.Parent = body

local function makePage(name)
	local f = Instance.new("ScrollingFrame")
	f.Name = name
	f.Size = UDim2.new(1, 0, 1, 0)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.ScrollBarThickness = 3
	f.ScrollBarImageColor3 = ACCENT
	f.CanvasSize = UDim2.fromOffset(0, 420)
	f.Visible = false
	f.Parent = content
	pad(f, 16, 14, 16, 14)
	local list = Instance.new("UIListLayout")
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
	b.Text = "  " .. text
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.TextColor3 = TEXT
	b.TextXAlignment = Enum.TextXAlignment.Left
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Parent = sideScroll
	corner(b, 8)
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 3, 0, 16)
	bar.Position = UDim2.new(0, 4, 0.5, -8)
	bar.BackgroundColor3 = ACCENT
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar.Parent = b
	corner(bar, 2)
	navBtns[pageName] = {
		btn = b,
		bar = bar,
		setText = function(t)
			b.Text = "  " .. tostring(t)
		end,
	}
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
	r.BackgroundTransparency = 0.25
	r.BorderSizePixel = 0
	r.Parent = parent
	corner(r, 12)
	stroke(r, Color3.fromRGB(200, 190, 255), 1)
	return r
end

local function makeToggle(parent, labelText, default, callback)
	local row = glassRow(parent, 48)
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Position = UDim2.fromOffset(14, 0)
	lbl.Size = UDim2.new(1, -90, 1, 0)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 14
	lbl.TextColor3 = TEXT
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = labelText
	lbl.Parent = row

	local track = Instance.new("TextButton")
	track.Size = UDim2.fromOffset(48, 26)
	track.Position = UDim2.new(1, -62, 0.5, -13)
	track.BackgroundColor3 = Color3.fromRGB(55, 52, 75)
	track.Text = ""
	track.BorderSizePixel = 0
	track.AutoButtonColor = false
	track.Parent = row
	corner(track, 13)

	local knob = Instance.new("Frame")
	knob.Size = UDim2.fromOffset(20, 20)
	knob.Position = UDim2.fromOffset(3, 3)
	knob.BackgroundColor3 = TEXT
	knob.BorderSizePixel = 0
	knob.Parent = track
	corner(knob, 10)

	local on = default and true or false
	local function paint()
		track.BackgroundColor3 = on and ACCENT or Color3.fromRGB(55, 52, 75)
		TweenService:Create(knob, TweenInfo.new(0.15), {
			Position = on and UDim2.fromOffset(25, 3) or UDim2.fromOffset(3, 3),
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
		setLabel = function(t)
			lbl.Text = tostring(t)
		end,
	}
end

local function makeSlider(parent, labelText, minV, maxV, default, callback)
	local row = glassRow(parent, 64)
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Position = UDim2.fromOffset(14, 6)
	lbl.Size = UDim2.new(1, -80, 0, 20)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 13
	lbl.TextColor3 = TEXT
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = labelText
	lbl.Parent = row

	local valLbl = Instance.new("TextLabel")
	valLbl.BackgroundTransparency = 1
	valLbl.Position = UDim2.new(1, -70, 0, 6)
	valLbl.Size = UDim2.fromOffset(56, 20)
	valLbl.Font = Enum.Font.GothamBold
	valLbl.TextSize = 13
	valLbl.TextColor3 = ACCENT
	valLbl.TextXAlignment = Enum.TextXAlignment.Right
	valLbl.Text = tostring(default)
	valLbl.Parent = row

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, -28, 0, 8)
	bar.Position = UDim2.fromOffset(14, 40)
	bar.BackgroundColor3 = Color3.fromRGB(45, 42, 65)
	bar.BorderSizePixel = 0
	bar.Parent = row
	corner(bar, 4)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new((default - minV) / (maxV - minV), 0, 1, 0)
	fill.BackgroundColor3 = ACCENT
	fill.BorderSizePixel = 0
	fill.Parent = bar
	corner(fill, 4)

	local knob = Instance.new("Frame")
	knob.Size = UDim2.fromOffset(16, 16)
	knob.Position = UDim2.new((default - minV) / (maxV - minV), -8, 0.5, -8)
	knob.BackgroundColor3 = TEXT
	knob.BorderSizePixel = 0
	knob.Parent = bar
	corner(knob, 8)

	local value = default
	local dragging = false

	local function setFromX(x)
		local rel = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
		value = math.floor(minV + rel * (maxV - minV) + 0.5)
		fill.Size = UDim2.new(rel, 0, 1, 0)
		knob.Position = UDim2.new(rel, -8, 0.5, -8)
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
		setLabel = function(t)
			lbl.Text = tostring(t)
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
	return a, b, function(lt, rt)
		a.PlaceholderText = tostring(lt)
		b.PlaceholderText = tostring(rt)
	end
end

-- Pages
local mainPage = makePage("Main")
local espPage = makePage("ESP")
local playerPage = makePage("Player")
local generalPage = makePage("General")

local featHdr = sectionLabel(sideScroll, "Features")
navItem("Main", "Main")
navItem("ESP", "ESP")
navItem("Player", "Player")
navItem("General", "General")

-- MAIN
local secFarm = sectionLabel(mainPage, "Autofarm")
local farmToggle
farmToggle = makeToggle(mainPage, "Auto Steal Egg", false, function(on)
	if not loadCore() then
		farmToggle.set(false)
		return
	end
	pushConfig()
	autoOn = on
	if on then
		coreApi.startFarm()
	else
		coreApi.stopFarm()
		setStatus("Auto off")
	end
end)

local zoneRow = glassRow(mainPage, 52)
biomeLbl = Instance.new("TextLabel")
biomeLbl.BackgroundTransparency = 1
biomeLbl.Position = UDim2.fromOffset(14, 0)
biomeLbl.Size = UDim2.new(1, -28, 1, 0)
biomeLbl.Font = Enum.Font.GothamBold
biomeLbl.TextSize = 14
biomeLbl.TextColor3 = Color3.fromRGB(255, 210, 110)
biomeLbl.TextXAlignment = Enum.TextXAlignment.Left
biomeLbl.Parent = zoneRow
setBiomeLabel()

local navRow = glassRow(mainPage, 48)
local prevB = Instance.new("TextButton")
prevB.Size = UDim2.new(0.42, 0, 0, 32)
prevB.Position = UDim2.new(0.05, 0, 0.5, -16)
prevB.Text = "< Prev"
prevB.Font = Enum.Font.GothamBold
prevB.TextSize = 13
prevB.TextColor3 = TEXT
prevB.BackgroundColor3 = Color3.fromRGB(45, 42, 70)
prevB.BorderSizePixel = 0
prevB.Parent = navRow
corner(prevB, 8)

local nextB = Instance.new("TextButton")
nextB.Size = UDim2.new(0.42, 0, 0, 32)
nextB.Position = UDim2.new(0.53, 0, 0.5, -16)
nextB.Text = "Next >"
nextB.Font = Enum.Font.GothamBold
nextB.TextSize = 13
nextB.TextColor3 = TEXT
nextB.BackgroundColor3 = Color3.fromRGB(45, 42, 70)
nextB.BorderSizePixel = 0
nextB.Parent = navRow
corner(nextB, 8)

local secAE = sectionLabel(mainPage, "Approach  ·  Escape")
local _, _, setAEPlaceholders = makeNumRow(mainPage, "Approach", "Escape", approachSpeed, escapeSpeed, function(n, box)
	if n >= 50 and n <= 1000 then
		approachSpeed = n
		pushConfig()
	else
		box.Text = tostring(approachSpeed)
	end
end, function(n, box)
	if n >= 50 and n <= 1000 then
		escapeSpeed = n
		pushConfig()
	else
		box.Text = tostring(escapeSpeed)
	end
end)

local statusRow = glassRow(mainPage, 90)
statusLbl = Instance.new("TextLabel")
statusLbl.BackgroundTransparency = 1
statusLbl.Position = UDim2.fromOffset(14, 8)
statusLbl.Size = UDim2.new(1, -28, 1, -16)
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 12
statusLbl.TextColor3 = MUTED
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.TextYAlignment = Enum.TextYAlignment.Top
statusLbl.TextWrapped = true
statusLbl.Text = tr("status_boot"):format(GLITCH_UI_VER, tostring(howMount))
statusLbl.Parent = statusRow

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
local secEsp = sectionLabel(espPage, "World ESP")
local togPlayers = makeToggle(espPage, "Players", false, function(on)
	if not loadCore() then return end
	pushConfig()
	if coreApi.setEspPlayers then coreApi.setEspPlayers(on) end
end)
local togEggs = makeToggle(espPage, "Eggs", false, function(on)
	if not loadCore() then return end
	pushConfig()
	if coreApi.setEspEggs then coreApi.setEspEggs(on) end
end)
local togBeasts = makeToggle(espPage, "Beasts / Night", false, function(on)
	if not loadCore() then return end
	pushConfig()
	if coreApi.setEspBeasts then coreApi.setEspBeasts(on) end
end)

local espHint = glassRow(espPage, 70)
local eh = Instance.new("TextLabel")
eh.BackgroundTransparency = 1
eh.Position = UDim2.fromOffset(14, 8)
eh.Size = UDim2.new(1, -28, 1, -16)
eh.Font = Enum.Font.Gotham
eh.TextSize = 12
eh.TextColor3 = MUTED
eh.TextWrapped = true
eh.TextXAlignment = Enum.TextXAlignment.Left
eh.TextYAlignment = Enum.TextYAlignment.Top
eh.Text = tr("esp_hint")
eh.Parent = espHint

-- PLAYER
local secMove = sectionLabel(playerPage, "Movement")
local walkToggle
walkToggle = makeToggle(playerPage, "Walk Speed", false, function(on)
	if not loadCore() then
		walkToggle.set(false)
		return
	end
	if coreApi.setWalkSpeed then coreApi.setWalkSpeed(on, walkSpeedVal) end
end)
local walkSlider = makeSlider(playerPage, "Walk Speed value", 16, 500, walkSpeedVal, function(v)
	walkSpeedVal = v
	if not walkToggle.get() then
		walkToggle.set(true)
	end
	if not loadCore() then return end
	if coreApi.setWalkSpeed then coreApi.setWalkSpeed(true, walkSpeedVal) end
end)

local flyToggle
flyToggle = makeToggle(playerPage, "Fly (WASD + Space/Ctrl)", false, function(on)
	if not loadCore() then
		flyToggle.set(false)
		return
	end
	if coreApi.setFly then coreApi.setFly(on, flySpeedVal) end
end)
local flySlider = makeSlider(playerPage, "Fly Speed", 20, 250, flySpeedVal, function(v)
	flySpeedVal = v
	if flyToggle.get() and coreApi and coreApi.setFly then
		coreApi.setFly(true, flySpeedVal)
	end
end)

local flyHint = glassRow(playerPage, 72)
local fh = Instance.new("TextLabel")
fh.BackgroundTransparency = 1
fh.Position = UDim2.fromOffset(14, 8)
fh.Size = UDim2.new(1, -28, 1, -16)
fh.Font = Enum.Font.Gotham
fh.TextSize = 12
fh.TextColor3 = MUTED
fh.TextWrapped = true
fh.TextXAlignment = Enum.TextXAlignment.Left
fh.TextYAlignment = Enum.TextYAlignment.Top
fh.Text = tr("fly_hint")
fh.Parent = flyHint

-- GENERAL / Language
local secLang = sectionLabel(generalPage, "Language")
local langHint = glassRow(generalPage, 48)
local lh = Instance.new("TextLabel")
lh.BackgroundTransparency = 1
lh.Position = UDim2.fromOffset(14, 0)
lh.Size = UDim2.new(1, -28, 1, 0)
lh.Font = Enum.Font.Gotham
lh.TextSize = 12
lh.TextColor3 = MUTED
lh.TextXAlignment = Enum.TextXAlignment.Left
lh.Text = tr("lang_hint")
lh.Parent = langHint

local langBtns = {}
local function paintLangBtns()
	for code, btn in pairs(langBtns) do
		btn.BackgroundColor3 = (code == locale) and ACCENT or Color3.fromRGB(45, 42, 70)
	end
end

local function applyLang(code)
	if not I18N[code] then return end
	locale = code
	featHdr.Text = string.upper(tr("features"))
	if navBtns.Main then navBtns.Main.setText(tr("main")) end
	if navBtns.ESP then navBtns.ESP.setText(tr("esp")) end
	if navBtns.Player then navBtns.Player.setText(tr("player")) end
	if navBtns.General then navBtns.General.setText(tr("general")) end
	secFarm.Text = string.upper(tr("autofarm"))
	farmToggle.setLabel(tr("auto_steal"))
	setBiomeLabel()
	prevB.Text = tr("prev")
	nextB.Text = tr("next")
	secAE.Text = string.upper(tr("approach_escape"))
	if setAEPlaceholders then setAEPlaceholders(tr("approach"), tr("escape")) end
	secEsp.Text = string.upper(tr("world_esp"))
	togPlayers.setLabel(tr("players"))
	togEggs.setLabel(tr("eggs"))
	togBeasts.setLabel(tr("beasts"))
	eh.Text = tr("esp_hint")
	secMove.Text = string.upper(tr("movement"))
	walkToggle.setLabel(tr("walk_speed"))
	walkSlider.setLabel(tr("walk_value"))
	flyToggle.setLabel(tr("fly"))
	flySlider.setLabel(tr("fly_speed"))
	fh.Text = tr("fly_hint")
	secLang.Text = string.upper(tr("language"))
	lh.Text = tr("lang_hint")
	sub.Text = tr("subtitle"):format(GLITCH_UI_VER)
	paintLangBtns()
end

local langRow1 = glassRow(generalPage, 48)
local langRow2 = glassRow(generalPage, 48)
for i, code in ipairs(LANG_ORDER) do
	local parent = (i <= 3) and langRow1 or langRow2
	local idx = ((i - 1) % 3)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0.3, 0, 0, 32)
	btn.Position = UDim2.new(0.03 + idx * 0.32, 0, 0.5, -16)
	btn.Text = LANG_LABEL[code]
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 12
	btn.TextColor3 = TEXT
	btn.BackgroundColor3 = Color3.fromRGB(45, 42, 70)
	btn.BorderSizePixel = 0
	btn.Parent = parent
	corner(btn, 8)
	langBtns[code] = btn
	btn.MouseButton1Click:Connect(function()
		applyLang(code)
	end)
end
paintLangBtns()
applyLang("en")

-- default page
mainPage.Visible = true
if navBtns.Main then
	navBtns.Main.bar.Visible = true
	navBtns.Main.btn.BackgroundTransparency = 0.35
	navBtns.Main.btn.BackgroundColor3 = Color3.fromRGB(55, 48, 95)
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
end)

if not okMount then
	setStatus("UI mount FAIL")
end
