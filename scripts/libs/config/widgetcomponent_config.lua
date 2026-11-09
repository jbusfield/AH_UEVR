local uevrUtils = require("libs/uevr_utils")
local configui = require("libs/configui")

local M = {}

local widgetPrefix = "uevr_widgetcomponent_user_"

---@type any
local paramManager = nil
---@type any
local userParamManager = nil
---@type any
local widgetComponentModule = nil
-- Attach To combo labels and the matching stored values: UI, the parent labels, then None
local attachToLabels = {}
local attachToValues = {}
local profileIds = {}

-- Filled in place: the Attach To combos hold attachToLabels as their selections, including before the panel exists
local function loadAttachToSelections()
	for i = #attachToLabels, 1, -1 do attachToLabels[i] = nil; attachToValues[i] = nil end
	table.insert(attachToLabels, "UI")
	table.insert(attachToValues, widgetComponentModule.AttachTo.UI)
	for _, parent in ipairs(widgetComponentModule.getAvailableParents()) do
		table.insert(attachToLabels, parent.label)
		table.insert(attachToValues, parent.label)
	end
	table.insert(attachToLabels, "None")
	table.insert(attachToValues, widgetComponentModule.AttachTo.None)
end

-- Shows the profile's settings with the user's overrides applied
local function refreshUI(id)
	local profile = paramManager:get(id) or {}
	local user = userParamManager:get(id) or {}
	local prefix = widgetPrefix .. id .. "_"
	local attachTo = user.attachTo or widgetComponentModule.AttachTo.UI
	for i, value in ipairs(attachToValues) do
		if value == attachTo then configui.setValue(prefix .. "attachTo", i, true) end
	end
	local onParent = type(attachTo) == "string"
	local t = widgetComponentModule.getParentTransform(profile, attachTo, user.transforms)
	configui.setValue(prefix .. "exposure", user.exposure or profile.exposure or 0, true)
	configui.setValue(prefix .. "location", t.location, true)
	configui.setValue(prefix .. "rotation", t.rotation, true)
	configui.setValue(prefix .. "scale", t.scale, true)
	configui.setHidden(prefix .. "exposure", not onParent or profile.useExposure ~= true)
	configui.setHidden(prefix .. "location", not onParent)
	configui.setHidden(prefix .. "rotation", not onParent)
	configui.setHidden(prefix .. "scale", not onParent)
end

local function setUserValue(id, key, value)
	userParamManager:set(key, value, true)
	widgetComponentModule.applyUserSettings(id)
end

function M.getConfigurationWidgets(options)
	loadAttachToSelections()
	local widgets = spliceableInlineArray{}
	local ids, names = paramManager:getProfiles()
	local order = {}
	for i, id in ipairs(ids) do
		local profile = paramManager:get(id)
		if profile ~= nil and profile.widgetClass ~= nil and profile.widgetClass ~= "" then table.insert(order, i) end
	end
	table.sort(order, function(a, b) return names[a] < names[b] end)
	profileIds = {}
	for _, i in ipairs(order) do
		local id = ids[i]
		local prefix = widgetPrefix .. id .. "_"
		table.insert(profileIds, id)
		for _, widget in ipairs({
			{ widgetType = "tree_node", id = prefix .. "tree", initialOpen = false, label = names[i] },
			{ widgetType = "slider_float", id = prefix .. "exposure", label = "Brightness", speed = 0.1, range = {-5, 5}, initialValue = 0 },
			{ widgetType = "combo", id = prefix .. "attachTo", label = "Attach To", selections = attachToLabels, initialValue = 1 },
			{ widgetType = "drag_float3", id = prefix .. "location", label = "Position", speed = 0.1, range = {-100, 100}, initialValue = {0, 0, 0} },
			{ widgetType = "drag_float3", id = prefix .. "rotation", label = "Rotation", speed = 0.1, range = {-180, 180}, initialValue = {0, 0, 0} },
			{ widgetType = "drag_float3", id = prefix .. "scale", label = "Scale", speed = 0.001, range = {0.001, 10}, initialValue = {0.1, 0.1, 0.1} },
			{ widgetType = "button", id = prefix .. "restore", label = "Restore Defaults", size = {150, 22} },
			{ widgetType = "tree_pop" },
		}) do
			table.insert(widgets, widget)
		end

		configui.onCreate(prefix .. "exposure", function()
			refreshUI(id)
		end)
		configui.onUpdate(prefix .. "exposure", function(value)
			setUserValue(id, {id, "exposure"}, value)
		end)
		configui.onUpdate(prefix .. "attachTo", function(value)
			setUserValue(id, {id, "attachTo"}, attachToValues[value])
			refreshUI(id)
		end)
		for _, key in ipairs({"location", "rotation", "scale"}) do
			configui.onUpdate(prefix .. key, function(value)
				local label = attachToValues[configui.getValue(prefix .. "attachTo")]
				if type(label) == "string" then setUserValue(id, {id, "transforms", label, key}, value) end
			end)
		end
		configui.onUpdate(prefix .. "restore", function()
			setUserValue(id, id, nil)
			refreshUI(id)
		end)
	end
	return configui.applyOptionsToConfigWidgets(widgets, options)
end

-- Reloads the parent list and shows current values. Call after the parents or the dev profiles change
function M.refresh()
	if widgetComponentModule == nil then return end
	loadAttachToSelections()
	for _, id in ipairs(profileIds) do
		configui.setSelections(widgetPrefix .. id .. "_attachTo", attachToLabels)
		refreshUI(id)
	end
end

function M.init(m_paramManager, m_userParamManager, widgetComponentApi)
	paramManager = m_paramManager
	userParamManager = m_userParamManager
	widgetComponentModule = widgetComponentApi
end

uevrUtils.registerUEVRCallback("on_widgetcomponent_config_param_change", function()
	M.refresh()
end)

return M
