--[=[
	A simple to use, table-like API for spoofing the camera location. This module is heavily inspired from Averiias's Universal-SilentAim.

	@class Silent
]=]
local Hooks = require("./hooks")
local Interface = require("@aria/interface")

local Players = game:GetService("Players")
local Run = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local players = Players.GetPlayers
local child = game.FindFirstChild
local dot = Vector3.new().Dot
local rad = math.rad
local cos = math.cos
local vec = Vector2.new

local camera
local convert
--@inline
local function setCamera()
	camera = workspace.CurrentCamera
	convert = camera and camera.WorldToViewportPoint or nil
end
setCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	setCamera()
end)

local connection
local params = RaycastParams.new()
params.IgnoreWater = true
params.FilterType = Enum.RaycastFilterType.Exclude

local angle = cos(rad(30))
local wall = false
local team = false
local part = "Head"
local selection = "crosshair"
local root = "HumanoidRootPart"
local real = false
local drag = 0
local speed = 100
local gravity = 196.2
local predict = 0
local target
local scanElapsed = 0
local SCAN_INTERVAL = 0.1

--[=[
	An Interface that stores settings related to the acquisition of targets and the routing of their position to the hooks

	@interface Router
	@within Silent
]=]
local router = Interface.New({
	--[=[
		Toggles the target acquisition functionality, basically a kill switch for the whole module

		@prop enabled boolean
		@within Router
	]=]
	enabled = function(v)
		if v then
			if connection then return end
			connection = Run.Heartbeat:Connect(function(deltaTime)
				scanElapsed += deltaTime
				if scanElapsed < SCAN_INTERVAL then return end
				scanElapsed = 0

				if not camera then
					target = nil
					return
				end

				local char = player.Character or child(workspace, player.Name)
				local self = char and child(char, root)
				if not self then
					target = nil
					return
				end

				local origin = self.Position
				local fwd = camera.CFrame.LookVector
				if wall then
					local localCharacter = player.Character
					params.FilterDescendantsInstances = {}
					if localCharacter then
						params.FilterDescendantsInstances = {localCharacter}
					end
				end

				local bestPos = nil
				local bestScore = math.huge

				for _, plr in pairs(players(Players)) do
					if plr == player then
						continue
					end

					if team and plr.Team ~= nil and plr.Team == player.Team then
						continue
					end

					local character = plr.Character or child(workspace, plr.Name)
					local humanoid = character and child(character, "Humanoid")
					local inst = character and child(character, part)

					if not inst or not humanoid or not (humanoid.Health > 0) then
						continue
					end

					if wall then
						local offset = inst.Position - origin
						local distance = offset.Magnitude
						if distance < 1e-4 then
							continue
						end
						local result = workspace:Raycast(origin, offset / distance * (distance + 1), params)

						if not result or not result.Instance:IsDescendantOf(character) then
							continue
						end
					end

					local pos = inst.Position
					local vel = inst.Velocity
					local aimPos

					if real then
						local t = (pos - origin).Magnitude / math.max(speed * (1 - drag), 1e-3)
						aimPos = pos + vel * (t + predict) + Vector3.new(0, -0.5 * gravity * t * t, 0)
					else
						aimPos = pos + vel * predict
					end

					local alignment = dot(fwd, (aimPos - origin).Unit)
					if alignment < angle then
						continue
					end

					local score
					if selection == "distance" then
						score = (aimPos - origin).Magnitude
					elseif selection == "angle" then
						score = 1 - alignment
					else
						local screen, onScreen = camera:WorldToViewportPoint(aimPos)
						if not onScreen then continue end
						local viewport = camera.ViewportSize
						local dx = screen.X - viewport.X / 2
						local dy = screen.Y - viewport.Y / 2
						score = dx * dx + dy * dy
					end

					if score < bestScore then
						bestPos = aimPos
						bestScore = score
					end
				end

				target = bestPos
			end)
		else
			if connection then
				connection:Disconnect()
				connection = nil
			end
			target = nil
		end
	end,

	--[=[
		Angle (in degrees) from the original direction to target part after which the hooks will ignore the vectors

		@prop angle number
		@within Router
	]=]
	angle = function(v)
		angle = cos(rad(v))
	end,

	--[=[
		Uses raycasts to check target visibility during selection

		@prop wall boolean
		@within Router
	]=]
	wall = function(v)
		wall = v
	end,

	--[=[
		Skips players on the same team as the local player

		@prop team boolean
		@within Router
	]=]
	team = function(v)
		team = v
	end,

	--[=[
		Name of the part the router will target

		@prop part string
		@within Router
	]=]
	part = function(v)
		part = v
	end,

	--[=[
		How valid targets are prioritized inside the angle limit.
		@prop selection string
		@within Router
	]=]
	selection = function(v)
		if v == "crosshair" or v == "distance" or v == "angle" then
			selection = v
			scanElapsed = SCAN_INTERVAL
		end
	end,

	--[=[
		Name of the root part of your local character

		@prop root string
		@within Router
	]=]
	root = function(v)
		root = v
	end,

	--[=[
		Realistic projectile ballistics, enable for non-hitscan weapons

		@prop real boolean
		@within Router
	]=]
	real = function(v)
		real = v
	end,

	--[=[
		Drag coefficient of the projectiles

		@prop drag number
		@within Router
	]=]
	drag = function(v)
		drag = v
	end,

	--[=[
		Average speed of the projectile

		@prop speed number
		@within Router
	]=]
	speed = function(v)
		speed = v
	end,

	--[=[
		Gravitational acceleration of the projectile

		@prop gravity number
		@within Router
	]=]
	gravity = function(v)
		gravity = v
	end,

	--[=[
		Time (in seconds) to project target velocity

		@prop predict number
		@within Router
	]=]
	predict = function(v)
		predict = v
	end,

})

