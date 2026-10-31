--[=[
	This module is an instance-like rewrite of Common Detections Bypass by zyletrophene, it will oftentime drastically decrease performance and game stability. We can only hope that the engine will compile our hooks to machine code as this behaviour is highly dependent on the executor implementation of hookfunction.

	Please keep in mind that this script is **NOT** a bypass for server sided anticheat methods nor will it automatically feed any potential watchdog, which can and in most cases will get you banned sooner or later. This module is only meant as a learning resource and jumpstart for developers so that they can extract the client-side scripts and begin the actual work.

	References can be found in the resources folder at the top of this repository.
	@class Bypass
]=]
local Hooks = require("./hooks")
local Interface = require("@aria/interface")

local Run = game:GetService("RunService")
local Players = game:GetService("Players")
local Content = game:GetService("ContentProvider")
local ScriptContext = game:GetService("ScriptContext")
local Localization = game:GetService("LocalizationService")
local Stats = game:GetService("Stats")

local player = Players.LocalPlayer

local nop
local useNop
local modified = {}
local nopHandle
local kickHandle
local kickUpperHandle
local preloadHandle
local contextHandle
local localizeHandle
local pcallHandle
local ypcallHandle
local xpcallHandle
local propertyHandle
local memoryHandle
local memoryConnection
local garbageHandle
local collectHandle
local garbageConnection
local logHandle
local analyticsHandle
local proxyHandle
local MAX_OVERFLOW_DEPTH = 32
local mainThread = {}
local overflowThreads = setmetatable({}, {__mode = "k"})

--@inline
local function isStackOverflow(message)
	local text = typeof(message) == "string" and string.lower(message) or nil
	return text ~= nil and string.find(text, "stack overflow", 1, true) ~= nil
end

--@inline
local function protectedCall(original, fn, args, count)
	local thread = coroutine.running() or mainThread
	local depth = (overflowThreads[thread] or 0) + 1
	local results

	-- Stop a recursive protected call before the extra hook frames can exhaust
	-- the engine stack. Answering as a success keeps the overflow invisible to
	-- the script without skipping ordinary nested calls below the limit.
	if depth > MAX_OVERFLOW_DEPTH then
		results = table.pack(true, nil)
	else
		overflowThreads[thread] = depth
		results = table.pack(original(fn, table.unpack(args, 1, count)))
		overflowThreads[thread] = depth > 1 and depth - 1 or nil

		if results[1] == false then
			local overflow = isStackOverflow(results[2])
			if overflow then
				results = table.pack(true, nil)
			end
		end
	end

	return table.unpack(results, 1, results.n)
end

--[=[
	Reads an instance member without letting a missing or renamed property break
	the toggle that is trying to hook it.
	@param instance any -- The instance to index
	@param name string -- The member name
	@return any -- The member, or nil when it does not exist
]=]
--@inline
local function member(instance, name)
	local success, value = pcall(function()
		return instance[name]
	end)
	local result
	if success then
		result = value
	end
	return result
end

--[=[
	Creates the proxy that stands in for every value a script does not deserve to see.
	@return any -- The proxy of the module
]=]
--@inline
local function createNop()
	local result = nop
	if not result then
		if newproxy then
			nop = newproxy(true)
			local mt = getmetatable(nop)
			mt.__metatable = {}
			mt.__index = function(self)
				return self
			end
			mt.__newindex = function() end
			mt.__call = function(self)
				return self
			end
			mt.__add = function(self)
				return self
			end
			mt.__sub = function(self)
				return self
			end
			mt.__mul = function(self)
				return self
			end
			mt.__div = function(self)
				return self
			end
			mt.__mod = function(self)
				return self
			end
			mt.__pow = function(self)
				return self
			end
			mt.__unm = function(self)
				return self
			end
			mt.__eq = function()
				return false
			end
			mt.__lt = function()
				return false
			end
			mt.__le = function()
				return false
			end
			mt.__len = function()
				return 0
			end
			mt.__tostring = function()
				return ""
			end
			mt.__iter = function()
				return function()
					return nil
				end
			end

			getgenv().nop = nop
			result = nop
		else
			warn("newproxy is not available in this executor")
		end
	end
	return result
end

--[=[
	Answers a call with the proxy while the nop property is enabled.
	@return any -- The proxy or nothing
]=]
--@inline
local function halt()
	if useNop then
		return nop
	end
end

