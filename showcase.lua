local Apogee = loadstring(game:HttpGet("https://github.com/umbreon-boop/apogee/releases/latest/download/artifact.lua"))()
local Orchestra = require("./src/lib")
local Input = game:GetService("UserInputService")

local Aim = Orchestra.Aim
local Bypass = Orchestra.Bypass
local Driver = Orchestra.Driver
local Performance = Orchestra.Performance
local Silent = Orchestra.Silent
local Router = Silent.route

-- Camera mode writes CFrame on top of the default camera, which cannot follow
-- it back into its own yaw/pitch state on touch devices. Start those in input
-- mode so the game's camera remains authoritative.
local defaultMode = "Camera"
if Input.TouchEnabled and not Input.KeyboardEnabled then defaultMode = "Input" end

-- Start the modules at the same values the widgets display.
Aim.targetPart = "HumanoidRootPart"
Aim.targetSelection = "angle"
Aim.aimMode = string.lower(defaultMode)
Aim.runPriority = 200
Aim.fovDeg = 90
Aim.smoothness = 1
Aim.sensitivity = 1
Aim.baseInputStepX = 10
Aim.baseInputStepY = -10
Aim.inputTouchArea = {Vector2.new(-1, -1), Vector2.new(-1, -1)}
Aim.prediction = 0
Aim.maxDistance = 500
Aim.jitterEnabled = false
Aim.jitterIntensity = 1
Aim.jitterFrequency = 1
Aim.jitterScale = 1
Aim.maxJitterOffset = 1
Aim.useRay = false
Aim.respectTeams = false

Router.enabled = false
Router.angle = 30
Router.wall = false
Router.team = false
Router.part = "Head"
Router.selection = "crosshair"
Router.root = "HumanoidRootPart"
Router.real = false
Router.drag = 0
Router.speed = 100
Router.gravity = 196.2
Router.predict = 0

local MODES = {Camera = "camera", Input = "input"}
local toggles = {}

-- Wires a toggle to an Interface property and remembers it for the shutdown sweep.
local function feature(section, interface, property, config)
	config.Callback = function(value)
		interface[property] = value
	end

	local toggle = section:Toggle(config)
	table.insert(toggles, toggle)
	return toggle
end

local function track(toggle)
	table.insert(toggles, toggle)
	return toggle
end

local function slider(section, title, interface, property, value, min, max, rounding)
	section:Slider({
		Title = title,
		Value = value,
		Min = min,
		Max = max,
		Rounding = rounding,
		Callback = function(newValue)
			interface[property] = newValue
		end,
	})
end

local function viewportCenter()
	local camera = workspace.CurrentCamera

	if not camera then
		return nil
	end

	local size = camera.ViewportSize
	return size.X / 2, size.Y / 2
end

local squircle = Apogee.ThemeService:Default("Frame")
local function ImGuiFrame(instance: any, _radius: number, shape: string)
	squircle(instance, 1, shape)
end

local function ImGuiCorner(corner: UICorner)
	corner.CornerRadius = UDim.new(0, 0)
end

local function ImGuiIcon(label: ImageLabel)
	label.Image = ""
end

local function ImGuiToggle(frame: Frame): any
	local checkmark = Apogee.Creator:New("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		Text = "V",
		FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold),
		Themed = {TextColor3 = "Accent"},
		TextTransparency = 1,
		ZIndex = 2
	})
	local box = Apogee.Creator:New("Frame", {
		Size = UDim2.fromOffset(18, 18),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Parent = frame,
		BorderSizePixel = 1,
		Themed = {BackgroundColor3 = "Field", BorderColor3 = "ControlBorder"}
	}, {checkmark})

	return {
		Paint = function(enabled: boolean)
			checkmark.TextTransparency = 1
			if enabled then checkmark.TextTransparency = 0 end
		end,
		Destroy = function()
			box:Destroy()
		end
	}
end

local function ImGuiSlider(frame: Frame): any
	local fill = Apogee.Creator:New("Frame", {Size = UDim2.fromScale(0, 1), Themed = {BackgroundColor3 = "Accent"}})
	local display = Apogee.Creator:New("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json"),
		TextSize = 13,
		ZIndex = 3
	})
	local hitbox = Apogee.Creator:New("TextButton", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 4})
	local rail = Apogee.Creator:New("Frame", {
		Size = UDim2.new(0.40, 0, 0, 20),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Parent = frame,
		BorderSizePixel = 1,
		Themed = {BackgroundColor3 = "Field", BorderColor3 = "ControlBorder"}
	}, {fill, display, hitbox})

	return {
		Rail = rail,
		Hitbox = hitbox,
		Paint = function(value: number, scale: number)
			fill.Size = UDim2.fromScale(scale, 1)
			display.Text = tostring(value)
		end,
		Destroy = function()
			rail:Destroy()
		end
	}
