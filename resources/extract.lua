-- Lune script by patangation
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local process = require("@lune/process")

-- Configuration
local CONFIG = {
	-- File extensions for different script types
	extensions = {
		Script = ".server.lua",
		LocalScript = ".client.lua",
		ModuleScript = ".lua",
	},

	-- Services to export in priority order
	services = {
		"ServerScriptService",
		"ReplicatedStorage",
		"ServerStorage",
		"StarterPlayer",
		"StarterGui",
		"ReplicatedFirst",
		"Workspace",
		"StarterPack",
		"Lighting",
		"SoundService",
		"Teams",
	},

	-- Skip these instances completely
	skipInstances = {
		"Camera",
		"Terrain",
	},
}

-- Stats tracking
local stats = {
	totalScripts = 0,
	scriptTypes = {},
	servicesProcessed = 0,
	nestedScripts = 0,
	errors = {},
}

-- Utility functions
local function sanitizePath(name)
	return name:gsub("[^%w%-%_%.%s]", "_"):gsub("%s+", "_"):gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
end

local function ensureDir(path)
	local success = pcall(function()
		fs.writeDir(path)
	end)
	return success
end

local function shouldSkip(instance)
	for _, skipName in pairs(CONFIG.skipInstances) do
		if instance.Name == skipName or instance.ClassName == skipName then
			return true
		end
	end
	return false
end

-- Extract filename without extension
local function getFileNameWithoutExtension(path)
	local filename = path:match("([^/\\]+)$") -- Get filename from path
	return filename:match("(.+)%..+$") or filename -- Remove extension
end

-- Check if instance is a script type
local function isScript(instance)
	return instance.ClassName == "Script" or instance.ClassName == "LocalScript" or instance.ClassName == "ModuleScript"
end

-- Enhanced script detection (now includes scripts inside scripts)
local function hasScriptsDeep(instance)
	if shouldSkip(instance) then
		return false
	end

	if isScript(instance) then
		return true
	end

	for _, child in pairs(instance:GetChildren()) do
		if hasScriptsDeep(child) then
			return true
		end
	end

	return false
end

-- Check if any direct children are scripts
local function hasDirectScriptChildren(instance)
	for _, child in pairs(instance:GetChildren()) do
		if isScript(child) then
			return true
		end
		-- Also check if any non-script children contain scripts
		if hasScriptsDeep(child) then
			return true
		end
	end
	return false
end

-- Create comprehensive metadata
local function createMetadata(instance)
	local metadata = {
		name = instance.Name,
		className = instance.ClassName,
		parent = instance.Parent and instance.Parent.Name or "DataModel",
		fullPath = {},
		properties = {},
		isNestedScript = false,
	}

	-- Build full path and check if this is a nested script
	local current = instance.Parent
	while current and current.Parent do
		table.insert(metadata.fullPath, 1, current.Name)

		-- Check if parent is a script (nested script detection)
		if isScript(current) then
			metadata.isNestedScript = true
		end

		current = current.Parent
	end

	-- Collect relevant properties based on class
	if instance.ClassName == "Script" then
		metadata.properties.Disabled = instance.Disabled
		metadata.properties.RunContext = instance.RunContext
	elseif instance.ClassName == "LocalScript" then
		metadata.properties.Disabled = instance.Disabled
	elseif instance.ClassName == "ModuleScript" then
		-- ModuleScripts don't have Disabled property
	end

	return metadata
end

-- Generate structured header
local function generateHeader(metadata)
	local lines = {
		string.format("--[["),
		string.format("    %s (%s)", metadata.name, metadata.className),
		string.format("    Path: %s", table.concat(metadata.fullPath, " → ")),
		string.format("    Parent: %s", metadata.parent),
	}

	if metadata.isNestedScript then
		table.insert(lines, "    ⚠️  NESTED SCRIPT: This script is inside another script")
	end

	if next(metadata.properties) then
		table.insert(lines, "    Properties:")
		for prop, value in pairs(metadata.properties) do
			table.insert(lines, string.format("        %s: %s", prop, tostring(value)))
		end
	end

	table.insert(lines, string.format("    Exported: %s", os.date("%Y-%m-%d %H:%M:%S")))
	table.insert(lines, "]]")
	table.insert(lines, "")

	return table.concat(lines, "\n")
end

