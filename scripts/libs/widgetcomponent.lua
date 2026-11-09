--[[
    local widgetComponent = require("libs/widgetcomponent")
    widgetComponent.init()

    -- From a saved profile (Widget Component Config Dev: New / Rename / etc.)
    -- create() tracks by profile key: reuses a live instance, or rebuilds if gone.
    -- destroyAll() on level change / script reset; optional widgetComponent.destroy("Reticle") or wc:destroy()
    local wc = widgetComponent.create("Reticle")
    wc:attachToParent("Right Hand")   -- uses the profile's transform for that parent
    wc:attachTo(wandMesh, "MuzzleSocket")   -- or attach manually (no per parent transform)

    -- Parents offered by attachToParent and the dev panel's Attach To. Each entry is { label, value (component), socket (optional) }.
    -- Without a callback, Right Controller and Left Controller are available.
    widgetComponent.registerGetAvailableParentsCallback(function()
        return {
            { label = "Right Hand", value = rightHandMesh, socket = "WandSocket" },
            { label = "Left Controller", value = controllers.getController(Handed.Left) },
        }
    end)
    Profiles store a position, rotation and scale per parent label in transforms[label] = { location, rotation, scale },
    and the parent to use in attachTo, so wc:attachToParent() with no label attaches to it.

    -- End user settings: one tree per profile with Brightness, Attach To, Position, Rotation, Scale and Restore Defaults.
    -- Saved separately in widgetcomponent_user_parameters.json and applied over the profile by create()
    -- Attach To also offers UI (widgetComponent.AttachTo.UI = 0, the default: create() returns nil and the widget stays
    -- in the game's UI) and None (widgetComponent.AttachTo.None = 999: the widget is shown nowhere)
    expandArray(widgetComponent.getConfigurationWidgets)

    -- Or build inline (no profile required)
    local hud = widgetComponent.new({
        widgetClass = "WidgetBlueprintGeneratedClass /Game/UI/HUD/Reticle/Reticle_BP.Reticle_BP_C",
        drawSize = {100, 100},
        scale = {0.1, 0.1, 0.1},
    })
    hud:attachTo(controllers.getController(Handed.Left))
    hud:destroy()

    -- Or from an already created widget (widget takes precedence over widgetClass)
    local wc = widgetComponent.new({ widget = myWidget, drawSize = {300, 300} })

    -- Or a component hosting a single centered Image (options are the same as new())
    local component, image, wc = widgetComponent.createImageComponent(40, { scale = {0.08, 0.08, 0.08}, twoSided = true, drawSize = {120, 120} })
    component:K2_AttachTo(handComponent, uevrUtils.fname_from_string("WandSocket"), 0, false)
    image:setTexture("Stupefy.png")

    new() options (all optional except widgetClass or widget):
		widgetClass, widgetName (a named widget inside widgetClass's or widget's tree, e.g. "QuickActionsSwitcher";
		non UserWidgets are wrapped in a host UserWidget), widget, drawSize, twoSided, location, rotation, scale,
		transforms (per parent label transforms used by attachToParent),
		useExposure (bool, default false), exposure (stops, default 0),
		manualAttachment, deferredFinish, parent, tag (passed to uevrUtils.createWidgetComponent),
		relativeTransform (deprecated, use location/rotation/scale; those override it when both are given)

    Widget exposure compensation
		World space WidgetComponents are affected by the game's auto-exposure, so they look dark in daylight and
		washed out at night. These functions counteract that by tinting the component by 2^(EV100 * 1.1 + stops).
		EV100 is the game's current auto-exposure value. Reading it is game specific (stock Unreal does not expose
		it to Lua), so your script supplies it. Pass nil to assume daylight (EV 11).
		Instances created with useExposure = true apply this automatically using the function passed to
		widgetComponent.setEV100Function(fn) and their exposure (stops) value.

    widgetComponent.applyWidgetComponentExposureFix(component, ev100, (optional)stops) - one time setup for an
		exposure compensated WidgetComponent. Enables gamma correction, disables the HDR render target and
		applies the initial exposure. stops is a brightness offset where each step doubles or halves (default 0).
        For games where the environment doesnt affect the widget you can just call this once and not call
        widgetComponent.setWidgetComponentExposure repeatedly.
        example:
            widgetComponent.applyWidgetComponentExposureFix(component, getEV100(), configui.getValue("my_icon_exposure"))

    widgetComponent.setWidgetComponentExposure(component, (optional)ev100, (optional)stops) - updates the exposure tint
		of a WidgetComponent so its on-screen brightness stays consistent as scene lighting changes. Call
		applyWidgetComponentExposureFix once first, then call this periodically (about once a second is plenty;
		auto-exposure adapts slowly).

		How it works:
			The tint applied is 2^(ev100 * 1.1 + stops), set via SetTintColorAndOpacity on R, G and B.
			Auto-exposure darkens the scene by roughly 2^EV100, so tinting by 2^EV100 cancels it out. The extra 1.1
			slope makes the widget slightly brighter in bright scenes, where it would otherwise look washed out
			next to the scene around it.

		Params:
			component - the WidgetComponent to update (required)

			ev100 - (optional) the game's current auto-exposure value in EV100 units. Higher means a brighter
				scene. Read this from the game every time you call; stock Unreal does not expose it to Lua, so
				each game needs its own source (e.g. Hogwarts Legacy:
				RenderSettingsSingleton.LastFrameExposure.Filtered.AutoExposureEV100).
				If nil, 11 (typical daylight) is assumed, which looks right outdoors in daytime but too bright
				in dark scenes.
				Typical values (varies per game):
					below 0 to 3 - night / very dark interiors
					4 to 8       - lit interiors, dusk
					9 to 13      - overcast to full daylight

			stops - (optional, default 0) user brightness offset in exposure stops. Each +1 doubles the
				brightness and each -1 halves it, by the same proportion in all lighting conditions.
				Recommended range: -5 to 5. Start at 0 and adjust; Hogwarts Legacy looks right around -1.
				Ideal for a configui slider, e.g.
					{ widgetType = "slider_float", id = "my_icon_exposure", label = "Icon Brightness", initialValue = 0, speed = 0.1, range = {-5, 5} }
        example:
            setInterval(1000, function()
                widgetComponent.setWidgetComponentExposure(component, getEV100(), configui.getValue("my_icon_exposure"))
            end)
]]--

