--[=[
	Basic module for cross platform input manipulation.
	@class Driver
]=]
local Input = game:GetService("UserInputService")
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local Virtual = game:GetService("VirtualInputManager")
if cloneref then
	Virtual = cloneref(Virtual)
end
local player = Players.LocalPlayer

-- The desktop camera consumes relative mouse movement. An absolute warp only
-- repositions the cursor without producing the camera's mouse delta.
local executorMouseMove
do
	local ok, environment = pcall(getgenv)
	if ok and type(environment) == "table" then
		for _, name in ipairs({"mousemoverel", "MouseMoveRel", "mouse_moverel"}) do
			local candidate = rawget(environment, name)
			if typeof(candidate) == "function" then
				executorMouseMove = candidate
				break
			end
		end
	end
end

local deltaMouseMove
if Virtual then
	local ok, sendDelta = pcall(function()
		return Virtual.SendMouseMoveDeltaEvent
	end)
	if ok and typeof(sendDelta) == "function" then
		deltaMouseMove = function(dx, dy)
			return pcall(sendDelta, Virtual, dx, dy, game)
		end
	end
end

local function relativeMouseMove(dx, dy)
	if executorMouseMove then
		if pcall(executorMouseMove, dx, dy) then
			return true
		end
		executorMouseMove = nil
	end
	if deltaMouseMove then
		if deltaMouseMove(dx, dy) then
			return true
		end
		deltaMouseMove = nil
	end
	return false
end

local function mouseMoveAvailable()
	return executorMouseMove ~= nil or deltaMouseMove ~= nil or Virtual ~= nil
end

local TYPE = { Mouse = "Mouse", Touch = "Touch" }
local SYNTHETIC_MATCH_TIME = 0.25
local SYNTHETIC_MATCH_RADIUS = 4
local TOUCH_ANCHORS = {
	Vector2.new(0.65, 0.5),
	Vector2.new(0.75, 0.5),
	Vector2.new(0.65, 0.35),
	Vector2.new(0.75, 0.65),
	Vector2.new(0.78, 0.35),
	Vector2.new(0.82, 0.2),
	Vector2.new(0.2, 0.2),
}

--@inline
local function viewportSize()
	local currentCamera = workspace.CurrentCamera
	local result = Vector2.zero
	if currentCamera then
		result = currentCamera.ViewportSize
	end
	return result
end

--@inline
local function automaticArea(area)
	return not area or not area[1] or not area[2]
	or area[1].X < 0 or area[1].Y < 0 or area[2].X < 0 or area[2].Y < 0
end

--@inline
local function guiAt(position)
	local result = false
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		local ok, objects = pcall(playerGui.GetGuiObjectsAtPosition, playerGui, position.X, position.Y)
		if ok then
			for _, object in ipairs(objects) do
				if object.Visible and (object:IsA("GuiButton") or object:IsA("ScrollingFrame") or object:IsA("TextBox") or object.Active) then
					result = true
					break
				end
			end
		end
	end
	return result
end

-- Keep the synthetic touch away from GUI controls. The result is cached because
-- a target that flickers in and out of view can call Begin repeatedly, and
-- GetGuiObjectsAtPosition is not cheap on mobile.
local cachedSpawn
local cachedSize
local cachedAt = 0
local manualTouches = {}
local manualTouchCount = 0
local syntheticStarts = {}
-- VirtualInputManager takes screen coordinates, while InputObject.Position is
-- reported in viewport coordinates. The conversion is fixed per viewport size,
-- so measure it from the first synthetic start instead of assuming an inset.
local viewportOrigin
local originSize
local ORIGIN_MATCH_LIMIT = 200

--@inline
local function defaultOrigin()
	return Vector2.new(0, GuiService:GetGuiInset().Y)
end

--@inline
local function sendTouch(touchId, state, position, offset)
	return pcall(
		Virtual.SendTouchEvent,
		Virtual,
		touchId,
		state,
		position.X + offset.X,
		position.Y + offset.Y
	)
end

