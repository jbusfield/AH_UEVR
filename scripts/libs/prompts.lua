--[[
Usage
    Drop the libs folder containing this file into your project folder
    Add code like this in your script:
        local prompts = require("libs/prompts")

    Changes what a game's on-screen input prompts show (the key, icon or text of a "Y Pick Up" prompt) while a mod feature
    changes the controls, and puts the game's original back when it doesn't. The game-specific parts (which prompts to look
    at, how to read and write what they show, and what each should show instead) are supplied as callbacks.

    How it works
        Games rebuild, reuse and reset their prompts at will, so the prompts are checked on an interval, compare-then-set:
        a prompt is only written when it doesn't already show what it should. What a prompt showed before it was changed is
        remembered per prompt, so it goes back to exactly that (the game's own key or icon, whatever the input device) when its
        replacement stops applying, when the override is disabled, and on level change and script reset. A prompt that is
        changed back by the game counts as showing its original again.

    Available functions:

    prompts.new(options) -> Override
        options:
            getPrompts: function() -> {prompt, ...}|nil (required)
                The prompts (UObjects, e.g. widgets or images) that may need changing right now. Prompts not returned keep
                whatever they show until the override restores them.
            get: function(prompt) -> value (required) - what the prompt shows (a key name, a texture, ...)
            set: function(prompt, value) (required)
            getReplacement: function(prompt, original) -> value|nil (required)
                What the prompt should show instead of original (what the game had it show), or nil for the original.
            equals: function(a, b) -> boolean (optional) - default compares UObjects by address and other values with ==
            interval: ms (default 250) - how often the prompts are checked; a prompt can show the game's original for up
                to one interval before it changes
            enabled: boolean (default false)

    prompts.materialTexture(parameterName) -> get, set
        Accessors for an Image whose dynamic material holds the icon as a texture parameter (e.g. "Texture").
    prompts.brushResource() -> get, set
        Accessors for an Image whose brush resource object (a texture or sprite) is the icon.
    prompts.loadAsset(path) -> UObject|nil
        The asset at a full path ("Texture2D /Game/UI/T_Key_RB.T_Key_RB"), loaded on first use and cached. Uses the
        asset registry, never a failing full-name lookup (which can scan the object hierarchy and pause the game). The
        cache is cleared on level change, and a cached asset is checked against its path about once a second, so one that
        was unloaded (its address reused by another object) is loaded again.

    Override:setEnabled(value)
        Disabling restores every changed prompt and stops the checks.
    Override:isEnabled() -> boolean
    Override:update()
        Checks the prompts now (it also runs on the interval while enabled).
    Override:restore()
        Puts every changed prompt that still shows its replacement back to its original. Also runs on level change and
        script reset.
]]

local uevrUtils = require("libs/uevr_utils")

local M = {}

local Override = {}
Override.__index = Override

local function defaultEquals(a, b)
	if a == b then return true end
	if type(a) == "userdata" and type(b) == "userdata" and a.get_address ~= nil and b.get_address ~= nil then
		return a:get_address() == b:get_address()
	end
	return false
end

-- Restores every changed prompt that is still valid and still shows its replacement (anything else is the game's).
function Override:restore()
	for key, entry in pairs(self.changed) do
		local prompt = uevrUtils.getValid(entry.prompt)
		if prompt ~= nil and self.equals(self.get(prompt), entry.replacement) then self.set(prompt, entry.original) end
		self.changed[key] = nil
	end
end

function Override:update()
	if not self.enabled then return end
	for key, entry in pairs(self.changed) do
		if uevrUtils.getValid(entry.prompt) == nil then self.changed[key] = nil end
	end
	for _, prompt in ipairs(self.getPrompts() or {}) do
		prompt = uevrUtils.getValid(prompt)
		if prompt ~= nil then
			local key = prompt:get_address()
			local entry = self.changed[key]
			local current = self.get(prompt)
			-- Showing anything but its replacement means the game set it again, which is its original from now on.
			local original = current
			if entry ~= nil and self.equals(current, entry.replacement) then original = entry.original end
			local replacement = self.getReplacement(prompt, original)
			if replacement ~= nil then
				if not self.equals(current, replacement) then self.set(prompt, replacement) end
				self.changed[key] = {prompt = prompt, original = original, replacement = replacement}
			else
				if entry ~= nil and self.equals(current, entry.replacement) then self.set(prompt, entry.original) end
				self.changed[key] = nil
			end
		end
	end
end

function Override:setEnabled(value)
	self.enabled = value == true
	if not self.enabled then self:restore() end
end

function Override:isEnabled()
	return self.enabled
end

function M.new(options)
	options = options or {}
	local self = setmetatable({
		getPrompts = options.getPrompts or function() return nil end,
		get = options.get,
		set = options.set,
		getReplacement = options.getReplacement or function() return nil end,
		equals = options.equals or defaultEquals,
		enabled = options.enabled == true,
		changed = {}, -- prompt address -> {prompt, original, replacement}
	}, Override)
	uevrUtils.setInterval(options.interval or 250, function() self:update() end)
	uevrUtils.registerLevelChangeCallback(function() self:restore() end)
	uevr.params.sdk.callbacks.on_script_reset(function() self:restore() end)
	return self
end

function M.materialTexture(parameterName)
	local name = nil
	local function getMaterial(image)
		local material = image:GetDynamicMaterial()
		name = name or uevrUtils.fname_from_string(parameterName)
		return material, name
	end
	local function get(image)
		local material, parameter = getMaterial(image)
		return material ~= nil and material:K2_GetTextureParameterValue(parameter) or nil
	end
	local function set(image, texture)
		local material, parameter = getMaterial(image)
		if material ~= nil then material:SetTextureParameterValue(parameter, texture) end
	end
	return get, set
end

function M.brushResource()
	local function get(image)
		local brush = image.Brush
		return brush ~= nil and brush.ResourceObject or nil
	end
	local function set(image, resource)
		image:SetBrushResourceObject(resource)
	end
	return get, set
end

-- A cached asset can be unloaded (e.g. on level change) and its address reused by an unrelated object, which still passes
-- getValid. The cache is cleared on level change, and each cached asset's full name is checked against its path once per
-- ASSET_CHECK_INTERVAL_MS (every other call returns it directly), so a mid-level unload is caught within that time.
local ASSET_CHECK_INTERVAL_MS = 1000
local assets = {} -- path -> {asset, needsCheck}
function M.loadAsset(path)
	local entry = assets[path]
	local asset = entry ~= nil and uevrUtils.getValid(entry.asset) or nil
	if asset ~= nil and entry.needsCheck then
		if asset:get_full_name() == path then entry.needsCheck = false else asset = nil end
	end
	if asset == nil then
		asset = uevrUtils.getValid(uevrUtils.getLoadedAsset(path))
		if asset ~= nil and asset:get_full_name() ~= path then asset = nil end
		assets[path] = asset ~= nil and {asset = asset, needsCheck = false} or nil
	end
	return asset
end

uevrUtils.setInterval(ASSET_CHECK_INTERVAL_MS, function()
	for _, entry in pairs(assets) do entry.needsCheck = true end
end)

uevrUtils.registerLevelChangeCallback(function()
	assets = {}
end)

return M
