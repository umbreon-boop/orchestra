--[=[
	A general purpose library for aiding you in orchestrating the typical toomfoolery.

	@class Orchestra
	@prop Aim         [Module](Aimbot.md)
	@prop Driver      [Module](Driver.md)
	@prop Bypass      [Module](Bypass.md)
	@prop Hooks       [Module](Hooks.md)
	@prop Performance [Module](Performance.md)
	@prop Silent      [Module](Silent.md)
]=]
local Orchestra = {
	Aim = require("./aim"),
	Bypass = require("./bypass"),
	Driver = require("./driver"),
	Hooks = require("./hooks"),
	Performance = require("./performance"),
	Silent = require("./silent"),
}

return Orchestra