local rayHandle
local mouseHandle
local viewHandle

--[=[
	Just go check the Router docs instead
	@prop route Router
]=]
return Interface.New({
	--[=[
		Makes all casted rays point towards the target
		@prop ray boolean
	]=]
	ray = function(v)
		if v then
			rayHandle = Hooks.HookMeta(workspace, "__namecall", function(original, self, ...)
				if self ~= workspace or not target then
					return nil
				end

				local method = getnamecallmethod()
				local args = { ... }

				if method == "Raycast" then
					local origin = args[1]
					local direction = args[2]

					if origin and direction and dot(direction.Unit, (target - origin).Unit) >= angle then
						args[2] = (target - origin).Unit * direction.Magnitude
						return original(self, table.unpack(args))
					end
				elseif
					method == "findPartOnRay"
					or method == "FindPartOnRay"
					or method == "FindPartOnRayWithIgnoreList"
					or method == "FindPartOnRayWithWhitelist"
				then
					local ray = args[1]

					if ray then
						local origin = ray.Origin
						local direction = ray.Direction

						if dot(direction.Unit, (target - origin).Unit) >= angle then
							args[1] = Ray.new(origin, (target - origin).Unit * direction.Magnitude)
							return original(self, table.unpack(args))
						end
					end
				end

				return nil
			end)
		else
			Hooks.Release(rayHandle)
			rayHandle = nil
		end
	end,

	--[=[
		Spoofs the mouse position to point towards the target
		@prop mouse boolean
	]=]
	mouse = function(v)
		if v then
			mouseHandle = Hooks.HookMeta(game, "__index", function(original, self, field, ...)
				if self == mouse and target then
					if field == "Target" or field == "target" then
						return target
					elseif field == "Hit" or field == "hit" then
						return CFrame.new(target)
					elseif field == "UnitRay" then
						local ray = original(self, field, ...)
						local origin = ray.Origin
						return Ray.new(origin, (target - origin).Unit * ray.Direction.Magnitude)
					end
				end

				return nil
			end)
		else
			Hooks.Release(mouseHandle)
			mouseHandle = nil
		end
	end,

	--[=[
		Spoofs your ViewportSize so that the crosshair always points towards the target
		@prop view boolean
	]=]
	view = function(v)
		if v then
			viewHandle = Hooks.HookMeta(game, "__index", function(_, self, field)
				if self == camera and target and field == "ViewportSize" and convert then
					local pos, on = convert(self, target)

					if on then
						return vec(pos.X * 2, pos.Y * 2)
					end
				end

				return nil
			end)
		else
			Hooks.Release(viewHandle)
			viewHandle = nil
		end
	end,
}, {route = router})
