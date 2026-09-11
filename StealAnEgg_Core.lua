--[[
  Steal An Egg — Core v11
  Fly = upright CFrame step (no lookAt NaN). No humanoid destroy/clone.
  Ground plant only when raycast hits — avoids void / ragdoll sky.
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
	approachSpeed = 70,
	escapeSpeed = 110,
	arriveDist = 3.5,
	finalArriveDist = 2.2,
	stealTimeout = 5,
	stealHold = 1.1,
	stepTimeout = 25,
	baseWait = 2.2,
	flyHeight = 6,
	status = function() end,
}

local EggState, PlotState, SlotIdentity
local CarryFn, SnapshotFn, SyncSnapshot, CarrySignal
local GetRespawn, GetPlot, InPlot, IsFirstUid, BuildSlotKey
local AreasFolder, GuardAreas, AreaEggs
local Bound = false
local autoFarm, espOn, carrying, farmBusy = false, false, false, false
local connections, espMap = {}, {}
local espFolder, espConn, carryConn
local noclipOn = false

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

-- Kill PushBack scripts only. Destroying Humanoid = ragdoll void (v10 bug).
local function disablePushScripts()
	local char = getChar()
	if not char then return false end
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("LocalScript") then
			local n = d.Name:lower()
			if n:find("push", 1, true) or n:find("knock", 1, true) then
				pcall(function()
					d.Disabled = true
					d:Destroy()
				end)
			end
		end
	end
	return true
end

local function isFiniteVec(v)
	return typeof(v) == "Vector3"
		and v.X == v.X and v.Y == v.Y and v.Z == v.Z
		and math.abs(v.X) < 1e5 and math.abs(v.Y) < 1e5 and math.abs(v.Z) < 1e5
end

local function uprightAt(pos, lookFlat)
	local look = lookFlat or Vector3.new(0, 0, -1)
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 0.05 then
		return CFrame.new(pos)
	end
	return CFrame.lookAt(pos, pos + look.Unit)
end

local function setNoclip(on)
	noclipOn = on
	local char = getChar()
	if not char then return end
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CanCollide = not on
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
		if gz and gz:IsA("BasePart") then return gz.Position.Y + CFG.flyHeight end
	end
	local hrp = getHRP()
	return (hrp and hrp.Position.Y or 70) + CFG.flyHeight
end

local function groundedY(x, z, fallback)
	local origin = Vector3.new(x, (fallback or getLaneY()) + 80, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local char = getChar()
	params.FilterDescendantsInstances = char and { char } or {}
	local hit = Workspace:Raycast(origin, Vector3.new(0, -220, 0), params)
	if hit then return hit.Position.Y + CFG.flyHeight end
	return fallback or getLaneY()
end

local function anchor(hrp, cf)
	if not hrp or not cf then return end
	local p = cf.Position
	if not isFiniteVec(p) then return end
	hrp.CFrame = cf
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
end

local function restoreWalk()
	setNoclip(false)
	local hum = getHum()
	if hum then
		hum.PlatformStand = false
		hum.Sit = false
		pcall(function()
			hum:ChangeState(Enum.HumanoidStateType.Running)
		end)
	end
end

-- Hub-style fly: upright CFrame steps only (lookAt(next,target) NaN = void)
local function flyTo(targetPos, speed, timeout, arrive)
	if not isFiniteVec(targetPos) then return false end
	local deadline = tick() + (timeout or CFG.stepTimeout)
	local arriveDist = arrive or CFG.arriveDist
	setNoclip(true)

	while tick() < deadline and autoFarm do
		local hrp = getHRP()
		local hum = getHum()
		if not hrp or not isFiniteVec(hrp.Position) then
			task.wait(0.05)
		else
			if hum then
				hum.Sit = false
				hum.PlatformStand = true
			end
			local y = groundedY(targetPos.X, targetPos.Z, targetPos.Y)
			local target = Vector3.new(targetPos.X, y, targetPos.Z)
			local delta = target - hrp.Position
			if not isFiniteVec(delta) then
				restoreWalk()
				return false
			end
			if delta.Magnitude <= arriveDist then
				anchor(hrp, uprightAt(target, delta))
				return true
			end
			local dt = RunService.Heartbeat:Wait()
			if typeof(dt) ~= "number" or dt <= 0 then dt = 1 / 60 end
			hrp = getHRP()
			if not hrp then return false end
			y = groundedY(targetPos.X, targetPos.Z, targetPos.Y)
			target = Vector3.new(targetPos.X, y, targetPos.Z)
			delta = target - hrp.Position
			if delta.Magnitude < 1e-3 or not isFiniteVec(delta) then
				anchor(hrp, uprightAt(target))
				return true
			end
			local step = math.min(delta.Magnitude, speed * dt)
			local nextPos = hrp.Position + delta.Unit * step
			if not isFiniteVec(nextPos) then
				restoreWalk()
				return false
			end
			anchor(hrp, uprightAt(nextPos, delta))
		end
	end
	return false
end

local function buildLanePath(fromPos, toPos)
	local laneZ, laneY = getLaneZ(), getLaneY()
	local pts = {}
	-- 1) get onto safe lane (dodge chicken to the side)
	if math.abs(fromPos.Z - laneZ) > 5 then
		table.insert(pts, Vector3.new(fromPos.X, laneY, laneZ))
	end
	-- 2) fly along corridor to egg X
	if math.abs(fromPos.X - toPos.X) > 3 then
		table.insert(pts, Vector3.new(toPos.X, laneY, laneZ))
	end
	-- 3) dip to egg
	table.insert(pts, Vector3.new(toPos.X, toPos.Y + CFG.flyHeight, toPos.Z))
	return pts
