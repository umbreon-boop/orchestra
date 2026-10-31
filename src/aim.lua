--[=[
	A simple to use aiming and target-acquisition utility that supports both camera and input based manipulation.

	@class Aimbot
]=]
local Interface = require("@aria/interface")
local Driver = require("./driver.lua")
local Players = game:GetService("Players")
local Run = game:GetService("RunService")

local MODE = { Camera = "camera", Input = "input" }
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
local raycastCharacter

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	camera = workspace.CurrentCamera
end)

local seed
local jitterTime = 0
local lastJitter = Vector3.zero
local currentTarget
local scanElapsed = 1
local SCAN_INTERVAL = 0.1
local ANGLE_SWITCH_MARGIN = math.rad(2)
-- The default camera rotates 0.5 degrees per pixel horizontally and 0.385
-- vertically for a desktop mouse; touch rotates 0.5 in both axes. Gain 5
-- removes about 44% of the raw angular error per 60 Hz frame; with the
-- one-frame input latency that remains below unity loop gain even when the
-- game renders at 30 FPS.
local INPUT_RESPONSE_GAIN = 5
-- Rotation per pixel at the default camera sensitivity, used to convert target
-- angular velocity to steps.
local INPUT_PLANT = math.rad(0.5)
-- The dead zone rejects camera shake from the feedback term; target motion is
-- still compensated while the positional error is inside it.
local AIM_DEADZONE = math.rad(0.3)
local inputRetryAt = 0
local active = false
-- Keep the camera short of vertical, where yaw is undefined and lookAt can flip.
local MAX_CAMERA_PITCH = math.rad(89)

local targetPart = "HumanoidRootPart"
local targetSelection = "angle"
local runPriority = 200
local smoothness = 1
local sensitivity = 1
local baseInputStepX = 10
local baseInputStepY = -10
local inputTouchArea = {Vector2.new(-1, -1), Vector2.new(-1, -1)}
local prediction = 0
local maxDistance = math.huge
local maxDistanceSquared = math.huge
local fovCosine = 0

local jitterEnabled = false
local jitterIntensity = 1
local jitterFrequency = 1
local jitterScale = 1
local maxJitterOffset = 1

local useRay = false
local respectTeams = false
local activeMode = MODE.Camera

--@inline
local function predictedPosition(character, position)
	local root = prediction > 0 and character:FindFirstChild("HumanoidRootPart")
	return root and position + root.AssemblyLinearVelocity * prediction or position
end

--@inline
local function refresh()
	seed = math.random(1, 1e6)
	jitterTime = 0
	lastJitter = Vector3.zero
end

--@inline
local function jitter(direction, distance, deltaTime)
	local result = direction
	if jitterEnabled then
		jitterTime += deltaTime
		local intensity = jitterIntensity * jitterScale * math.clamp(1 - distance / maxDistance, 0.2, 1.0)
		local maxRadians = math.rad(maxJitterOffset) * intensity
		local phase = jitterTime * jitterFrequency
		local jitterX = math.noise(phase, seed * 0.01) * maxRadians
		local jitterY = math.noise(phase + 50, seed * 0.02) * maxRadians
		lastJitter = lastJitter:Lerp(Vector3.new(jitterX, jitterY, 0), math.clamp(deltaTime * 15, 0, 1))

		local up = math.abs(direction.Y) > 0.99 and Vector3.new(0, 0, 1) or Vector3.new(0, 1, 0)
		local right = direction:Cross(up).Unit
		result = (direction + right * lastJitter.X + right:Cross(direction).Unit * lastJitter.Y).Unit
	end
	return result
end

--@inline
local function valid(targetPlayer)
	local character = targetPlayer.Character
	local humanoid = character and character:FindFirstChild("Humanoid")
	local hit = character and character:FindFirstChild(targetPart)
	local position = hit and hit.Position
	local offset = position and position - camera.CFrame.Position
	local ok = targetPlayer ~= player
	and not (respectTeams and targetPlayer.Team ~= nil and targetPlayer.Team == player.Team)
	and humanoid ~= nil
	and humanoid:IsA("Humanoid")
	and humanoid.Health > 0
	and hit ~= nil
	and hit:IsA("BasePart")
	and offset:Dot(offset) <= maxDistanceSquared

	if ok and useRay then
		local characterToExclude = player.Character
		if characterToExclude ~= raycastCharacter then
			raycastCharacter = characterToExclude
			raycastParams.FilterDescendantsInstances = characterToExclude and {characterToExclude} or {}
		end
		local ray = workspace:Raycast(camera.CFrame.Position, offset, raycastParams)
		ok = not ray or ray.Instance:IsDescendantOf(character)
	end

	if not ok then
		character, hit, position = nil, nil, nil
	end
	return character, hit, position
