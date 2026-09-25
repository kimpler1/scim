--[[
  Glitch Core — Steal An Egg
  Farm: V18 path plus clean reset/retry after a failed guard sequence.
  WS/Fly/ESP: Best Version V25 (unchanged).
  VER: V113
  FROZEN (LO 2026-09-16):
    - Autofarm = V18 guardHitThenRegrab / peelThenEscape / farmOnce with clean retry
    - WS + Fly: V25 scrub @0.2s, unanchored velocity fly
    - Auto Steal: repeat pickup returns to base on a stable route (no upward drift)
    - Original Humanoid is restored after Auto Farm for normal controls and jumping
]]

local GLITCH_CORE_VER = "V113"

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer

-- Oxide AREA_COORDINATES — used when GuardAreas Bounds missing / name mismatch
local BIOME_CENTERS = {
	["Forest"] = Vector3.new(596.0, 68.0, -328.0),
	["Lake"] = Vector3.new(744.0, 68.5, -408.0),
	["Desert"] = Vector3.new(948.0, 69.5, -323.0),
	["Jungle"] = Vector3.new(1188.0, 68.5, -408.0),
	["Snow"] = Vector3.new(1492.0, 69.0, -315.0),
	["Volcano"] = Vector3.new(1882.0, 68.0, -398.0),
	["Abyss Ocean"] = Vector3.new(2280.0, 68.0, -326.0),
	["Prehistoric"] = Vector3.new(2812.0, 69.0, -398.0),
	["Cosmic"] = Vector3.new(3390.0, 68.0, -324.0),
	["Cherry Blossom"] = Vector3.new(4028.0, 68.5, -396.0),
	["Titan Temple"] = Vector3.new(4796.0, 69.5, -328.0),
}

local CFG = {
	biomeIndex = 1,
	biomes = {
		"Forest", "Lake", "Desert", "Jungle", "Snow", "Volcano",
		"Abyss Ocean", "Prehistoric", "Cosmic", "Cherry Blossom", "Titan Temple",
	},
	approachSpeed = 250,
	escapeSpeed = 480,
	arriveDist = 1.35,
	grabDelay = 1.6,
	moveTimeout = 14,
	baseWait = 3.0,
	escapeHeight = 10,
	carryGrace = 0.25,
	reclaimRadius = 250,
	biomeRadiusX = 220,
	biomeRadiusZ = 140,
	guardHit = true, -- Oxide: steal -> get hit -> stand -> regrab -> return (fixes Delivery failed)
	retryRecoveryWait = 4.0,
	retryAttempts = 3,
	targetMode = "all",
	carrierFollowDistance = 3.5,
	status = function() end,
}

local EggState, PlotState, SlotIdentity, AssetsData, SaveModule
local IsEggReadyFn, BeginHatchFn, FinishHatchFn, WearEggToolFn, PlantEggFn
local EquipBestPetsRemote, BatSwingRemote
local CarryFn, SnapshotFn, SyncSnapshot, CarrySignal
local GetRespawn, GetPlot, InPlot, IsFirstUid, BuildSlotKey
local AreasFolder, GuardAreas, AreaEggs
local Bound = false
local autoFarm, carrying, farmBusy = false, false, false
local autoActions = { plant = false, hatch = false, equip = false }
local autoActionsBusy = false
local connections = {}
local espFlags = { players = false, eggs = false, beasts = false }
local espMap = {} -- [key] = { hl, bb, label, kind }
local espFolder, espConn
local walkSpeedOn, walkSpeedVal = false, 32
local flyOn, flySpeed = false, 60
local infiniteJumpOn, noClipOn = false, false
local moveConn
local flyConn, flyVelocity = nil, nil
local auraVelocity = nil
local infiniteJumpConn, noClipConn
local noClipOriginal = setmetatable({}, { __mode = "k" })
local refreshNoClip
local freezeMoveForValidate = false -- pause WS boost / fly travel during guard-hit validate
local deliverAssistConn = nil
local deliverAssistBusy = false
local stealValidated = false
local wasCarryingEdge = false
local acInstalled = false
local acStatus = "off"
local lastScanInfo = "slots=0 snap=0"
local lastBestInfo = ""

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

-- Reference scripts operate on each UID; there is no real "HatchAll" API.
local function findRemoteByPathOrName(path, name)
	for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
		local full = obj:GetFullName():gsub("%.", "/")
		if (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction"))
			and (obj.Name == name or obj.Name:find(name, 1, true) or full:find(path, 1, true)) then
			return obj
		end
	end
end

local function invokeRemote(remote, ...)
	if not remote then return false end
	local args = table.pack(...)
	local ok, result = pcall(function()
		if remote:IsA("RemoteFunction") then
			return remote:InvokeServer(table.unpack(args, 1, args.n))
		end
		remote:FireServer(table.unpack(args, 1, args.n))
		return true
	end)
	return ok and result ~= false
end

local function getSave()
	if not SaveModule or typeof(SaveModule.Get) ~= "function" then return nil end
	local ok, save = pcall(SaveModule.Get)
	return ok and save or nil
end

local function bindGame()
	if Bound then return true end
	local Client = ch(ReplicatedStorage, "Client", 2)
	local Shared = ch(ReplicatedStorage, "Shared", 2)
	local Util = Shared and ch(Shared, "Util", 1)
	local Data = ch(ReplicatedStorage, "Data", 2)

	EggState = Client and req(Client, "Egg" .. "State", 2)
	PlotState = Client and req(Client, "Plot" .. "State", 2)
	SaveModule = Shared and req(Shared, "Save", 2)
	SlotIdentity = Util and req(Util, "Area" .. "Egg" .. "Slot" .. "Identity", 1)
	AssetsData = Data and req(Data, "Assets", 2)

	CarryFn = pick(EggState, "CarryFieldEgg", "RequestCarryAreaEgg")
	SnapshotFn = pick(EggState, "ReadFieldEggs", "GetAreaEggSnapshot")
	SyncSnapshot = pick(EggState, "SyncFieldEggs", "RequestAreaEggSnapshot")
	CarrySignal = EggState and (EggState.CarryChanged or EggState.AreaEggCarryStateChanged)
	GetRespawn = pick(PlotState, "FindRespawnCFrame", "GetRespawnPointCFrame")
	GetPlot = pick(PlotState, "ResolvePlot", "GetPlotData")
	InPlot = pick(PlotState, "ContainsLocalPoint", "IsWorldPositionWithinLocalPlotBounds")
	IsFirstUid = pick(SlotIdentity, "LooksLikeFirstAreaUid", "IsFirstAreaUid")
	BuildSlotKey = pick(SlotIdentity, "SlotKey", "BuildSlotKey")
	IsEggReadyFn = pick(EggState, "IsReadyToHatch", "IsLocalEggReady")
	BeginHatchFn = pick(EggState, "BeginHatch", "RequestHatchEgg")
	FinishHatchFn = pick(EggState, "FinishHatch", "RequestCompleteHatchEgg")
	WearEggToolFn = pick(EggState, "WearEggTool", "RequestEquipTool")
	PlantEggFn = pick(EggState, "PlantEgg", "RequestPlaceEgg")
	EquipBestPetsRemote = findRemoteByPathOrName("Haul/WearBest", "WearBest")
		or findRemoteByPathOrName("PenRoster/ConfirmEquipBestBadge", "ConfirmEquipBestBadge")
	BatSwingRemote = findRemoteByPathOrName("BatSwing/Trigger", "BatSwing")

	-- Oxide: Packages.Networking["RF/EggWorld/AskFieldEggCarry"]
	local function findCarryRemote()
		local packages = ch(ReplicatedStorage, "Packages", 1)
		local networking = packages and ch(packages, "Networking", 1)
		if networking then
			local rem = networking:FindFirstChild("RF/EggWorld/AskFieldEggCarry")
			if rem then return rem end
			for _, d in ipairs(networking:GetDescendants()) do
				if (d:IsA("RemoteFunction") or d:IsA("RemoteEvent"))
					and tostring(d.Name):find("AskFieldEggCarry", 1, true) then
					return d
				end
			end
		end
		for _, folderName in ipairs({ "RF", "Remotes", "Net" }) do
			local folder = ch(ReplicatedStorage, folderName, 0)
			if folder then
				local ew = ch(folder, "Egg" .. "World", 0)
				local rem = (ew and ch(ew, "Ask" .. "Field" .. "Egg" .. "Carry", 0))
					or ch(folder, "Ask" .. "Field" .. "Egg" .. "Carry", 0)
				if rem then return rem end
			end
		end
	end

	local CarryRemote = findCarryRemote()
	local eggStateCarry = CarryFn
	-- Fire BOTH module + remote, both arg shapes (Boblo uid,slotKey / Oxide {Uid=...})
	CarryFn = function(uid, slotKey)
		local got = false
		if eggStateCarry then
			local ok, res = pcall(eggStateCarry, uid, slotKey)
			if ok and res == true then got = true end
		end
		if CarryRemote then
			pcall(function()
				if CarryRemote:IsA("RemoteFunction") then
					CarryRemote:InvokeServer(uid, slotKey)
					CarryRemote:InvokeServer({ Uid = uid, FirstAreaSlotKey = slotKey })
				else
					CarryRemote:FireServer(uid, slotKey)
					CarryRemote:FireServer({ Uid = uid, FirstAreaSlotKey = slotKey })
				end
			end)
		end
		return got
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

-- Previous stable anti-push setup. This replacement is required by the
-- current server's guard/return checks; without it the server repeatedly
-- returns the player to the finish and can eventually reset the character.
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
	-- Preserve Roblox's original control target while the farm runs on the
	-- guarded clone.  Destroying it permanently breaks normal jump input on
	-- some clients; it is reattached only from stopFarm, never mid-route.
	if CFG.preFarmHumanoid and CFG.preFarmHumanoid.Parent == nil then
		pcall(function() CFG.preFarmHumanoid:Destroy() end)
	end
	CFG.preFarmHumanoid = hum
	hum.Parent = nil
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

-- Auto Farm intentionally uses a replacement Humanoid for the guard route.
-- When it stops, restart Roblox's Animate script against that replacement so
-- manual walking returns to a real running animation instead of gliding.
local function restoreManualRunAnimation()
	local char = getChar()
	local hum = getHum()
	if char and CFG.preFarmHumanoid and CFG.preFarmHumanoid.Parent == nil then
		if hum and hum ~= CFG.preFarmHumanoid then
			pcall(function() hum:Destroy() end)
		end
		CFG.preFarmHumanoid.Parent = char
		hum = CFG.preFarmHumanoid
		CFG.preFarmHumanoid = nil
	end
	if not (char and hum) then return end
	hum.Sit = false
	hum.PlatformStand = false
	hum.AutoRotate = true
	pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
	pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
	pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end)
	local animate = char:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		pcall(function() animate.Disabled = true end)
		task.defer(function()
			if animate.Parent == char then
				pcall(function() animate.Disabled = false end)
			end
		end)
	end
end

local function getLaneZ()
	if AreasFolder then
		local gz = AreasFolder:FindFirstChild("GameplayZ")
		if gz and gz:IsA("BasePart") then return gz.Position.Z end
		local sep = AreasFolder:FindFirstChild("SeparationLine")
		if sep and sep:IsA("BasePart") then return sep.Position.Z end
	end
	-- Streaming can temporarily hide the routing parts.  This must remain a
	-- fixed route coordinate: using the current root position makes the path
	-- collapse after a knockback or while returning from a stolen egg.
	return -365.5
end

local function getLaneY()
	if AreasFolder then
		local gz = AreasFolder:FindFirstChild("GameplayZ")
		if gz and gz:IsA("BasePart") then return gz.Position.Y + 3 end
	end
	-- Never derive the ground baseline from the current character height.
	-- During an elevated escape that would add escapeHeight again every step
	-- when GameplayZ has not streamed in yet, sending the character upward.
	return (BIOME_CENTERS.Forest and BIOME_CENTERS.Forest.Y) or 70
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
	local arriveDistance = opts.arriveDist or CFG.arriveDist
	local deadline = tick() + (opts.timeout or CFG.moveTimeout)
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