end

local function travelAlong(path, speed)
	for i, p in ipairs(path) do
		if not autoFarm then return false end
		setStatus("Fly " .. i .. "/" .. #path)
		local isLast = i == #path
		if not flyTo(p, speed, CFG.stepTimeout, isLast and CFG.finalArriveDist or CFG.arriveDist) then
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
	local biome = CFG.biomes[CFG.biomeIndex]
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

local function faceTarget(targetPos)
	local hrp = getHRP()
	if not hrp or not isFiniteVec(targetPos) then return end
	local look = Vector3.new(targetPos.X - hrp.Position.X, 0, targetPos.Z - hrp.Position.Z)
	anchor(hrp, uprightAt(hrp.Position, look))
end

local function plantOnEgg(egg)
	local hrp = getHRP()
	local hum = getHum()
	local pos = eggPos(egg)
	if not hrp or not pos or not isFiniteVec(pos) then return false end

	-- stay flying/noclip until ground confirmed — otherwise fall into void
	local origin = Vector3.new(pos.X, pos.Y + 60, pos.Z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { getChar() }
	local hit = Workspace:Raycast(origin, Vector3.new(0, -120, 0), params)
	if not hit then
		setStatus("No ground")
		return false
	end

	local y = hit.Position.Y + 3
	anchor(hrp, uprightAt(Vector3.new(pos.X, y, pos.Z), Vector3.new(0, 0, -1)))
	setNoclip(false)
	if hum then
		hum.PlatformStand = false
		hum.Sit = false
		pcall(function()
			hum:ChangeState(Enum.HumanoidStateType.Running)
		end)
	end
	faceTarget(pos)
	task.wait(0.25)
	return true
end

local function trySteal(egg)
	local uid = egg.Name
	local slotKey
	local rec = recordsByUid()[uid]
	if rec and IsFirstUid and IsFirstUid(uid) and BuildSlotKey then
		pcall(function() slotKey = BuildSlotKey(rec.AreaId, rec.NestId) end)
	end

	plantOnEgg(egg)
	local prompt = findPrompt(egg)
	local deadline = tick() + CFG.stealTimeout
	while tick() < deadline and autoFarm and not carrying do
		local hrp = getHRP()
		local pos = eggPos(egg)
		if hrp and pos and (hrp.Position - pos).Magnitude > 5 then
			plantOnEgg(egg)
		end
		if CarryFn then
			local ok, res = pcall(function() return CarryFn(uid, slotKey) end)
			if ok and res == true then carrying = true end
		end
		if prompt and prompt.Parent then
			local hold = tonumber(prompt.HoldDuration) or CFG.stealHold
			pcall(function() prompt:InputHoldBegin() end)
			task.wait(math.max(hold, CFG.stealHold) + 0.1)
			pcall(function() prompt:InputHoldEnd() end)
			if typeof(fireproximityprompt) == "function" then
				pcall(fireproximityprompt, prompt)
			end
		else
			prompt = findPrompt(egg)
			task.wait(0.15)
		end
		refreshCarry()
		if carrying then
			setStatus("Stolen")
			return true
		end
		task.wait(0.08)
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
	local path = buildLanePath(hrp.Position, Vector3.new(base.X, base.Y + 3, base.Z))
	return travelAlong(path, speed)
end

local function farmOnce()
	disablePushScripts()
	refreshCarry()

	if carrying then
		setStatus("Escape")
		returnToBase(CFG.escapeSpeed)
		local untilT = tick() + CFG.baseWait
		while tick() < untilT and autoFarm do
			if isInPlot() or not carrying then break end
			RunService.Heartbeat:Wait()
		end
		restoreWalk()
		carrying = false
		return
	end

	local biome = CFG.biomes[CFG.biomeIndex]
	local center = getBiomeCenter(biome)
	local hrp = getHRP()
	if center and hrp and (hrp.Position - center).Magnitude > 120 then
		setStatus("To " .. biome)
		if not travelAlong(buildLanePath(hrp.Position, center), CFG.approachSpeed) then
			setStatus("Fly abort")
			restoreWalk()
			return
		end
	end

	local egg = nearestEggInBiome()
	if not egg then
		setStatus("No eggs " .. biome)
		task.wait(0.5)
		return
	end

	local pos = eggPos(egg)
	hrp = getHRP()
	setStatus("Approach")
	if not hrp or not pos or not travelAlong(buildLanePath(hrp.Position, pos), CFG.approachSpeed) then
		setStatus("Approach abort")
		restoreWalk()
		return
	end

	setStatus("Grab")
	if not trySteal(egg) then
		setStatus("Miss")
		restoreWalk()
		task.wait(0.25)
		return
	end

	setStatus("Return")
	returnToBase(CFG.escapeSpeed)
	setStatus("Bank")
	local bankUntil = tick() + CFG.baseWait + 2
	while tick() < bankUntil and autoFarm do
		refreshCarry()
		if isInPlot() and not carrying then break end
		if not carrying then break end
		RunService.Heartbeat:Wait()
	end
	restoreWalk()
	carrying = false
	setStatus("OK")
end

local function startFarmLoop()
	if farmBusy then return end
	farmBusy = true
	disablePushScripts()
	local velGuard = RunService.Heartbeat:Connect(function()
		if not autoFarm then return end
		local hrp = getHRP()
		if hrp then
			local p = hrp.Position
			if not isFiniteVec(p) then
				restoreWalk()
				return
			end
			local v = hrp.AssemblyLinearVelocity
			if math.abs(v.Y) > 40 then
				hrp.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
			end
		end
		if noclipOn then
			local char = getChar()
			if char then
				for _, part in ipairs(char:GetChildren()) do
					if part:IsA("BasePart") then part.CanCollide = false end
				end
			end
		end
	end)
	table.insert(connections, velGuard)

	task.spawn(function()
		while autoFarm do
			local ok, err = pcall(farmOnce)
			if not ok then
				setStatus("Err " .. tostring(err))
				restoreWalk()
				task.wait(0.4)
			end
			task.wait(0.1)
		end
		restoreWalk()
		farmBusy = false
	end)
end

-- ESP unchanged
local function resolveHiddenParent()
	if typeof(gethui) == "function" then
		local ok, h = pcall(gethui)
		if ok and h then return h end
	end
end

local function protectInstance(inst)
	pcall(function() if syn and syn.protect_gui then syn.protect_gui(inst) end end)
	pcall(function() if protectgui then protectgui(inst) end end)
	pcall(function() if protect_gui then protect_gui(inst) end end)
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
	if t.approachSpeed then CFG.approachSpeed = math.clamp(t.approachSpeed, 40, 180) end
	if t.escapeSpeed then CFG.escapeSpeed = math.clamp(t.escapeSpeed, 50, 220) end
	if typeof(t.status) == "function" then CFG.status = t.status end
end

function Api.startFarm()
	bindGame()
	disablePushScripts()
	setStatus(("v11 Bound E=%s P=%s Eggs=%s"):format(
		EggState and "Y" or "N",
		PlotState and "Y" or "N",
		AreaEggs and "Y" or "N"
	))
	autoFarm = true
	startFarmLoop()
end

function Api.stopFarm()
	autoFarm = false
	restoreWalk()
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
	restoreWalk()
	clearEsp()
	for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
	connections = {}
end

LP.CharacterAdded:Connect(function()
	task.wait(0.4)
	if autoFarm then disablePushScripts() end
end)

return Api