local uevrUtils = require("libs/uevr_utils")
local paramModule = require("libs/core/params")
local widgetModule = require("libs/widget")
local controllers = require("libs/controllers")
local widgetComponentConfig = require("libs/config/widgetcomponent_config")

local M = {}
M.getAvailableParentsCallback = nil
-- User Attach To values besides parent labels. UI leaves the widget in the game's UI, None shows it nowhere
M.AttachTo = { UI = 0, None = 999 }

local widgetComponentConfigDev = nil
local getEV100 = nil
local currentLogLevel = LogLevel.Error
local parametersFileName = "widgetcomponent_parameters"
local activeInstances = {}
local createdByKey = {}
-- Runtime-only: disabled profiles stay on the UI without clearing saved Attach To / transforms
local disabledByKey = {}
local isScriptResetting = false
local parameters = {
	widgetClass = "",
	widgetName = "",
	drawSize = {100, 100},
	twoSided = true,
	transforms = {},
	useExposure = false,
	exposure = 0,
}

local paramManager = paramModule.new(parametersFileName, parameters, true)
-- End user overrides keyed by profile id: { exposure, attachTo, transforms = { [label] = { location, rotation, scale } } }
local userParamManager = paramModule.new("widgetcomponent_user_parameters", {}, true)

local function unregisterInstance(inst)
	for i = #activeInstances, 1, -1 do
		if activeInstances[i] == inst then
			table.remove(activeInstances, i)
			return
		end
	end