local function areaMatches(a, b)
	if typeof(a) ~= "string" or typeof(b) ~= "string" then return false end
	if a == b then return true end
	local x, y = a:lower():gsub("%s+", ""):gsub("_", ""), b:lower():gsub("%s+", ""):gsub("_", "")
	return x == y or x:find(y, 1, true) ~= nil or y:find(x, 1, true) ~= nil
end

-- Update 4's twelfth map is one nightly area with two server-side names.
-- Do not hard-code a position for it: use the live Bounds object for the side
-- (Angels or Demons) which is actually present in this server.
local function biomeAliases(name)
	if name == "Angels / Demons" then
		return { "Angels", "Demons", "Angel", "Demon", "Light", "Darkness", "Light vs Darkness" }
	end
	return { name }
end

local function stopAuraFollowMotion()
	if auraVelocity then
		pcall(function() auraVelocity:Destroy() end)
		auraVelocity = nil
	end
	local hum = getHum()
	if hum then hum.PlatformStand = false end
end

-- One continuous pursuit step for Bat Aura.  Follow the live target offset
-- directly, rather than applying a force that collides with lane walls.
local function chaseCarrierStep(targetPosition, speed)
	local root = getHRP()
	if not root or not targetPosition or not isFiniteVec(root.Position) then return false end
	local hum = getHum()
	if not hum then return false end
	hum.Sit = false
	root.Anchored = false
	hum.PlatformStand = false
	local destination = Vector3.new(targetPosition.X, targetPosition.Y, targetPosition.Z)
	local delta = destination - root.Position
	if not isFiniteVec(delta) then return false end
	local horizontal = Vector3.new(delta.X, 0, delta.Z)
	local desired = horizontal.Magnitude > 0.05
		and CFrame.lookAt(destination, destination + horizontal)
		or CFrame.new(destination)
	-- A high, frame-rate independent response closes a long gap quickly, then
	-- settles at the 3.5-stud trailing offset without the physics bounce.
	local dt = RunService.RenderStepped:Wait()
	if typeof(dt) ~= "number" or dt <= 0 then dt = 1 / 60 end
	local alpha = math.clamp(1 - math.exp(-24 * dt), 0.18, 0.72)
	root.CFrame = root.CFrame:Lerp(desired, alpha)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	return true
end

local function matchesBiome(areaId, biome)
	for _, alias in ipairs(biomeAliases(biome)) do
		if areaMatches(areaId, alias) then return true end
	end
	return false
end

local function hasEggSignal(obj)
	if not obj then return false end
	for key, value in pairs(obj:GetAttributes()) do
		local k = tostring(key):lower()
		if (k:find("egg", 1, true) or k:find("carry", 1, true))
			and value ~= nil and value ~= false and value ~= "" then
			return true
		end
	end
	local n = obj.Name:lower()
	return n:find("egg", 1, true) ~= nil or n:find("carry", 1, true) ~= nil
end

local function valueIdentifiesPlayer(value, plr)
	if value == nil or not plr then return false end
	if tonumber(value) == plr.UserId then return true end
	if typeof(value) == "string" then
		local s = value:lower()
		return s == plr.Name:lower() or s == plr.DisplayName:lower()
	end
	return false
end

-- Field-egg snapshots can include the player who picked the egg up even when
-- the carried model itself is not replicated below that player's character.
-- Names vary between releases, so accept only explicit carrier/holder fields.
local function recordBelongsToPlayer(record, plr)
	if typeof(record) ~= "table" then return false end
	for key, value in pairs(record) do
		local k = tostring(key):lower():gsub("_", "")
		if k:find("carrier", 1, true) or k:find("holder", 1, true)
			or k:find("carriedby", 1, true) or k:find("carryingplayer", 1, true) then
			if valueIdentifiesPlayer(value, plr) then return true end
			if typeof(value) == "table" then
				for _, nested in pairs(value) do
					if valueIdentifiesPlayer(nested, plr) then return true end
				end
			end
		end
	end
	return false
end

-- A player reference may remain in a snapshot after delivery.  It is a valid
-- aura target only while the record explicitly says the egg is being carried.
local function recordIsActivelyCarried(record)
	if typeof(record) ~= "table" then return false end
	if record.IsCarrying == true or record.IsHeld == true then return true end
	local state = tostring(record.State or record.Status or ""):lower()
	return state:find("carry", 1, true) ~= nil
		or state:find("held", 1, true) ~= nil

end

local carrierWorldCache, carrierWorldCacheAt = {}, 0
local function isConnectedToCharacter(part, char)
	if not (part and char) then return false end
	local ok, connected = pcall(function() return part:GetConnectedParts(true) end)
	if not ok then return false end
	for _, linked in ipairs(connected) do
		if linked:IsDescendantOf(char) then return true end
	end
	return false
end