--@inline
local function spawnPoint(size)
	local result
	if cachedSpawn and cachedSize == size and time() - cachedAt < 0.5 then
		result = cachedSpawn
	else
		-- Prefer the right-side look region and keep the starting point near the
		-- middle so either direction has room before the touch must be rebased.
		for _, anchor in ipairs(TOUCH_ANCHORS) do
			for _ = 1, 2 do
				local point = Vector2.new(size.X * (anchor.X + (math.random() - 0.5) * 0.04), size.Y * (anchor.Y + (math.random() - 0.5) * 0.04))
				if not guiAt(point) then
					result = point
					break
				end
			end
			if result then break end
		end

		if not result then
			result = Vector2.new(math.clamp(size.X * 0.65, 1, size.X - 1), math.clamp(size.Y * 0.5, 1, size.Y - 1))
		end
		cachedSpawn = result
		cachedSize = size
		cachedAt = time()
	end
	return result
end

--@inline
local function pruneSynthetic(now)
	for index = #syntheticStarts, 1, -1 do
		if now - syntheticStarts[index].at > SYNTHETIC_MATCH_TIME then
			table.remove(syntheticStarts, index)
		end
	end
end

--@inline
local function markSynthetic(position, offset)
	local now = time()
	pruneSynthetic(now)
	table.insert(syntheticStarts, {position = position, offset = offset or Vector2.zero, at = now})
end

