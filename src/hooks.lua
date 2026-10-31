--[=[
	A table dispatch based hook manager.

	Every target keeps a single underlying hook and a table of handlers. The handlers are dispatched in the order they were added and the first one that returns a result wins, so several features can share a target and recover it without stepping on each other.

	A metamethod or function handler is called with the function that was in place before the hook was installed, followed by the arguments of the call. Returning `nil` hands the call over to the next handler and finally to that previous function, returning anything else answers the call. Event handlers are called with the arguments of the callback and answer it in the same way.

	The dispatch wrapper is installed by a build time macro, so the hot path of every hook carries no extra call.
	@class Hooks
]=]
local Hooks = {}

export type Handler = (...any) -> ...any

export type Entry = {
	handlers: { Handler },
	original: Handler?,
	wrapper: Handler?,
	target: any,
	meta: string,
	isMeta: boolean?,
	isEvent: boolean?,
	connections: { any }?,
}

export type Handle = {
	entry: Entry,
	handler: Handler,
	released: boolean,
}

local META = {}
local FUNC = {}
local EVENT = {}
local EVENT_HOOKS = {}

--@inline
local function hookMeta(target, meta, wrapper)
	return hookmetamethod(target, meta, wrapper)
end

--@inline
local function hookFunc(target, _, wrapper)
	return hookfunction(target, wrapper)
end

--[=[
	Whether the call comes from a game script instead of the executor itself.
	@return boolean -- True when the call should be dispatched
]=]
--@inline
local function isGame()
	return not checkcaller() and getthreadidentity() < 5
end

--[=[
	Installs the dispatch wrapper of a hook target and records the function that was in place before it.

	The wrapper hands the previous function to every handler, the first handler that returns a result wins and the previous function is called when no handler does. Only calls that come from a game script are dispatched, calls made by the executor itself are passed straight through.
	@param entry Entry -- The dispatch entry of the target
	@param hook function -- Installs the wrapper and returns the previous function
	@param target any -- The hooked target
	@param meta string -- The name of the hooked function
]=]
--@macro
local function install(entry, hook, target, meta)
	local previous
	local wrapper
	wrapper = newcclosure(function(...)
		if isGame() then
			for _, handler in ipairs(entry.handlers) do
				local results = table.pack(handler(previous, ...))
				if results[1] ~= nil then
					return table.unpack(results, 1, results.n)
				end
			end
		end
		return previous(...)
	end)
	previous = hook(target, meta, wrapper)
	entry.original = previous
	entry.wrapper = wrapper
end

--[=[
	Restores the metamethod of a target.
	@param target any -- The hooked target
	@param meta string -- The name of the hooked metamethod
]=]
--@inline
local function restoreMeta(target, meta)
	restorefunction(getrawmetatable(target)[meta])
end

--[=[
	Restores a hooked function.
	@param target function -- The hooked function
]=]
--@inline
local function restoreFunc(target)
	restorefunction(target)
end

--[=[
	Adds a handler for a metamethod of the target and installs the hook when the target does not have one yet.

	The hook is shared by every target that uses the same metatable, which is the case for all instances.
	@param target any -- The instance that owns the metamethod
	@param meta string -- The name of the metamethod
	@param handler Handler -- The handler that answers the call
	@return Handle -- The handle of the registered handler
]=]
function Hooks.HookMeta(target: any, meta: string, handler: Handler): Handle
	local metatable = getrawmetatable(target)
	local entries = META[metatable]

	if not entries then
		entries = {}
		META[metatable] = entries
	end

	local entry = entries[meta]

	if not entry then
		entry = { handlers = {}, target = target, meta = meta, isMeta = true }
		entries[meta] = entry
		install(entry, function(...)
			return hookMeta(...)
		end, target, meta)
	end

	table.insert(entry.handlers, handler)

	return { entry = entry, handler = handler, released = false }
end

--[=[
	Adds a handler for a function and installs the hook when the function does not have one yet.
	@param target function -- The function to hook
	@param handler Handler -- The handler that answers the call
	@return Handle -- The handle of the registered handler
]=]
function Hooks.HookFunc(target: Handler, handler: Handler): Handle
	local entry = FUNC[target]

	if not entry then
		entry = { handlers = {}, target = target, meta = "", isMeta = false }
		FUNC[target] = entry
		install(entry, function(...)
			return hookFunc(...)
		end, target, "")
	end

	table.insert(entry.handlers, handler)

	return { entry = entry, handler = handler, released = false }
end