end

local ImGuiSymbols = {
	x = "X",
	scan = "O",
	["minimize-2"] = "O",
	minus = "_"
}

local function ImGuiTitleBarButton(button: TextButton, window: any, _image: string, highlight: string?, name: string): any
	button.Size = UDim2.fromOffset(24, 24)
	local fill = Apogee.Creator:New("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0,
		BorderSizePixel = 1,
		Parent = button,
		Text = ImGuiSymbols[name] or "",
		TextSize = 13,
		FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold),
		Themed = {BackgroundColor3 = "Control", BorderColor3 = "ControlBorder"}
	})
	local function paint(key: string)
		Apogee.ThemeService:Override(fill, {BackgroundColor3 = key})
	end
	local entered = button.MouseEnter:Connect(function()
		paint(highlight or "Hover")
	end)
	local left = button.MouseLeave:Connect(function()
		paint("Control")
	end)

	return {
		Destroy = function()
			entered:Disconnect()
			left:Disconnect()
			fill:Destroy()
		end
	}
end

local function ImGuiNotificationClose(button: TextButton, _window: any, _image: string?): any
	local label = Apogee.Creator:New("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "X",
		TextSize = 13,
		FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold),
		Parent = button,
		Themed = {TextColor3 = "SubText"}
	})
	local entered = button.MouseEnter:Connect(function()
		Apogee.ThemeService:Override(label, {TextColor3 = "Text"})
	end)
	local left = button.MouseLeave:Connect(function()
		Apogee.ThemeService:Override(label, {TextColor3 = "SubText"})
	end)
	return {
		Destroy = function()
			entered:Disconnect()
			left:Disconnect()
			label:Destroy()
		end
	}
end

Apogee:AddTheme("ImGui", {
	Background = Color3.fromRGB(15, 15, 15),
	Surface = Color3.fromRGB(25, 25, 25),
	Overlay = Color3.fromRGB(36, 54, 91),
	Control = Color3.fromRGB(41, 74, 122),
	Field = Color3.fromRGB(18, 18, 18),
	Divider = Color3.fromRGB(80, 80, 80),
	Border = Color3.fromRGB(80, 80, 80),
	ControlBorder = Color3.fromRGB(80, 80, 80),
	Text = Color3.fromRGB(240, 240, 240),
	SubText = Color3.fromRGB(160, 160, 160),
	Accent = Color3.fromRGB(66, 150, 250),
	Destructive = Color3.fromRGB(200, 50, 50),
	Hover = Color3.fromRGB(66, 150, 250),
	HoverChange = 0.15,
	Font = Enum.Font.RobotoMono,
	Components = {
		Frame = ImGuiFrame,
		Corner = ImGuiCorner,
		Icon = ImGuiIcon,
		Toggle = ImGuiToggle,
		Slider = ImGuiSlider,
		TitleBarButton = ImGuiTitleBarButton,
		NotificationClose = ImGuiNotificationClose
	}
})

local minimizerMark = Apogee.Creator:New("TextLabel", {
	Name = "ImGuiRestoreMark",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Text = "O",
	TextSize = 22,
	FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold),
	Themed = {TextColor3 = "Text"},
})

local window = Apogee:Window({
	Title = "Orchestra",
	SubTitle = "Apogee showcase",
	Icon = "orbit",
	Theme = "ImGui",
	Minimizer = {Body = minimizerMark},
	Maximizer = {Text = "O"},
	CloseCallback = function()
		for _, toggle in ipairs(toggles) do
			toggle:SetValue(false)
		end

		Driver.End()
	end,
})

-- Aim

local aimTab = window:Tab({Title = "Aim", Icon = "crosshair"})
aimTab:Paragraph({
	Title = "Camera or input",
	Description = "Camera mode rotates the current view in place and input mode moves the game's camera through synthetic input. On desktop, input mode needs first-person, shift lock, or right-mouse panning so the default camera consumes mouse movement.",
})

