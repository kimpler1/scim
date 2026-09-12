--[[
  Steal An Egg - Core v17
  Base: Best Version v12 (Boblo grounded stealMoveTo).
  Upgrades: fast grab/escape, carry check, elevated peel, reclaim, RigSync KB patch.
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
	approachSpeed = 250,
	escapeSpeed = 480,
	arriveDist = 1.35,
	grabDelay = 0.3,
	moveTimeout = 14,
	baseWait = 2.2,
	escapeHeight = 5,
	carryGrace = 0.25,
	reclaimRadius = 250,
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

local function isFiniteVec(v)
	return typeof(v) == "Vector3"
		and v.X == v.X and v.Y == v.Y and v.Z == v.Z
		and math.abs(v.X) < 1e5 and math.abs(v.Y) < 1e5 and math.abs(v.Z) < 1e5
end

-- MUST be declared before stealMoveTo (Lua local scope)
local lastEggUid, lastEggPos, lastStealAt = nil, nil, 0
local rigSyncPatched = false

local function isActuallyCarrying()
	local pg = LP:FindFirstChildOfClass("PlayerGui")
	local dropGui = pg and pg:FindFirstChild("DropHeldEgg")
	if dropGui and dropGui.Enabled == true then
		return true
	end
	if LP:GetAttribute("IsCarryingEgg") == true then
		return true
	end
	local char = getChar()
	if not char then return false end
	if char:GetAttribute("IsCarryingEgg") == true then
		return true
	end
	for _, t in ipairs(char:GetChildren()) do
		if t:IsA("Tool") then
			local n = t.Name:lower()
			if n:find("egg", 1, true) or n:find("carry", 1, true)
				or t:GetAttribute("IsEgg") == true or t:GetAttribute("Uid") ~= nil then
				return true
			end
		elseif t:IsA("Model") then
			local n = t.Name:lower()
			if n:find("egg", 1, true) or t:GetAttribute("Uid") or t:GetAttribute("AssetCategory") then
				return true
			end
		end
	end
	return false
end

local function isAlive()
	local hum = getHum()
	local hrp = getHRP()
	if not hum or not hrp or not hrp.Parent then return false end
	if hum.Health <= 0 then return false end
	return true
end

local function isDowned()
	local hum = getHum()
	if not hum then return true end
	if hum.PlatformStand or hum.Sit then return true end
	local st = hum:GetState()
	return st == Enum.HumanoidStateType.Physics
		or st == Enum.HumanoidStateType.Ragdoll
		or st == Enum.HumanoidStateType.FallingDown
end

local function recoverStand()
	local hum = getHum()
	local hrp = getHRP()
	if hum then
		hum.PlatformStand = false
		hum.Sit = false
		pcall(function()
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end)
		pcall(function()
			hum:ChangeState(Enum.HumanoidStateType.Running)
		end)
	end
	if hrp then
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
	end
end

local function patchRigSyncKnockback()
	if rigSyncPatched then return true end
	if typeof(getconnections) ~= "function" then
		return false
	end
	local packages = ch(ReplicatedStorage, "Packages", 1)
	local networking = packages and ch(packages, "Networking", 1)
	if not networking then return false end
	local refresh = networking:FindFirstChild("RE/RigSync/Refresh")
	if not refresh then
		for _, d in ipairs(networking:GetDescendants()) do
			if d:IsA("RemoteEvent") and d.Name == "Refresh"
				and tostring(d:GetFullName()):find("RigSync", 1, true) then
				refresh = d
				break
			end
		end
	end
	if not refresh then return false end
	local ok, conns = pcall(getconnections, refresh.OnClientEvent)
	if not ok or typeof(conns) ~= "table" then return false end
	local n = 0
	for _, conn in ipairs(conns) do
		pcall(function()
			if conn.Disconnect then conn:Disconnect() end
			if conn.Disable then conn:Disable() end
		end)
		n = n + 1
	end
	rigSyncPatched = n > 0
	return rigSyncPatched
end

-- Boblo: kill PushBack + optional humanoid clone (chicken knockback)
local function swapStealHumanoid()
	local char = getChar()
	if not char then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return false end
	if hum:GetAttribute("SAE_SafeHum") == true then return true end

	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("LocalScript") and string.find(d.Name, "Push", 1, true) then
			pcall(function()
				d.Disabled = true
				d:Destroy()
			end)
		end
	end

	hum.Archivable = true
	local clone = hum:Clone()
	if not clone then return false end
	clone:SetAttribute("SAE_SafeHum", true)
	clone.Sit = false
	clone.PlatformStand = false
	clone.AutoRotate = true
	hum:Destroy()
	clone.Parent = char
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
	end
	pcall(function()
		clone:ChangeState(Enum.HumanoidStateType.Running)
	end)
	return true
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

-- Boblo groundedY: prefer Ground parts, clamp to lane band
local function groundedY(x, z, fallbackY)
	local laneY = getLaneY()
	local root = getHRP()
	local humanoid = getHum()
	local hipHeight = (humanoid and humanoid.HipHeight > 0) and humanoid.HipHeight or 2
	local rootHalf = root and root.Size.Y * 0.5 or 1
	local characterOffset = hipHeight + rootHalf
	local groundThreshold = laneY + 1.5
	local excluded = {}
	local char = getChar()
	if char then table.insert(excluded, char) end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local originY = laneY + 40
	local hitY = nil
	for _ = 1, 20 do
		params.FilterDescendantsInstances = excluded
		local hit = Workspace:Raycast(Vector3.new(x, originY, z), Vector3.new(0, -160, 0), params)
		if not hit then break end
		local y = hit.Position.Y
		local name = hit.Instance.Name
		local looksLikeGround = name == "Ground" or string.find(string.lower(name), "ground", 1, true) ~= nil
		if looksLikeGround or y <= groundThreshold then
			hitY = y
			break
		end
		table.insert(excluded, hit.Instance)
	end
	if hitY then
		return math.clamp(hitY + characterOffset, laneY - 2, laneY + 5)
	end
	if typeof(fallbackY) == "number" then
		return math.clamp(fallbackY, laneY - 2, laneY + 5)
	end
	return laneY + 3
end

local function anchor(hrp, cf)
	if not hrp or not cf then return end
	local p = cf.Position
	if not isFiniteVec(p) then return end
	hrp.CFrame = cf
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
end

-- Boblo stealMoveTo: PlatformStand OFF, walk on ground along XZ
local function stealMoveTo(targetX, targetZ, speed, opts)
	opts = opts or {}
	local root = getHRP()
	if not root then return false end
	local humanoid = getHum()
	if humanoid then
		humanoid.Sit = false
		humanoid.PlatformStand = false
	end
	local arriveDistance = CFG.arriveDist
	local deadline = tick() + CFG.moveTimeout
	local spd = speed or CFG.approachSpeed
	local elev = opts.elevated and (CFG.escapeHeight or 5) or 0

	while tick() < deadline and autoFarm do
		if not isAlive() then
			return false
		end
		if opts.requireCarry and (tick() - (lastStealAt or 0)) > (CFG.carryGrace or 0.25) then
			if not isActuallyCarrying() then
				carrying = false
				setStatus("Egg lost")
				return false
			end
		end
		if isDowned() then
			recoverStand()
			task.wait(0.06)
		end
		root = getHRP()
		if not root or not isFiniteVec(root.Position) then
			task.wait(0.05)
		else
			humanoid = getHum()
			if humanoid then
				humanoid.Sit = false
				humanoid.PlatformStand = false
			end
			local y = groundedY(targetX, targetZ, root.Position.Y) + elev
			local target = Vector3.new(targetX, y, targetZ)
			local delta = target - root.Position
			if not isFiniteVec(delta) then return false end
			local distance = delta.Magnitude
			if distance <= arriveDistance then
				anchor(root, CFrame.new(target))
				if humanoid then
					pcall(function()
						humanoid:ChangeState(Enum.HumanoidStateType.Running)
					end)
				end
				return true
			end
			local dt = RunService.Heartbeat:Wait()
			if typeof(dt) ~= "number" or dt <= 0 then dt = 1 / 60 end
			root = getHRP()
			if not root then return false end
			if isDowned() then
				recoverStand()
			end
			y = groundedY(targetX, targetZ, root.Position.Y) + elev
			target = Vector3.new(targetX, y, targetZ)
			delta = target - root.Position
			distance = delta.Magnitude
			if distance <= arriveDistance then
				anchor(root, CFrame.new(target))
				return true
			end
			if distance < 1e-3 then
				anchor(root, CFrame.new(target))
				return true
			end
			local step = math.min(distance, spd * dt)
			local nextPosition = root.Position + delta.Unit * step
			nextPosition = Vector3.new(
				nextPosition.X,
				groundedY(nextPosition.X, nextPosition.Z, nextPosition.Y) + elev,
				nextPosition.Z
			)
			if not isFiniteVec(nextPosition) then return false end
			local horizontal = Vector3.new(delta.X, 0, delta.Z)
			local nextCFrame = horizontal.Magnitude > 0.05
				and CFrame.lookAt(nextPosition, nextPosition + horizontal)
				or CFrame.new(nextPosition)
			anchor(root, nextCFrame)
		end
	end
	return false
end

local function buildStealPath(startPosition, targetPosition)
	local laneZ = getLaneZ()
	local laneY = getLaneY()
	local waypoints = {}
	if math.abs(startPosition.Z - laneZ) > 3 then
		table.insert(waypoints, Vector3.new(startPosition.X, laneY, laneZ))
	end
	if math.abs(startPosition.X - targetPosition.X) > 2 then
		table.insert(waypoints, Vector3.new(targetPosition.X, laneY, laneZ))
	end
	table.insert(waypoints, Vector3.new(targetPosition.X, laneY, targetPosition.Z))
	return waypoints
end

local function stealAlong(waypoints, speed, opts)
	for i, wp in ipairs(waypoints) do
		if not autoFarm then return false end
		setStatus(("Move %d/%d"):format(i, #waypoints))
		if not stealMoveTo(wp.X, wp.Z, speed, opts) then
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

local function refreshCarry()
	if isActuallyCarrying() then
		carrying = true
		return true
	end
	-- short grace only after steal (attribute/GUI lag) - not 1s+ sticky
	if lastStealAt > 0 and (tick() - lastStealAt) < (CFG.carryGrace or 0.25) then
		carrying = true
		return true
	end
	carrying = false
	return false
end

local function tryCarryEgg(egg)
	if not egg or not CarryFn then return false end
	local uid = egg.Name
	local slotKey
	local rec = recordsByUid()[uid]
	if rec and IsFirstUid and IsFirstUid(uid) and BuildSlotKey then
		pcall(function() slotKey = BuildSlotKey(rec.AreaId, rec.NestId) end)
	end
	local ok, res = pcall(function() return CarryFn(uid, slotKey) end)
	if ok and res == true then
		carrying = true
		lastStealAt = tick()
		return true
	end
	if isActuallyCarrying() then
		carrying = true
		lastStealAt = tick()
		return true
	end
	return false
end

-- Grab: first successful tryCarryEgg -> return IMMEDIATELY (no linger)
local function trySteal(egg)
	local pos = eggPos(egg)
	local root = getHRP()
	if not root or not pos then return false end

	local targetY = groundedY(pos.X, pos.Z, pos.Y)
	anchor(root, CFrame.new(pos.X, targetY, pos.Z))

	local prompt = findPrompt(egg)
	local grabStarted = tick()
	while tick() - grabStarted < CFG.grabDelay and autoFarm do
		if tryCarryEgg(egg) then
			lastEggUid = egg.Name
			lastEggPos = pos
			lastStealAt = tick()
			setStatus("Stolen->GO")
			return true
		end
		if prompt and prompt.Parent then
			pcall(function() prompt:InputHoldBegin() end)
			task.wait(0.05)
			pcall(function() prompt:InputHoldEnd() end)
			if typeof(fireproximityprompt) == "function" then
				pcall(fireproximityprompt, prompt)
			end
		end
		task.wait(0.04)
	end

	-- Extra window only if still not carrying (max 0.35s)
	if not isActuallyCarrying() then
		local extra = tick() + 0.35
		while tick() < extra and autoFarm do
			if tryCarryEgg(egg) then
				lastEggUid = egg.Name
				lastEggPos = pos
				lastStealAt = tick()
				setStatus("Stolen->GO")
				return true
			end
			task.wait(0.04)
		end
	else
		lastEggUid = egg.Name
		lastEggPos = pos
		lastStealAt = tick()
		carrying = true
		setStatus("Stolen->GO")
		return true
	end

	return false
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

local function returnToBase(speed, opts)
	local base = getBasePos()
	local hrp = getHRP()
	if not base or not hrp then return false end
	opts = opts or { requireCarry = true, elevated = true }
	return stealAlong(buildStealPath(hrp.Position, base), speed, opts)
end

local function findEggByUid(uid)
	if not uid then return nil end
	AreaEggs = AreaEggs or ch(Workspace, "Area" .. "Egg" .. "Slots" .. "Client", 1)
	if not AreaEggs then return nil end
	return AreaEggs:FindFirstChild(uid)
end

local function findReclaimEgg()
	AreaEggs = AreaEggs or ch(Workspace, "Area" .. "Egg" .. "Slots" .. "Client", 1)
	local hrp = getHRP()
	if not AreaEggs or not hrp then return nil end
	local recs = recordsByUid()
	local radius = CFG.reclaimRadius or 250
	local best, bestDist, bestPri

	local function consider(egg, pri)
		local pos = eggPos(egg)
		if not pos then return end
		local d = (pos - hrp.Position).Magnitude
		if d > radius then return end
		if not bestDist or pri > bestPri or (pri == bestPri and d < bestDist) then
			best, bestDist, bestPri = egg, d, pri
		end
	end

	for _, egg in ipairs(AreaEggs:GetChildren()) do
		local uid = egg.Name
		local rec = recs[uid]
		local isDropped = rec and rec.State == "Dropped"
		local isLast = lastEggUid and uid == lastEggUid
		if isLast then
			consider(egg, 3)
		elseif isDropped then
			consider(egg, 2)
		end
	end
	return best
end

local function approachAndSteal(egg, speed)
	local pos = eggPos(egg)
	local hrp = getHRP()
	if not hrp or not pos then return false end
	lastEggUid = egg.Name
	lastEggPos = pos
	setStatus("Reclaim")
	if isDowned() then recoverStand() end
	if not stealAlong(buildStealPath(hrp.Position, pos), speed or CFG.approachSpeed) then
		return false
	end
	setStatus("Grab")
	return trySteal(egg)
end

local function peelThenEscape()
	local hrp = getHRP()
	if not hrp then return false end
	setStatus("Peel")
	local peelOk = stealMoveTo(hrp.Position.X, getLaneZ(), CFG.escapeSpeed, {
		requireCarry = true,
		elevated = true,
	})
	if not peelOk and not isActuallyCarrying() then
		carrying = false
		setStatus("Egg lost")
		local reclaim = findReclaimEgg() or findEggByUid(lastEggUid)
		if reclaim and approachAndSteal(reclaim, CFG.approachSpeed) then
			hrp = getHRP()
			if not hrp then return false end
			setStatus("Peel")
			stealMoveTo(hrp.Position.X, getLaneZ(), CFG.escapeSpeed, {
				requireCarry = true,
				elevated = true,
			})
		else
			return false
		end
	end

	setStatus("Escape")
	local escaped = returnToBase(CFG.escapeSpeed, { requireCarry = true, elevated = true })
	if not escaped and not isActuallyCarrying() then
		carrying = false
		setStatus("Egg lost")
		local reclaim = findReclaimEgg() or findEggByUid(lastEggUid)
		if reclaim and approachAndSteal(reclaim, CFG.approachSpeed) then
			hrp = getHRP()
			if hrp then
				setStatus("Peel")
				stealMoveTo(hrp.Position.X, getLaneZ(), CFG.escapeSpeed, {
					requireCarry = true,
					elevated = true,
				})
			end
			setStatus("Escape")
			escaped = returnToBase(CFG.escapeSpeed, { requireCarry = true, elevated = true })
		else
			return false
		end
	end
	return escaped ~= false or isActuallyCarrying() or isInPlot()
end

local function farmOnce()
	patchRigSyncKnockback()
	swapStealHumanoid()
	refreshCarry()

	if carrying then
		peelThenEscape()
		local untilT = tick() + CFG.baseWait
		while tick() < untilT and autoFarm do
			if isInPlot() or not carrying then break end
			refreshCarry()
			RunService.Heartbeat:Wait()
		end
		carrying = false
		return
	end

	local biome = CFG.biomes[CFG.biomeIndex]
	local center = getBiomeCenter(biome)
	local hrp = getHRP()
	if center and hrp and (hrp.Position - center).Magnitude > 120 then
		setStatus("To " .. biome)
		if not stealAlong(buildStealPath(hrp.Position, center), CFG.approachSpeed) then
			setStatus("Move abort")
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
	if not hrp or not pos or not stealAlong(buildStealPath(hrp.Position, pos), CFG.approachSpeed) then
		setStatus("Approach abort")
		return
	end

	setStatus("Grab")
	if not trySteal(egg) then
		setStatus("Miss")
		task.wait(0.25)
		return
	end

	peelThenEscape()
	setStatus("Bank")
	local bankUntil = tick() + CFG.baseWait + 2
	while tick() < bankUntil and autoFarm do
		refreshCarry()
		if isInPlot() and not carrying then break end
		if not carrying then break end
		RunService.Heartbeat:Wait()
	end
	carrying = false
	lastEggUid, lastEggPos = nil, nil
	lastStealAt = 0
	setStatus("OK")
end

local function startFarmLoop()
	if farmBusy then return end
	farmBusy = true
	swapStealHumanoid()
	local velGuard = RunService.Heartbeat:Connect(function()
		if not autoFarm then return end
		local hrp = getHRP()
		if not hrp then return end
		if not isFiniteVec(hrp.Position) then return end
		local v = hrp.AssemblyLinearVelocity
		-- Boblo-style: kill upward fling from chicken, keep horizontal
		if math.abs(v.Y) > 25 then
			hrp.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
		end
	end)
	table.insert(connections, velGuard)

	task.spawn(function()
		while autoFarm do
			local ok, err = pcall(farmOnce)
			if not ok then
				setStatus("Err " .. tostring(err))
				task.wait(0.4)
			end
			task.wait(0.1)
		end
		farmBusy = false
	end)
end

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
	if t.approachSpeed then CFG.approachSpeed = math.clamp(t.approachSpeed, 50, 1000) end
	if t.escapeSpeed then CFG.escapeSpeed = math.clamp(t.escapeSpeed, 50, 1000) end
	if typeof(t.status) == "function" then CFG.status = t.status end
end

function Api.startFarm()
	bindGame()
	patchRigSyncKnockback()
	swapStealHumanoid()
	setStatus(("v17 Bound E=%s P=%s Eggs=%s KB=%s"):format(
		EggState and "Y" or "N",
		PlotState and "Y" or "N",
		AreaEggs and "Y" or "N",
		rigSyncPatched and "Y" or "N"
	))
	autoFarm = true
	startFarmLoop()
end

function Api.stopFarm()
	autoFarm = false
	local hum = getHum()
	if hum then hum.PlatformStand = false end
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
	clearEsp()
	for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
	connections = {}
end

LP.CharacterAdded:Connect(function()
	task.wait(0.4)
	if autoFarm then
		swapStealHumanoid()
		patchRigSyncKnockback()
	end
end)

return Api
