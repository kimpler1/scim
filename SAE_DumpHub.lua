--[[
  SAE_DumpHub.lua — run this FIRST, then execute any working hub.
  Saves loaded Lua sources + Remote traffic to workspace folder via writefile.
  Delta/Synapse/Wave: needs writefile + hookfunction/hookmetamethod.
]]

local TAG = "[SAE_DUMP]"
local outDir = "sae_dump_" .. tostring(os.time())
local n = 0

local function safeWrite(name, data)
	n = n + 1
	local path = outDir .. "/" .. string.format("%03d_%s", n, name)
	if typeof(writefile) ~= "function" then
		warn(TAG, "no writefile — print only", path, #(tostring(data)))
		print(TAG, "BEGIN", path)
		print(tostring(data):sub(1, 4000))
		print(TAG, "END", path)
		return
	end
	pcall(function()
		if makefolder and not isfolder(outDir) then
			makefolder(outDir)
		end
	end)
	writefile(path, tostring(data))
	print(TAG, "saved", path, "bytes", #tostring(data))
end

print(TAG, "armed. folder=", outDir)

-- 1) Capture every HttpGet payload hubs load
do
	local http = game:GetService("HttpService")
	local old
	if typeof(hookfunction) == "function" and typeof(http.GetAsync) == "function" then
		-- some executors expose game.HttpGet as global env
	end
	local gHttpGet = game.HttpGet
	if typeof(hookfunction) == "function" and typeof(gHttpGet) == "function" then
		old = hookfunction(gHttpGet, function(self, url, ...)
			local ok, body = pcall(old, self, url, ...)
			if ok and typeof(body) == "string" and #body > 50 then
				local short = tostring(url):gsub("[^%w]+", "_"):sub(1, 80)
				safeWrite("http_" .. short .. ".lua", "-- URL: " .. tostring(url) .. "\n\n" .. body)
			end
			if not ok then error(body) end
			return body
		end)
		print(TAG, "hooked game.HttpGet")
	else
		warn(TAG, "HttpGet hook unavailable on this executor")
	end
end

-- 2) Capture loadstring sources when hubs compile them
do
	local oldLoad = loadstring
	if typeof(hookfunction) == "function" and typeof(oldLoad) == "function" then
		hookfunction(oldLoad, newcclosure(function(src, chunk)
			if typeof(src) == "string" and #src > 80 then
				safeWrite("loadstring_" .. tostring(chunk or "chunk") .. ".lua", src)
			end
			return oldLoad(src, chunk)
		end))
		print(TAG, "hooked loadstring")
	end
end

-- 3) Log remotes used for eggs and pet equip/unequip actions.
-- Run this before manually returning one pet through the game's own UI; the
-- executor console will print the exact endpoint and arguments to reproduce.
do
	local mt = getrawmetatable and getrawmetatable(game)
	if mt and typeof(hookmetamethod) == "function" then
		local oldNamecall
		oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
			local method = getnamecallmethod()
			if method == "FireServer" or method == "InvokeServer" then
				local name = self:GetFullName()
				local watched = name:find("Egg", 1, true)
					or name:find("Carry", 1, true)
					or name:find("Field", 1, true)
					or name:find("Pet", 1, true)
					or name:find("Haul", 1, true)
					or name:find("Pen", 1, true)
					or name:find("Wear", 1, true)
					or name:find("Doff", 1, true)
					or name:find("Unequip", 1, true)
				if watched then
					local args = { ... }
					local line = os.date("%H:%M:%S") .. " " .. method .. " " .. name
					for i, a in ipairs(args) do
						line = line .. " |#" .. i .. "=" .. tostring(a)
					end
					safeWrite("remotes.log", (readfile and isfile(outDir .. "/remotes.log") and readfile(outDir .. "/remotes.log") or "") .. line .. "\n")
					print(TAG, line)
				end
			end
			return oldNamecall(self, ...)
		end))
		print(TAG, "hooked remotes (Egg/Pet/Haul/Pen)")
	else
		warn(TAG, "namecall hook unavailable — skip remotes")
	end
end

print(TAG, "now execute the WORKING hub. After it farms once, check executor workspace /", outDir)