local aimSection = aimTab:Section({Title = "Targeting"})
local touchArea = {topLeftX = -1, topLeftY = -1, bottomRightX = -1, bottomRightY = -1}
--@inline
local function updateTouchArea()
	Aim.inputTouchArea = {
		Vector2.new(touchArea.topLeftX, touchArea.topLeftY),
		Vector2.new(touchArea.bottomRightX, touchArea.bottomRightY),
	}
end

--@inline
local function coordinateInput(title, field)
	aimSection:Input({
		Title = title,
		Value = "-1",
		Callback = function(value)
			local number = tonumber(value)
			if not number then return end
			touchArea[field] = number
			updateTouchArea()
		end,
	})
end

feature(aimSection, Aim, "aim", {
	Title = "Enable aim",
	Description = "Acquires the closest player inside the field of view.",
})
feature(aimSection, Aim, "useRay", {
	Title = "Line of sight",
	Description = "Keeps only targets that are not behind walls.",
})
feature(aimSection, Aim, "respectTeams", {Title = "Respect teams"})
aimSection:Dropdown({
	Title = "Mode",
	Values = {"Camera", "Input"},
	Value = defaultMode,
	Callback = function(value)
		Aim.aimMode = MODES[value]
	end,
})
aimSection:Dropdown({
	Title = "Aim target part",
	Values = {"Head", "HumanoidRootPart", "UpperTorso", "LowerTorso"},
	Value = "HumanoidRootPart",
	Callback = function(value)
		Aim.targetPart = value
	end,
})
slider(aimSection, "Field of view", Aim, "fovDeg", 90, 0, 360, 0)
aimSection:Dropdown({
	Title = "Target priority",
	Values = {"Distance", "Angle"},
	Value = "Angle",
	Callback = function(value)
		Aim.targetSelection = string.lower(value)
	end,
})
slider(aimSection, "Smoothness", Aim, "smoothness", 1, 0, 20, 2)
slider(aimSection, "Sensitivity", Aim, "sensitivity", 1, 0.1, 5, 2)
slider(aimSection, "Base input step X", Aim, "baseInputStepX", 10, -300, 300, 0)
slider(aimSection, "Base input step Y", Aim, "baseInputStepY", -10, -300, 300, 0)
coordinateInput("Ignored area top-left X", "topLeftX")
coordinateInput("Ignored area top-left Y", "topLeftY")
coordinateInput("Ignored area bottom-right X", "bottomRightX")
coordinateInput("Ignored area bottom-right Y", "bottomRightY")
slider(aimSection, "Prediction", Aim, "prediction", 0, 0, 1, 2)
slider(aimSection, "Max distance", Aim, "maxDistance", 500, 10, 1000, 0)
slider(aimSection, "Run priority", Aim, "runPriority", 200, 1, 2000, 0)

local jitterSection = aimTab:Section({Title = "Jitter"})
feature(jitterSection, Aim, "jitterEnabled", {Title = "Enable jitter"})
slider(jitterSection, "Intensity", Aim, "jitterIntensity", 1, 0, 5, 2)
slider(jitterSection, "Frequency", Aim, "jitterFrequency", 1, 0, 10, 2)
slider(jitterSection, "Scale", Aim, "jitterScale", 1, 0, 10, 2)
slider(jitterSection, "Max offset", Aim, "maxJitterOffset", 1, 0, 15, 1)

-- Silent
local silentTab = window:Tab({Title = "Silent", Icon = "eye"})
silentTab:Paragraph({
	Title = "Acquire, then spoof",
	Description = "As universal as a silent aim can get, the Viewport mode should work on most games with minimal issues.",
})