--[=[
	Answers the connections of a signal that has event handlers.

	The wrapper runs every handler of the signal before the callback of the script and answers the call when one of them returns a result.
	@param original function -- The previous `__index` of the metatable
	@param self any -- The signal that was indexed
	@param key string -- The name of the indexed member
	@return function? -- The wrapper of the connection method
	@private
]=]
local function eventIndex(original, self, key, ...)
	local entry = EVENT[self]

	if not entry then
		return nil
	end

	if key ~= "Connect" and key ~= "ConnectParallel" and key ~= "Once" then
		return nil
	end

	local connect = original(self, key, ...)

	return function(instance, callback, ...)
		return connect(instance, function(...)
			for _, handler in ipairs(entry.handlers) do
				local results = table.pack(handler(...))
				if results[1] ~= nil then
					return table.unpack(results, 1, results.n)
				end
			end
			return callback(...)
		end, ...)
	end
end

--[=[
	Disables the connections of a signal and answers every callback that is connected to it afterwards.

	Handlers of a signal are dispatched in the order they were added and the first one that returns a result answers the call, otherwise the callback of the script runs. The disabled connections are enabled again when the last handler is released.
	@param signal any -- The signal to hook
	@param handler Handler -- The handler that runs before the callback
	@return Handle -- The handle of the registered handler
]=]
function Hooks.HookEvent(signal: any, handler: Handler): Handle
	local entry = EVENT[signal]

	if not entry then
		entry = {
			handlers = {},
			target = signal,
			meta = "__index",
			isEvent = true,
			connections = {},
		}
		EVENT[signal] = entry

		for _, connection in ipairs(getconnections(signal)) do
			connection:Disable()
			table.insert(entry.connections, connection)
		end

		local metatable = getrawmetatable(signal)

		if not EVENT_HOOKS[metatable] then
			EVENT_HOOKS[metatable] = Hooks.HookMeta(signal, "__index", eventIndex)
		end
	end

	table.insert(entry.handlers, handler)

	return { entry = entry, handler = handler, released = false }
end

--[=[
	Removes a handler from its target and restores the underlying hook once the last handler is gone.
	@param handle Handle? -- The handle of the handler to remove
]=]
function Hooks.Release(handle: Handle?)
	if not handle or handle.released then
		return
	end
	handle.released = true

	local entry = handle.entry
	local handlers = entry.handlers

	for index, handler in ipairs(handlers) do
		if handler == handle.handler then
			table.remove(handlers, index)
			break
		end
	end

	if #handlers > 0 then
		return
	end

	if entry.isEvent then
		EVENT[entry.target] = nil

		for _, connection in ipairs(entry.connections or {}) do
			connection:Enable()
		end

		local metatable = getrawmetatable(entry.target)
		local shared = false

		for _, other in pairs(EVENT) do
			if getrawmetatable(other.target) == metatable then
				shared = true
				break
			end
		end

		if not shared then
			local dispatch = EVENT_HOOKS[metatable]
			EVENT_HOOKS[metatable] = nil
			Hooks.Release(dispatch)
		end
	elseif entry.isMeta then
		local metatable = getrawmetatable(entry.target)

		if metatable[entry.meta] == entry.wrapper then
			restoreMeta(entry.target, entry.meta)
		end

		local entries = META[metatable]

		if entries then
			entries[entry.meta] = nil

			if next(entries) == nil then
				META[metatable] = nil
			end
		end
	else
		restoreFunc(entry.target)
		FUNC[entry.target] = nil
	end
end

--[=[
	Creates a setter that installs a handler for a metamethod while the value is true and recovers it afterwards.
	@param target any -- The instance that owns the metamethod
	@param meta string -- The name of the metamethod
	@param handler Handler -- The handler that answers the call
	@return (boolean) -> () -- The setter of the property
]=]
function Hooks.ToggleMeta(target: any, meta: string, handler: Handler): (boolean) -> ()
	local handle

	return function(value)
		if value then
			if handle then return end
			handle = Hooks.HookMeta(target, meta, handler)
		else
			Hooks.Release(handle)
			handle = nil
		end
	end
end

--[=[
	Creates a setter that installs a handler for a function while the value is true and recovers it afterwards.
	@param target function -- The function to hook
	@param handler Handler -- The handler that answers the call
	@return (boolean) -> () -- The setter of the property
]=]
function Hooks.ToggleFunc(target: Handler, handler: Handler): (boolean) -> ()
	local handle

	return function(value)
		if value then
			if handle then return end
			handle = Hooks.HookFunc(target, handler)
		else
			Hooks.Release(handle)
			handle = nil
		end
	end
end

--[=[
	Creates a setter that installs a handler for a signal while the value is true and recovers it afterwards.
	@param signal any -- The signal to hook
	@param handler Handler -- The handler that runs before the callback
	@return (boolean) -> () -- The setter of the property
]=]
function Hooks.ToggleEvent(signal: any, handler: Handler): (boolean) -> ()
	local handle

	return function(value)
		if value then
			if handle then return end
			handle = Hooks.HookEvent(signal, handler)
		else
			Hooks.Release(handle)
			handle = nil
		end
	end
end

return Hooks