end

local function clearCreatedKey(inst)
	if inst == nil or inst.profileKey == nil then return end
	if createdByKey[inst.profileKey] == inst then
		createdByKey[inst.profileKey] = nil
	end
	inst.profileKey = nil
end

function M.destroyAll()
	if widgetComponentConfigDev ~= nil and widgetComponentConfigDev.stopTest ~= nil then
		widgetComponentConfigDev.stopTest()
	end
	createdByKey = {}
	local list = activeInstances
	activeInstances = {}
	for i = 1, #list do
		list[i].profileKey = nil
		list[i]:destroy()
	end
end

function M.setLogLevel(val)
	currentLogLevel = val
end

function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[widgetcomponent] " .. text, logLevel)
	end
end

-- Game specific source of the current auto-exposure EV100. nil assumes daylight.
function M.setEV100Function(fn)
	getEV100 = fn
end

-- World space WidgetComponents render through Widget3DPassThrough materials, which multiply by TintColorAndOpacity.
-- Auto-exposure scales the scene by ~1/(1.2 * 2^EV100), so tinting by 2^EV100 cancels it. The 1.1 slope adds extra
-- brightness in bright scenes, where widgets otherwise look washed out against the scene.
-- ev100 is the game's current auto-exposure (nil assumes daylight), stops is a user brightness offset (each step doubles)
function M.setWidgetComponentExposure(component, ev100, stops)
	if uevrUtils.getValid(component) == nil or component.SetTintColorAndOpacity == nil then return end
	local boost = 2 ^ ((ev100 or 11) * 1.1 + (stops or 0))
	component:SetTintColorAndOpacity(uevrUtils.color_from_rgba(boost, boost, boost, 1.0, true))
end

-- One-time setup for an exposure compensated WidgetComponent: gamma correction on, HDR render target off, then applies the exposure
function M.applyWidgetComponentExposureFix(component, ev100, stops)
	if uevrUtils.getValid(component) == nil then return end
	M.setWidgetComponentExposure(component, ev100, stops)
	component.bApplyGammaCorrection = true
	local rt = component:GetRenderTarget()
	if uevrUtils.getValid(rt) ~= nil then
		rt.bHDR = false
	end
	component:RequestRenderUpdate()
end

function M.setParametersFileName(fileName)
	parametersFileName = fileName
	paramManager.fileName = fileName
end

function M.getParamManager()
	return paramManager
end

function M.getParameters()
	return paramManager:getAll()
end

-- Build options from a profile's parameter table (for Test UI or create). userSettings (optional) overrides the profile
function M.optionsFromProfile(profile, userSettings)
	if profile == nil or profile.widgetClass == nil or profile.widgetClass == "" then return nil end
	userSettings = userSettings or {}
	return {
		widgetClass = profile.widgetClass,
		widgetName = profile.widgetName,
		drawSize = profile.drawSize or {100, 100},
		twoSided = profile.twoSided ~= false,
		scale = profile.scale,
		rotation = profile.rotation,
		location = profile.location,
		transforms = profile.transforms or {},
		userTransforms = userSettings.transforms,
		attachTo = userSettings.attachTo or profile.attachTo,
		useExposure = profile.useExposure == true,
		exposure = userSettings.exposure or profile.exposure or 0,
	}
end

local function findProfile(idOrLabel)
	if idOrLabel == nil then return nil, nil end
	local all = paramManager:getAll()
	if all == nil then return nil, nil end
	if idOrLabel ~= "_profileState" and idOrLabel ~= "_profileLabels" and type(all[idOrLabel]) == "table" then
		return idOrLabel, all[idOrLabel]
	end
	for id, label in pairs(all._profileLabels or {}) do
		if label == idOrLabel and type(all[id]) == "table" then
			return id, all[id]
		end
	end
	return nil, nil
