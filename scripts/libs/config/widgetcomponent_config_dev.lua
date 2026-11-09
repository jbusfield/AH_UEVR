local uevrUtils = require("libs/uevr_utils")
local configui = require("libs/configui")
local interaction = require("libs/interaction")
local mathLib = require("libs/core/math_lib")
local controllers = require("libs/controllers")

local M = {}

local configFileName = "dev/widgetcomponent_config_dev"
local configTabLabel = "Widget Component Config Dev"
local widgetPrefix = "uevr_widgetcomponent_"

local paramManager = nil
local widgetComponentModule = nil
local suppressUI = false

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[widgetcomponent config] " .. text, logLevel)
	end
end

local function getConfigWidgets(m_paramManager)
	return spliceableInlineArray {
		expandArray(m_paramManager.getProfilePreConfigurationWidgets, widgetPrefix, "Widget Component"),
        { widgetType = "begin_group", id = widgetPrefix .. "current_widget_info", isHidden = false }, { widgetType = "indent", width = 10 }, { widgetType = "text", label = "Widget Component Settings" }, { widgetType = "begin_rect", },
		{
			widgetType = "tree_node",
			id = widgetPrefix .. "finder_tool",
			initialOpen = true,
			label = "Widget Finder"
		},
            {
                widgetType = "tree_node",
                id = widgetPrefix .. "finder_instruction_tree",
                initialOpen = false,
                label = "Widget Finder Instructions"
            },
                {
                    widgetType = "text",
                    id = widgetPrefix .. "finder_instructions",
                    label = "Lists the classes of currently active User Widgets. You can enter text in the search text box below to filter the list. Press the Find button to see an updated list.",
                    wrapped = true
                },
            { widgetType = "tree_pop" },
			{
				widgetType = "checkbox",
				id = widgetPrefix .. "finder_tool_pointer",
				label = "Use Pointer (Use laser pointer to find widgets)",
				initialValue = false,
			},
			{ widgetType = "begin_group", id = widgetPrefix .. "finder_tool_pointer_group", isHidden = false },
			{
				widgetType = "checkbox",
				id = widgetPrefix .. "finder_tool_pointer_locked",
				label = "Locked (Press Trigger while hovering over a widget to lock in selection)",
				initialValue = false,
			},
			{
				widgetType = "input_text",
				id = widgetPrefix .. "finder_tool_pointer_text",
				label = "Found Widget",
				initialValue = "",
				isHidden = true,
			},
			{
				widgetType = "input_text",
				id = widgetPrefix .. "finder_tool_pointer_name_text",
				label = "Widget Name",
				initialValue = "",
			},
			{ widgetType = "end_group" },
			{ widgetType = "begin_group", id = widgetPrefix .. "finder_tool_search_group", isHidden = false },
			{
				widgetType = "input_text",
				id = widgetPrefix .. "finder_tool_search_text",
				label = "",
				initialValue = "",
			},
			{ widgetType = "same_line" },
			{
				widgetType = "button",
				id = widgetPrefix .. "finder_tool_search_button",
				label = "Find",
				size = {80, 22},
			},
			{
				widgetType = "button",
				id = widgetPrefix .. "finder_tool_list_prev",
				label = "<",
				size = {40, 22},
			},
			{ widgetType = "same_line" },
			{
				widgetType = "combo",
				id = widgetPrefix .. "finder_tool_list",
				label = "Widgets",
				selections = {"None"},
				initialValue = 1,
                width = 300,
			},
			{ widgetType = "same_line" },
			{
				widgetType = "button",
				id = widgetPrefix .. "finder_tool_list_next",
				label = ">",
				size = {40, 22},
			},
			{ widgetType = "end_group" },
            --{ widgetType = "indent", width = 48 },
			{
				widgetType = "combo",
				id = widgetPrefix .. "finder_tool_hierarchy",
				label = "Hierarchy",
				selections = {"None"},
				initialValue = 1,
                --width = 300,
			},
            --{ widgetType = "unindent", width = 48 },
            { widgetType = "indent", width = 120 },
			{
				widgetType = "button",
				id = widgetPrefix .. "use_hierarchy_selected_button",
				label = "Use Selected",
				size = {120, 22},
			},
			{ widgetType = "same_line" },
			{
				widgetType = "button",
				id = widgetPrefix .. "toggle_selected_button",
				label = "Hide/Show",
				size = {120, 22},
			},
            { widgetType = "unindent", width = 120 },
			{ widgetType = "new_line" },
			{ widgetType = "tree_pop" },
		{
			widgetType = "input_text",
			id = widgetPrefix .. "widgetClass",
			label = "Widget Class",
			initialValue = "",
		},
		{
			widgetType = "input_text",
			id = widgetPrefix .. "widgetName",
			label = "Widget Name",
			initialValue = "",
		},
		{
			widgetType = "drag_float2",
			id = widgetPrefix .. "drawSize",
			label = "Draw Size",
			speed = 1,
			range = {1, 4096},
			initialValue = {100, 100},
		},
		{
			widgetType = "checkbox",
			id = widgetPrefix .. "twoSided",
			label = "Two Sided",
			initialValue = true,
		},
		{
			widgetType = "checkbox",
			id = widgetPrefix .. "useExposure",
			label = "Apply Exposure Compensation",
			initialValue = false,
		},
		{
			widgetType = "slider_float",
			id = widgetPrefix .. "exposure",
			label = "Brightness",
			speed = 0.1,
			range = {-5, 5},
			initialValue = 0,
		},
		{
			widgetType = "combo",
			id = widgetPrefix .. "test_hand",
			label = "Attach To",
			selections = {"Right Controller", "Left Controller"},
			initialValue = 1,
			--width = 140,
		},
		{
			widgetType = "drag_float3",
			id = widgetPrefix .. "location",
			label = "Position",
			speed = 0.1,
			range = {-100, 100},
			initialValue = {0, 0, 0},
		},
		{
			widgetType = "drag_float3",
			id = widgetPrefix .. "rotation",
			label = "Rotation",
			speed = 0.1,
			range = {-180, 180},
			initialValue = {0, 0, 0},
		},
		{
			widgetType = "drag_float3",
			id = widgetPrefix .. "scale",
			label = "Scale",
			speed = 0.001,
			range = {0.001, 10},
			initialValue = {0.1, 0.1, 0.1},
		},
	    { widgetType = "indent", width = 150 },
        { widgetType = "begin_group", id = widgetPrefix .. "test_group", isHidden = false },
		{ widgetType = "text", label = " " },
        { widgetType = "same_line" },
        {
			widgetType = "button",
			id = widgetPrefix .. "test_button",
			label = "Test",
			size = {80, 22},
		},
		{ widgetType = "same_line" },
		{
			widgetType = "button",
			id = widgetPrefix .. "stop_test_button",
			label = "Stop",
			size = {80, 22},
		},
		{ widgetType = "same_line" },
        { widgetType = "end_group", },
        { widgetType = "unindent", width = 150 },
        { widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 10 }, { widgetType = "end_group", },
		{ widgetType = "new_line" },
        expandArray(m_paramManager.getProfilePostConfigurationWidgets, widgetPrefix, ""),
	}
