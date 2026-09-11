--[[
  Steal An Egg — Core v8
  Fixes: (1) final approach too far → egg not stolen, (2) return path through danger → death,
         (3) egg not banking → wait on base, (4) alignposition timeout/abort.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LP = Players.LocalPlayer

local CFG = {
	biomeIndex = 1,
	biomes = {
		"Forest", "Lake", "Desert", "Jungle", "Snow", "Volcano",
		"Abyss Ocean", "Prehistoric", "Cosmic", "Cherry Blossom", "Titan Temple",
	},
	approachSpeed = 60,
	finalApproachSpeed = 22,
	escapeSpeed = 130,
	arriveDist = 3.5,
	finalArriveDist = 1.6,
	stealTimeout = 6,
	stealHold = 1.2,
	stepTimeout = 30,
	baseWait = 2.5,
	status = function() end,
}

local EggState, PlotState, SlotIdentity
local CarryFn, SnapshotFn, SyncSnapshot, CarrySignal
local GetRespawn, GetPlot, InPlot, IsFirstUid, BuildSlotKey
local AreasFolder, GuardAreas, AreaEggs
local Bound = false
local autoFarm, espOn, carrying, farmBusy = false, false, false, false
local connections, espMap = {}, {}
local espFolder, velConn, espConn, carryConn
local moverAlign, moverAtt, moverRot

local function setStatus(t)
	CFG.status(t)
end

local function ch(parent, name, t)
	if not parent then return nil end
	local c = parent:FindFirstChild(name)
	if c then return c end
	if t and t > 0 then
		local ok, r = pcall(function() return parent:WaitForChild(name, t) end)
		if ok then return r end
	end
end

local function req(parent, name, t)
	local m = ch(parent, name, t)
	if not (m and m:IsA("ModuleScript")) then return nil end
	local ok, mod = pcall(require, m)
	return ok and mod or nil
end

local function pick(mod, ...)
	if typeof(mod) ~= "table" then return nil end
	for i = 1, select("#", ...) do
		local f = mod[select(i, ...)]
		if typeof(f) == "function" then return f end
	end
end

local function bindGame()
	if Bound then return true end
	local Client = ch(ReplicatedStorage, "Client", 2)
	local Shared = ch(ReplicatedStorage, "Shared", 2)
	local Util = Shared and ch(Shared, "Util", 1)

	EggState = Client and req(Client, "Egg" .. "State", 2)
	PlotState = Client and req(Client, "Plot" .. "State", 2)
	SlotIdentity = Util and req(Util, "Area" .. "Egg" .. "Slot" .. "Identity", 1)

	CarryFn = pick(EggState, "CarryFieldEgg", "RequestCarryAreaEgg")
	SnapshotFn = pick(EggState, "ReadFieldEggs", "GetAreaEggSnapshot")
	SyncSnapshot = pick(EggState, "SyncFieldEggs", "RequestAreaEggSnapshot")
	CarrySignal = EggState and (EggState.CarryChanged or EggState.AreaEggCarryStateChanged)
	GetRespawn = pick(PlotState, "FindRespawnCFrame", "GetRespawnPointCFrame")
	GetPlot = pick(PlotState, "ResolvePlot", "GetPlotData")
	InPlot = pick(PlotState, "ContainsLocalPoint", "IsWorldPositionWithinLocalPlotBounds")
	IsFirstUid = pick(SlotIdentity, "LooksLikeFirstAreaUid", "IsFirstAreaUid")
	BuildSlotKey = pick(SlotIdentity, "SlotKey", "BuildSlotKey")

	if not CarryFn then
		for _, folderName in ipairs({ "RF", "Remotes", "Net" }) do
			local folder = ch(ReplicatedStorage, folderName, 0)
			if folder then
				local ew = ch(folder, "Egg" .. "World", 0)
				local rem = (ew and ch(ew, "Ask" .. "Field" .. "Egg" .. "Carry", 0))
					or ch(folder, "Ask" .. "Field" .. "Egg" .. "Carry", 0)
				if rem then
					CarryFn = function(uid, slotKey)
						if rem:IsA("RemoteFunction") then
							return rem:InvokeServer(uid, slotKey)
						end
						rem:FireServer(uid, slotKey)
						return true
					end
					break
				end
			end
		end
	end

	local objects = ch(Workspace, "__" .. "OBJECTS", 3)
	AreasFolder = objects and ch(objects, "Areas", 2)
	GuardAreas = AreasFolder and ch(AreasFolder, "Guard" .. "Areas", 2)
	AreaEggs = ch(Workspace, "Area" .. "Egg" .. "Slots" .. "Client", 3)

	if CarrySignal and typeof(CarrySignal.Connect) == "function" and not carryConn then
		carryConn = CarrySignal:Connect(function(state)
			if typeof(state) == "table" then
				carrying = state.IsCarrying == true
			end
		end)
		table.insert(connections, carryConn)
	end

	Bound = true
	return true
end

local function getChar() return LP.Character end
local function getHRP()
	local c = getChar()
	return c and c:FindFirstChild("HumanoidRootPart")
end
local function getHum()
	local c = getChar()
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function antiDeath()
	local hum = getHum()
	if not hum then return end
	if hum.PlatformStand or hum.Sit then
		hum.PlatformStand = false
		hum.Sit = false
	end
	if hum.Health > 0 and hum.Health < hum.MaxHealth * 0.5 then
		-- cannot heal without game remote; at least unragdoll
	end
	if hum:GetState() == Enum.HumanoidStateType.Dead or hum.Health <= 0 then
		-- wait respawn
	end
end

local function softHarden()
	local char = getChar()
	if not char then return end
	for _, d in ipairs(char:GetChildren()) do
		if d:IsA("LocalScript") and string.find(d.Name, "Push", 1, true) then
			pcall(function() d.Disabled = true end)
		end
	end
	for _, folderName in ipairs({ "Animate", "Scripts", "Client" }) do
		local f = char:FindFirstChild(folderName)
		if f then
			for _, d in ipairs(f:GetDescendants()) do
				if d:IsA("LocalScript") and string.find(d.Name, "Push", 1, true) then
					pcall(function() d.Disabled = true end)
				end
			end
		end
	end
end

local function refreshCarry()
	if carrying then return true end
	local char = getChar()
	if not char then return false end
	if LP:GetAttribute("IsCarryingEgg") == true or char:GetAttribute("IsCarryingEgg") == true then
		carrying = true
		return true
	end
	for _, chd in ipairs(char:GetChildren()) do
		if chd:IsA("Tool") then
			local n = chd.Name:lower()
			if n:find("egg") or n:find("carry") then
				carrying = true
				return true
			end
		end
	end
	return false
end

local function getLaneZ()
	if AreasFolder then
		local gz = AreasFolder:FindFirstChild("GameplayZ")
		if gz and gz:IsA("BasePart") then return gz.Position.Z end
		local sep = AreasFolder:FindFirstChild("SeparationLine")
		if sep and sep:IsA("BasePart") then return sep.Position.Z end
	end
	local hrp = getHRP()
	return hrp and hrp.Position.Z or -365.5
end

local function getLaneY()
	if AreasFolder then
		local gz = AreasFolder:FindFirstChild("GameplayZ")
		if gz and gz:IsA("BasePart") then return gz.Position.Y + 3 end
	end
	local hrp = getHRP()
	return hrp and hrp.Position.Y or 70
end

local function groundedY(x, z, fallback)
	local origin = Vector3.new(x, (fallback or getLaneY()) + 80, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local char = getChar()
	params.FilterDescendantsInstances = char and { char } or {}
	local hit = Workspace:Raycast(origin, Vector3.new(0, -200, 0), params)
	if hit then return hit.Position.Y + 3 end
	return fallback or getLaneY()
end

local function clearMover()
	if moverAlign then pcall(function() moverAlign:Destroy() end) end
	if moverRot then pcall(function() moverRot:Destroy() end) end
	if moverAtt then pcall(function() moverAtt:Destroy() end) end
	moverAlign, moverRot, moverAtt = nil, nil, nil
end

local function setupMover()
	clearMover()
	local hrp = getHRP()
	if not hrp then return false end

	local att = Instance.new("Attachment")
	att.Name = "SAE" .. tostring(math.random(10000, 99999))
	att.Position = Vector3.zero
	att.Parent = hrp

	local align = Instance.new("AlignPosition")
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.RigidityEnabled = false
	align.ReactionForceEnabled = false
	align.ApplyAtCenterOfMass = false
	align.MaxForce = 5e6
	align.MaxVelocity = CFG.approachSpeed
	align.Responsiveness = 18
	align.Parent = hrp

	local rot = Instance.new("AlignOrientation")
	rot.Mode = Enum.OrientationAlignmentMode.OneAttachment
	rot.Attachment0 = att
	rot.RigidityEnabled = false
	rot.MaxTorque = 3e6
	rot.Responsiveness = 12
	rot.Parent = hrp

	moverAtt = att
	moverAlign = align
	moverRot = rot
	return true
end

local function moveToPosition(targetPos, speed, timeout, arriveThreshold)
	local deadline = tick() + (timeout or CFG.stepTimeout)
	if not moverAlign or not moverAtt then
		setupMover()
	end
	local hrp = getHRP()
	if not hrp or not moverAlign then return false end

	moverAlign.MaxVelocity = speed
	moverAlign.Position = targetPos

	local stuckTick = tick()
	local lastPos = hrp.Position
	local threshold = arriveThreshold or CFG.arriveDist

	while tick() < deadline and autoFarm do
		hrp = getHRP()
		if not hrp then return false end
		antiDeath()

		local dist = (hrp.Position - targetPos).Magnitude
		if dist <= threshold then
			return true
		end

		-- update Y if ground changed
		moverAlign.Position = Vector3.new(targetPos.X, groundedY(targetPos.X, targetPos.Z, targetPos.Y), targetPos.Z)

		-- stuck detection: if no progress in 2.5s, small CFrame nudge
		if (hrp.Position - lastPos).Magnitude > 1 then
			stuckTick = tick()
			lastPos = hrp.Position
		elseif tick() - stuckTick > 2.5 then
			pcall(function()
				hrp.CFrame = CFrame.new(hrp.Position + (targetPos - hrp.Position).Unit * 8)
			end)
			stuckTick = tick()
			lastPos = hrp.Position
		end

		RunService.Heartbeat:Wait()
	end
	return false
end

local function faceTarget(targetPos)
	local hrp = getHRP()
	if not hrp then return end
	local flat = Vector3.new(targetPos.X, hrp.Position.Y, targetPos.Z)
	local cf = CFrame.lookAt(hrp.Position, flat)
	pcall(function()
		hrp.CFrame = CFrame.new(hrp.Position) * (cf - cf.Position)
	end)
end

local function getLanePoint(x)
	return Vector3.new(x, getLaneY(), getLaneZ())
end

local function buildLanePath(fromPos, toPos)
	local laneZ, laneY = getLaneZ(), getLaneY()
	local pts = {}
	-- first get to lane center line
	if math.abs(fromPos.Z - laneZ) > 6 then
		table.insert(pts, Vector3.new(fromPos.X, laneY, laneZ))
	end
	-- then move along lane to target X
	if math.abs(fromPos.X - toPos.X) > 4 then
		table.insert(pts, Vector3.new(toPos.X, laneY, laneZ))
	end
	-- finally approach target Z (nest depth)
	table.insert(pts, Vector3.new(toPos.X, laneY, toPos.Z))
	return pts
end

local function travelAlong(path, speed, finalSpeed)
	for i, p in ipairs(path) do
		if not autoFarm then return false end
		local isLast = i == #path
		local spd = isLast and (finalSpeed or speed) or speed
		setStatus("Move " .. i .. "/" .. #path)
		if not moveToPosition(p, spd, CFG.stepTimeout, isLast and CFG.finalArriveDist or CFG.arriveDist) then
			return false
		end
	end
	return true
end

local function getZoneBounds(name)
	if not GuardAreas then return nil end
	local zone = GuardAreas:FindFirstChild(name)
	local bounds = zone and zone:FindFirstChild("Bounds")
	if bounds and bounds:IsA("BasePart") then return bounds end
end

local function getBiomeCenter(name)
	local bounds = getZoneBounds(name)
	if bounds then
		return Vector3.new(bounds.Position.X, getLaneY(), getLaneZ())
	end
end

local function eggPos(egg)
	local part = egg:FindFirstChild("Hitbox")
		or egg:FindFirstChild("CustomBoundingBox")
		or egg:FindFirstChildWhichIsA("BasePart", true)
	if part then return part.Position end
	local ok, pivot = pcall(function() return egg:GetPivot() end)
	if ok and pivot then return pivot.Position end
end

local function recordsByUid()
	local map = {}
	if not SnapshotFn then return map end
	pcall(function()
		if SyncSnapshot then SyncSnapshot() end
		local snap = SnapshotFn()
		if typeof(snap) == "table" and typeof(snap.Records) == "table" then
			for _, rec in pairs(snap.Records) do
				if typeof(rec) == "table" and typeof(rec.Uid) == "string" then
					map[rec.Uid] = rec
				end
			end
		end
	end)
	return map
end

local function areaMatches(a, b)
	if typeof(a) ~= "string" then return false end
	if a == b then return true end
	local x, y = a:lower():gsub("%s+", ""), b:lower():gsub("%s+", "")
	return x == y or x:find(y, 1, true) ~= nil or y:find(x, 1, true) ~= nil
end

local function eggInSelectedBiome(egg, record)
	local biomes = CFG.biomes
	local biome = biomes[CFG.biomeIndex]
	if record and areaMatches(record.AreaId, biome) then return true end
	local bounds = getZoneBounds(biome)
	local pos = eggPos(egg)
	if bounds and pos then
		local lp = bounds.CFrame:PointToObjectSpace(pos)
		local half = bounds.Size * 0.5
		return math.abs(lp.X) <= half.X + 12
			and math.abs(lp.Y) <= half.Y + 60
			and math.abs(lp.Z) <= half.Z + 12
	end
	return CFG.biomeIndex == 1 and record == nil
end

local function nearestEggInBiome()
	AreaEggs = AreaEggs or ch(Workspace, "Area" .. "Egg" .. "Slots" .. "Client", 1)
	if not AreaEggs then return nil end
	local hrp = getHRP()
	if not hrp then return nil end
	local recs = recordsByUid()
	local best, bestDist
	for _, egg in ipairs(AreaEggs:GetChildren()) do
		local rec = recs[egg.Name]
		if eggInSelectedBiome(egg, rec) then
			local pos = eggPos(egg)
			if pos then
				local d = (pos - hrp.Position).Magnitude
				if not bestDist or d < bestDist then
					best, bestDist = egg, d
				end
			end
		end
	end
	return best, bestDist
end

local function findPrompt(egg)
	for _, d in ipairs(egg:GetDescendants()) do
		if d:IsA("ProximityPrompt") then return d end
	end
end

local function firePrompt(prompt)
	if not prompt then return end
	if typeof(fireproximityprompt) == "function" then
		pcall(fireproximityprompt, prompt)
		return
	end
	local hold = prompt.HoldDuration
	pcall(function()
		prompt.HoldDuration = 0
		prompt:InputHoldBegin()
		task.wait(0.05)
		prompt:InputHoldEnd()
		prompt.HoldDuration = hold
	end)
end

local function trySteal(egg)
	local uid = egg.Name
	local slotKey
	local rec = recordsByUid()[uid]
	if rec and IsFirstUid and IsFirstUid(uid) and BuildSlotKey then
		pcall(function() slotKey = BuildSlotKey(rec.AreaId, rec.NestId) end)
	end

	-- stand still right next to egg so server sees proximity
	local pos = eggPos(egg)
	if pos then
		moveToPosition(Vector3.new(pos.X, pos.Y, pos.Z), CFG.finalApproachSpeed, 3, CFG.finalArriveDist)
		faceTarget(pos)
		task.wait(0.25)
	end

	local deadline = tick() + CFG.stealTimeout
	while tick() < deadline and autoFarm and not carrying do
		if CarryFn then
			local ok, res = pcall(function() return CarryFn(uid, slotKey) end)
			if ok and res == true then carrying = true end
		end
		firePrompt(findPrompt(egg))
		refreshCarry()
		if carrying then return true end
		task.wait(0.12)
	end

	local prompt = findPrompt(egg)
	if prompt and not carrying then
		local hold = prompt.HoldDuration
		pcall(function()
			prompt:InputHoldBegin()
			task.wait(math.max(hold, CFG.stealHold))
			prompt:InputHoldEnd()
		end)
		refreshCarry()
	end
	return carrying
end

local function getBasePos()
	if GetRespawn then
		local ok, cf = pcall(GetRespawn)
		if ok and cf then return cf.Position end
	end
	if GetPlot then
		local ok, plot = pcall(GetPlot)
		if ok and plot then
			if plot.CenterPoint then return plot.CenterPoint.Position end
			if plot.PetArea then return plot.PetArea.Position end
		end
	end
end

local function isInPlot()
	if not InPlot then return false end
	local hrp = getHRP()
	if not hrp then return false end
	local ok, inside = pcall(function() return InPlot(hrp.Position) end)
	return ok and inside == true
end

local function returnToBase(speed)
	local base = getBasePos()
	local hrp = getHRP()
	if not base or not hrp then return false end
	local path = buildLanePath(hrp.Position, Vector3.new(base.X, base.Y + 4, base.Z))
	return travelAlong(path, speed, speed)
end

local function farmOnce()
	softHarden()
	antiDeath()
	refreshCarry()

	if carrying then
		setStatus("Escape base")
		returnToBase(CFG.escapeSpeed)
		local waitUntil = tick() + CFG.baseWait
		while tick() < waitUntil and autoFarm do
			antiDeath()
			if not carrying or isInPlot() then break end
			RunService.Heartbeat:Wait()
		end
		carrying = false
		task.wait(0.2)
		return
	end

	local biome = CFG.biomes[CFG.biomeIndex]
	local center = getBiomeCenter(biome)
	local hrp = getHRP()
	if center and hrp and (hrp.Position - center).Magnitude > 120 then
		setStatus("To " .. biome)
		local path = buildLanePath(hrp.Position, center)
		if not travelAlong(path, CFG.approachSpeed) then
			setStatus("Move abort")
			return
		end
	end

	local egg = nearestEggInBiome()
	if not egg then
		setStatus("No eggs " .. biome)
		task.wait(0.6)
		return
	end

	local pos = eggPos(egg)
	hrp = getHRP()
	setStatus("Approach")
	local path = buildLanePath(hrp.Position, pos)
	if not travelAlong(path, CFG.approachSpeed, CFG.finalApproachSpeed) then
		setStatus("Approach abort")
		return
	end

	setStatus("Grab")
	if not trySteal(egg) then
		setStatus("Miss")
		task.wait(0.3)
		return
	end

	setStatus("Return")
	returnToBase(CFG.escapeSpeed)

	-- wait on base until egg is banked / plot accepts it
	setStatus("Bank")
	local bankDeadline = tick() + CFG.baseWait + 3
	while tick() < bankDeadline and autoFarm do
		antiDeath()
		refreshCarry()
		if isInPlot() and not carrying then break end
		if not carrying then break end
		RunService.Heartbeat:Wait()
	end
	carrying = false
	setStatus("OK")
end

local function startFarmLoop()
	if farmBusy then return end
	farmBusy = true
	setupMover()
	task.spawn(function()
		while autoFarm do
			local ok, err = pcall(farmOnce)
			if not ok then
				setStatus("Err " .. tostring(err))
				task.wait(0.5)
			end
			task.wait(0.15)
		end
		clearMover()
		farmBusy = false
	end)
end

-- ESP
local function resolveHiddenParent()
	if typeof(gethui) == "function" then
		local ok, h = pcall(gethui)
		if ok and h then return h end
	end
	if typeof(get_hidden_gui) == "function" then
		local ok, h = pcall(get_hidden_gui)
		if ok and h then return h end
	end
end

local function protectInstance(inst)
	pcall(function() if syn and syn.protect_gui then syn.protect_gui(inst) end end)
	pcall(function() if protect_gui then protect_gui(inst) end end)
	pcall(function() if protectgui then protectgui(inst) end end)
	pcall(function() if hidgui then hidgui(inst) end end)
end

local function clearEsp()
	for _, p in pairs(espMap) do
		if p.hl then p.hl:Destroy() end
		if p.bb then p.bb:Destroy() end
	end
	table.clear(espMap)
	if espFolder then espFolder:Destroy() espFolder = nil end
end

local function ensureEspFolder()
	if espFolder and espFolder.Parent then return espFolder end
	espFolder = Instance.new("Folder")
	espFolder.Name = "v" .. tostring(math.random(100000, 999999))
	protectInstance(espFolder)
	espFolder.Parent = resolveHiddenParent() or game:GetService("CoreGui")
	return espFolder
end

local function ensureEsp(plr)
	if plr == LP then return end
	local pack = espMap[plr.UserId]
	if pack and pack.hl and pack.hl.Parent then return pack end
	local folder = ensureEspFolder()
	local hl = Instance.new("Highlight")
	hl.FillColor = Color3.fromRGB(255, 70, 70)
	hl.OutlineColor = Color3.fromRGB(255, 255, 255)
	hl.FillTransparency = 0.5
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = folder
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 140, 0, 34)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 2000
	bb.Parent = folder
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.Text = plr.DisplayName
	label.Parent = bb
	pack = { hl = hl, bb = bb, label = label }
	espMap[plr.UserId] = pack
	return pack
end

local function updateEsp()
	if not espOn then return end
	local me = getHRP()
	local seen = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP then
			seen[plr.UserId] = true
			local char = plr.Character
			local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
			local pack = ensureEsp(plr)
			if char and head and pack then
				pack.hl.Adornee = char
				pack.bb.Adornee = head
				local dist = me and math.floor((head.Position - me.Position).Magnitude) or 0
				pack.label.Text = ("%s [%d]"):format(plr.DisplayName, dist)
			end
		end
	end
	for uid, pack in pairs(espMap) do
		if not seen[uid] then
			if pack.hl then pack.hl:Destroy() end
			if pack.bb then pack.bb:Destroy() end
			espMap[uid] = nil
		end
	end
end

local Api = {}

function Api.setConfig(t)
	if typeof(t) ~= "table" then return end
	if t.biomeIndex then CFG.biomeIndex = t.biomeIndex end
	if t.biomes then CFG.biomes = t.biomes end
	if t.approachSpeed then CFG.approachSpeed = math.clamp(t.approachSpeed, 30, 150) end
	if t.escapeSpeed then CFG.escapeSpeed = math.clamp(t.escapeSpeed, 60, 250) end
	if typeof(t.status) == "function" then CFG.status = t.status end
end

function Api.startFarm()
	bindGame()
	setupMover()
	setStatus(("Bound E=%s P=%s Eggs=%s"):format(
		EggState and "Y" or "N",
		PlotState and "Y" or "N",
		AreaEggs and "Y" or "N"
	))
	autoFarm = true
	startFarmLoop()
end

function Api.stopFarm()
	autoFarm = false
	clearMover()
	setStatus("Auto off")
end

function Api.setEsp(on)
	espOn = on and true or false
	if espOn then
		if not espConn then
			espConn = RunService.RenderStepped:Connect(updateEsp)
			table.insert(connections, espConn)
		end
		updateEsp()
	else
		clearEsp()
	end
end

function Api.destroy()
	autoFarm = false
	espOn = false
	clearMover()
	clearEsp()
	for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
	connections = {}
end

return Api