end

--@inline
local function viewOf(targetPlayer, releaseMargin)
	local result
	local character, hit, position = valid(targetPlayer)
	if position then
		position = predictedPosition(character, position)
		local cf = camera.CFrame
		local offset = position - cf.Position
		local distance = offset.Magnitude
		if distance >= 1e-4 then
			local dot = cf.LookVector:Dot(offset / distance)
			if dot > fovCosine - (releaseMargin or 0) and camera:WorldToViewportPoint(position).Z > 0 then
				result = {part = hit, position = position, dot = dot, distance = distance, player = targetPlayer}
			end
		end
	end
	return result
end

--@inline
local function acquireTarget()
	local best
	local bestScore = math.huge
	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		local candidate = viewOf(targetPlayer)
		if candidate then
			local score = targetSelection == "distance" and candidate.distance or 1 - candidate.dot
			if score < bestScore then
				bestScore = score
				best = candidate
			end
		end
	end
	return best
end

--@inline
local function retainTarget(targetData)
	-- Keep the lock through small camera/controller jitter. Acquisition still
	-- uses the configured FOV; the wider release edge prevents rapid drop/relock.
	local result = viewOf(targetData.player, 0.08)
	return result
end

--@inline
local function rotateCamera(cf, direction, weight)
	local look = cf.LookVector
	local yaw = math.atan2(look.X, -look.Z)
	local pitch = math.asin(math.clamp(look.Y, -1, 1))

	local horizontal = Vector3.new(direction.X, 0, direction.Z)
	local targetYaw = yaw
	if horizontal.Magnitude > 1e-4 then
		targetYaw = math.atan2(horizontal.X, -horizontal.Z)
	end
	local targetPitch = math.clamp(math.asin(math.clamp(direction.Y, -1, 1)), -MAX_CAMERA_PITCH, MAX_CAMERA_PITCH)

	local yawDelta = (targetYaw - yaw + math.pi) % (2 * math.pi) - math.pi
	yaw += yawDelta * weight
	pitch = math.clamp(pitch + (targetPitch - pitch) * weight, -MAX_CAMERA_PITCH, MAX_CAMERA_PITCH)

	local aimed = Vector3.new(math.cos(pitch) * math.sin(yaw), math.sin(pitch), -math.cos(pitch) * math.cos(yaw))
	camera.CFrame = CFrame.lookAt(cf.Position, cf.Position + aimed, Vector3.yAxis)
end

--@inline
local function aim(targetData, deltaTime)
	local cf = camera.CFrame
	local offset = targetData.position - cf.Position
	local distance = offset.Magnitude
	if distance >= 1e-4 then
		local direction = jitter(offset / distance, distance, deltaTime)
		if activeMode == MODE.Camera then
			-- Treat the setting as a response time: low values track quickly, while
			-- higher values damp the movement. Zero is the explicit snap setting.
			local weight = 1
			if smoothness > 0 then
				weight = 1 - math.exp(-12 / smoothness * deltaTime)
			end
			rotateCamera(cf, direction, weight)
		elseif Driver.Active() then
			local forward = direction:Dot(cf.LookVector)
			if forward > 0 then
				local yaw = math.atan2(direction:Dot(cf.RightVector), forward)
				local pitch = math.atan2(direction:Dot(cf.UpVector), forward)

				-- Smoothness divides the step and zero snaps, so it uses a scale of 1. The
				-- elapsed-time factor keeps the angular rate independent of render cadence;
				-- the cap bounds the step after a long frame.
				local inputScale = (smoothness > 0 and 1 / smoothness or 1) * math.min(deltaTime * 60, 2)
				local responseScale = inputScale * sensitivity
				local limitX = math.abs(baseInputStepX * inputScale)
				local limitY = math.abs(baseInputStepY * inputScale)
				local controlX, controlY = 0, 0
				if yaw * yaw + pitch * pitch >= AIM_DEADZONE * AIM_DEADZONE then
					controlX = yaw * INPUT_RESPONSE_GAIN
					controlY = pitch * INPUT_RESPONSE_GAIN
				end

				-- Feed-forward converts the target's angular velocity into the touch step
				-- that cancels it over this frame. It is a physical rate, so it uses real
				-- elapsed time rather than the frame-rate-normalized feedback scale.
				local omega = offset:Cross(targetData.part.AssemblyLinearVelocity) / (distance * distance)
				local feedScale = deltaTime / INPUT_PLANT * sensitivity
				local signX = baseInputStepX < 0 and -1 or 1
				local signY = baseInputStepY < 0 and -1 or 1
				local dx = baseInputStepX * controlX * responseScale - signX * omega:Dot(cf.UpVector) * feedScale
				local dy = baseInputStepY * controlY * responseScale + signY * omega:Dot(cf.RightVector) * feedScale
				dx = math.clamp(dx, -limitX, limitX)
				dy = math.clamp(dy, -limitY, limitY)

				if dx ~= 0 or dy ~= 0 then
					Driver.Step(dx, dy)
				end
			end
		end
	end