end

-- Destroy by profile id/label, or by instance. Optional — create() reuses/replaces by key.
function M.destroy(idOrLabelOrInst)
	if idOrLabelOrInst == nil then return end
	if type(idOrLabelOrInst) == "table" and idOrLabelOrInst.destroy ~= nil then
		idOrLabelOrInst:destroy()
		return
	end
	local id = select(1, findProfile(idOrLabelOrInst)) or idOrLabelOrInst
	if createdByKey[id] ~= nil then
		createdByKey[id]:destroy()
	end
end

function M.get(idOrLabel)
	local id = select(1, findProfile(idOrLabel))
	local inst = id and createdByKey[id]
	if inst ~= nil and inst:isValid() then
		return inst
	end
	return nil
end

function M.getPresetList()
	local ids, names = paramManager:getProfiles()
	local list = {}
	for i, id in ipairs(ids) do
		table.insert(list, { id = id, label = names[i] or id })
	end
	return list
end

-- Profiles that have a widget class (same set as getConfigurationWidgets)
function M.getLabeledWidgets()
	local ids, names = paramManager:getProfiles()
	local list = {}
	for i, id in ipairs(ids) do
		local profile = paramManager:get(id)
		if profile ~= nil and profile.widgetClass ~= nil and profile.widgetClass ~= "" then
			table.insert(list, { id = id, label = names[i] or id })
		end
	end
	table.sort(list, function(a, b) return a.label < b.label end)
	return list
end

-- Runtime enable/disable by profile id or label. Disable returns the widget to the UI without clearing user settings.
function M.setEnabled(idOrLabel, enabled)
	local id = select(1, findProfile(idOrLabel))
	if id == nil then
		M.print("setEnabled: profile not found: " .. tostring(idOrLabel), LogLevel.Warning)
		return
	end
	if enabled then
		disabledByKey[id] = nil
		M.applyUserSettings(id)
	else
		disabledByKey[id] = true
		M.destroy(id)
	end
end

-- Create/reuse a configured instance from a profile id or label. Caller attaches it.
-- Returns nil when the user's Attach To is UI (the default). With None the instance is created but hidden
function M.create(idOrLabel)
	local id, profile = findProfile(idOrLabel)
	if profile == nil then
		M.print("create: profile not found: " .. tostring(idOrLabel), LogLevel.Error)
		return nil
	end
	if id == nil then
		M.print("create: id not found: " .. tostring(idOrLabel), LogLevel.Error)
		return nil
	end
	if disabledByKey[id] then
		if createdByKey[id] ~= nil then createdByKey[id]:destroy() end
		return nil
	end
	local userSettings = userParamManager:get(id) or {}
	if (userSettings.attachTo or M.AttachTo.UI) == M.AttachTo.UI then
		if createdByKey[id] ~= nil then createdByKey[id]:destroy() end
		return nil
	end
	local existing = createdByKey[id]
	if existing ~= nil then
		if existing:isValid() then
			return existing
		end
		existing:destroy()
	end
	local opts = M.optionsFromProfile(profile, userSettings)
	if opts == nil then
		M.print("create: profile has no widget class: " .. tostring(idOrLabel) .. " (" .. tostring(id) .. ")", LogLevel.Error)
		return nil
	end
	local inst = M.new(opts)
	if inst ~= nil then
		inst.profileKey = id
		createdByKey[id] = inst
		if inst.parentLabel == M.AttachTo.None then inst:setVisibility(false) end
	end
	return inst
end

function M.init(isDeveloperMode, logLevel)
	if logLevel ~= nil then
		M.setLogLevel(logLevel)
	end
	if isDeveloperMode == nil and uevrUtils.getDeveloperMode() ~= nil then
		isDeveloperMode = uevrUtils.getDeveloperMode()
	end
	paramManager:load(false)
	paramManager:convertToProfile()
	userParamManager:load(false)
	widgetComponentConfig.init(paramManager, userParamManager, M)
	if isDeveloperMode then
		widgetComponentConfigDev = require("libs/config/widgetcomponent_config_dev")
		widgetComponentConfigDev.init(paramManager, M)
	end