local function visibleWorldCarriers()
	if tick() - carrierWorldCacheAt < 0.45 then return carrierWorldCache end
	carrierWorldCacheAt = tick()
	local found, roots = {}, {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP then
			local char = plr.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then table.insert(roots, { player = plr, root = root }) end
		end
	end
	for _, obj in ipairs(Workspace:GetDescendants()) do
		-- A carried egg can be a workspace Model welded to the character rather
		-- than a child named "Egg".  Accept only a physical connection to that
		-- character; proximity alone previously selected finish decorations.
		if obj:IsA("Model") and hasEggSignal(obj) then
			local part = obj:FindFirstChildWhichIsA("BasePart", true)
			if part then
				for _, candidate in ipairs(roots) do
					if not obj:IsDescendantOf(candidate.player.Character)
						and isConnectedToCharacter(part, candidate.player.Character) then
						found[candidate.player] = obj
						break
					end
				end
			end
		end
	end
	carrierWorldCache = found
	return found
end

local function playerIsCarryingEgg(plr, records, worldCarriers)
	if not plr or plr == LP then return false end
	if plr:GetAttribute("IsCarryingEgg") == true then return true end
	local char = plr.Character
	if not char then return false end
	if char:GetAttribute("IsCarryingEgg") == true then return true end
	-- A normal non-combat Tool is not evidence of an egg: bases and finish
	-- areas contain several of them, which previously produced false targets.
	for _, item in ipairs(char:GetDescendants()) do
		if item:IsA("Tool") then
			if hasEggSignal(item) or item:GetAttribute("IsEgg") == true or item:GetAttribute("EggUid") ~= nil then return true end
		elseif item:IsA("Model") or item:IsA("BasePart") then
			if hasEggSignal(item) or item:GetAttribute("IsEgg") == true or item:GetAttribute("EggUid") ~= nil then return true end
		end
	end
	if records then
		for _, record in pairs(records) do
			if recordIsActivelyCarried(record) and recordBelongsToPlayer(record, plr) then return true end
		end
	end
	-- This visual fallback is safe only because visibleWorldCarriers requires
	-- a physical joint connection to the character, not nearby geometry.
	if (worldCarriers or visibleWorldCarriers())[plr] then return true end
	return false
end

local function findZoneFolder(name)
	if not GuardAreas then return nil end
	for _, alias in ipairs(biomeAliases(name)) do
		local exact = GuardAreas:FindFirstChild(alias)
		if exact then return exact end
		for _, child in ipairs(GuardAreas:GetChildren()) do
			if areaMatches(child.Name, alias) then
				return child
			end
		end
	end
end

local function getZoneBounds(name)
	local zone = findZoneFolder(name)
	local bounds = zone and zone:FindFirstChild("Bounds")
	if bounds and bounds:IsA("BasePart") then return bounds end
end

local function getBiomeCenter(name)
	local hard = BIOME_CENTERS[name]
	local bounds = getZoneBounds(name)
	if bounds then
		return Vector3.new(bounds.Position.X, getLaneY(), getLaneZ())
	end
	if hard then
		return Vector3.new(hard.X, getLaneY(), getLaneZ())
	end
end

local function eggPos(egg)
	if typeof(egg) == "table" then
		return egg.Position
	end
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

local function nearBiomeCenter(pos, biome)
	if not pos then return false end
	local center = BIOME_CENTERS[biome] or getBiomeCenter(biome)
	if not center then return false end
	local rx = CFG.biomeRadiusX or 220
	local rz = CFG.biomeRadiusZ or 140
	return math.abs(pos.X - center.X) <= rx and math.abs(pos.Z - center.Z) <= rz
end

-- Initial discovery happens where the live field slots are.  This keeps aura
-- off plots/finish areas even if an old carrier record is still present.
local function isNearLiveFieldEgg(position)
	if not position then return false end
	AreaEggs = ch(Workspace, "Area" .. "Egg" .. "Slots" .. "Client", 0)
	if not AreaEggs then return false end
	for _, egg in ipairs(AreaEggs:GetChildren()) do
		local pos = eggPos(egg)
		-- A carrier must be discovered at the actual egg cluster.  A wide radius
		-- reaches the finish lane on this map and produces false Bat Aura targets.
		if pos and (pos - position).Magnitude <= 65 then return true end
	end
	return false
end

-- A carrier event is derived from a real slot disappearing while a player is
-- next to it.  This is stronger than guessing from their avatar/backpack.
local carrierSlotCache, recentCarrierPickups, carrierSlotScanAt = nil, {}, 0
local CarrierState = { eggs = {} } -- [uid] = { lastPos, carrier, expires, dropSeenAt }
local function recentSlotPickups()
	local now = tick()
	if now - carrierSlotScanAt < 0.15 then return recentCarrierPickups end
	carrierSlotScanAt = now
	AreaEggs = ch(Workspace, "Area" .. "Egg" .. "Slots" .. "Client", 0)
	local current = {}
	if AreaEggs then
		for _, egg in ipairs(AreaEggs:GetChildren()) do
			local pos = eggPos(egg)
			if pos then current[egg.Name] = pos end
		end
	end
	if carrierSlotCache then
		for uid, oldPos in pairs(carrierSlotCache) do
			if not current[uid] then
				local closest, closestDist
				for _, plr in ipairs(Players:GetPlayers()) do
					if plr ~= LP then
						local char = plr.Character
						local root = char and char:FindFirstChild("HumanoidRootPart")
						local dist = root and (root.Position - oldPos).Magnitude
						if dist and dist <= 28 and (not closestDist or dist < closestDist) then
							closest, closestDist = plr, dist
						end
					end
				end
				if closest then
					recentCarrierPickups[closest] = { uid = uid, expires = now + 5 }
					CarrierState.eggs[uid] = { lastPos = oldPos, carrier = closest, expires = now + 30 }
				end
			end
		end
	end
	carrierSlotCache = current
	for plr, event in pairs(recentCarrierPickups) do
		if not plr.Parent or event.expires <= now then recentCarrierPickups[plr] = nil end
	end
	for uid, session in pairs(CarrierState.eggs) do
		if session.expires <= now then CarrierState.eggs[uid] = nil end
	end
	return recentCarrierPickups
end

local function isInsideBiomeBounds(pos, biome)
	local bounds = getZoneBounds(biome)
	if not bounds then return nil end
	if not pos then return false end
	local lp = bounds.CFrame:PointToObjectSpace(pos)
	local half = bounds.Size * 0.5
	return math.abs(lp.X) <= half.X + 40
		and math.abs(lp.Y) <= half.Y + 80
		and math.abs(lp.Z) <= half.Z + 40
end

-- Carrier interception is deliberately limited to field zones.  A player at
-- their plot/finish must never be selected even if a nearby visual happens to
-- look like an egg to the client.
local function isInsideAnyEggField(pos)
	if not pos then return false end
	for _, biome in ipairs(CFG.biomes) do
		local inBounds = isInsideBiomeBounds(pos, biome)
		if inBounds == true then return true end
		if inBounds == nil and nearBiomeCenter(pos, biome) then return true end
	end
	return false
end

local function eggInSelectedBiome(egg, record)
	local biome = CFG.biomes[CFG.biomeIndex]
	local pos = eggPos(egg)
	local inBounds = isInsideBiomeBounds(pos, biome)
	local reportedHere = record and matchesBiome(record.AreaId, biome)
	-- Immediately after PlantEgg the snapshot can be stale.  A matching AreaId
	-- must never pull a visible egg from another zone when live Bounds disagree.
	if reportedHere and inBounds ~= false then return true end
	if inBounds == true then return true end
	if reportedHere and not pos then return true end
	if inBounds == false then return false end
	if not pos then
		return false
	end
	-- Late biomes often have eggs with nil/stale snapshot records — match by Oxide coords
	if nearBiomeCenter(pos, biome) then
		return true
	end
	return false
end

local nearestEggInBiome

local RARITY_WEIGHT = {
	Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5,
	Mythic = 6, Cosmic = 7, Secret = 8, Eternal = 9, Divine = 10,
}

local function recordRarity(record)
	if typeof(record) ~= "table" then return "Common" end
	local r = record.Rarity
	if typeof(r) == "string" then return r end
	if typeof(r) == "table" then return r._id or r.DisplayName or "Common" end
	local directory = AssetsData and (AssetsData.Directory or AssetsData)
	local entry = directory and directory[record.AssetCategory or ""]
	local assetRarity = entry and entry.Rarity
	if typeof(assetRarity) == "string" then return assetRarity end
	if typeof(assetRarity) == "table" then return assetRarity._id or assetRarity.DisplayName or "Common" end
	return "Common"
end

local function bestEggScore(record, distance)
	local rarity = recordRarity(record)
	local score = (RARITY_WEIGHT[rarity] or 0) * 100000000
	local mutations = typeof(record.Mutations) == "table" and record.Mutations or {}
	for _, mutation in pairs(mutations) do
		if mutation == "Rainbow" then score = score + 35000000
		elseif mutation == "Gold" or mutation == "Golden" then score = score + 20000000
		elseif mutation == "Silver" then score = score + 10000000
		elseif mutation == "Parasite" or mutation == "Monstrous" then score = score + 800000000
		end
	end
	if record.HasParasite == true or record.BaseMutation == "Parasite" or record.BaseMutation == "Monstrous" then
		score = score + 800000000
	end
	score = score + (tonumber(record.AssetScale) or 1) * 100000
	score = score + (tonumber(record.NestScale) or 1) * 50000
	return score - math.min(distance or 0, 99999), rarity
end

local function bestEggInBiome()
	AreaEggs = ch(Workspace, "Area" .. "Egg" .. "Slots" .. "Client", 3)
	local hrp = getHRP()
	if not hrp then return nil end
	local recs = recordsByUid()
	local best, bestScore, bestRarity, bestRecord
	for uid, rec in pairs(recs) do
		local cf = rec.BoundsCFrame or rec.BottomCFrame
		if rec.State == "Slot" and typeof(cf) == "CFrame" then
			local live = AreaEggs and AreaEggs:FindFirstChild(uid)
			local candidate = live or { Name = uid, Position = cf.Position, Record = rec }
			if eggInSelectedBiome(candidate, rec) then
				local score, rarity = bestEggScore(rec, (cf.Position - hrp.Position).Magnitude)
				if not bestScore or score > bestScore then
					best, bestScore, bestRarity, bestRecord = candidate, score, rarity, rec
				end
			end
		end
	end
	if best then
		local mutations = bestRecord and typeof(bestRecord.Mutations) == "table" and bestRecord.Mutations or {}
		local mutationText = #mutations > 0 and (" + " .. table.concat(mutations, ",")) or ""
		local scale = bestRecord and tonumber(bestRecord.AssetScale) or 1
		lastBestInfo = ("%s · %s · x%.2f%s"):format(
			tostring(bestRecord and bestRecord.AssetCategory or "Egg"), tostring(bestRarity), scale, mutationText
		)
		setStatus("Best " .. lastBestInfo)
		return best
	end
	return nearestEggInBiome()
end

nearestEggInBiome = function()
	-- The game can replace this client folder after a failed pickup. Re-resolve it
	-- on every scan so a stale instance cannot lead to a false "No eggs" state.
	AreaEggs = ch(Workspace, "Area" .. "Egg" .. "Slots" .. "Client", 3)
	local hrp = getHRP()
	if not hrp then return nil end
	local biome = CFG.biomes[CFG.biomeIndex]
	local center = getBiomeCenter(biome) or BIOME_CENTERS[biome]
	local recs = recordsByUid()
	local slotCount = AreaEggs and #AreaEggs:GetChildren() or 0
	local snapCount = 0
	for _ in pairs(recs) do snapCount = snapCount + 1 end
	lastScanInfo = ("slots=%d snap=%d"):format(slotCount, snapCount)
	local best, bestDist
	local fallback, fallbackDist
	if AreaEggs then
		for _, egg in ipairs(AreaEggs:GetChildren()) do
			local rec = recs[egg.Name]
			local pos = eggPos(egg)
			if not pos then
				-- skip
			elseif eggInSelectedBiome(egg, rec) then
				local d = (pos - hrp.Position).Magnitude
				if not bestDist or d < bestDist then
					best, bestDist = egg, d
				end
			elseif center and nearBiomeCenter(pos, biome) then
				local d = (pos - center).Magnitude
				if not fallbackDist or d < fallbackDist then
					fallback, fallbackDist = egg, d
				end
			end
		end
	end
	if best then return best, bestDist end
	-- Last resort: any egg near hard-coded biome X corridor
	if fallback then return fallback, fallbackDist end
	if AreaEggs and center then
		for _, egg in ipairs(AreaEggs:GetChildren()) do
			local pos = eggPos(egg)
			if pos and math.abs(pos.X - center.X) < 280 then
				local d = (pos - hrp.Position).Magnitude
				if not bestDist or d < bestDist then
					best, bestDist = egg, d
				end
			end
		end
	end
	if best then return best, bestDist end

	-- Snapshot fallback: the record is authoritative for UID and position even
	-- while the matching visual slot is absent or temporarily stale on the client.
	for uid, rec in pairs(recs) do
		local cf = rec.BoundsCFrame or rec.BottomCFrame
		if rec.State == "Slot" and typeof(cf) == "CFrame" then
			local live = AreaEggs and AreaEggs:FindFirstChild(uid)
			local candidate = live or { Name = uid, Position = cf.Position, Record = rec }
			if eggInSelectedBiome(candidate, rec) then
				local d = (cf.Position - hrp.Position).Magnitude
				if not bestDist or d < bestDist then
					best, bestDist = candidate, d
				end
			end
		end
	end
	return best, bestDist
end

local function selectFarmEgg()
	if CFG.targetMode == "best" then
		return bestEggInBiome()
	end
	return nearestEggInBiome()
end

local function promptPart(prompt)
	local parent = prompt and prompt.Parent
	while parent and parent ~= Workspace do
		if parent:IsA("BasePart") then return parent end
		parent = parent.Parent
	end
end

local function isAtLiveNest(position)
	if not (AreaEggs and position) then return false end
	-- Prompts are not always parented below their egg model, so hierarchy alone
	-- cannot identify a nest.  A normal egg's prompt is nevertheless at the
	-- exact live slot position; a dropped egg is not.
	for _, slot in ipairs(AreaEggs:GetChildren()) do
		local slotPos = eggPos(slot)
		if slotPos and (slotPos - position).Magnitude <= 12 then
			return true
		end
	end
	return false
end

local function visibleDroppedCandidates(knownUids)
	-- A normal nest egg lives in AreaEggSlotsClient.  The snapshot can briefly
	-- label that slot as Dropped, so never use it for global recovery.  Match the
	-- real world pickup prompt plus its UID outside the slot folder instead.
	local found, anonymous = {}, {}
	for _, prompt in ipairs(Workspace:GetDescendants()) do
		local action = prompt:IsA("ProximityPrompt") and string.lower(tostring(prompt.ActionText or "")) or ""
		local pickupLike = prompt.Name == "CarryAreaEgg"
			or action:find("carry", 1, true) ~= nil
			or action:find("pick", 1, true) ~= nil
			or action:find("grab", 1, true) ~= nil
		if prompt:IsA("ProximityPrompt") and prompt.Enabled and pickupLike then
			local node, holder, uid = prompt, nil, nil
			while node and node ~= Workspace do
				local id = node:GetAttribute("Uid") or node:GetAttribute("EggUid")
				if typeof(id) ~= "string" and knownUids and knownUids[node.Name] then
					id = node.Name
				end
				if typeof(id) == "string" then
					holder, uid = node, id
					break
				end
				node = node.Parent
			end
			local part = (holder and (holder:IsA("BasePart") and holder or holder:FindFirstChildWhichIsA("BasePart", true))) or promptPart(prompt)
			if part and not isAtLiveNest(part.Position) then
				if uid then
					found[uid] = { Name = uid, Position = part.Position, Prompt = prompt }
				else
					table.insert(anonymous, { Name = "", Position = part.Position, Prompt = prompt })
				end
			end
		end
	end
	return found, anonymous
end

-- Recovery mode requires both a Dropped record and a visible, out-of-nest
-- pickup object. Higher zone index wins first; rarity/mutation/size choose
-- between drops in the same zone, then distance breaks a remaining tie.
local function findDroppedEggGlobal()
	AreaEggs = ch(Workspace, "Area" .. "Egg" .. "Slots" .. "Client", 3)
	local hrp = getHRP()
	if not hrp then return nil end
	local recs = recordsByUid()
	local visible, anonymous = visibleDroppedCandidates(recs)
	local best, bestScore, bestZone
	for uid, rec in pairs(recs) do
		if rec.State == "Dropped" then
			local candidate = visible[uid]
			if not candidate then
				continue
			end
			local zoneIndex = 0
			for i, biomeName in ipairs(CFG.biomes) do
				if matchesBiome(rec.AreaId, biomeName) then
					zoneIndex = i
					break
				end
			end
			local eggScore = bestEggScore(rec, (candidate.Position - hrp.Position).Magnitude)
			local score = zoneIndex * 1000000000000 + eggScore
			if not bestScore or score > bestScore then
				best, bestScore, bestZone = candidate, score, zoneIndex
			end
		end
	end
	-- Some dropped objects are intentionally client-only and have no exposed UID.
	-- They are still safe to collect because their own pickup prompt is outside
	-- the nest-slot folder.  Use position to keep the end-of-map-first rule.
	if not best then
		for _, candidate in ipairs(anonymous) do
			local zoneIndex = 0
			for i = #CFG.biomes, 1, -1 do
				local boundsInside = isInsideBiomeBounds(candidate.Position, CFG.biomes[i])
				if boundsInside == true or nearBiomeCenter(candidate.Position, CFG.biomes[i]) then
					zoneIndex = i
					break
				end
			end
			local score = zoneIndex * 1000000000000 - (candidate.Position - hrp.Position).Magnitude
			if not bestScore or score > bestScore then
				best, bestScore, bestZone = candidate, score, zoneIndex
			end
		end
	end
	if best then
		setStatus(("Dropped %d/%d -> reclaim"):format(bestZone, #CFG.biomes))
	else
		setStatus("No visible dropped eggs")
	end
	return best
end

local function findPrompt(egg)
	if typeof(egg) == "Instance" then
		for _, d in ipairs(egg:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d.Enabled then
				return d
			end
		end
	end
	if typeof(egg) == "table" and egg.Prompt and egg.Prompt:IsA("ProximityPrompt") and egg.Prompt.Enabled then
		return egg.Prompt
	end
	-- Oxide: CarryAreaEgg near player
	local hrp = getHRP()
	if not hrp then return nil end
	local best, bestDist
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == "CarryAreaEgg" and d.Enabled then
			local act = string.lower(tostring(d.ActionText or ""))
			if act:find("skip", 1, true) or act:find("robux", 1, true) then
				-- skip
			else
				local p = d.Parent
				if p and p:IsA("Attachment") then p = p.Parent end
				local part = p and (p:IsA("BasePart") and p or p:FindFirstChildWhichIsA("BasePart"))
				if part then
					local dist = (part.Position - hrp.Position).Magnitude
					if dist < 16 and (not bestDist or dist < bestDist) then
						best, bestDist = d, dist
					end
				end
			end
		end
	end
	return best
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
	if not egg then return false end
	if not CarryFn then
		return isActuallyCarrying()
	end
	local uid = egg.Name
	local slotKey
	local rec = recordsByUid()[uid]
	if rec and IsFirstUid and IsFirstUid(uid) and BuildSlotKey then
		pcall(function() slotKey = BuildSlotKey(rec.AreaId, rec.NestId) end)
	end
	if typeof(uid) == "string" and uid ~= "" then
		pcall(function() CarryFn(uid, slotKey) end)
	end
	task.wait()
	if isActuallyCarrying() then
		carrying = true
		lastStealAt = tick()
		return true
	end
	return false
end

local function fireStealPrompt(prompt)
	if not (prompt and prompt.Parent) then return end
	pcall(function() prompt.HoldDuration = 0 end)
	pcall(function() prompt:InputHoldBegin() end)
	if typeof(fireproximityprompt) == "function" then
		pcall(fireproximityprompt, prompt)
		pcall(fireproximityprompt, prompt, 0)
	end
	pcall(function() prompt:InputHoldEnd() end)
end

-- Grab: plant on egg, spam Carry + CarryAreaEgg prompt (Oxide-style)
local function trySteal(egg)
	local pos = eggPos(egg)
	local root = getHRP()
	if not root or not pos then return false end

	local targetY = groundedY(pos.X, pos.Z, pos.Y)
	anchor(root, CFrame.new(pos.X, targetY, pos.Z))
	task.wait(0.12)
	root = getHRP()
	if root then
		anchor(root, CFrame.new(pos.X, targetY, pos.Z))
	end

	setStatus("Grab spam")
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
		prompt = prompt or findPrompt(egg)
		fireStealPrompt(prompt)
		if isActuallyCarrying() then
			carrying = true
			lastEggUid = egg.Name
			lastEggPos = pos
			lastStealAt = tick()
			setStatus("Stolen->GO")
			return true
		end
		RunService.Heartbeat:Wait()
	end

	if isActuallyCarrying() then
		carrying = true
		lastEggUid = egg.Name
		lastEggPos = pos
		lastStealAt = tick()
		setStatus("Stolen->GO")
		return true
	end

	setStatus("Miss (no carry)")
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
	return Vector3.new(464.7, 68.2, -364.0)
end

local function isInPlot()
	if not InPlot then return false end
	local hrp = getHRP()
	if not hrp then return false end
	local ok, inside = pcall(function() return InPlot(hrp.Position) end)
	return ok and inside == true
end

-- Oxide PlantEgg — without this server often rejects delivery and returns egg to nest
local function plantCarriedEggs()
	if not PlantEggFn then return 0 end
	local uids = {}
	local function collect(container)
		if not container then return end
		for _, t in ipairs(container:GetChildren()) do
			if t:IsA("Tool") then
				local uid = t:GetAttribute("Uid") or t:GetAttribute("EggUid")
				if typeof(uid) ~= "string" then
					local n = t.Name:lower()
					if n:find("egg", 1, true) then
						uid = t.Name
					end
				end
				if typeof(uid) == "string" then
					table.insert(uids, uid)
				end
			end
		end
	end
	collect(getChar())
	collect(LP:FindFirstChild("Backpack"))
	local planted = 0
	for _, eggUid in ipairs(uids) do
		for _ = 1, 3 do
			local offset = CFrame.new(math.random(-6, 6), 0, math.random(-6, 6))
			local ok, res = pcall(function()
				return PlantEggFn(eggUid, offset)
			end)
			if ok and res then
				planted = planted + 1
				break
			end
			task.wait(0.1)
		end
	end
	return planted
end

local function plotPlacementCFrames()
	if not GetPlot then return {} end
	local ok, plot = pcall(GetPlot)
	if not ok or not plot or not plot.PetArea or not plot.CenterPoint then return {} end
	local area, center = plot.PetArea, plot.CenterPoint
	local result = {}
	for x = -area.Size.X * 0.5 + 5, area.Size.X * 0.5 - 5, 7 do
		for z = -area.Size.Z * 0.5 + 5, area.Size.Z * 0.5 - 5, 7 do
			local world = area.CFrame:PointToWorldSpace(Vector3.new(x, 1, z))
			table.insert(result, center.CFrame:ToObjectSpace(CFrame.new(world)))
		end
	end
	return result
end

local function autoPlantOwnedEggs()
	if not PlantEggFn or not WearEggToolFn or not isInPlot() or isActuallyCarrying() then return 0 end
	local save = getSave()
	local inventory = save and save.EggInventory
	if typeof(inventory) ~= "table" then return 0 end
	local positions = plotPlacementCFrames()
	if #positions == 0 then return 0 end
	local planted, index = 0, 1
	for uid, egg in pairs(inventory) do
		if typeof(uid) == "string" and typeof(egg) == "table" and egg.Placement == nil and not egg.Locked then
			pcall(WearEggToolFn, uid)
			task.wait(0.12)
			local ok, result = pcall(PlantEggFn, uid, positions[index])
			if ok and result == true then
				planted += 1
				index = index % #positions + 1
				task.wait(0.22)
			end
		end
	end
	return planted
end

local function autoHatchReadyEggs()
	if not IsEggReadyFn or not BeginHatchFn or not FinishHatchFn or isActuallyCarrying() then return 0 end
	local save = getSave()
	local inventory = save and save.EggInventory
	if typeof(inventory) ~= "table" then return 0 end
	local count = 0
	for uid, egg in pairs(inventory) do
		if typeof(uid) == "string" and typeof(egg) == "table" and egg.Placement ~= nil then
			local ready = false
			pcall(function() ready = IsEggReadyFn(uid) == true end)
			if not ready then pcall(function() ready = IsEggReadyFn(egg) == true end) end
			if ready then
				local started = false
				pcall(function() started = BeginHatchFn(uid) == true end)
				if started then
					task.wait(0.08)
					pcall(FinishHatchFn, uid)
					count += 1
					task.wait(0.3)
				end
			end
		end
	end
	return count
end

local function runAutoActions()
	if autoActionsBusy then return end
	autoActionsBusy = true
	task.spawn(function()
		while autoActions.plant or autoActions.hatch or autoActions.equip do
			bindGame()
			if autoActions.plant then
				local n = autoPlantOwnedEggs()
				if n > 0 then setStatus("Auto planted " .. tostring(n)) end
			end
			if autoActions.hatch then
				local n = autoHatchReadyEggs()
				if n > 0 then setStatus("Auto hatched " .. tostring(n)) end
			end
			if autoActions.equip and EquipBestPetsRemote then invokeRemote(EquipBestPetsRemote) end
			task.wait(3.0)
		end
		autoActionsBusy = false
	end)
end

local function returnToBase(speed, opts)
	local base = getBasePos()
	local hrp = getHRP()
	if not base or not hrp then return false end
	opts = opts or { requireCarry = true, elevated = true }
	-- Oxide: stage then slow final approach so deliver handshake lands
	local dist = (hrp.Position - base).Magnitude
	if dist > 55 and (speed or 0) > 260 then
		local toBase = base - hrp.Position
		local stage = base - toBase.Unit * 35
		stage = Vector3.new(stage.X, math.max(stage.Y, getLaneY()), stage.Z)
		if not stealAlong(buildStealPath(hrp.Position, stage), speed, opts) then
			if not isActuallyCarrying() then return false end
		end
		hrp = getHRP()
		if not hrp then return false end
		task.wait(0.25)
		return stealAlong(buildStealPath(hrp.Position, base), math.min(speed, 240), opts)
	end
	return stealAlong(buildStealPath(hrp.Position, base), speed, opts)
end

-- The game's streamed area and its movement lane are not reliable while the
-- player is still inside their plot.  Leave the base first, without selecting
-- an egg, so every farm mode can scan and travel immediately afterwards.
local function leaveBaseForFarm()
	local hrp = getHRP()
	local base = getBasePos()
	if not (hrp and base) then return false end
	local atBase = isInPlot() or (hrp.Position - base).Magnitude <= 85
	if not atBase then return true end
	local forest = getBiomeCenter("Forest") or BIOME_CENTERS.Forest
	if not forest then return true end
	setStatus("Leave base -> Forest")
	return stealAlong(buildStealPath(hrp.Position, forest), CFG.approachSpeed)
end

local function findEggByUid(uid)
	if not uid then return nil end
	AreaEggs = AreaEggs or ch(Workspace, "Area" .. "Egg" .. "Slots" .. "Client", 1)
	if not AreaEggs then return nil end
	return AreaEggs:FindFirstChild(uid)
end

local function findReclaimEgg()
	AreaEggs = ch(Workspace, "Area" .. "Egg" .. "Slots" .. "Client", 2)
	local hrp = getHRP()
	if not hrp then return nil end
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

	if AreaEggs then
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
	end
	-- A knocked egg can be visible in the snapshot before its client model arrives.
	for uid, rec in pairs(recs) do
		local cf = rec.BoundsCFrame or rec.BottomCFrame
		if rec.State == "Dropped" and typeof(cf) == "CFrame" then
			local live = AreaEggs and AreaEggs:FindFirstChild(uid)
			consider(live or { Name = uid, Position = cf.Position, Record = rec }, uid == lastEggUid and 4 or 2)
		end
	end
	-- State replication can lag after an impact. If the original dropped UID has
	-- not appeared yet, take the nearest live egg in the immediate recovery area.
	if not best and AreaEggs then
		for _, egg in ipairs(AreaEggs:GetChildren()) do
			local pos = eggPos(egg)
			if pos and (pos - hrp.Position).Magnitude <= 85 then
				consider(egg, 1)
			end
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

-- Proven V18 guard sequence: wait for stand → guard cooldown → full regrab.
-- keepGoing: only for manual WS/Fly validate; farm uses autoFarm.
local function guardHitThenRegrab(egg, keepGoing)
	if not CFG.guardHit then return isActuallyCarrying() end
	if not egg then return isActuallyCarrying() end
	local pos = eggPos(egg)
	if not pos then return isActuallyCarrying() end
	local alive = keepGoing or function()
		return autoFarm
	end

	setStatus("Guard-hit wait")
	local hum0 = getHum()
	local startHealth = hum0 and hum0.Health or 100
	local wasHit = false
	local t0 = tick()
	while tick() - t0 < 4.0 and alive() do
		if not isActuallyCarrying() then
			wasHit = true
			break
		end
		local h = getHum()
		if h then
			local st = h:GetState()
			if h.Health < startHealth - 1.5
				or st == Enum.HumanoidStateType.Physics
				or st == Enum.HumanoidStateType.Ragdoll
				or st == Enum.HumanoidStateType.FallingDown then
				wasHit = true
				local tPost = tick()
				while tick() - tPost < 0.85 and alive() do
					if not isActuallyCarrying() then break end
					task.wait(0.05)
				end
				break
			end
		end
		task.wait(0.05)
	end

	if not wasHit and isActuallyCarrying() then
		setStatus("No hit->GO")
		return true
	end

	task.wait(0.55)
	setStatus("Stand")
	local tStand = tick()
	while tick() - tStand < 3.0 and alive() do
		if not isDowned() then break end
		recoverStand()
		task.wait(0.12)
	end
	recoverStand()
	task.wait(0.35)

	local hrp = getHRP()
	if hrp and (hrp.Position - pos).Magnitude > 14 then
		local y = groundedY(pos.X, pos.Z, pos.Y)
		anchor(hrp, CFrame.new(pos.X, y, pos.Z))
		task.wait(0.3)
	end

	setStatus("Guard sleep")
	task.wait(1.4)

	setStatus("Regrab")
	if isActuallyCarrying() then
		carrying = true
		return true
	end
	local reclaim = findEggByUid(egg.Name) or egg
	if trySteal(reclaim) then
		return true
	end
	reclaim = findReclaimEgg() or findEggByUid(lastEggUid) or reclaim
	if reclaim and approachAndSteal(reclaim, CFG.approachSpeed) then
		return true
	end
	return isActuallyCarrying()
end

local function findNearestFieldEgg(maxDist)
	AreaEggs = AreaEggs or ch(Workspace, "Area" .. "Egg" .. "Slots" .. "Client", 1)
	local hrp = getHRP()
	if not AreaEggs or not hrp then return nil end
	maxDist = maxDist or 45
	local best, bestD
	for _, egg in ipairs(AreaEggs:GetChildren()) do
		local pos = eggPos(egg)
		if pos then
			local d = (pos - hrp.Position).Magnitude
			if d <= maxDist and (not bestD or d < bestD) then
				best, bestD = egg, d
			end
		end
	end
	return best
end

-- Manual WS/Fly: Oxide delivery fix without Auto Farm
-- On pickup → pause move → guard-hit regrab → then PlantEgg spam in plot
local function cancelManualDeliverAssist()
	freezeMoveForValidate = false
	deliverAssistBusy = false
	stealValidated = false
end

local function cheatMoveActive()
	return (walkSpeedOn or flyOn) and not autoFarm
end

local function runManualStealValidate()
	if deliverAssistBusy or autoFarm then return end
	if not cheatMoveActive() then return end
	deliverAssistBusy = true
	freezeMoveForValidate = true
	task.spawn(function()
		if autoFarm then
			cancelManualDeliverAssist()
			return
		end
		bindGame()
		patchRigSyncKnockback()
		local egg = findEggByUid(lastEggUid) or findNearestFieldEgg(50) or findReclaimEgg()
		if egg and not autoFarm then
			lastEggUid = egg.Name
			local pos = eggPos(egg)
			if pos then lastEggPos = pos end
			setStatus("Validate steal (guard-hit)")
			local ok = guardHitThenRegrab(egg, function()
				-- Stop the moment Auto Farm takes over — never fight farmOnce
				return (not autoFarm) and (cheatMoveActive() or isActuallyCarrying())
			end)
			if autoFarm then
				cancelManualDeliverAssist()
				return
			end
			stealValidated = ok and isActuallyCarrying()
			if stealValidated then
				setStatus("Steal OK — run to base")
			else
				setStatus("Validate weak — PlantEgg on base")
			end
		elseif not autoFarm then
			stealValidated = isActuallyCarrying()
			setStatus("No nest egg — PlantEgg on base")
		end
		freezeMoveForValidate = false
		deliverAssistBusy = false
	end)
end

local function ensureDeliverAssist()
	if deliverAssistConn then return end
	-- Manual WS/Fly: PlantEgg only when in plot.
	-- Do NOT auto-run guardHitThenRegrab here — freezes movement + steals control from LO.
	-- (Autofarm already owns full guard-hit → peel path. Leave it alone.)
	deliverAssistConn = RunService.Heartbeat:Connect(function()
		if autoFarm then
			if freezeMoveForValidate or deliverAssistBusy then
				cancelManualDeliverAssist()
			end
			wasCarryingEdge = isActuallyCarrying()
			return
		end
		if not (walkSpeedOn or flyOn) then
			wasCarryingEdge = isActuallyCarrying()
			return
		end

		local carryingNow = isActuallyCarrying()
		if carryingNow and not wasCarryingEdge then
			carrying = true
			setStatus("Carrying — bank in plot (PlantEgg)")
		elseif not carryingNow and wasCarryingEdge then
			carrying = false
		end
		wasCarryingEdge = carryingNow

		if carryingNow and isInPlot() then
			local n = plantCarriedEggs()
			if n > 0 then
				setStatus("Planted " .. tostring(n))
				carrying = false
			end
		end
	end)
	table.insert(connections, deliverAssistConn)
end

local function peelThenEscape(reclaimDepth, strictUid)
	local hrp = getHRP()
	if not hrp then return false end
	setStatus("Peel")
	-- Lift before the first horizontal step: Titan's follow-up attack is ground
	-- based, and waiting for the movement loop leaves one exposed frame.
	local liftY = groundedY(hrp.Position.X, hrp.Position.Z, hrp.Position.Y) + (CFG.escapeHeight or 10)
	anchor(hrp, CFrame.new(hrp.Position.X, liftY, hrp.Position.Z))
	local peelOk = stealMoveTo(hrp.Position.X, getLaneZ(), CFG.escapeSpeed, {
		requireCarry = true,
		elevated = true,
	})
	if not peelOk and not isActuallyCarrying() then
		carrying = false
		setStatus("Egg lost")
		if not strictUid and (reclaimDepth or 0) < 1 then
			local dropped = findReclaimEgg()
			if dropped then
				setStatus("Drop -> reclaim")
				if approachAndSteal(dropped, CFG.approachSpeed) then
					return peelThenEscape((reclaimDepth or 0) + 1, strictUid)
				end
			end
		end
		return false
	end

	setStatus("Escape")
	local escaped = returnToBase(CFG.escapeSpeed, { requireCarry = true, elevated = true })
	if not escaped and not isActuallyCarrying() then
		carrying = false
		setStatus("Egg lost")
		if not strictUid and (reclaimDepth or 0) < 1 then
			local dropped = findReclaimEgg()
			if dropped then
				setStatus("Drop -> reclaim")
				if approachAndSteal(dropped, CFG.approachSpeed) then
					return peelThenEscape((reclaimDepth or 0) + 1, strictUid)
				end
			end
		end
		return false
	end
	return escaped ~= false or isActuallyCarrying() or isInPlot()
end

local function carriedEggValue(plr, records)
	local char = plr and plr.Character
	if not char then return 0 end
	records = records or recordsByUid()
	for _, item in ipairs(char:GetChildren()) do
		if item:IsA("Tool") or item:IsA("Model") then
			local uid = item:GetAttribute("Uid") or item:GetAttribute("EggUid")
			local record = typeof(uid) == "string" and records[uid] or nil
			if not record then
				local name = item.Name:lower()
				if name:find("egg", 1, true) or name:find("carry", 1, true) then
					record = {
					Rarity = item:GetAttribute("Rarity"),
					AssetCategory = item:GetAttribute("AssetCategory") or item.Name,
					AssetScale = item:GetAttribute("AssetScale") or item:GetAttribute("Scale"),
				}
				end
			end
			if record then return bestEggScore(record, 0), recordRarity(record) end
		end
	end
	-- When the egg visual is not parented to the target's character, retain
	-- the rarity from the globally replicated carrier record for prioritising.
	for _, record in pairs(records) do
		if recordBelongsToPlayer(record, plr) then
			return bestEggScore(record, 0), recordRarity(record)
		end
	end
	return 0, "Common"
end

-- The UID is the identity check that prevents an aura hit from turning into a
-- pickup of a different field egg near the target.
local function carriedEggUid(plr, records)
	local char = plr and plr.Character
	if char then
		for _, item in ipairs(char:GetChildren()) do
			if item:IsA("Tool") or item:IsA("Model") then
				local uid = item:GetAttribute("Uid") or item:GetAttribute("EggUid")
				if typeof(uid) == "string" then return uid end
			end
		end
	end
	for uid, record in pairs(records or {}) do
		if recordIsActivelyCarried(record) and recordBelongsToPlayer(record, plr) then return uid end
	end
	return nil
end

local function nearestEggCarrier()
	local hrp = getHRP()
	if not hrp then return nil end
	local records = recordsByUid()
	local pickupEvents = recentSlotPickups()
	local worldCarriers = visibleWorldCarriers()
	local best, bestDist, bestValue, bestRarity, bestUid, bestExpires
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local pickup = pickupEvents[plr]
		local repickUid, repickSession
		if root then
			for uid, session in pairs(CarrierState.eggs) do
				if session.dropSeenAt and tick() - session.dropSeenAt <= 3
					and session.lastPos and (root.Position - session.lastPos).Magnitude <= 35 then
					repickUid, repickSession = uid, session
					break
				end
			end
		end
		local confirmed = (pickup and pickup.expires > tick()) or repickUid
		if root and (confirmed or (isInsideAnyEggField(root.Position) and isNearLiveFieldEgg(root.Position)
			and playerIsCarryingEgg(plr, records, worldCarriers))) then
			local dist = (root.Position - hrp.Position).Magnitude
			local value, rarity = carriedEggValue(plr, records)
			if not bestValue or value > bestValue or (value == bestValue and dist < bestDist) then
				best, bestDist, bestValue, bestRarity = plr, dist, value, rarity
				bestUid = (pickup and pickup.uid) or repickUid or carriedEggUid(plr, records)
				bestExpires = pickup and pickup.expires or (repickSession and tick() + 5) or nil
			end
		end
	end
	return best, bestRarity, bestUid, bestExpires
end

local function findBatTool()
	local function scan(container)
		if not container then return nil end
		for _, item in ipairs(container:GetChildren()) do
			if item:IsA("Tool") then
				local name = item.Name:lower()
				if name:find("bat", 1, true) or name:find("club", 1, true) then return item end
			end
		end
	end
	return scan(getChar()) or scan(LP:FindFirstChild("Backpack"))
end

local function findDroppedNear(position, radius, expectedUid)
	local recs = recordsByUid()
	if expectedUid then
		local visible = visibleDroppedCandidates(recs)
		-- The pickup prompt becomes visible before the state snapshot is always
		-- updated after a guard hit, so the visible UID is the trusted signal.
		local candidate = visible[expectedUid]
		if candidate and (candidate.Position - position).Magnitude <= radius then return candidate end
		return nil
	end
	local visible, anonymous = visibleDroppedCandidates(recs)
	local best, bestDist
	local function consider(candidate)
		local d = (candidate.Position - position).Magnitude
		if d <= radius and (not bestDist or d < bestDist) then best, bestDist = candidate, d end
	end
	for uid, rec in pairs(recs) do
		if rec.State == "Dropped" and visible[uid] then consider(visible[uid]) end
	end
	for _, candidate in ipairs(anonymous) do consider(candidate) end
	return best
end

local function interceptCarrierOnce()
	local trackedDrop, trackedUid
	local now = tick()
	for uid, session in pairs(CarrierState.eggs) do
		if session.lastPos and session.expires > now then
			local candidate = findDroppedNear(session.lastPos, 90, uid)
			if candidate then
				session.lastPos, session.dropSeenAt = candidate.Position, now
				trackedDrop, trackedUid = candidate, uid
				break
			end
		end
	end
	if trackedDrop then
		setStatus("Recover tracked egg")
		if approachAndSteal(trackedDrop, CFG.approachSpeed) then
			return peelThenEscape(0, trackedUid or true)
		end
	end
	local target, rarity, carriedUid, trackedUntil = nearestEggCarrier()
	if not target then setStatus("No egg carrier"); task.wait(0.6); return false end
	local bat = findBatTool()
	if not bat then setStatus("Bat not equipped"); task.wait(0.8); return false end
	local hum = getHum()
	if hum then pcall(function() hum:EquipTool(bat) end) end
	local root = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	local me = getHRP()
	if not (root and me) then return false end
	if carriedUid then
		CarrierState.eggs[carriedUid] = CarrierState.eggs[carriedUid] or {}
		CarrierState.eggs[carriedUid].carrier = target
		CarrierState.eggs[carriedUid].lastPos = root.Position
		CarrierState.eggs[carriedUid].expires = tick() + 30
	end
	setStatus("Track " .. target.DisplayName .. " · " .. tostring(rarity))
	-- Stay just behind the carrier rather than chasing the position they occupied
	-- a frame ago.  Velocity is preferred while they run; look direction keeps the
	-- position stable when they stop briefly.  There is deliberately no initial
	-- waypoint path: every move is immediately re-aimed at the live target.
	local carrierLost = false
	local dropped, swingAt = nil, nil
	for _ = 1, 600 do
		if not autoFarm then
			stopAuraFollowMotion()
			return false
		end
		root = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
		local now = tick()
		local keepTracking = trackedUntil and now < trackedUntil
		local liveRecords = keepTracking and nil or recordsByUid()
		local liveWorldCarriers = keepTracking and nil or visibleWorldCarriers()
		if not root or (not keepTracking and not playerIsCarryingEgg(target, liveRecords, liveWorldCarriers)) then
			carrierLost = true
			break
		end
		if carriedUid and CarrierState.eggs[carriedUid] then
			CarrierState.eggs[carriedUid].carrier = target
			CarrierState.eggs[carriedUid].lastPos = root.Position
			CarrierState.eggs[carriedUid].expires = tick() + 30
		end
		me = getHRP()
		if me then
			local velocity = root.AssemblyLinearVelocity
			local planarVelocity = Vector3.new(velocity.X, 0, velocity.Z)
			local heading = planarVelocity.Magnitude > 2
				and planarVelocity.Unit
				or Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			if heading.Magnitude < 0.01 then heading = Vector3.new(0, 0, -1) end
			local followPos = root.Position - heading.Unit * CFG.carrierFollowDistance
			chaseCarrierStep(followPos, CFG.escapeSpeed)
		else
			RunService.Heartbeat:Wait()
		end
		me = getHRP()
		if me and (root.Position - me.Position).Magnitude <= 20 then
			setStatus("Bat aura · " .. target.DisplayName)
			pcall(function() bat:Activate() end)
			swingAt = swingAt or tick()
		end
		-- Do not wait for the temporary carrier event to expire.  Once a swing
		-- has had time to land, Recovery can see the spawned drop immediately.
		if swingAt and tick() - swingAt >= 0.22 then
			dropped = carriedUid and findDroppedNear(root.Position, 45, carriedUid) or nil
			if not dropped then dropped = findDroppedNear(root.Position, 30) end
			if dropped then
				if carriedUid and CarrierState.eggs[carriedUid] then
					CarrierState.eggs[carriedUid].lastPos = dropped.Position
					CarrierState.eggs[carriedUid].dropSeenAt = tick()
				end
				break
			end
		end
	end
	stopAuraFollowMotion()
	if not dropped and not carrierLost then return false end
	local finalRoot = getHRP()
	local dropPos = root and root.Position or (finalRoot and finalRoot.Position)
	if not dropPos then return false end
	local untilT = tick() + 3.0
	while not dropped and tick() < untilT and autoFarm do
		-- Never fall back to a generic field/reclaim search in carrier mode.
		-- If the carrier's UID is not visible, doing nothing is safer than
		-- stealing a different egg.
		dropped = carriedUid and findDroppedNear(dropPos, 45, carriedUid) or nil
		-- Recovery's visible-drop scan is the fallback only after the tracked
		-- carrier has actually lost the egg, and only at that carrier's last spot.
		if not dropped then dropped = findDroppedNear(dropPos, 30) end
		if dropped then break end
		task.wait(0.1)
	end
	if not dropped then setStatus("Carrier drop not found"); return false end
	setStatus("Take carrier drop")
	if not approachAndSteal(dropped, CFG.approachSpeed) then return false end
	-- Carrier mode must not switch to the generic reclaim path after its own
	-- verified drop has been picked up.
	return peelThenEscape(0, carriedUid or true)
end

local function resetFarmAttempt()
	carrying = false
	setStatus("Reset 4")
	local untilT = tick() + (CFG.retryRecoveryWait or 4.0)
	while tick() < untilT and autoFarm do
		recoverStand()
		task.wait(0.12)
	end
	recoverStand()
end

local function farmOnce()
	patchRigSyncKnockback()
	swapStealHumanoid()
	refreshCarry()

	if carrying then
		peelThenEscape()
		local untilT = tick() + CFG.baseWait
		while tick() < untilT and autoFarm do
			if isInPlot() then
				plantCarriedEggs()
				if not carrying then break end
			end
			if not carrying then break end
			refreshCarry()
			RunService.Heartbeat:Wait()
		end
		if isInPlot() then plantCarriedEggs() end
		carrying = false
		return
	end

	if CFG.targetMode == "carrier" then
		interceptCarrierOnce()
		return
	end

	if not leaveBaseForFarm() then
		setStatus("Base exit abort")
		return
	end

	local biome = CFG.biomes[CFG.biomeIndex]
	local egg
	if CFG.targetMode == "dropped" then
		egg = findDroppedEggGlobal()
		if not egg then
			setStatus("No dropped eggs — rescan")
			AreaEggs = nil
			task.wait(1.0)
			return
		end
	else
		local center = getBiomeCenter(biome)
		local hrp = getHRP()
		if center and hrp and (hrp.Position - center).Magnitude > 120 then
			setStatus("To " .. biome)
			if not stealAlong(buildStealPath(hrp.Position, center), CFG.approachSpeed) then
				setStatus("Move abort")
				return
			end
		end
		egg = selectFarmEgg()
		if not egg then
			-- Treat an empty client scan as transient: the slot list may still be
			-- syncing after a failed steal. Never stop the farm on this condition.
			setStatus("Rescan " .. biome .. " " .. lastScanInfo)
			AreaEggs = nil
			task.wait(1.0)
			return
		end
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
		setStatus("Miss -> reset")
		lastEggUid, lastEggPos = nil, nil
		AreaEggs = nil
		resetFarmAttempt()
		return
	end

	-- A failed regrab or escape must not immediately retry inside the guard zone.
	-- Reset first, then re-approach the egg and run the full guard sequence again.
	local escaped = false
	local attemptEgg = egg
	for attempt = 1, (CFG.retryAttempts or 3) do
		if attempt > 1 then
			resetFarmAttempt()
			if not autoFarm then return end
			attemptEgg = findReclaimEgg() or findEggByUid(lastEggUid) or selectFarmEgg()
			if not attemptEgg or not approachAndSteal(attemptEgg, CFG.approachSpeed) then
				setStatus("Retry miss " .. tostring(attempt))
				continue
			end
		end

		-- A ground drop has already left its nest: do not wait for a new guard
		-- hit.  Carry it straight into the existing immediate-escape path.
		if (CFG.targetMode == "dropped" or guardHitThenRegrab(attemptEgg)) and isActuallyCarrying() then
			if peelThenEscape() then
				escaped = true
				break
			end
		end
		carrying = false
	end
	if not escaped then
		setStatus("Lost -> reset")
		lastEggUid, lastEggPos = nil, nil
		AreaEggs = nil
		resetFarmAttempt()
		return
	end

	setStatus("Bank")
	local bankUntil = tick() + CFG.baseWait + 2
	while tick() < bankUntil and autoFarm do
		refreshCarry()
		if isInPlot() then
			local n = plantCarriedEggs()
			if n > 0 then
				setStatus("Planted " .. tostring(n))
			end
			if not carrying then break end
		end
		if not carrying then break end
		RunService.Heartbeat:Wait()
	end
	if isInPlot() then
		plantCarriedEggs()
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
		if p.anchor then p.anchor:Destroy() end
	end
	table.clear(espMap)
	if espFolder then
		espFolder:Destroy()
		espFolder = nil
	end
end

local function ensureEspFolder()
	if espFolder and espFolder.Parent then return espFolder end
	espFolder = Instance.new("Folder")
	espFolder.Name = "G_" .. tostring(math.random(100000, 999999))
	protectInstance(espFolder)
	espFolder.Parent = resolveHiddenParent() or game:GetService("CoreGui")
	return espFolder
end

local function ensureEspEntry(key, color, fillTransparency)
	local pack = espMap[key]
	if pack and pack.hl and pack.hl.Parent then
		if color then
			pack.hl.FillColor = color
			pack.hl.OutlineColor = Color3.new(1, 1, 1)
		end
		return pack
	end
	local folder = ensureEspFolder()
	local hl = Instance.new("Highlight")
	hl.FillColor = color or Color3.fromRGB(255, 70, 70)
	hl.OutlineColor = Color3.fromRGB(255, 255, 255)
	hl.FillTransparency = fillTransparency or 0.55
	hl.OutlineTransparency = 0.1
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = folder
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 160, 0, 40)
	bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 2500
	bb.Parent = folder
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.35
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.Text = ""
	label.Parent = bb
	pack = { hl = hl, bb = bb, label = label }
	espMap[key] = pack
	return pack
end

local function espAnyOn()
	return espFlags.players or espFlags.eggs or espFlags.beasts
end

local function updatePlayerEsp(me, seen)
	if not espFlags.players then return end
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP then
			local key = "p_" .. plr.UserId
			seen[key] = true
			local char = plr.Character
			local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
			local pack = ensureEspEntry(key, Color3.fromRGB(120, 190, 255), 0.5)
			if char and head and pack then
				pack.hl.Adornee = char
				pack.bb.Adornee = head
				local dist = me and math.floor((head.Position - me.Position).Magnitude) or 0
				pack.label.Text = ("%s  ·  %dm"):format(plr.DisplayName, dist)
			end
		end
	end
end

local function updateEggEsp(me, seen)
	if not espFlags.eggs then return end
	AreaEggs = AreaEggs or ch(Workspace, "Area" .. "Egg" .. "Slots" .. "Client", 0)
	local recs = recordsByUid()
	local function markEgg(uid, pos, label, color, adornee)
		local key = "e_" .. tostring(uid)
		seen[key] = true
		local pack = ensureEspEntry(key, color, 0.45)
		if pack then
			if adornee then
				pack.hl.Adornee = adornee
				pack.bb.Adornee = adornee:IsA("BasePart") and adornee
					or adornee:FindFirstChild("Hitbox")
					or adornee:FindFirstChildWhichIsA("BasePart", true)
					or adornee
			end
			if pack.bb.Adornee == nil and pos then
				-- floating anchor if no part
				if not pack.anchor or not pack.anchor.Parent then
					local a = Instance.new("Part")
					a.Name = "ea"
					a.Size = Vector3.new(0.2, 0.2, 0.2)
					a.Transparency = 1
					a.Anchored = true
					a.CanCollide = false
					a.CanQuery = false
					a.Parent = ensureEspFolder()
					pack.anchor = a
				end
				pack.anchor.CFrame = CFrame.new(pos)
				pack.bb.Adornee = pack.anchor
				pack.hl.Adornee = pack.anchor
			end
			local dist = me and math.floor((pos - me.Position).Magnitude) or 0
			pack.label.Text = ("%s  ·  %dm"):format(label, dist)
		end
	end

	if AreaEggs then
		for _, egg in ipairs(AreaEggs:GetChildren()) do
			local pos = eggPos(egg)
			if pos and (not me or (pos - me.Position).Magnitude < 2200) then
				local rec = recs[egg.Name]
				local name = (rec and (rec.AssetCategory or rec.AreaId)) or "Egg"
				local rare = rec and typeof(rec.Mutations) == "table" and #rec.Mutations > 0
				local col = rare and Color3.fromRGB(255, 80, 220) or Color3.fromRGB(255, 200, 60)
				markEgg(egg.Name, pos, tostring(name), col, egg)
			end
		end
	end

	-- Snapshot fallback (Boblo-style) when client slots empty/stale
	if SnapshotFn then
		pcall(function()
			if SyncSnapshot then SyncSnapshot() end
			local snap = SnapshotFn()
			if typeof(snap) ~= "table" or typeof(snap.Records) ~= "table" then return end
			for _, rec in pairs(snap.Records) do
				if typeof(rec) == "table" and rec.Uid and (rec.State == "Slot" or rec.State == "Dropped") then
					local cf = rec.BoundsCFrame or rec.BottomCFrame
					if typeof(cf) == "CFrame" then
						local pos = cf.Position
						if not me or (pos - me.Position).Magnitude < 2200 then
							local rare = typeof(rec.Mutations) == "table" and #rec.Mutations > 0
							local col = rare and Color3.fromRGB(255, 80, 220) or Color3.fromRGB(255, 200, 60)
							local label = tostring(rec.AssetCategory or "Egg")
							if rec.State == "Dropped" then label = label .. " [drop]" end
							markEgg(rec.Uid, pos, label, col, AreaEggs and AreaEggs:FindFirstChild(rec.Uid))
						end
					end
				end
			end
		end)
	end
end

local function looksLikeBeast(inst)
	if not inst or not inst:IsA("Model") then return false end
	if Players:GetPlayerFromCharacter(inst) then return false end
	local n = string.lower(inst.Name)
	-- Guards are a separate game mechanic, never an event beast.
	if n:find("guard", 1, true) or inst:GetAttribute("GuardState") ~= nil then return false end
	if n:find("beast", 1, true) or n:find("boss", 1, true) or n:find("monster", 1, true) then return true end
	if n:find("parasite", 1, true) or n:find("dragon", 1, true) or n:find("night", 1, true) then return true end
	if inst:GetAttribute("IsMonster") or inst:GetAttribute("IsBeast") or inst:GetAttribute("EventBoss") then
		return true
	end
	return false
end

local function beastRoot(model)
	return model.PrimaryPart
		or model:FindFirstChild("HumanoidRootPart")
		or model:FindFirstChild("Head")
		or model:FindFirstChildWhichIsA("BasePart", true)
end

local function updateBeastEsp(me, seen)
	if not espFlags.beasts then return end

	local function consider(model)
		if not looksLikeBeast(model) then return end
		local root = beastRoot(model)
		if not root then return end
		local pos = root.Position
		if me and (pos - me.Position).Magnitude > 2500 then return end
		local key = "b_" .. model:GetFullName()
		seen[key] = true
		local pack = ensureEspEntry(key, Color3.fromRGB(255, 90, 50), 0.4)
		pack.hl.Adornee = model
		pack.bb.Adornee = root
		local dist = me and math.floor((pos - me.Position).Magnitude) or 0
		pack.label.Text = ("Beast: %s  ·  %dm"):format(model.Name, dist)
	end

	-- Night/event folders can nest their spawned beast models one or more levels deep.
	local roots = {
		Workspace:FindFirstChild("MonsterParasiteMonsters"),
		Workspace:FindFirstChild("__OBJECTS"),
		Workspace:FindFirstChild("__DEBRIS"),
		Workspace:FindFirstChild("Events"),
		Workspace:FindFirstChild("NightEvent"),
		Workspace,
	}
	for _, root in ipairs(roots) do
		if root then
			for _, m in ipairs(root:GetChildren()) do
				if m:IsA("Model") then consider(m) end
			end
			if root ~= Workspace then
				for _, m in ipairs(root:GetDescendants()) do
					if m:IsA("Model") then consider(m) end
				end
			end
		end
	end
end

local function updateEsp()
	if not espAnyOn() then return end
	local me = getHRP()
	local seen = {}
	updatePlayerEsp(me, seen)
	updateEggEsp(me, seen)
	updateBeastEsp(me, seen)
	for key, pack in pairs(espMap) do
		if not seen[key] then
			if pack.hl then pack.hl:Destroy() end
			if pack.bb then pack.bb:Destroy() end
			if pack.anchor then pack.anchor:Destroy() end
			espMap[key] = nil
		end
	end
end

local function ensureEspLoop()
	if espAnyOn() then
		if not espConn then
			espConn = RunService.RenderStepped:Connect(updateEsp)
			table.insert(connections, espConn)
		end
		updateEsp()
	else
		if espConn then
			pcall(function() espConn:Disconnect() end)
			espConn = nil
		end
		clearEsp()
	end
end

-- Oxide-style client AC: Evidence scrub + WalkSpeed signal kill
-- (Foxname/Fn is Luraph — same class of bypass lives readable in Oxide)
local function disableSignalConns(signal)
	if typeof(getconnections) ~= "function" or not signal then return 0 end
	local n = 0
	local ok, list = pcall(getconnections, signal)
	if not ok or type(list) ~= "table" then return 0 end
	for _, c in ipairs(list) do
		pcall(function()
			if c.Disable then c:Disable() elseif c.Disconnect then c:Disconnect() end
		end)
		n = n + 1
	end
	return n
end

local function scrubIntegrityTables()
	if typeof(getgc) ~= "function" then return false end
	local hit = false
	local ok, objs = pcall(getgc, true)
	if not ok or not objs then return false end
	local forceSamples = walkSpeedOn or flyOn
	for _, o in pairs(objs) do
		if type(o) == "table" then
			local isEv = false
			pcall(function()
				isEv = (rawget(o, "ValidationLocked") ~= nil and rawget(o, "Evidence") ~= nil)
					or (rawget(o, "ThreatLevel") ~= nil and rawget(o, "LastObservedSample") ~= nil)
			end)
			if isEv then
				hit = true
				pcall(function()
					local ev = rawget(o, "Evidence")
					if type(ev) == "table" then
						if (tonumber(ev.Speed) or 0) > 0 then rawset(ev, "Speed", 0) end
						if (tonumber(ev.Teleport) or 0) > 0 then rawset(ev, "Teleport", 0) end
						if (tonumber(ev.Flight) or 0) > 0 then rawset(ev, "Flight", 0) end
					end
					if rawget(o, "ThreatLevel") ~= "Trusted" then rawset(o, "ThreatLevel", "Trusted") end
					if rawget(o, "ValidationLocked") == true then rawset(o, "ValidationLocked", false) end
					if rawget(o, "FirstSuspiciousAt") ~= nil then rawset(o, "FirstSuspiciousAt", nil) end
					if rawget(o, "KickQueued") == true then rawset(o, "KickQueued", false) end
					if rawget(o, "TamperScore") ~= nil then rawset(o, "TamperScore", 0) end
					if rawget(o, "InvalidHeartbeatCount") ~= nil then rawset(o, "InvalidHeartbeatCount", 0) end
					local los = rawget(o, "LastObservedSample")
					if los ~= nil then
						if forceSamples or rawget(o, "LastGameplayTrustedSample") == nil then
							rawset(o, "LastGameplayTrustedSample", los)
						end
						if forceSamples or rawget(o, "LastValidatedSample") == nil then
							rawset(o, "LastValidatedSample", los)
						end
						if forceSamples or rawget(o, "LastValidatedGroundedSample") == nil then
							rawset(o, "LastValidatedGroundedSample", los)
						end
						if forceSamples or rawget(o, "LastConfirmedGroundSample") == nil then
							rawset(o, "LastConfirmedGroundSample", los)
						end
						if forceSamples or rawget(o, "LastGoodSample") == nil then
							rawset(o, "LastGoodSample", los)
						end
					end
				end)
			end
		end
	end
	return hit
end

-- Oxide: find Evidence table once, scrub ~5/s — NEVER getgc every Heartbeat (that freezes the client)
local integrityState = nil
local scrubLoopStarted = false

local function findIntegrityTable()
	if typeof(getgc) ~= "function" then return nil end
	local ok, objs = pcall(getgc, true)
	if not ok or not objs then return nil end
	for _, o in pairs(objs) do
		if type(o) == "table" then
			local hit = false
			pcall(function()
				hit = (rawget(o, "ValidationLocked") ~= nil and rawget(o, "Evidence") ~= nil)
					or (rawget(o, "ThreatLevel") ~= nil and rawget(o, "LastObservedSample") ~= nil)
			end)
			if hit then return o end
		end
	end
	return nil
end

local function scrubCachedIntegrity()
	if not integrityState then
		integrityState = findIntegrityTable()
		if not integrityState then return false end
	end
	local st = integrityState
	local forceSamples = walkSpeedOn or flyOn
	pcall(function()
		local ev = rawget(st, "Evidence")
		if type(ev) == "table" then
			if (tonumber(ev.Speed) or 0) > 0 then rawset(ev, "Speed", 0) end
			if (tonumber(ev.Teleport) or 0) > 0 then rawset(ev, "Teleport", 0) end
			if (tonumber(ev.Flight) or 0) > 0 then rawset(ev, "Flight", 0) end
		end
		if rawget(st, "ThreatLevel") ~= "Trusted" then rawset(st, "ThreatLevel", "Trusted") end
		if rawget(st, "ValidationLocked") == true then rawset(st, "ValidationLocked", false) end
		if rawget(st, "FirstSuspiciousAt") ~= nil then rawset(st, "FirstSuspiciousAt", nil) end
		if rawget(st, "KickQueued") == true then rawset(st, "KickQueued", false) end
		if rawget(st, "TamperScore") ~= nil then rawset(st, "TamperScore", 0) end
		if rawget(st, "InvalidHeartbeatCount") ~= nil then rawset(st, "InvalidHeartbeatCount", 0) end
		local los = rawget(st, "LastObservedSample")
		if los ~= nil and forceSamples then
			rawset(st, "LastGameplayTrustedSample", los)
			rawset(st, "LastValidatedSample", los)
			rawset(st, "LastValidatedGroundedSample", los)
			rawset(st, "LastConfirmedGroundSample", los)
			rawset(st, "LastGoodSample", los)
		end
	end)
	return true
end

local function startEvidenceScrubLoop()
	if scrubLoopStarted then return end
	scrubLoopStarted = true
	task.spawn(function()
		while true do
			if walkSpeedOn or flyOn then
				if not scrubCachedIntegrity() then
					integrityState = nil -- retry find next tick
				end
				task.wait(0.2) -- Oxide cadence
			else
				task.wait(0.5)
			end
		end
	end)
end

local function hardenCharacterSignals()
	local char = getChar()
	local hum = getHum()
	local hrp = getHRP()
	local killed = 0
	if hum then
		killed = killed + disableSignalConns(hum:GetPropertyChangedSignal("WalkSpeed"))
		killed = killed + disableSignalConns(hum:GetPropertyChangedSignal("JumpPower"))
		killed = killed + disableSignalConns(hum:GetPropertyChangedSignal("JumpHeight"))
		killed = killed + disableSignalConns(hum:GetPropertyChangedSignal("Health"))
	end
	if hrp then
		killed = killed + disableSignalConns(hrp:GetPropertyChangedSignal("CFrame"))
		killed = killed + disableSignalConns(hrp:GetPropertyChangedSignal("AssemblyLinearVelocity"))
	end
	-- Kill PushBack localscripts (same as steal swap)
	if char then
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("LocalScript") then
				local n = string.lower(d.Name)
				if n:find("push", 1, true) or n:find("anti", 1, true) or n:find("speed", 1, true) then
					pcall(function()
						d.Disabled = true
						d:Destroy()
					end)
				end
			end
		end
	end
	return killed
end

local function installClientAc()
	if acInstalled then
		hardenCharacterSignals()
		scrubIntegrityTables()
		return acStatus
	end
	acInstalled = true
	local parts = {}

	-- Oxide Layer1-ish: freeze detection tables via filtergc if present
	pcall(function()
		if typeof(filtergc) == "function" and debug and debug.getupvalues then
			local ok, fn = pcall(function()
				return filtergc("function", { Constants = { "gmatch", "GetFullName" } }, true)
			end)
			if ok and typeof(fn) == "function" then
				local setMeta = setrawmetatable or setmetatable
				local okUv, ups = pcall(debug.getupvalues, fn)
				if okUv and type(ups) == "table" and setMeta then
					for _, tbl in pairs(ups) do
						if typeof(tbl) == "table" then
							pcall(setMeta, tbl, { __newindex = function() end })
						end
					end
					table.insert(parts, "filtergc")
				end
			end
		end
	end)

	hardenCharacterSignals()
	table.insert(parts, "signals")

	-- Oxide-style Evidence scrub: cached table @ 0.2s (NOT getgc every Heartbeat)
	startEvidenceScrubLoop()
	if scrubCachedIntegrity() or scrubIntegrityTables() then
		table.insert(parts, "evidence")
	else
		table.insert(parts, "evidence?")
	end

	-- Block game from overwriting WalkSpeed while we own it
	pcall(function()
		if typeof(hookmetamethod) ~= "function" then return end
		local old
		old = hookmetamethod(game, "__newindex", function(self, key, value)
			if walkSpeedOn and typeof(self) == "Instance" and self:IsA("Humanoid") and key == "WalkSpeed" then
				if not checkcaller or not checkcaller() then
					if typeof(value) == "number" and value ~= walkSpeedVal then
						return old(self, key, walkSpeedVal)
					end
				end
			end
			return old(self, key, value)
		end)
		table.insert(parts, "newindex")
	end)

	acStatus = table.concat(parts, "+")
	return acStatus
end

local function applyWalkSpeed()
	local hum = getHum()
	if not hum or not walkSpeedOn then return end
	hum.WalkSpeed = walkSpeedVal
end

-- WalkSpeed loop only (fly is separate)
local function ensureMoveLoop()
	if moveConn then return end
	moveConn = RunService.RenderStepped:Connect(function(dt)
		if not walkSpeedOn then return end
		-- Never CFrame-boost while Auto Farm drives stealMoveTo
		if autoFarm then
			return
		end
		applyWalkSpeed()
		if freezeMoveForValidate then return end
		local hum = getHum()
		local hrp = getHRP()
		if hum and hrp and not flyOn and hum.MoveDirection.Magnitude > 0.05 then
			local boost = math.max(0, walkSpeedVal - math.max(hum.WalkSpeed, 16))
			if boost > 1 then
				hrp.CFrame = hrp.CFrame + hum.MoveDirection * boost * math.min(dt, 0.05)
			end
		end
	end)
	table.insert(connections, moveConn)
end

local function setWalkSpeedEnabled(on)
	walkSpeedOn = on and true or false
	if walkSpeedOn then
		local ac = installClientAc()
		ensureMoveLoop()
		ensureDeliverAssist()
		hardenCharacterSignals()
		applyWalkSpeed()
		setStatus(("WS on %d | AC %s | %s"):format(walkSpeedVal, tostring(ac), GLITCH_CORE_VER))
	else
		local hum = getHum()
		if hum then
			pcall(function() hum.WalkSpeed = 16 end)
		end
	end
end

-- Physical fly: preserve normal collision with floors/walls and drive only a
-- BodyVelocity. This avoids CFrame movement/no-clip, which the server rejects.
local function stopFly()
	flyOn = false
	if flyConn then
		pcall(function() flyConn:Disconnect() end)
		flyConn = nil
	end
	if flyVelocity then
		pcall(function() flyVelocity:Destroy() end)
		flyVelocity = nil
	end
	local hrp = getHRP()
	if hrp then
		pcall(function() hrp.Anchored = false end)
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
	end
	local hum = getHum()
	if hum then
		hum.PlatformStand = false
		pcall(function()
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end)
		pcall(function()
			hum:ChangeState(Enum.HumanoidStateType.Running)
		end)
	end
end

local function startFly()
	if autoFarm then
		setStatus("Fly paused (Auto on)")
		return
	end
	stopFly()
	local hrp = getHRP()
	local hum = getHum()
	if not (hrp and hum) then
		setStatus("Fly: no character")
		return
	end
	local ac = installClientAc()
	hardenCharacterSignals()
	flyOn = true
	-- No Clip is deliberately NOT enabled here: flight must still collide with
	-- the map instead of passing through floors and walls.
	hrp.Anchored = false
	hum.PlatformStand = true
	flyVelocity = Instance.new("BodyVelocity")
	flyVelocity.Name = "GlitchFlyVelocity"
	flyVelocity.MaxForce = Vector3.new(90000, 90000, 90000)
	flyVelocity.P = 30000
	flyVelocity.Velocity = Vector3.zero
	flyVelocity.Parent = hrp

	flyConn = RunService.Heartbeat:Connect(function()
		if not flyOn or autoFarm then return end
		local root = getHRP()
		local humanoid = getHum()
		local cam = Workspace.CurrentCamera
		if not (root and humanoid and cam and flyVelocity and flyVelocity.Parent == root) then return end

		if root.Anchored then
			root.Anchored = false
		end
		humanoid.PlatformStand = true

		if freezeMoveForValidate then
			flyVelocity.Velocity = Vector3.zero
			return
		end

		local look = cam.CFrame.LookVector
		local right = cam.CFrame.RightVector

		local dir = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + look end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - look end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - right end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + right end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			dir = dir - Vector3.new(0, 1, 0)
		end

		if dir.Magnitude > 0.05 then
			flyVelocity.Velocity = dir.Unit * flySpeed
		else
			flyVelocity.Velocity = Vector3.zero
		end
	end)
	table.insert(connections, flyConn)
	ensureDeliverAssist()
	setStatus(("Fly on %d | AC %s | %s"):format(flySpeed, tostring(ac), GLITCH_CORE_VER))
end

local function setInfiniteJump(on)
	infiniteJumpOn = on and true or false
	if not infiniteJumpOn then
		if infiniteJumpConn then
			pcall(function() infiniteJumpConn:Disconnect() end)
			infiniteJumpConn = nil
		end
		return
	end
	if infiniteJumpConn then return end
	-- JumpRequest also fires in mid-air, unlike a one-time Space key listener.
	infiniteJumpConn = UserInputService.JumpRequest:Connect(function()
		if not infiniteJumpOn then return end
		local hum = getHum()
		if hum and hum.Health > 0 and not hum.PlatformStand then
			pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
		end
	end)
end

local function restoreNoClip()
	for part, wasCollidable in pairs(noClipOriginal) do
		pcall(function()
			if part and part.Parent then part.CanCollide = wasCollidable end
		end)
	end
	table.clear(noClipOriginal)
end

local function applyNoClip()
	local char = getChar()
	if not char then return end
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			if noClipOriginal[part] == nil then
				noClipOriginal[part] = part.CanCollide
			end
			part.CanCollide = false
		end
	end
end

refreshNoClip = function()
	local active = noClipOn
	if not active then
		if noClipConn then
			pcall(function() noClipConn:Disconnect() end)
			noClipConn = nil
		end
		restoreNoClip()
		return
	end
	applyNoClip()
	if not noClipConn then
		-- Apply before each physics simulation so new character parts and game
		-- scripts that restore collision cannot make the player stick in a wall.
		noClipConn = RunService.Stepped:Connect(function()
			if noClipOn then applyNoClip() end
		end)
	end
end

local function setNoClip(on)
	noClipOn = on and true or false
	refreshNoClip()
end

local Api = {}

function Api.getVersion()
	return GLITCH_CORE_VER
end

function Api.setConfig(t)
	if typeof(t) ~= "table" then return end
	if t.biomeIndex then CFG.biomeIndex = t.biomeIndex end
	if t.biomes then CFG.biomes = t.biomes end
	if t.approachSpeed then CFG.approachSpeed = math.clamp(t.approachSpeed, 50, 1000) end
	if t.escapeSpeed then CFG.escapeSpeed = math.clamp(t.escapeSpeed, 50, 1000) end
	if t.targetMode == "all" or t.targetMode == "best" or t.targetMode == "dropped" or t.targetMode == "carrier" then CFG.targetMode = t.targetMode end
	if t.carrierFollowDistance then CFG.carrierFollowDistance = math.clamp(t.carrierFollowDistance, 2, 8) end
	if typeof(t.status) == "function" then CFG.status = t.status end
end

function Api.startFarm()
	bindGame()
	patchRigSyncKnockback()
	swapStealHumanoid()
	cancelManualDeliverAssist()
	if flyOn then stopFly() end
	setStatus(("Glitch %s Bound E=%s P=%s Eggs=%s KB=%s"):format(
		GLITCH_CORE_VER,
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
	stopAuraFollowMotion()
	cancelManualDeliverAssist()
	local hum = getHum()
	if hum then hum.PlatformStand = false end
	restoreManualRunAnimation()
	setStatus("Auto off")
end

function Api.setAutoAction(name, on)
	if autoActions[name] == nil then return false end
	bindGame()
	if on and name == "plant" and (not PlantEggFn or not WearEggToolFn or not SaveModule) then setStatus("Auto plant unavailable"); return false end
	if on and name == "hatch" and (not IsEggReadyFn or not BeginHatchFn or not FinishHatchFn or not SaveModule) then setStatus("Auto hatch unavailable"); return false end
	if on and name == "equip" and not EquipBestPetsRemote then setStatus("Auto equip unavailable"); return false end
	autoActions[name] = on and true or false
	if on then
		setStatus("Auto " .. name .. " on")
		runAutoActions()
	else
		setStatus("Auto " .. name .. " off")
	end
	return true
end

function Api.setEsp(on)
	espFlags.players = on and true or false
	ensureEspLoop()
end

function Api.setEspPlayers(on)
	espFlags.players = on and true or false
	ensureEspLoop()
end

function Api.setEspEggs(on)
	espFlags.eggs = on and true or false
	ensureEspLoop()
end

function Api.setEspBeasts(on)
	espFlags.beasts = on and true or false
	ensureEspLoop()
end

function Api.setWalkSpeed(on, speed)
	if typeof(speed) == "number" then
		walkSpeedVal = math.clamp(speed, 16, 500)
	end
	setWalkSpeedEnabled(on)
end

function Api.setFly(on, speed)
	if typeof(speed) == "number" then
		flySpeed = math.clamp(speed, 10, 500)
	end
	if on then
		startFly()
	else
		stopFly()
	end
end

function Api.setInfiniteJump(on)
	setInfiniteJump(on)
	setStatus(on and "Infinite Jump on" or "Infinite Jump off")
end

function Api.setNoClip(on)
	setNoClip(on)
	setStatus(on and "No Clip on" or "No Clip off")
end

function Api.destroy()
	autoFarm = false
	stopAuraFollowMotion()
	stopFly()
	restoreManualRunAnimation()
	setInfiniteJump(false)
	setNoClip(false)
	walkSpeedOn = false
	cancelManualDeliverAssist()
	espFlags.players, espFlags.eggs, espFlags.beasts = false, false, false
	clearEsp()
	for _, c in ipairs(connections) do
		pcall(function() c:Disconnect() end)
	end
	connections = {}
	espConn, moveConn, flyConn, deliverAssistConn = nil, nil, nil, nil
	infiniteJumpConn, noClipConn = nil, nil
end

LP.CharacterAdded:Connect(function()
	task.wait(0.45)
	if autoFarm then
		swapStealHumanoid()
		patchRigSyncKnockback()
	end
	if walkSpeedOn or flyOn then
		installClientAc()
		hardenCharacterSignals()
	end
	if walkSpeedOn then
		applyWalkSpeed()
	end
	if flyOn and not autoFarm then
		startFly()
	end
end)

-- Install AC early so farm/ESP load doesn't leave BAC hot
pcall(installClientAc)

return Api