end

--@inline
local function renderPriority()
	-- The stock camera writes at Camera priority. Running after it prevents its
	-- update from immediately replacing our camera rotation.
	return math.clamp(runPriority, Enum.RenderPriority.Camera.Value + 1, Enum.RenderPriority.Last.Value)
end

--@inline
local function findTarget()
	local retained
	if currentTarget then
		retained = retainTarget(currentTarget)
	end
	local acquired
	if targetSelection == "angle" then
		acquired = acquireTarget()
		if retained and acquired and acquired.player ~= retained.player then
			local acquiredAngle = math.acos(math.clamp(acquired.dot, -1, 1))
			local retainedAngle = math.acos(math.clamp(retained.dot, -1, 1))
			if acquiredAngle + ANGLE_SWITCH_MARGIN < retainedAngle then
				retained = acquired
			end
		end
	elseif not retained then
		acquired = acquireTarget()
	end
	return retained or acquired
end

local function bound(deltaTime)
	if not camera then return end
	if activeMode == MODE.Input and Driver.Manual() then
		Driver.End()
		inputRetryAt = 0
		return
	end

	scanElapsed += deltaTime
	local found
	if scanElapsed >= SCAN_INTERVAL then
		scanElapsed %= SCAN_INTERVAL
		found = findTarget()
	elseif currentTarget and currentTarget.part.Parent then
		currentTarget.position = predictedPosition(currentTarget.part.Parent, currentTarget.part.Position)
		found = currentTarget
	end

	if not found then
		if currentTarget then
			currentTarget = nil
			refresh()
		end
		return
	end

	if not currentTarget or found.player ~= currentTarget.player then
		refresh()
	end
	currentTarget = found
	if activeMode == MODE.Input and not Driver.Active() and time() >= inputRetryAt then
		inputRetryAt = Driver.Begin(inputTouchArea) and 0 or time() + 0.5
	end
	aim(currentTarget, deltaTime)
end