end

local WidgetComponent = {}
WidgetComponent.__index = WidgetComponent

function M.new(options)
	options = options or {}
	if not options.widgetClass and not options.widget then
		M.print("widgetClass or widget is required to create WidgetComponent", LogLevel.Error)
		return nil
	end
	local self = setmetatable({
		widgetClass = options.widgetClass,
		widgetName = options.widgetName,
		sourceWidget = options.widget,
		drawSize = options.drawSize,
		twoSided = options.twoSided,
		scale = options.scale,
		rotation = options.rotation,
		location = options.location,
		transforms = options.transforms,
		userTransforms = options.userTransforms,
		parentLabel = options.attachTo,
		relativeTransform = options.relativeTransform,
		manualAttachment = options.manualAttachment,
		deferredFinish = options.deferredFinish,
		parent = options.parent,
		tag = options.tag,
		useExposure = options.useExposure == true,
		exposure = options.exposure or 0,
		component = nil,
	}, WidgetComponent)
	if self:create() == nil then
		return nil
	end
	table.insert(activeInstances, self)
	return self
end

-- Creates a WidgetComponent hosting a single centered Image (see widgetModule.createImageWidget). options are passed to M.new
function M.createImageComponent(imageSize, options)
	local hostWidget, image = widgetModule.createImageWidget(imageSize)
	if hostWidget == nil then return nil end
	local componentOptions = { widget = hostWidget }
	for key, value in pairs(options or {}) do componentOptions[key] = value end
	local wc = M.new(componentOptions)
	if wc == nil then return nil end
	return wc:getComponent(), image, wc
end

function WidgetComponent:create()
	if self.component ~= nil then
		return self.component
	end
	local widget = uevrUtils.getValid(self.sourceWidget) or (self.widgetClass and uevrUtils.getActiveWidgetByClass(self.widgetClass))
	if widget ~= nil and self.widgetName ~= nil and self.widgetName ~= "" then
		widget = widgetModule.getWidgetFromName(widget, self.widgetName)
		if widget == nil then
			M.print("Widget " .. self.widgetName .. " not found in " .. tostring(self.widgetClass), LogLevel.Error)
			return nil
		end
	end
	-- WidgetComponents can only host a UserWidget, so other widgets become the root of a host UserWidget
	if widget ~= nil and not widget:is_a(uevrUtils.get_class("Class /Script/UMG.UserWidget")) then
		self.hostWidget = widgetModule.createHostWidget()
		if self.hostWidget == nil then
			M.print("Failed to create host widget for " .. widget:get_full_name(), LogLevel.Error)
			return nil
		end
	end
	-- Widgets are never reparented: removing a widget rebuilds its Slate and permanently unbinds game-driven widgets.
	-- The component shares the widget's existing Slate instead.
	-- Its original parent is collapsed meanwhile, or that location would draw the widget using the component's layout.
	-- Parents with other visible children stay visible so siblings are not hidden; a canvas slot is moved offscreen instead.
	-- A WidgetSwitcher only shows the active child, so it is collapsed like a single child parent
	self.widget = widget
	local parent = widget ~= nil and widget:GetParent() or nil
	self.originalParent = parent
	if widget ~= nil and parent ~= nil then
		local slot = widget.Slot
		if parent:GetChildrenCount() == 1 or parent:is_a(uevrUtils.get_class("Class /Script/UMG.WidgetSwitcher")) then
			self.originalParentVisibility = parent:GetVisibility()
			parent:SetVisibility(1)
		elseif slot ~= nil and slot.GetLayout ~= nil then
			self.originalSlot = slot
			self.originalLayout = slot:GetLayout()
			slot:SetMinimum(uevrUtils.vector2D(0, 0))
			slot:SetMaximum(uevrUtils.vector2D(0, 0))
			slot:SetPosition(uevrUtils.vector2D(-100000, -100000))
		end
	end
	if self.hostWidget ~= nil then
		self.hostWidget.WidgetTree.RootWidget = widget
		widget = self.hostWidget
	end
	self.component = uevrUtils.createWidgetComponent(widget or self.widgetClass, {
		removeFromViewport = self.originalParent == nil,
		twoSided = self.twoSided,
		drawSize = self.drawSize and uevrUtils.vector2D(self.drawSize),
		manualAttachment = self.manualAttachment,
		relativeTransform = self.relativeTransform,
		deferredFinish = self.deferredFinish,
		parent = self.parent,
		tag = self.tag,
	})
	if self.component == nil then
		M.print("Failed to create widget component for " .. tostring(self.widgetClass), LogLevel.Error)
		return nil
	end
	if self.location ~= nil then self.component.RelativeLocation = uevrUtils.vector(self.location) end
	if self.rotation ~= nil then self.component.RelativeRotation = uevrUtils.rotator(self.rotation) end
	if self.scale ~= nil then self.component.RelativeScale3D = uevrUtils.vector(self.scale) end
	if self.useExposure then
		M.applyWidgetComponentExposureFix(self.component, getEV100 and getEV100(), self.exposure)
	end
	return self.component
