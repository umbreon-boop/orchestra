--[=[
	A simple to use, table-like API for optimizing the resource usage of the Roblox engine.
	@class Performance
]=]
local Interface = require("@aria/interface")
local Lighting = game:GetService("Lighting")
local Terrain = workspace:FindFirstChildWhichIsA("Terrain")

local Performance = {
	terrain = {},
	light = {},
	settings = {},
}

local useLight
local connection
local function patch(instance)
	local isLight = useLight and instance:IsA("Light")
	if isLight or instance:IsA("PostEffect") or instance:IsA("Beam") or instance:IsA("Highlight") then
		instance.Enabled = false
	elseif instance:IsA("ParticleEmitter") then
		instance.Enabled = false
		instance:Clear()
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		instance.Transparency = 1
	elseif instance:IsA("Explosion") then
		instance.Visible = false
	elseif instance:IsA("BasePart") then
		instance.CastShadow = false
		instance.Material = Enum.Material.SmoothPlastic
		instance.Reflectance = 0
	end
end

return Interface.New({
	--[=[
		Disables water waves and reflections.
		@prop water bool
	]=]
	water = function(v)
		if not Terrain then return end
		if v then
			Performance.terrain.size = Terrain.WaterWaveSize
			Performance.terrain.speed = Terrain.WaterWaveSpeed
			Performance.terrain.reflectance = Terrain.WaterReflectance
			Performance.terrain.transparency = Terrain.WaterTransparency

			Terrain.WaterWaveSize = 0
			Terrain.WaterWaveSpeed = 0
			Terrain.WaterReflectance = 0
			Terrain.WaterTransparency = 1
		elseif Performance.terrain.size ~= nil then
			Terrain.WaterWaveSize = Performance.terrain.size
			Terrain.WaterWaveSpeed = Performance.terrain.speed
			Terrain.WaterReflectance = Performance.terrain.reflectance
			Terrain.WaterTransparency = Performance.terrain.transparency
		end
	end,

	--[=[
		Disables dynamic lighting.
		@prop light bool
	]=]
	light = function(v)
		if v then
			if useLight then return end
			useLight = true
			Performance.light.shadow = Lighting.GlobalShadows
			Performance.light.diffuse = Lighting.EnvironmentDiffuseScale
			Performance.light.specular = Lighting.EnvironmentSpecularScale
			Performance.light.ambient = Lighting.OutdoorAmbient
			Performance.light.brightness = Lighting.Brightness
			Performance.light.fogEnd = Lighting.FogEnd
			Performance.light.fogStart = Lighting.FogStart

			Lighting.GlobalShadows = false
			Lighting.EnvironmentDiffuseScale = 0
			Lighting.EnvironmentSpecularScale = 0
			Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
			Lighting.Brightness = 2
			Lighting.FogEnd = 9e9
			Lighting.FogStart = 9e9
		else
			if not useLight then return end
			useLight = false
			Lighting.GlobalShadows = Performance.light.shadow
			Lighting.EnvironmentDiffuseScale = Performance.light.diffuse
			Lighting.EnvironmentSpecularScale = Performance.light.specular
			Lighting.OutdoorAmbient = Performance.light.ambient
			Lighting.Brightness = Performance.light.brightness
			Lighting.FogEnd = Performance.light.fogEnd
			Lighting.FogStart = Performance.light.fogStart
		end
	end,

	--[=[
		Allows the physics engine to sleep.
		@prop settings bool
	]=]
	settings = function(v)
		if v then
			if Performance.settings.quality ~= nil then return end
			Performance.settings.quality = settings().Rendering.QualityLevel
			Performance.settings.sleep = settings().Physics.AllowSleep

			settings().Rendering.QualityLevel = 1
			settings().Physics.AllowSleep = true
		elseif Performance.settings.quality ~= nil then
			settings().Rendering.QualityLevel = Performance.settings.quality
			settings().Physics.AllowSleep = Performance.settings.sleep
		end
	end,

	--[=[
		Hides resource intensive instances to reduce GPU strain.
		@prop patch bool
	]=]
	patch = function(v)
		if v then
			for _, instance in ipairs(game:GetDescendants()) do
				patch(instance)
			end

			connection = game.DescendantAdded:Connect(patch)
		else
			if connection then
				connection:Disconnect()
			end
		end
	end,
})