return Interface.New({
	--[=[
		Toggles the main aiming logic loop

		@prop aim boolean
		@within Aimbot
	]=]
	aim = function(v)
		if v then
			if active then return end
			active = true
			Run:BindToRenderStep("Aimbot", renderPriority(), bound)
		else
			if not active then return end
			active = false
			Run:UnbindFromRenderStep("Aimbot")
			Driver.End()
			currentTarget = nil
			inputRetryAt = 0
		end
	end,

	--[=[
		The name of the character part to target

		@prop targetPart string
		@within Aimbot
	]=]
	targetPart = function(v)
		targetPart = v
	end,

	--[=[
		How valid targets are prioritized inside the field of view: nearest in
		world space or smallest angle from camera look.
		@prop targetSelection string
	]=]
	targetSelection = function(v)
		if v == "distance" or v == "angle" then
			targetSelection = v
			currentTarget = nil
			scanElapsed = SCAN_INTERVAL
		end
	end,

	--[=[
		Camera or input based manipulation mode. On desktop, input mode needs
		first-person, shift lock, or right-mouse panning so the default camera
		consumes mouse movement.

		@prop aimMode string
		@within Aimbot
	]=]
	aimMode = function(v)
		if v ~= MODE.Input and v ~= MODE.Camera then return end
		Driver.End()
		activeMode = v
		currentTarget = nil
		scanElapsed = SCAN_INTERVAL
		inputRetryAt = 0
	end,

	--[=[
		The RenderStep priority for calculations

		@prop runPriority number
		@within Aimbot
	]=]
	runPriority = function(v)
		runPriority = v
		if active then
			Run:UnbindFromRenderStep("Aimbot")
			Run:BindToRenderStep("Aimbot", renderPriority(), bound)
		end
	end,

	--[=[
		Field of View (in degrees) for target acquisition

		@prop fovDeg number
		@within Aimbot
	]=]
	fovDeg = function(v)
		fovCosine = math.cos(math.rad(v / 2))
	end,

	--[=[
		Response-time factor for camera smoothing and inverse input-step scaling.
		Zero snaps in camera mode and uses an input-step scale of 1.

		@prop smoothness number
		@within Aimbot
	]=]
	smoothness = function(v)
		smoothness = math.max(v, 0)
	end,

	--[=[
		Extra multiplier applied to the input step. Values above 1 are allowed,
		but the per-frame multiplier is capped for stability.

		@prop sensitivity number
		@within Aimbot
	]=]
	sensitivity = function(v)
		sensitivity = math.max(v, 0)
	end,

	--[=[
		Base horizontal input movement per radian of aim error. The effective
		step is inversely scaled by smoothness; the sign controls direction.

		@prop baseInputStepX number
		@within Aimbot
	]=]
	baseInputStepX = function(v)
		baseInputStepX = v
	end,

	--[=[
		Base vertical input movement per radian of aim error. The effective step
		is inversely scaled by smoothness; the default sign matches non-inverted
		camera Y.

		@prop baseInputStepY number
		@within Aimbot
	]=]
	baseInputStepY = function(v)
		baseInputStepY = v
	end,

	--[=[
		Viewport-pixel top-left and bottom-right corners of the ignored touch
		region. Synthetic input stays within this rectangle. Set a negative
		coordinate in either corner to choose a GUI-safe region automatically.

		@prop inputTouchArea {Vector2}
		@within Aimbot
	]=]
	inputTouchArea = function(v)
		if type(v) ~= "table" or typeof(v[1]) ~= "Vector2" or typeof(v[2]) ~= "Vector2" then return end
		inputTouchArea = {v[1], v[2]}
		Driver.End()
		inputRetryAt = 0
	end,

	--[=[
		Time (in seconds) to predict target movement

		@prop prediction number
		@within Aimbot
	]=]
	prediction = function(v)
		prediction = v
	end,

	--[=[
		Maximum distance for valid targets

		@prop maxDistance number
		@within Aimbot
	]=]
	maxDistance = function(v)
		maxDistanceSquared = v * v
		maxDistance = v
	end,

	--[=[
		Toggles procedural noise in aim direction

		@prop jitterEnabled boolean
		@within Aimbot
	]=]
	jitterEnabled = function(v)
		jitterEnabled = v
	end,

	--[=[
		Strength of the jitter effect

		@prop jitterIntensity number
		@within Aimbot
	]=]
	jitterIntensity = function(v)
		jitterIntensity = v
	end,

	--[=[
		How fast jitter noise fluctuates

		@prop jitterFrequency number
		@within Aimbot
	]=]
	jitterFrequency = function(v)
		jitterFrequency = v
	end,

	--[=[
		Scalar multiplier for jitter noise

		@prop jitterScale number
		@within Aimbot
	]=]
	jitterScale = function(v)
		jitterScale = v
	end,

	--[=[
		Maximum angular offset (in degrees) for jitter

		@prop maxJitterOffset number
		@within Aimbot
	]=]
	maxJitterOffset = function(v)
		maxJitterOffset = v
	end,

	--[=[
		Uses raycasts to check for wall obstruction

		@prop useRay boolean
		@within Aimbot
	]=]
	useRay = function(v)
		useRay = v
	end,

	--[=[
		Skips players on the same team as the local player

		@prop respectTeams boolean
		@within Aimbot
	]=]
	respectTeams = function(v)
		respectTeams = v
	end
})