-- Enhanced script processing with better nested script handling
local function processInstance(instance, currentPath, depth, parentIsScript)
	depth = depth or 0
	parentIsScript = parentIsScript or false

	if depth > 25 then -- Increased depth limit for nested scripts
		table.insert(stats.errors, "Max depth reached at: " .. currentPath)
		return
	end

	if shouldSkip(instance) then
		return
	end

	local sanitizedName = sanitizePath(instance.Name)
	local isCurrentScript = isScript(instance)

	-- Handle script instances
	if isCurrentScript then
		local extension = CONFIG.extensions[instance.ClassName] or ".lua"
		local filePath = currentPath .. "/" .. sanitizedName .. extension

		-- Get source with fallback
		local source = instance.Source or "-- No source code found"

		-- Generate metadata and header
		local metadata = createMetadata(instance)
		local header = generateHeader(metadata)

		-- Write file
		local success = pcall(function()
			fs.writeFile(filePath, header .. source)
		end)

		if success then
			stats.totalScripts = stats.totalScripts + 1
			stats.scriptTypes[instance.ClassName] = (stats.scriptTypes[instance.ClassName] or 0) + 1

			if metadata.isNestedScript then
				stats.nestedScripts = stats.nestedScripts + 1
				print(string.format("✓ %s (NESTED)", filePath))
			else
				print(string.format("✓ %s", filePath))
			end
		else
			table.insert(stats.errors, "Failed to write: " .. filePath)
			print(string.format("✗ Failed: %s", filePath))
		end

		-- IMPORTANT: Only create contents folder if there are actually scripts inside
		local children = instance:GetChildren()
		if #children > 0 and hasDirectScriptChildren(instance) then
			-- Create a subfolder for nested scripts/objects
			local scriptFolder = currentPath .. "/" .. sanitizedName .. "_contents"
			ensureDir(scriptFolder)

			-- Sort children for consistent output
			table.sort(children, function(a, b)
				local aIsScript = isScript(a)
				local bIsScript = isScript(b)

				if aIsScript and not bIsScript then
					return true
				elseif not aIsScript and bIsScript then
					return false
				else
					return a.Name < b.Name
				end
			end)

			for _, child in pairs(children) do
				processInstance(child, scriptFolder, depth + 1, true)
			end
		end
	else
		-- Handle non-script containers
		if hasScriptsDeep(instance) then
			local newPath = currentPath .. "/" .. sanitizedName

			if ensureDir(newPath) then
				local children = instance:GetChildren()

				-- Sort children for consistent output
				table.sort(children, function(a, b)
					local aIsScript = isScript(a)
					local bIsScript = isScript(b)

					if aIsScript and not bIsScript then
						return true
					elseif not aIsScript and bIsScript then
						return false
					else
						return a.Name < b.Name
					end
				end)

				for _, child in pairs(children) do
					processInstance(child, newPath, depth + 1, parentIsScript)
				end
			end
		end
	end
end

-- Create project structure file
local function createProjectInfo(outputDir, inputPath)
	local projectInfo = {
		sourceFile = inputPath,
		exportDate = os.date("%Y-%m-%d %H:%M:%S"),
		luneVersion = "0.9.3",
		structure = "Service-based organization with nested script support",
		notes = {
			"Server scripts have .server.lua extension",
			"Client scripts have .client.lua extension",
			"Module scripts have .lua extension",
			"Nested scripts are placed in '_contents' folders",
			"Scripts inside scripts are marked as NESTED in headers",
			"Metadata preserved in file headers",
			"Empty '_contents' folders are not created",
		},
	}

	local content = "-- Project Export Information\n"
	content = content .. "-- Generated by Roblox Script Exporter\n\n"
	content = content
		.. string.format(
			"return %s",
			table.concat({
				"{",
				string.format('    sourceFile = "%s",', projectInfo.sourceFile),
				string.format('    exportDate = "%s",', projectInfo.exportDate),
				string.format('    luneVersion = "%s",', projectInfo.luneVersion),
				string.format('    structure = "%s",', projectInfo.structure),
				"    notes = {",
				'        "Server scripts have .server.lua extension",',
				'        "Client scripts have .client.lua extension",',
				'        "Module scripts have .lua extension",',
				"        \"Nested scripts are placed in '_contents' folders\",",
				'        "Scripts inside scripts are marked as NESTED in headers",',
				'        "Metadata preserved in file headers",',
				"        \"Empty '_contents' folders are not created\"",
				"    }",
				"}",
			}, "\n")
		)

	fs.writeFile(outputDir .. "/project-info.lua", content)
end