local routerSection = silentTab:Section({Title = "Router"})
feature(routerSection, Router, "enabled", {
	Title = "Enable router",
	Description = "Kill switch for target acquisition.",
})
feature(routerSection, Router, "wall", {Title = "Wall check"})
feature(routerSection, Router, "team", {Title = "Respect teams"})
feature(routerSection, Router, "real", {
	Title = "Ballistic prediction",
	Description = "Accounts for projectile speed, drag, and gravity.",
})
slider(routerSection, "Angle", Router, "angle", 30, 0, 180, 0)
routerSection:Dropdown({
	Title = "Target priority",
	Values = {"Crosshair", "Distance", "Angle"},
	Value = "Crosshair",
	Callback = function(value)
		Router.selection = string.lower(value)
	end,
})
routerSection:Dropdown({
	Title = "Silent target part",
	Values = {"Head", "HumanoidRootPart", "UpperTorso", "LowerTorso"},
	Value = "Head",
	Callback = function(value)
		Router.part = value
	end,
})
routerSection:Input({
	Title = "Root part",
	Value = "HumanoidRootPart",
	Callback = function(value)
		Router.root = value
	end,
})
slider(routerSection, "Drag", Router, "drag", 0, 0, 0.99, 2)
slider(routerSection, "Speed", Router, "speed", 100, 1, 1000, 0)
slider(routerSection, "Gravity", Router, "gravity", 196.2, 0, 500, 1)
slider(routerSection, "Predict", Router, "predict", 0, 0, 1, 2)

local spoofSection = silentTab:Section({Title = "Spoofing"})
feature(spoofSection, Silent, "ray", {
	Title = "Raycasts",
	Description = "Redirects workspace raycasts toward the target.",
})
feature(spoofSection, Silent, "mouse", {
	Title = "Mouse",
	Description = "Spoofs Target, Hit, and UnitRay.",
})
feature(spoofSection, Silent, "view", {
	Title = "Viewport",
	Description = "Centers the reported viewport on the target.",
})

-- Bypass

local bypassTab = window:Tab({Title = "Bypass", Icon = "shield"})
bypassTab:Paragraph({
	Title = "Client side only",
	Description = "Please keep in mind that this script is NOT a bypass for server sided anticheat methods nor will it automatically feed any potential watchdog, which CAN and in most cases WILL get you BANNED sooner or later. This module is only meant as a learning resource and jumpstart for developers so that they can extract the client-side scripts and begin the actual work.",
})

local bypassSection = bypassTab:Section({Title = "Detections"})
local bypassEntries = {
	{"nop", "Nop proxy", "Answers engine calls that receive the proxy."},
	{"kick", "Local kicks", "Ignores kicks issued by local scripts."},
	{"preload", "Asset preload", "Blanks preload callbacks for foreign assets."},
	{"context", "Script context", "Lowers the execution budget and silences errors."},
	{"localize", "Localization", "Stops the translator from loading."},
	{"overflow", "Stack overflows", "Hides overflow errors from protected calls."},
	{"property", "Property signals", "Answers Changed, Added, and Removed lookups."},
	{"parent", "Hidden scripts", "Disables scripts that were reparented to nil."},
	{"memory", "Memory usage", "Reports a stable memory footprint."},
	{"garbage", "Garbage count", "Reports a stable collector count."},
	{"log", "Log service", "Drops messages sent through LogService."},
	{"analytics", "Analytics", "Drops AnalyticsService calls."},
	{"proxy", "Newproxy", "Rejects newproxy calls."},
}

for _, entry in ipairs(bypassEntries) do
	feature(bypassSection, Bypass, entry[1], {Title = entry[2], Description = entry[3]})
end

-- Performance

local performanceTab = window:Tab({Title = "Performance", Icon = "gauge"})
performanceTab:Paragraph({
	Title = "Engine tuning",
	Description = "Trades visual fidelity for frame time. The instance patch walks every descendant once and then follows DescendantAdded.",
})

local performanceSection = performanceTab:Section({Title = "Optimizations"})
feature(performanceSection, Performance, "water", {
	Title = "Water",
	Description = "Removes waves and reflections.",
})
feature(performanceSection, Performance, "light", {
	Title = "Lighting",
	Description = "Flattens dynamic lighting and fog.",
})
feature(performanceSection, Performance, "settings", {
	Title = "Physics sleep",
	Description = "Lowers quality and lets idle parts sleep.",
})
feature(performanceSection, Performance, "patch", {
	Title = "Instance patch",
	Description = "Hides lights, particles, decals, and shadows.",
})

window:Settings({Title = "Settings", Icon = "settings"})
Apogee:Notify({
	Title = "Orchestra",
	Content = "Finished setting up the UI.",
	Duration = 4,
})

-- loads autoload.bin if it exists.
local autoloaded, autoloadError = Apogee.Config:Autoload()
if autoloaded then
	Apogee:Notify("Interface", "Config loaded", {SubContent = "Loaded autoload.bin", Duration = 7})
elseif autoloadError then
	Apogee:Notify("Interface", "Config loader", {SubContent = autoloadError, Duration = 7})
end