end

local widgetClassNames = {}

local hierarchyWidgets = {}
local function refreshHierarchy(w)
	local hierarchy = {}
	hierarchyWidgets = {}
	if w == nil then
		local widgetClass = widgetClassNames[configui.getValue(widgetPrefix .. "finder_tool_list")]
		w = widgetClass and uevrUtils.getActiveWidgetByClass(widgetClass)
	end
	local widgetTreeClass = uevrUtils.get_class("Class /Script/UMG.WidgetTree")
	while uevrUtils.getValid(w) ~= nil do
		table.insert(hierarchyWidgets, w)
		table.insert(hierarchy, string.rep("  ", #hierarchy) .. w:get_class():get_fname():to_string() .. " : " .. w:get_fname():to_string())
		local parent = w:GetParent()
		if parent == nil then
			local tree = w:get_outer()
			parent = tree ~= nil and tree:is_a(widgetTreeClass) and tree:get_outer() or nil
		end
		w = parent
	end
	if #hierarchy == 0 then hierarchy = {"None"} end
	configui.setSelections(widgetPrefix .. "finder_tool_hierarchy", hierarchy)
	configui.setValue(widgetPrefix .. "finder_tool_hierarchy", 1, true)
end

local function loadWidgetClasses()
	widgetClassNames = {}
	local searchText = configui.getValue(widgetPrefix .. "finder_tool_search_text")
	local seen = {}
	local instances = uevrUtils.find_all_instances("Class /Script/UMG.UserWidget", false)
	if instances ~= nil then
		for _, widget in pairs(instances) do
			local className = widget:get_class():get_full_name()
			if not seen[className] and (searchText == nil or searchText == "" or string.find(className:lower(), searchText:lower(), 1, true)) then
				seen[className] = true
				table.insert(widgetClassNames, className)
			end
		end
	end
	configui.setSelections(widgetPrefix .. "finder_tool_list", widgetClassNames)
	refreshHierarchy()
end

local currentTest = nil

local function stopTest()
	if currentTest ~= nil then
		currentTest:destroy()
	end
	currentTest = nil
	configui.setHidden(widgetPrefix .. "test_button", false)
	configui.setHidden(widgetPrefix .. "stop_test_button", true)
end

function M.stopTest()
	stopTest()
end

local function updateSetting(key, value)
	if paramManager == nil then return end
	paramManager:setInActiveProfile(key, value, true)
	uevrUtils.executeUEVRCallbacks("on_widgetcomponent_config_param_change", key, value)
end

local function updateUIValue(key, value)
	suppressUI = true
	configui.setValue(widgetPrefix .. key, value, true)
	suppressUI = false
	if key == "useExposure" then
		configui.setHidden(widgetPrefix .. "exposure", value ~= true)
	end
end

local parentLabels = {"Right Controller", "Left Controller"}
local function getSelectedParentLabel()
	return parentLabels[configui.getValue(widgetPrefix .. "test_hand")]
end

local function refreshTransformUI()
	if paramManager == nil or widgetComponentModule == nil then return end
	local attachTo = paramManager:getFromActiveProfile("attachTo")
	for i, label in ipairs(parentLabels) do
		if label == attachTo then configui.setValue(widgetPrefix .. "test_hand", i, true) end
	end
	local t = widgetComponentModule.getParentTransform(paramManager:getAllActiveProfileParams() or {}, getSelectedParentLabel())
	updateUIValue("location", t.location)
	updateUIValue("rotation", t.rotation)
	updateUIValue("scale", t.scale)
end

local function updateTransform(key, value)
	local label = getSelectedParentLabel()
	if label == nil then return end
	updateSetting({"transforms", label, key}, value)
end

local function attachTest()
	if currentTest ~= nil then
		currentTest:attachToParent(getSelectedParentLabel())
	end
end

local function startTest()
	stopTest()
	if paramManager == nil or widgetComponentModule == nil then return end
	local opts = widgetComponentModule.optionsFromProfile(paramManager:getAllActiveProfileParams() or {})
	if opts == nil then
		M.print("Test failed: set a widget class first (Use Selected)", LogLevel.Error)
		return
	end
	currentTest = widgetComponentModule.new(opts)
	if currentTest == nil then
		M.print("Test failed: widget component was not created", LogLevel.Error)
		return
	end
	attachTest()
	configui.setHidden(widgetPrefix .. "test_button", true)
	configui.setHidden(widgetPrefix .. "stop_test_button", false)
end

function M.getConfigurationWidgets(options)
	return configui.applyOptionsToConfigWidgets(getConfigWidgets(paramManager), options)
end

function M.showConfiguration(saveFileName, options)
	configui.createConfigPanel(configTabLabel, saveFileName, spliceableInlineArray{expandArray(M.getConfigurationWidgets, options)})
end

function M.init(m_paramManager, widgetComponentApi)
	paramManager = m_paramManager
	widgetComponentModule = widgetComponentApi
	M.showConfiguration(configFileName)
	configui.setHidden(widgetPrefix .. "stop_test_button", true)
	loadWidgetClasses()

	paramManager:initProfileHandler(widgetPrefix, function(profileParams)
		stopTest()
		for key, def in pairs(paramManager.defaultParameters or {}) do
			local value = profileParams[key]
			if value == nil then value = def end
			if key ~= "transforms" then
				updateUIValue(key, value)
			end
		end
		refreshTransformUI()
	end)
	M.refreshParentSelections()
end

configui.onUpdate(widgetPrefix .. "widgetClass", function(value)
	if suppressUI then return end
	updateSetting("widgetClass", value)
end)
configui.onUpdate(widgetPrefix .. "widgetName", function(value)
	if suppressUI then return end
	updateSetting("widgetName", value)
end)
configui.onUpdate(widgetPrefix .. "drawSize", function(value)
	if suppressUI then return end
	updateSetting("drawSize", value)
	if currentTest ~= nil then currentTest:setDrawSize(value) end
end)
configui.onUpdate(widgetPrefix .. "scale", function(value)
	if suppressUI then return end
	updateTransform("scale", value)
	if currentTest ~= nil then currentTest:setRelativeScale(value) end
end)
configui.onUpdate(widgetPrefix .. "location", function(value)
	if suppressUI then return end
	updateTransform("location", value)
	if currentTest ~= nil then currentTest:setRelativeLocation(value) end
end)
configui.onUpdate(widgetPrefix .. "rotation", function(value)
	if suppressUI then return end
	updateTransform("rotation", value)
	if currentTest ~= nil then currentTest:setRelativeRotation(value) end
end)
configui.onUpdate(widgetPrefix .. "useExposure", function(value)
	configui.setHidden(widgetPrefix .. "exposure", value ~= true)
	if suppressUI then return end
	updateSetting("useExposure", value == true)
	if currentTest ~= nil then currentTest:setUseExposure(value) end
end)
configui.onCreate(widgetPrefix .. "useExposure", function()
	configui.setHidden(widgetPrefix .. "exposure", configui.getValue(widgetPrefix .. "useExposure") ~= true)
end)
configui.onUpdate(widgetPrefix .. "exposure", function(value)
	if suppressUI then return end
	updateSetting("exposure", value)
	if currentTest ~= nil then currentTest:setExposure(value) end
end)
configui.onUpdate(widgetPrefix .. "twoSided", function(value)
	if suppressUI then return end
	updateSetting("twoSided", value == true)
	if currentTest ~= nil then currentTest:setTwoSided(value) end
end)
configui.onUpdate(widgetPrefix .. "finder_tool_search_button", function()
	loadWidgetClasses()
end)
configui.onUpdate(widgetPrefix .. "finder_tool_list", function(value)
	print(widgetClassNames[value])
	refreshHierarchy()
end)
configui.onUpdate(widgetPrefix .. "finder_tool_hierarchy", function(value)
	local w = uevrUtils.getValid(hierarchyWidgets[value])
	if w ~= nil then print(w:get_full_name()) end
end)
configui.onUpdate(widgetPrefix .. "finder_tool_list_prev", function()
	local index = (configui.getValue(widgetPrefix .. "finder_tool_list") or 1) - 1
	if index < 1 then index = 1 end
	if index <= #widgetClassNames then
		configui.setValue(widgetPrefix .. "finder_tool_list", index)
	end
end)
configui.onUpdate(widgetPrefix .. "finder_tool_list_next", function()
	if #widgetClassNames < 1 then return end
	local index = (configui.getValue(widgetPrefix .. "finder_tool_list") or 1) + 1
	if index > #widgetClassNames then index = #widgetClassNames end
	configui.setValue(widgetPrefix .. "finder_tool_list", index)
end)
local function useWidget(widget, widgetClass, widgetName)
	updateSetting("widgetClass", widgetClass)
	updateSetting("widgetName", widgetName)
	suppressUI = true
	configui.setValue(widgetPrefix .. "widgetClass", widgetClass, true)
	configui.setValue(widgetPrefix .. "widgetName", widgetName, true)
	suppressUI = false
	local size = widget ~= nil and widget:GetDesiredSize()
	if size and size.X > 0 and size.Y > 0 then
		updateSetting("drawSize", {size.X, size.Y})
		updateUIValue("drawSize", {size.X, size.Y})
	end
	stopTest()
end

configui.onUpdate(widgetPrefix .. "use_hierarchy_selected_button", function()
	local w = uevrUtils.getValid(hierarchyWidgets[configui.getValue(widgetPrefix .. "finder_tool_hierarchy")])
	if w == nil then return end
	if w:is_a(uevrUtils.get_class("Class /Script/UMG.UserWidget")) then
		useWidget(w, w:get_class():get_full_name(), "")
	else
		local owner = w:get_outer():get_outer()
		useWidget(w, owner:get_class():get_full_name(), w:get_fname():to_string())
	end
end)

local hiddenWidget = nil
local hiddenWidgetVisibility = nil
configui.onUpdate(widgetPrefix .. "toggle_selected_button", function()
	local widgetClass = widgetClassNames[configui.getValue(widgetPrefix .. "finder_tool_list")]
	local widget = widgetClass and uevrUtils.getActiveWidgetByClass(widgetClass)
	local wasHidden = widget ~= nil and widget == hiddenWidget
	local previous = uevrUtils.getValid(hiddenWidget)
	if previous ~= nil then
		previous:SetVisibility(hiddenWidgetVisibility)
	end
	hiddenWidget = nil
	if widget == nil or wasHidden then return end
	hiddenWidget = widget
	hiddenWidgetVisibility = widget:GetVisibility()
	widget:SetVisibility(2) -- ESlateVisibility.Hidden
end)

local previousInteractionType = nil
local slateLibrary = nil
local pointedWidget = nil
local function getModFloat(name)
	return tonumber(string.match(uevr.params.vr:get_mod_value(name) or "", "[%-%d%.]+")) or 0
end
-- Intersects the right controller ray with UEVR's UI quad and reports the smallest visible UserWidget under that point.
-- Assumes UI Follows View is off
local function findPointedWidget()
	local vr = uevr.params.vr
	vr.get_rotation_offset(temp_quatf)
	local uiRotation = {X = temp_quatf.X, Y = temp_quatf.Y, Z = temp_quatf.Z, W = temp_quatf.W}
	vr.get_standing_origin(temp_vec3f)
	local origin = {X = temp_vec3f.X, Y = temp_vec3f.Y, Z = temp_vec3f.Z}
	vr.get_pose(vr.get_right_controller_index(), temp_vec3f, temp_quatf)
	local start = mathLib.vectorRotate_Quat({X = temp_vec3f.X - origin.X, Y = temp_vec3f.Y - origin.Y, Z = temp_vec3f.Z - origin.Z}, uiRotation, false)
	-- Lua only exposes the grip pose, which points well above the aim ray, so take the in-game aim direction
	-- relative to the HMD and re-express it in tracking space through the HMD's tracked rotation
	local hmdRotation = controllers.getControllerRotation(2)
	local aimDirection = controllers.getControllerDirection(Handed.Right)
	if hmdRotation == nil or aimDirection == nil then return end
	local d = kismet_math_library:LessLess_VectorRotator(aimDirection, hmdRotation)
	vr.get_pose(vr.get_hmd_index(), temp_vec3f, temp_quatf)
	local dir = mathLib.vectorRotate_Quat(mathLib.vectorRotate_Quat({X = d.Y, Y = d.Z, Z = -d.X}, temp_quatf, false), uiRotation, false)
	if start == nil or dir == nil then return end
	local x = start.X - getModFloat("UI_X_Offset")
	local y = start.Y - getModFloat("UI_Y_Offset")
	local z = start.Z + getModFloat("UI_Distance")
	local t = dir.Z ~= 0 and -z / dir.Z or -1
	local height = getModFloat("UI_Size")
	local width = height * vr.get_ui_width() / vr.get_ui_height()
	local u = (x + dir.X * t) / width + 0.5
	local v = 0.5 - (y + dir.Y * t) / height
	if t <= 0 or u < 0 or u > 1 or v < 0 or v > 1 then
		if pointedWidget ~= nil then
			pointedWidget = nil
			configui.setValue(widgetPrefix .. "finder_tool_pointer_text", "")
			configui.setValue(widgetPrefix .. "finder_tool_pointer_name_text", "")
		end
		return
	end

	local world = uevrUtils.get_world()
	---@diagnostic disable-next-line: undefined-field
	local viewportSize = WidgetLayoutLibrary:GetViewportSize(world)
	if slateLibrary == nil then slateLibrary = uevrUtils.find_default_instance("Class /Script/UMG.SlateBlueprintLibrary") end
	if slateLibrary == nil then return end
	-- Cached geometry is in desktop space, offset and scaled from the viewport. There is no ViewportToAbsolute,
	-- so derive the mapping from two reference points and convert the pointer to absolute space once
	local p0, p1 = {}, {}
	slateLibrary:AbsoluteToViewport(world, uevrUtils.vector2D(0, 0), p0, {})
	slateLibrary:AbsoluteToViewport(world, uevrUtils.vector2D(1000, 1000), p1, {})
	if p0.result == nil or p1.result == nil or p1.result.X == p0.result.X or p1.result.Y == p0.result.Y then return end
	local point = uevrUtils.vector2D(
		(u * viewportSize.X - p0.result.X) * 1000 / (p1.result.X - p0.result.X),
		(v * viewportSize.Y - p0.result.Y) * 1000 / (p1.result.Y - p0.result.Y))
	local best, bestArea = nil, nil
	for _, w in pairs(uevrUtils.find_all_instances("Class /Script/UMG.UserWidget", false) or {}) do
		if w:IsVisible() then
			local geometry = w:GetCachedGeometry()
			if slateLibrary:IsUnderLocation(geometry, point) then
				local size = slateLibrary:GetAbsoluteSize(geometry)
				local area = size.X * size.Y
				if area > 0 and (bestArea == nil or area < bestArea) then best, bestArea = w, area end
			end
		end
	end
	if best == pointedWidget then return end
	pointedWidget = best
	configui.setValue(widgetPrefix .. "finder_tool_pointer_text", best and best:get_class():get_full_name() or "")
	configui.setValue(widgetPrefix .. "finder_tool_pointer_name_text", uevrUtils.getShortName(best))
end

configui.onCreateOrUpdate(widgetPrefix .. "finder_tool_pointer", function(value)
	configui.setHidden(widgetPrefix .. "finder_tool_pointer_group", not value)
	configui.setHidden(widgetPrefix .. "finder_tool_search_group", value == true)
	if value then
		previousInteractionType = previousInteractionType or configui.getValue("interactionType") or interaction.InteractionType.None
		interaction.setInteractionType(interaction.InteractionType.Mesh)
	elseif previousInteractionType ~= nil then
		-- setInteractionType persists, so a refresh while the pointer was on captures Mesh as the previous type
		interaction.setInteractionType(previousInteractionType ~= interaction.InteractionType.Mesh and previousInteractionType or interaction.InteractionType.None)
		previousInteractionType = nil
	end
end)

setInterval(250, function()
	if configui.getValue(widgetPrefix .. "finder_tool_pointer") and not configui.getValue(widgetPrefix .. "finder_tool_pointer_locked") then findPointedWidget() end
end)

configui.onUpdate(widgetPrefix .. "finder_tool_pointer_locked", function(value)
	if value then refreshHierarchy(uevrUtils.getValid(pointedWidget)) end
end)

local wasTriggerPressed = false
uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
	if not configui.getValue(widgetPrefix .. "finder_tool_pointer") then return end
	local vr = uevr.params.vr
	local isTriggerPressed = vr.is_action_active(vr.get_action_handle("/actions/default/in/Trigger"), vr.get_right_joystick_source())
	if isTriggerPressed and not wasTriggerPressed then
		configui.setValue(widgetPrefix .. "finder_tool_pointer_locked", not configui.getValue(widgetPrefix .. "finder_tool_pointer_locked"))
	end
	wasTriggerPressed = isTriggerPressed
end)

configui.onUpdate(widgetPrefix .. "test_hand", function()
	updateSetting("attachTo", getSelectedParentLabel())
	refreshTransformUI()
	attachTest()
end)
function M.refreshParentSelections()
	if widgetComponentModule == nil then return end
	parentLabels = {}
	for i, parent in ipairs(widgetComponentModule.getAvailableParents()) do
		parentLabels[i] = parent.label
	end
	configui.setSelections(widgetPrefix .. "test_hand", parentLabels)
	refreshTransformUI()
end
configui.onUpdate(widgetPrefix .. "test_button", function()
	startTest()
end)
configui.onUpdate(widgetPrefix .. "stop_test_button", function()
	stopTest()
end)

return M