local dispatchers = {
	[TYPE.Touch] = {
		_touchId = nil,
		_firstTouchPos = nil,
		_lastCommand = nil,
		_pendingDelta = Vector2.new(0, 0),
		_currentPos = nil,
		_sendOffset = Vector2.zero,

		Begin = function(self, requestedArea)
			local size = viewportSize()
			if not Virtual or size.X <= 0 or size.Y <= 0 then return false end

			self._touchId = math.random(100, 999)
			local margin = math.min(size.X, size.Y) * 0.02
			local autoArea = automaticArea(requestedArea)
			local start
			if autoArea then
				start = spawnPoint(size)
				local radius = math.min(size.X, size.Y) * 0.4
				self._regionMin = Vector2.new(math.max(margin, start.X - radius), math.max(margin, start.Y - radius))
				self._regionMax = Vector2.new(math.min(size.X - margin, start.X + radius), math.min(size.Y - margin, start.Y + radius))
			else
				local first = requestedArea[1]
				local second = requestedArea[2]
				self._regionMin = Vector2.new(
					math.clamp(math.min(first.X, second.X), margin, size.X - margin),
					math.clamp(math.min(first.Y, second.Y), margin, size.Y - margin)
				)
				self._regionMax = Vector2.new(
					math.clamp(math.max(first.X, second.X), margin, size.X - margin),
					math.clamp(math.max(first.Y, second.Y), margin, size.Y - margin)
				)
				start = (self._regionMin + self._regionMax) / 2
			end
			if not start then
				self._touchId = nil
				return false
			end
			self._firstTouchPos = start
			self._currentPos = self._firstTouchPos
			-- Move is expressed in viewport coordinates; initialize its origin so
			-- the first relative Step is not silently discarded.
			self._lastCommand = size / 2
			self._pendingDelta = Vector2.new(0, 0)
			-- Keep one conversion for the whole session. Switching halfway would
			-- jump the touch by the viewport origin.
			self._sendOffset = viewportOrigin or defaultOrigin()
			markSynthetic(start, self._sendOffset)
			if not sendTouch(self._touchId, 0, start, self._sendOffset) then
				self:End()
				return false
			end
			return true
		end,

		Move = function(self, x, y)
			if not self._touchId then return end
			local size = viewportSize()
			if size.X <= 0 or size.Y <= 0 then return end

			local target = Vector2.new(x, y)
			local commandDelta = self._lastCommand and target - self._lastCommand or Vector2.new(0, 0)
			self._lastCommand = target
			self._pendingDelta += commandDelta
			-- Near the target the controller intentionally emits sub-pixel
			-- steps. Forward them every frame; _currentPos keeps the fractional
			-- remainder, so a quantizing pipeline accumulates it instead of
			-- losing it.
			if self._pendingDelta.Magnitude < 0.01 then return end
			commandDelta = self._pendingDelta
			self._pendingDelta = Vector2.new(0, 0)

			local final = self._currentPos + commandDelta
			if final.X < self._regionMin.X or final.X > self._regionMax.X
				or final.Y < self._regionMin.Y or final.Y > self._regionMax.Y
			then
				-- A fresh id keeps camera modules from diffing positions across
				-- the end/begin boundary and treating the recenter as movement.
				local previousId = self._touchId
				sendTouch(previousId, 2, self._currentPos, self._sendOffset)
				repeat
					self._touchId = math.random(100, 999)
				until self._touchId ~= previousId
				self._currentPos = self._firstTouchPos
				markSynthetic(self._currentPos, self._sendOffset)
				sendTouch(self._touchId, 0, self._currentPos, self._sendOffset)
				-- Send the new start alone. If a move follows in the same frame,
				-- the reported start position can already include that move; the
				-- manual-touch detector then mistakes the synthetic touch for a
				-- real one and the aim loop stops for half a second. Carry the
				-- command into the next Move instead.
				self._pendingDelta = commandDelta
				return
			end
			final = Vector2.new(
				math.clamp(final.X, self._regionMin.X, self._regionMax.X),
				math.clamp(final.Y, self._regionMin.Y, self._regionMax.Y)
			)
			self._currentPos = final
			sendTouch(self._touchId, 1, final, self._sendOffset)
		end,

		End = function(self)
			if self._touchId then
				sendTouch(self._touchId, 2, self._currentPos, self._sendOffset)
			end
			self._touchId = nil
			self._firstTouchPos = nil
			self._lastCommand = nil
			self._pendingDelta = Vector2.new(0, 0)
			self._currentPos = nil
			self._sendOffset = Vector2.zero
		end,

		Fire = function(self, x, y)
			local fireTouchId = (self._touchId or math.random(100, 999)) + 1
			local offset = viewportOrigin or defaultOrigin()
			if self._touchId then
				offset = self._sendOffset
			end
			local position = Vector2.new(x, y)
			markSynthetic(position, offset)
			sendTouch(fireTouchId, 0, position, offset)
			task.delay(0.05, function()
				sendTouch(fireTouchId, 2, position, offset)
			end)
		end
	},

	[TYPE.Mouse] = {
		_active = false,
		_relative = false,
		_lastCommand = Vector2.new(0, 0),
		_pendingDelta = Vector2.new(0, 0),

		Begin = function(self)
			if not mouseMoveAvailable() then return false end
			self._active = true
			self._relative = executorMouseMove ~= nil or deltaMouseMove ~= nil
			self._lastCommand = Input:GetMouseLocation()
			self._pendingDelta = Vector2.new(0, 0)
			return true
		end,

		Move = function(self, x, y)
			if not self._active then return end
			local target = Vector2.new(x, y)
			local origin = self._lastCommand or Input:GetMouseLocation()
			self._lastCommand = target
			self._pendingDelta += target - origin
			-- The aim loop emits sub-pixel steps near the target. Send whole
			-- pixels and retain the remainder so those steps accumulate.
			local stepX = math.floor(self._pendingDelta.X + 0.5)
			local stepY = math.floor(self._pendingDelta.Y + 0.5)
			if stepX == 0 and stepY == 0 then return end
			self._pendingDelta -= Vector2.new(stepX, stepY)
			if self._relative then
				if relativeMouseMove(stepX, stepY) then return end
				self._relative = false
			end
			if Virtual then
				pcall(
					Virtual.SendMouseMoveEvent,
					Virtual,
					target.X - self._pendingDelta.X,
					target.Y - self._pendingDelta.Y,
					game
				)
			end
		end,

		End = function(self)
			self._active = false
			self._relative = false
			self._lastCommand = nil
			self._pendingDelta = Vector2.new(0, 0)
		end,

		Fire = function(_, x, y)
			Virtual:SendMouseButtonEvent(x, y, 0, true, game, 1)
			task.delay(0.05, function()
				Virtual:SendMouseButtonEvent(x, y, 0, false, game, 1)
			end)
		end
	}
}