end

function WidgetComponent:setUseExposure(enabled)
	self.useExposure = enabled == true
	local c = uevrUtils.getValid(self.component)
	if c == nil then return end
	if self.useExposure then
		M.applyWidgetComponentExposureFix(c, getEV100 and getEV100(), self.exposure)
		return
	end
	c:SetTintColorAndOpacity(uevrUtils.color_from_rgba(1.0, 1.0, 1.0, 1.0, true))
	c.bApplyGammaCorrection = false
	local rt = c:GetRenderTarget()
	if uevrUtils.getValid(rt) ~= nil then
		rt.bHDR = true
	end
	c:RequestRenderUpdate()
end

function WidgetComponent:setExposure(stops)
	self.exposure = stops or 0
	if not self.useExposure then return end
	M.setWidgetComponentExposure(self.component, getEV100 and getEV100(), self.exposure)
end

function WidgetComponent:attachTo(mesh, socketName, attachType, weld)
	local c = uevrUtils.getValid(self.component)
	local m = uevrUtils.getValid(mesh)
	if c ~= nil and m ~= nil then
		return c:K2_AttachTo(m, uevrUtils.fname_from_string(socketName or ""), attachType or 0, weld or false)
	end
end

-- Attach to a parent from getAvailableParents() by label and apply that parent's transform.
-- Without a label, uses the user's Attach To, then the profile's
function WidgetComponent:attachToParent(label)
	label = label or self.parentLabel
	for _, parent in ipairs(M.getAvailableParents()) do
		if parent.label == label then
			self:attachTo(parent.value, parent.socket)
			local c = uevrUtils.getValid(self.component)
			if c ~= nil then
				local t = M.getParentTransform(self, label, self.userTransforms)
				c.RelativeLocation = uevrUtils.vector(t.location)
				c.RelativeRotation = uevrUtils.rotator(t.rotation)
				c.RelativeScale3D = uevrUtils.vector(t.scale)
			end
			return true
		end
	end
	M.print("attachToParent: parent not found: " .. tostring(label), LogLevel.Warning)
	return false
end

-- Detach and keep world pose. Clears create() key so a new profile instance can be spawned.
function WidgetComponent:detach(maintainWorld)
	local c = uevrUtils.getValid(self.component)
	if c ~= nil then
		c:DetachFromParent(maintainWorld ~= false, false)
	end
	clearCreatedKey(self)
end

function WidgetComponent:getComponent()
	return self.component
end