-- Main execution
local function main()
	local args = process.args
	local inputPath = args[1]

	if not inputPath then
		print("Roblox Script Exporter")
		print("Usage: export-scripts.lua <input.rbxl> [output-directory]")
		print("\nExample: export-scripts.lua MyGame.rbxl")
		print("         export-scripts.lua MyGame.rbxl custom-folder")
		return
	end

	-- Generate output directory based on filename or use provided argument
	local outputDir = args[2]
	if not outputDir then
		local baseName = getFileNameWithoutExtension(inputPath)
		outputDir = sanitizePath(baseName) .. "-scripts"
	end

	print("🚀 Roblox Script Exporter (with Nested Script Support)")
	print("======================================================")
	print(string.format("Input: %s", inputPath))
	print(string.format("Output: %s", outputDir))
	print()

	-- Check if file exists and can be read
	if not fs.isFile(inputPath) then
		print("❌ Error: Input file does not exist")
		return
	end

	-- Read and deserialize with error handling
	local fileContent, readError = fs.readFile(inputPath)
	if not fileContent then
		print("❌ Error reading file:", readError)
		return
	end

	print("✅ File read successfully")

	local success, dataModel = pcall(roblox.deserializePlace, fileContent)
	if not success then
		print("❌ Error: Failed to deserialize RBXM file")
		print("The file format might not be supported")
		print("Error:", dataModel) -- This will contain the actual error message
		return
	end

	print("✅ RBXM file deserialized successfully")

	-- DEBUG: Show everything in the DataModel
	print("\n🔍 DataModel Contents:")
	print("=====================")
	local function printHierarchy(instance, depth)
		depth = depth or 0
		local indent = string.rep("  ", depth)
		print(string.format("%s%s (%s)", indent, instance.Name, instance.ClassName))

		-- Show script sources if it's a script
		if isScript(instance) then
			local sourceLength = instance.Source and #instance.Source or 0
			print(string.format("%s  📜 Source: %d characters", indent, sourceLength))
		end

		-- Limit children to avoid too much output
		local children = instance:GetChildren()
		if #children > 0 and depth < 3 then -- Only show 3 levels deep
			for _, child in pairs(children) do
				printHierarchy(child, depth + 1)
			end
		elseif #children > 0 then
			print(string.format("%s  ... and %d more children", indent, #children))
		end
	end

	printHierarchy(dataModel)

	ensureDir(outputDir)

	-- Process ALL children of DataModel, not just predefined services
	print("\n🔍 Searching for scripts in all containers...")
	local foundAnyScripts = false

	for _, service in pairs(dataModel:GetChildren()) do
		if hasScriptsDeep(service) then
			foundAnyScripts = true
			print(string.format("📁 Processing %s (%s)...", service.Name, service.ClassName))

			local servicePath = outputDir .. "/" .. sanitizePath(service.Name)
			ensureDir(servicePath)

			for _, child in pairs(service:GetChildren()) do
				processInstance(child, servicePath)
			end

			stats.servicesProcessed = stats.servicesProcessed + 1
		else
			print(string.format("⏭️  Skipping %s (%s) - no scripts detected", service.Name, service.ClassName))
		end
	end

	-- If no scripts found with standard detection, try brute force search
	if not foundAnyScripts then
		print("\n🔍 No scripts found with standard detection. Performing deep search...")

		local allScripts = dataModel:GetDescendants()
		local scriptCount = 0
		for _, instance in pairs(allScripts) do
			if isScript(instance) then
				scriptCount = scriptCount + 1
				print(
					string.format("  Found: %s (%s) at %s", instance.Name, instance.ClassName, instance:GetFullName())
				)
			end
		end

		if scriptCount > 0 then
			print(string.format("🎯 Found %d scripts with deep search!", scriptCount))
			print("Attempting to export them...")

			-- Create a catch-all folder for these scripts
			local catchAllPath = outputDir .. "/DiscoveredScripts"
			ensureDir(catchAllPath)

			for _, instance in pairs(allScripts) do
				if isScript(instance) then
					processInstance(instance, catchAllPath, 0, false)
				end
			end
		else
			print("❌ No scripts found even with deep search")
		end
	end

	-- Create project information file
	createProjectInfo(outputDir, inputPath)

	-- Print summary
	print("\n📊 Export Summary")
	print("=================")
	print(string.format("Total scripts exported: %d", stats.totalScripts))
	print(string.format("Nested scripts found: %d", stats.nestedScripts))
	print(string.format("Services processed: %d", stats.servicesProcessed))

	if next(stats.scriptTypes) then
		print("\nScript types:")
		for scriptType, count in pairs(stats.scriptTypes) do
			print(string.format("  %s: %d", scriptType, count))
		end
	end

	if #stats.errors > 0 then
		print(string.format("\n⚠️  Errors encountered: %d", #stats.errors))
		for _, error in pairs(stats.errors) do
			print("  " .. error)
		end
	end

	if stats.totalScripts == 0 then
		print("\n❌ No scripts were exported. Possible reasons:")
		print("   - The file might be a different format than expected")
		print("   - The file might be encrypted or compressed")
		print("   - The file might not contain any Lua scripts")
		print("   - The scripts might be in an unusual location")
	else
		print(string.format("\n✅ Export completed: %s", outputDir))
	end
end

main()