--@inline
local function consumeSynthetic(position, viewportPosition, size)
	pruneSynthetic(time())
	if viewportOrigin and originSize ~= size then
		viewportOrigin = nil
		originSize = nil
	end
	local result = false
	for index = #syntheticStarts, 1, -1 do
		local entry = syntheticStarts[index]
		local matched = (position - entry.position).Magnitude <= SYNTHETIC_MATCH_RADIUS
		or (viewportPosition - entry.position).Magnitude <= SYNTHETIC_MATCH_RADIUS
		if not matched then
			if viewportOrigin then
				matched = (position - entry.offset + viewportOrigin - entry.position).Magnitude
				<= SYNTHETIC_MATCH_RADIUS
			else
				local guessed = entry.position + entry.offset - position
				if guessed.Magnitude <= ORIGIN_MATCH_LIMIT and guessed.X >= 0 and guessed.Y >= 0 then
					viewportOrigin = guessed
					originSize = size
					matched = true
				end
			end
		end
		if matched then
			table.remove(syntheticStarts, index)
			result = true
			break
		end
	end
	return result
end

Input.TouchStarted:Connect(function(touchObj, processed)
	if processed then return end
	local position = Vector2.new(touchObj.Position.X, touchObj.Position.Y)
	local inset = GuiService:GetGuiInset()
	local size = viewportSize()
	local viewportPosition = Vector2.new(position.X - inset.X, position.Y - inset.Y)
	if consumeSynthetic(position, viewportPosition, size) then return end
	local leftHalf = size.X > 0 and size.Y > 0 and (
		(position.X <= size.X * 0.5 and position.Y >= size.Y * 0.35)
		or (viewportPosition.X <= size.X * 0.5 and viewportPosition.Y >= size.Y * 0.35)
	)
	if leftHalf then return end
	manualTouches[touchObj] = {position = position, distance = 0, moved = false}
end)

Input.TouchMoved:Connect(function(touchObj)
	local entry = manualTouches[touchObj]
	if not entry then return end
	local position = Vector2.new(touchObj.Position.X, touchObj.Position.Y)
	entry.distance += (position - entry.position).Magnitude
	entry.position = position
	if not entry.moved and entry.distance >= 2 then
		entry.moved = true
		manualTouchCount += 1
	end
end)

Input.TouchEnded:Connect(function(touchObj)
	local entry = manualTouches[touchObj]
	if entry and entry.moved then
		manualTouchCount -= 1
	end
	manualTouches[touchObj] = nil
end)

--@inline
local function activeInput()
	local result = TYPE.Mouse
	-- Keyboard availability is not a reliable desktop/mobile discriminator
	-- (tablets and some mobile executors report a keyboard). Prefer touch when
	-- the device has no physical mouse, while still honoring the last real input.
	if Input:GetLastInputType() == Enum.UserInputType.Touch
		or (Input.TouchEnabled and not Input.MouseEnabled) then
		result = TYPE.Touch
	end
	return result
end

local current = dispatchers[activeInput()]
local active
Input.LastInputTypeChanged:Connect(function()
	current = dispatchers[activeInput()]
end)

local Driver = {}

--@inline
local function session()
	return active or current
end

--[=[
	Moves the active pointer/touch toward the given screen position.

	@param x number
	@param y number
	@return ()
]=]
function Driver.Move(x: number, y: number)
	local dispatcher = session()
	dispatcher:Move(x, y)
end

--[=[
	Moves the active pointer/touch by a relative amount in pixels.

	@param dx number
	@param dy number
	@return ()
]=]
function Driver.Step(dx: number, dy: number)
	local dispatcher = session()
	local origin = dispatcher._lastCommand or Input:GetMouseLocation()
	dispatcher:Move(origin.X + dx, origin.Y + dy)
end

--[=[
	Starts an input session for the active input type.
	@return ()
]=]
function Driver.Begin(touchArea: {Vector2}?): boolean
	if active then
		return true
	end
	active = current
	if not active.Begin then
		active = nil
		return false
	end
	local started = active:Begin(touchArea) ~= false
	if not started then
		active = nil
	end
	return started
end

--[=[
	Ends the current input session for the active input type.
	@return ()
]=]
function Driver.End()
	if active then
		active:End()
		active = nil
	end
end

function Driver.Active(): boolean
	return active ~= nil
end

function Driver.Manual(): boolean
	return manualTouchCount > 0
end

--[=[
	Fires a press-and-release input at the given screen position.

	@param x number
	@param y number
	@return ()
]=]
function Driver.Fire(x: number, y: number)
	if not Virtual then return end
	session():Fire(x, y)
end

return Driver