function WidgetComponent:getWidget()
	local c = uevrUtils.getValid(self.component)
	return c ~= nil and c:GetWidget() or nil
end

function WidgetComponent:setDrawSize(drawSize)
	self.drawSize = drawSize
	local c = uevrUtils.getValid(self.component)
	if c ~= nil then
		c:SetDrawSize(uevrUtils.vector2D(drawSize))
	end
end

function WidgetComponent:setTwoSided(twoSided)
	self.twoSided = twoSided == true
	local c = uevrUtils.getValid(self.component)
	if c ~= nil then
		c:SetTwoSided(self.twoSided)
	end
end

function WidgetComponent:setRelativeLocation(location)
	local c = uevrUtils.getValid(self.component)
	if c ~= nil and location ~= nil then
		c.RelativeLocation = uevrUtils.vector(location)
	end
end

function WidgetComponent:setRelativeRotation(rotation)
	local c = uevrUtils.getValid(self.component)
	if c ~= nil and rotation ~= nil then
		c.RelativeRotation = uevrUtils.rotator(rotation)
	end
end

function WidgetComponent:setRelativeScale(scale)
	local c = uevrUtils.getValid(self.component)
	if c ~= nil and scale ~= nil then
		c.RelativeScale3D = uevrUtils.vector(scale)
	end
end

function WidgetComponent:setVisibility(isVisible, propagateToChildren)
	local c = uevrUtils.getValid(self.component)
	if c ~= nil then
		c:SetVisibility(isVisible == true, propagateToChildren ~= false)
	end
end

function WidgetComponent:isValid()
	return uevrUtils.getValid(self.component) ~= nil
end

function WidgetComponent:destroy()
	clearCreatedKey(self)
	unregisterInstance(self)
	-- The shared widget must leave the host before the host releases its Slate, or the widget's Slate is released too
	local host = uevrUtils.getValid(self.hostWidget)
	if host ~= nil and host.WidgetTree ~= nil then
		host.WidgetTree.RootWidget = uevrUtils.spawn_object("Class /Script/UMG.CanvasPanel", host.WidgetTree)
	end
	self.hostWidget = nil
	local c = uevrUtils.getValid(self.component)
	if c ~= nil  then
		if c.SetWidget ~= nil then c:SetWidget(nil) end
		if c.DetachFromParent ~= nil then c:DetachFromParent(false, false) end
		uevrUtils.destroyComponent(self.component, true, true)
	end
	self.component = nil
	-- The original location keeps the component's layout until it is re-laid out
	local parent = uevrUtils.getValid(self.originalParent)
	local slot = uevrUtils.getValid(self.originalSlot)
	local widget = uevrUtils.getValid(self.widget)
	if parent ~= nil and self.originalParentVisibility ~= nil then
		parent:SetVisibility(self.originalParentVisibility)
	else
		if slot ~= nil then
			slot:SetLayout(self.originalLayout)
		end
		if parent ~= nil then
			parent:InvalidateLayoutAndVolatility()
		end
	end
	-- A panel's children are not redrawn in the original location until their own visibility changes for a while.
	-- Skipped on script reset, where the delayed restore never runs and the children would stay collapsed
	if not isScriptResetting and widget ~= nil and widget.GetChildrenCount ~= nil then
		local children = {}
		for i = 0, widget:GetChildrenCount() - 1 do
			local child = widget:GetChildAt(i)
			children[child] = child:GetVisibility()
			child:SetVisibility(1)
		end
		delay(250, function()
			for child, visibility in pairs(children) do
				if uevrUtils.getValid(child) ~= nil then
					child:SetVisibility(visibility)
				end
			end
		end)
	end
	self.widget = nil
	self.originalParent = nil
	self.originalParentVisibility = nil
	self.originalSlot = nil
	self.originalLayout = nil
end