return Interface.New({
	--[=[
		Makes it so that all engine functions called by a script using the nop type as an argument also return the nop type.
		@prop nop bool
	]=]
	nop = function(v)
		if v then
			local value = createNop()
			if not value then
				return
			end
			useNop = true
			nopHandle = Hooks.HookMeta(game, "__namecall", function(_, _, ...)
				local count = select("#", ...)
				for index = 1, count do
					if rawequal(select(index, ...), value) then
						return value
					end
				end
			end)
		else
			useNop = false
			Hooks.Release(nopHandle)
			nopHandle = nil
		end
	end,

	--[=[
		Bypass kicks caused by local scripts. Keep in mind that you can't really change anything caused by the server.
		@prop kick bool
	]=]
	kick = function(v)
		if v then
			local lower = member(player, "kick")
			if type(lower) == "function" and lower ~= player.Kick then
				kickHandle = Hooks.HookFunc(lower, function(_, self)
					if self == player then
						return halt()
					end
				end)
			end
			kickUpperHandle = Hooks.HookFunc(player.Kick, function(_, self)
				if self == player then
					return halt()
				end
			end)
		else
			Hooks.Release(kickHandle)
			Hooks.Release(kickUpperHandle)
			kickHandle = nil
			kickUpperHandle = nil
		end
	end,

	--[=[
		Bypass asset loading callbacks that fire when loading icons or images that don't belong to the game. Remember that this event fires regardless of the location of the loaded asset unless explicitly stopped by the executor.
		@prop preload bool
	]=]
	preload = function(v)
		if v then
			preloadHandle = Hooks.HookEvent(Content.PreloadAsync, function()
				return halt()
			end)
		else
			Hooks.Release(preloadHandle)
			preloadHandle = nil
		end
	end,

	--[=[
		Lowers the execution budget to prevent scripts from running pointless computations untill our client crashes and prevents them from connecting to the error event.
		@prop context bool
	]=]
	context = function(v)
		if v then
			ScriptContext:SetTimeout(2)
			contextHandle = Hooks.HookEvent(ScriptContext.Error, function()
				return halt()
			end)
		else
			ScriptContext:SetTimeout(30)
			Hooks.Release(contextHandle)
			contextHandle = nil
		end
	end,

	--[=[
		Disables localization since it can be used to crash your game when an element with AutoLocalize set to true is present in CoreGUI.
		@prop localize bool
	]=]
	localize = function(v)
		if v then
			local translator = Localization:GetTranslatorForLocaleAsync(Localization.RobloxLocaleId)
			if not translator then return end
			localizeHandle = Hooks.HookFunc(translator.Translate, function(_, self)
				if typeof(self) == "Instance" and self.ClassName == "Translator" then
					return halt()
				end
			end)
		else
			Hooks.Release(localizeHandle)
			localizeHandle = nil
		end
	end,

	--[=[
		Stops scripts from using protected calls for trying to overflow hooks.
		@prop overflow bool
	]=]
	overflow = function(v)
		if v then
			pcallHandle = Hooks.HookFunc(pcall, function(original, fn, ...)
				local args = table.pack(...)
				return protectedCall(original, fn, args, args.n)
			end)

			if type(ypcall) == "function" then
				ypcallHandle = Hooks.HookFunc(ypcall, function(original, fn, ...)
					local args = table.pack(...)
					return protectedCall(original, fn, args, args.n)
				end)
			end

			xpcallHandle = Hooks.HookFunc(xpcall, function(original, fn, given, ...)
				if type(given) ~= "function" then
					return original(fn, given, ...)
				end
				local handler = function(message)
					if isStackOverflow(message) then return message end
					return given(message)
				end
				local args = table.pack(handler, ...)
				return protectedCall(original, fn, args, args.n)
			end)
		else
			Hooks.Release(pcallHandle)
			Hooks.Release(ypcallHandle)
			Hooks.Release(xpcallHandle)
			pcallHandle = nil
			ypcallHandle = nil
			xpcallHandle = nil
		end
	end,

	--[=[
		Usually used for detecting the backround blur implementation of most UI libraries. Will probably cause issues in most games.
		@prop property bool
	]=]
	property = function(v)
		if v then
			propertyHandle = Hooks.HookMeta(game, "__index", function(_, _, key)
				if typeof(key) == "string" and (string.find(key, "Changed") or string.find(key, "Added") or string.find(key, "Removed")) then
					return halt()
				end
			end)
		else
			Hooks.Release(propertyHandle)
			propertyHandle = nil
		end
	end,

	--[=[
		Disables scripts that don't have a parent, a trick usually used to hide from scripts such as Dex Explorer. This could cause some issues if the hidden logic is also used for actual functionality.
		@prop parent bool
	]=]
	parent = function(v)
		if v then
			for _, script in getrunningscripts() do
				if not script:IsDescendantOf(workspace.Parent) then
					table.insert(modified, {script = script, enabled = script.Enabled})
					script.Enabled = false
					warn("Script '" .. script.Name .. "' was reparented to nil")
				end
			end
		else
			for _, entry in modified do
				entry.script.Enabled = entry.enabled
			end
			modified = {}
		end
	end,

	--[=[
		Spoofs memory usage to a constant credible level.
		@prop memory bool
	]=]
	memory = function(v)
		if v then
			local rng = Random.new()
			local maxDelta = 4
			local totalMemory = Stats:GetTotalMemoryUsageMb()
			local guiMemory = Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Gui)
			local smoothed = Stats:GetTotalMemoryUsageMb()
			local smoothedGui = Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Gui)
			local lastCheck = tick()

			memoryConnection = Run.Heartbeat:Connect(function()
				local currentTime = tick()
				if currentTime - lastCheck <= 0.5 then
					return
				end
				lastCheck = currentTime

				local realMemory = Stats:GetTotalMemoryUsageMb()
				smoothed += math.clamp(realMemory - smoothed, -maxDelta, maxDelta)

				local realGui = Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Gui)
				smoothedGui += math.clamp(realGui - smoothedGui, -maxDelta * 0.3, maxDelta * 0.3)

				totalMemory = smoothed + rng:NextNumber(-0.1, 0.1)
				guiMemory = smoothedGui + rng:NextNumber(-0.05, 0.05)
			end)

			memoryHandle = Hooks.HookMeta(game, "__namecall", function(_, self, ...)
				if typeof(self) == "Instance" and self.ClassName == "Stats" then
					local method = getnamecallmethod()
					if method == "GetTotalMemoryUsageMb" then
						return totalMemory
					elseif method == "GetMemoryUsageMbForTag" then
						local args = { ... }
						if args[1] == Enum.DeveloperMemoryTag.Gui then
							return guiMemory
						end
					end
				end
			end)
		else
			if memoryConnection then
				memoryConnection:Disconnect()
				memoryConnection = nil
			end
			Hooks.Release(memoryHandle)
			memoryHandle = nil
		end
	end,

	--[=[
		Spoofs garbage collector statistics to a constant credible level.
		@prop garbage bool
	]=]
	garbage = function(v)
		if v then
			local rng = Random.new()
			local baselineGc = 0
			if type(gcinfo) == "function" then
				baselineGc = gcinfo()
			end
			local lastUpdate = tick()
			local drift = 0

			garbageConnection = Run.Heartbeat:Connect(function()
				local currentTime = tick()
				if currentTime - lastUpdate < 3 then
					return
				end
				lastUpdate = currentTime
				drift = math.clamp(drift + rng:NextNumber(-2, 2), -10, 10)
			end)

			local function handler()
				return baselineGc + drift + rng:NextNumber(-0.5, 0.5)
			end

			if type(gcinfo) == "function" then
				garbageHandle = Hooks.HookFunc(gcinfo, handler)
			end
			collectHandle = Hooks.HookFunc(collectgarbage, function(_, arg)
				if arg == "count" then
					return handler()
				end
			end)
		else
			if garbageConnection then
				garbageConnection:Disconnect()
				garbageConnection = nil
			end
			Hooks.Release(garbageHandle)
			Hooks.Release(collectHandle)
			garbageHandle = nil
			collectHandle = nil
		end
	end,

	--[=[
		Prevents local data from being sent out to the server discretely using the LogService.
		@prop log bool
	]=]
	log = function(v)
		if v then
			logHandle = Hooks.HookMeta(game, "__index", function(_, _, key)
				if typeof(key) == "string" and key == "MessageOut" then
					return halt()
				end
			end)
		else
			Hooks.Release(logHandle)
			logHandle = nil
		end
	end,

	--[=[
		Prevents scripts from transferring data through the AnalyticsService.
		@prop analytics bool
	]=]
	analytics = function(v)
		if v then
			analyticsHandle = Hooks.HookMeta(game, "__namecall", function(_, self)
				if typeof(self) == "Instance" and self.ClassName == "AnalyticsService" then
					return halt()
				end
			end)
		else
			Hooks.Release(analyticsHandle)
			analyticsHandle = nil
		end
	end,

	--[=[
		Prevents the use of newproxy by scripts as it is something rarely accounted for in the development of lower grade executors.
		@prop proxy bool
	]=]
	proxy = function(v)
		if v then
			if not newproxy then
				warn("newproxy is not available in this executor")
				return
			end
			proxyHandle = Hooks.HookFunc(newproxy, function()
				return halt()
			end)
		else
			Hooks.Release(proxyHandle)
			proxyHandle = nil
		end
	end,
})