function M.getAvailableParents()
	if M.getAvailableParentsCallback ~= nil then
		return M.getAvailableParentsCallback() or {}
	end
	return {
		{ label = "Right Controller", value = controllers.getController(Handed.Right) },
		{ label = "Left Controller", value = controllers.getController(Handed.Left) },
	}
end

-- settings is a profile or an instance. Each field comes from userTransforms[label] (optional), then the profile's
-- transforms[label], then its flat location/rotation/scale, then defaults
function M.getParentTransform(settings, label, userTransforms)
	local u = userTransforms and userTransforms[label] or {}
	local t = settings.transforms and settings.transforms[label] or {}
	return {
		location = u.location or t.location or settings.location or {0, 0, 0},
		rotation = u.rotation or t.rotation or settings.rotation or {0, 0, 0},
		scale = u.scale or t.scale or settings.scale or {0.1, 0.1, 0.1},
	}
end

-- Applies the user settings of a profile: UI destroys its instance, otherwise it is created if needed and updated
function M.applyUserSettings(id)
	if disabledByKey[id] then
		M.destroy(id)
		return
	end
	local inst = M.create(id)
	if inst == nil then return end
	local opts = M.optionsFromProfile(paramManager:get(id), userParamManager:get(id))
	if opts == nil then return end
	inst.parentLabel = opts.attachTo
	inst.userTransforms = opts.userTransforms
	inst:setExposure(opts.exposure)
	if inst.parentLabel ~= M.AttachTo.None then inst:attachToParent() end
	inst:setVisibility(inst.parentLabel ~= M.AttachTo.None and inst.component:GetAttachParent() ~= nil)
end

-- Detaches and hides every create() instance but keeps it alive. Call before destroying a parent (e.g. hand meshes
-- destroyed with their children), or the component is destroyed too and its shared widget goes blank. They are
-- reattached and shown by the user settings timer once the parent exists again
function M.detachAll()
	for _, inst in pairs(createdByKey) do
		local c = uevrUtils.getValid(inst.component)
		if c ~= nil and c.DetachFromParent ~= nil then
			c:DetachFromParent(true, false)
			inst:setVisibility(false)
		end
	end
end

-- End user settings (Brightness, Attach To, Position, Rotation, Scale and Restore Defaults) for each profile
function M.getConfigurationWidgets(options)
	return widgetComponentConfig.getConfigurationWidgets(options)
end

function M.registerGetAvailableParentsCallback(callback)
	M.getAvailableParentsCallback = callback
	widgetComponentConfig.refresh()
	if widgetComponentConfigDev ~= nil then
		widgetComponentConfigDev.refreshParentSelections()
	end
end

setInterval(1000, function()
	if getEV100 == nil or #activeInstances == 0 then return end
	local ev100 = getEV100()
	for _, inst in ipairs(activeInstances) do
		if inst.useExposure then
			M.setWidgetComponentExposure(inst.component, ev100, inst.exposure)
		end
	end
end)

-- Realizes the user's Attach To after script resets and level changes, once the game's widget exists.
-- Retries attaching while the parent (e.g. a hand mesh) is not ready yet
setInterval(1000, function()
	for id, settings in pairs(userParamManager:getAll() or {}) do
		if not disabledByKey[id] then
			local attachTo = type(settings) == "table" and settings.attachTo
			if attachTo and attachTo ~= M.AttachTo.UI then
				local inst = createdByKey[id]
				if inst == nil or not inst:isValid() or (attachTo ~= M.AttachTo.None and inst.component:GetAttachParent() == nil) then
					local profile = paramManager:get(id)
					if profile ~= nil and uevrUtils.getActiveWidgetByClass(profile.widgetClass) ~= nil then
						M.applyUserSettings(id)
					end
				end
			end
		end
	end
end)

uevrUtils.registerPreLevelChangeCallback(function()
	M.destroyAll()
end)

uevr.params.sdk.callbacks.on_script_reset(function()
	isScriptResetting = true
	M.destroyAll()
end)

return M
