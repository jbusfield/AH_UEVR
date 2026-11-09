local uevrLib = require("libs/core/uevr_lib")
local uevrUtils = require("libs/uevr_utils")
local configui = require("libs/configui")
local controllers = require("libs/controllers")
local reticule = require("libs/reticule")
local plugin = require("libs/core/plugin")
-- Loaded on first use; not every project sharing this file ships libs/particles.lua
local particles = nil

local M = {}

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[dev] " .. text, logLevel)
	end
end

---@type any
local currentComponent = nil

local meshNames = {}
local currentSelectionIndex = 1

local materialNames = {}
local currentMaterialSelectionIndex = 1

local widgetNames = {}
local currentWidgetSelectionIndex = 1

local reticuleNames = {}
local currentReticuleSelectionIndex = 1

local particleNames = {}
local currentParticleSelectionIndex = 1
local currentParticle = nil
local particleEmitterAsset = nil
local particleEmitterNames = {}
local particleEmitterDefaults = {}
local particleEmitterOverrides = {}

local configDefinition = {
	{
		panelLabel = "Dev Utils",
		windowed = false,
		saveFile = "config_dev_utils",
		id = "uevr_dev_panel",
		layout =
		{
			{
				widgetType = "tree_node",
				id = "uevr_dev_mesh_viewer",
				label = "Mesh Viewer"
			},
				{
					widgetType = "combo",
					id = "uevr_dev_mesh_type",
					label = "Mesh Type",
					selections = {"Static Mesh","Skeletal Mesh"},
					initialValue = 1
				},
				{
					widgetType = "input_text",
					id = "uevr_dev_mesh_filter",
					label = "Filter",
					initialValue = ""
				},
				{
					widgetType = "same_line",
				},
				{
					widgetType = "button",
					id = "uevr_dev_mesh_refresh_button",
					label = "Refresh",
					size = {80,22}
				},
				{
					widgetType = "button",
					id = "uevr_dev_mesh_prev",
					label = "<",
					size = {40,22}
				},
				{
					widgetType = "same_line",
				},
				{
					widgetType = "combo",
					id = "uevr_dev_mesh_list",
					label = "",
					selections = {"None"},
					initialValue = 1
				},
				{
					widgetType = "same_line",
				},
				{
					widgetType = "button",
					id = "uevr_dev_mesh_next",
					label = ">",
					size = {40,22}
				},
				{
					widgetType = "input_text",
					id = "uevr_dev_mesh_selected_name",
					label = "Current Selection",
					initialValue = ""
				},
				{
					widgetType = "begin_group"
				},
					{
						widgetType = "text",
						id = "uevr_dev_mesh_total_count",
						label = "Total static meshes"
					},
					{
						widgetType = "text",
						id = "uevr_dev_mesh_filtered_count",
						label = "Filtered static meshes"
					},
				{
					widgetType = "end_group"
				},
				{
					widgetType = "indent",
					width = 12
				},
				{
					widgetType = "text",
					label = "UI"
				},
				{
					widgetType = "begin_rect",
				},
					{
						widgetType = "checkbox",
						id = "uevr_dev_mesh_nativescale",
						label = "Show at native scale",
						initialValue = false
					},
					{
						widgetType = "drag_float",
						id = "uevr_dev_mesh_relativescale",
						label = "Scale Adjust",
						speed = 0.01,
						range = {0.01, 10},
						initialValue = 1.0
					},
				{
					widgetType = "end_rect",
					additionalSize = 12,
					rounding = 5
				},
				{
					widgetType = "unindent",
					width = 12
				},
			{
				widgetType = "tree_pop"
			},
			{
				widgetType = "tree_node",
				id = "uevr_dev_material_viewer",
				label = "Material Viewer"
			},
				{
					widgetType = "input_text",
					id = "uevr_dev_material_filter",
					label = "Filter",
					initialValue = ""
				},
				{
					widgetType = "same_line",
				},
				{
					widgetType = "button",
					id = "uevr_dev_material_refresh_button",
					label = "Refresh",
					size = {80,22}
				},
				{
					widgetType = "button",
					id = "uevr_dev_material_prev",
					label = "<",
					size = {40,22}
				},
				{
					widgetType = "same_line",
				},
				{
					widgetType = "combo",
					id = "uevr_dev_material_list",
					label = "",
					selections = {"None"},
					initialValue = 1
				},
				{
					widgetType = "same_line",
				},
				{
					widgetType = "button",
					id = "uevr_dev_material_next",
					label = ">",
					size = {40,22}
				},
				{
					widgetType = "begin_group"
				},
					{
						widgetType = "text",
						id = "uevr_dev_material_total_count",
						label = "Total materials"
					},
					{
						widgetType = "text",
						id = "uevr_dev_material_filtered_count",
						label = "Filtered materials"
					},
				{
					widgetType = "end_group"
				},
			{
				widgetType = "tree_pop"
			},
			{
				widgetType = "tree_node",
				id = "uevr_dev_widget_viewer",
				label = "Widget Viewer"
			},
				{
					widgetType = "input_text",
					id = "uevr_dev_widget_filter",
					label = "Filter",
					initialValue = ""
				},
				{
					widgetType = "same_line",
				},
				{
					widgetType = "button",
					id = "uevr_dev_widget_refresh_button",
					label = "Refresh",
					size = {80,22}
				},
				{
					widgetType = "button",
					id = "uevr_dev_widget_prev",
					label = "<",
					size = {40,22}
				},
				{
					widgetType = "same_line",
				},
				{
					widgetType = "combo",
					id = "uevr_dev_widget_list",
					label = "",
					selections = {"None"},
					initialValue = 1
				},
				{
					widgetType = "same_line",
				},
				{
					widgetType = "button",
					id = "uevr_dev_widget_next",
					label = ">",
					size = {40,22}
				},
				{
					widgetType = "begin_group"
				},
					{
						widgetType = "text",
						id = "uevr_dev_widget_total_count",
						label = "Total widgets"
					},
					{
						widgetType = "text",
						id = "uevr_dev_widget_filtered_count",
						label = "Filtered widgets"
					},
				{
					widgetType = "end_group"
				},
				{
					widgetType = "checkbox",
					id = "uevr_dev_widget_user_only",
					label = "Show UserWidgets only",
					initialValue = true
				},
				{
					widgetType = "text_colored",
					id = "uevr_dev_widget_error",
					color = "#FF0000FF",
					isHidden = true,
					label = "Selected item not found. Press Refresh and try again."
				},
				{
					widgetType = "checkbox",
					id = "uevr_dev_widget_loop_toggle",
					label = "Toggle all widgets on/off",
					initialValue = false
				},

			{
				widgetType = "tree_pop"
			},
			{
				widgetType = "tree_node",
				id = "uevr_dev_reticule_viewer",
				label = "Reticule Viewer"
			},
				{
					widgetType = "input_text",
					id = "uevr_dev_reticule_filter",
					label = "Find",
					initialValue = ""
				},
				{
					widgetType = "same_line",
				},
				{
					widgetType = "button",
					id = "uevr_dev_reticule_refresh_button",
					label = "Refresh",
					size = {80,22}
				},
				{
					widgetType = "button",
					id = "uevr_dev_reticule_prev",
					label = "<",
					size = {40,22}
				},
				{
					widgetType = "same_line",
				},
				{
					widgetType = "combo",
					id = "uevr_dev_reticule_list",
					label = "",
					selections = {"None"},
					initialValue = 1
				},
				{
					widgetType = "same_line",
				},
				{
					widgetType = "button",
					id = "uevr_dev_reticule_next",
					label = ">",
					size = {40,22}
				},
				{
					widgetType = "begin_group"
				},
					{
						widgetType = "text",
						id = "uevr_dev_reticule_total_count",
						label = "Reticules found"
					},
				{
					widgetType = "end_group"
				},
				{
					widgetType = "checkbox",
					id = "uevr_dev_reticule_active",
					label = "Show only active",
					initialValue = true
				},
				{
					widgetType = "text_colored",
					id = "uevr_dev_reticule_error",
					color = "#FF0000FF",
					isHidden = true,
					label = "Selected item not found. Press Refresh and try again."
				},
				-- {
					-- widgetType = "new_line"
				-- },
				{
					widgetType = "button",
					id = "uevr_dev_reticule_use_button",
					label = "Use as reticule",
					size = {130,22}
				},

			{
				widgetType = "tree_pop"
			},
			{
				widgetType = "tree_node",
				id = "uevr_dev_particle_viewer",
				label = "Particle Viewer"
			},
				{
					widgetType = "combo",
					id = "uevr_dev_particle_type",
					label = "Particle Type",
					selections = {"NiagaraSystem","ParticleSystem"},
					initialValue = 1
				},
				{
					widgetType = "input_text",
					id = "uevr_dev_particle_filter",
					label = "Filter",
					initialValue = ""
				},
				{
					widgetType = "same_line",
				},
				{
					widgetType = "button",
					id = "uevr_dev_particle_refresh_button",
					label = "Refresh",
					size = {80,22}
				},
				{
					widgetType = "button",
					id = "uevr_dev_particle_prev",
					label = "<",
					size = {40,22}
				},
				{
					widgetType = "same_line",
				},
				{
					widgetType = "combo",
					id = "uevr_dev_particle_list",
					label = "",
					selections = {"None"},
					initialValue = 1
				},
				{
					widgetType = "same_line",
				},
				{
					widgetType = "button",
					id = "uevr_dev_particle_next",
					label = ">",
					size = {40,22}
				},
				{
					widgetType = "input_text",
					id = "uevr_dev_particle_selected_name",
					label = "Current Selection",
					initialValue = ""
				},
				{
					widgetType = "begin_group"
				},
					{
						widgetType = "text",
						id = "uevr_dev_particle_total_count",
						label = "Total particle systems"
					},
					{
						widgetType = "text",
						id = "uevr_dev_particle_filtered_count",
						label = "Filtered particle systems"
					},
				{
					widgetType = "end_group"
				},
				{
					widgetType = "drag_float",
					id = "uevr_dev_particle_scale",
					label = "Scale",
					speed = 0.001,
					range = {0.001, 10},
					initialValue = 0.04
				},
				{
					widgetType = "checkbox",
					id = "uevr_dev_particle_loop",
					label = "Looping",
					initialValue = true
				},
				{
					widgetType = "begin_group",
					id = "uevr_dev_particle_loop_settings",
					isHidden = false
				},
					{
						widgetType = "indent",
						width = 20
					},
					{
						widgetType = "drag_float",
						id = "uevr_dev_particle_loop_start",
						label = "Start (s)",
						speed = 0.05,
						range = {0, 30},
						initialValue = 1.0,
						width = 100
					},
					{
						widgetType = "same_line",
					},
					{
						widgetType = "space_horizontal",
						space = 30
					},
					{
						widgetType = "drag_float",
						id = "uevr_dev_particle_loop_end",
						label = "Loop End (s)",
						speed = 0.05,
						range = {0.05, 60},
						initialValue = 3.0,
						width = 100
					},
					{
						widgetType = "unindent",
						width = 20
					},
				{
					widgetType = "end_group"
				},
				{
					widgetType = "combo",
					id = "uevr_dev_particle_emitter_list",
					label = "Emitter",
					selections = {"None"},
					initialValue = 1
				},
				{
					widgetType = "same_line",
				},
				{
					widgetType = "checkbox",
					id = "uevr_dev_particle_emitter_enabled",
					label = "Enabled",
					initialValue = true
				},
				{
					widgetType = "button",
					id = "uevr_dev_particle_replay",
					label = "Replay",
					size = {80,22}
				},
				{
					widgetType = "same_line",
				},
				{
					widgetType = "button",
					id = "uevr_dev_particle_stop",
					label = "Stop",
					size = {80,22}
				},
				{
					widgetType = "text_colored",
					id = "uevr_dev_particle_error",
					color = "#FF0000FF",
					isHidden = true,
					label = "Selected particle system could not be spawned. Press Refresh and try again."
				},
			{
				widgetType = "tree_pop"
			},
		}
	}
}

function M.init()
	configui.create(configDefinition)
	M.displayStaticMeshes(configui.getValue("uevr_dev_mesh_filter"))
	M.displayMaterials(configui.getValue("uevr_dev_material_filter"))
	M.displayWidgets(configui.getValue("uevr_dev_widget_filter"))
	M.displayReticules(configui.getValue("uevr_dev_reticule_filter"))
	M.displayParticles(configui.getValue("uevr_dev_particle_filter"))
	configui.hideWidget("uevr_dev_particle_loop_settings", configui.getValue("uevr_dev_particle_loop") == false)
	configui.hideWidget("uevr_dev_mesh_relativescale", configui.getValue("uevr_dev_mesh_nativescale"))
end


local function setCurrentComponentScale(relativeScale)
	if configui.getValue("uevr_dev_mesh_nativescale") == false then
		local radius = 10
		if configui.getValue("uevr_dev_mesh_type") == 1 then
			print("1",currentComponent)
			print("2",currentComponent.StaticMesh)
			print("3",currentComponent.StaticMesh.ExtendedBounds)
			if uevrLib.extremeCompatibilityMode == false then
				radius = currentComponent.StaticMesh.ExtendedBounds.SphereRadius
			else
				local result = plugin.getProperty(currentComponent.StaticMesh.ExtendedBounds, "SphereRadius")
				radius = result and result.ReturnValue or 10
				print("Radius: " , radius)
			end
		elseif configui.getValue("uevr_dev_mesh_type") == 2 and currentComponent.SkeletalMesh ~= nil then
			radius = currentComponent.SkeletalMesh.ExtendedBounds.SphereRadius
		end

		local scale = 10 / radius
		local scaleMultiplier = relativeScale
		uevrUtils.set_component_relative_scale(currentComponent, {X=scale * scaleMultiplier, Y=scale * scaleMultiplier, Z=scale * scaleMultiplier})
		-- currentComponent.RelativeScale3D.X = scale * scaleMultiplier
		-- currentComponent.RelativeScale3D.Y = scale * scaleMultiplier
		-- currentComponent.RelativeScale3D.Z = scale * scaleMultiplier
	end
end

local function updateMesh()
	if currentComponent ~= nil then
		uevrUtils.detachAndDestroyComponent(currentComponent, false)
		currentComponent = nil
	end

	if configui.getValue("uevr_dev_mesh_type") == 1 then
		currentComponent = uevrUtils.createStaticMeshComponent(meshNames[currentSelectionIndex])
	elseif configui.getValue("uevr_dev_mesh_type") == 2 then
		currentComponent = uevrUtils.createSkeletalMeshComponent(meshNames[currentSelectionIndex])
		--currentComponent = uevrUtils.createPoseableMeshFromSkeletalMesh(meshNames[currentSelectionIndex], {parent=nil, useDefaultPose = true, showDebug = true})
	end

	if uevrUtils.getValid(currentComponent) ~= nil then
		M.print("Created component " .. currentComponent:get_full_name(), LogLevel.Critical)
		setCurrentComponentScale(configui.getValue("uevr_dev_mesh_relativescale"))
		local leftConnected = controllers.attachComponentToController(Handed.Left, currentComponent, nil, nil, nil, true)
	end
end

local function updateMaterial()
	if currentComponent ~= nil then
		uevrUtils.detachAndDestroyComponent(currentComponent, false)
		currentComponent = nil
	end

	currentComponent = uevrUtils.createStaticMeshComponent("StaticMesh /Engine/EngineMeshes/Sphere.Sphere")
	if uevrUtils.getValid(currentComponent) ~= nil then
		setCurrentComponentScale(1.0)
		local leftConnected = controllers.attachComponentToController(Handed.Left, currentComponent, nil, nil, nil, true)
		local material = uevrUtils.getSafeInstanceOf("Class /Script/Engine.Material", materialNames[currentMaterialSelectionIndex])
		if uevrUtils.getValid(material) ~= nil then
---@diagnostic disable-next-line: need-check-nil
			currentComponent:SetMaterial(0, material)
---@diagnostic disable-next-line: need-check-nil
			M.print("Applied material " .. material:get_full_name(), LogLevel.Critical)
		end
	end
end

local function updateWidget()
	if currentComponent ~= nil then
		uevrUtils.detachAndDestroyComponent(currentComponent, false)
		currentComponent = nil
	end

	if widgetNames ~= nil and currentWidgetSelectionIndex <= #widgetNames and currentWidgetSelectionIndex > 0 then
		local className = "Class /Script/UMG.Widget"
		if configui.getValue("uevr_dev_widget_user_only") == true then className = "Class /Script/UMG.UserWidget" end
		local widget = uevrUtils.getSafeInstanceOf(className, widgetNames[currentWidgetSelectionIndex])
		if widget == nil then
			configui.hideWidget("uevr_dev_widget_error" ,false)
		else
			currentComponent = uevrUtils.createWidgetComponent(widget, {removeFromViewport=false, twoSided=true, drawSize=vector_2(620, 620)})
			if uevrUtils.getValid(currentComponent) ~= nil then
				--setCurrentComponentScale(1.0)
				uevrUtils.set_component_relative_transform(currentComponent, {X=0.0, Y=0.0, Z=0.0}, {Pitch=0,Yaw=0 ,Roll=0}, {X=-0.1, Y=-0.1, Z=0.1})
				local leftConnected = controllers.attachComponentToController(Handed.Left, currentComponent, nil, nil, nil, true)
			end
		end
	else
		M.print("Failed to update reticule at index " .. currentWidgetSelectionIndex)
		print(widgetNames, #widgetNames)
	end
end

local function updateReticule()
	if currentComponent ~= nil then
		uevrUtils.detachAndDestroyComponent(currentComponent, false)
		currentComponent = nil
	end

	if reticuleNames ~= nil and currentReticuleSelectionIndex <= #reticuleNames and currentReticuleSelectionIndex > 0 then
		local widget = uevrUtils.getSafeInstanceOf("Class /Script/UMG.Widget", reticuleNames[currentReticuleSelectionIndex])
		if widget == nil then
			configui.hideWidget("uevr_dev_reticule_error" ,false)
		else
			-- print("Widget is",widget)
			-- print(reticuleNames[currentReticuleSelectionIndex])
			-- print(widget:get_full_name())
			-- print("Has function", widget.HandleShowTargetReticule ~= nil)

			currentComponent = uevrUtils.createWidgetComponent(widget, {removeFromViewport=false, twoSided=true})--, drawSize=vector_2(620, 620)})
			if uevrUtils.getValid(currentComponent) ~= nil then
				--setCurrentComponentScale(1.0)
				uevrUtils.set_component_relative_transform(currentComponent, {X=0.0, Y=0.0, Z=0.0}, {Pitch=0,Yaw=0 ,Roll=0}, {X=-0.1, Y=-0.1, Z=0.1})
				local leftConnected = controllers.attachComponentToController(Handed.Left, currentComponent, nil, nil, nil, true)
				M.print("Added reticule to controller " .. (leftConnected and "true" or "false"))
			end
		end
	else
		M.print("Failed to update reticule at index " .. currentReticuleSelectionIndex)
		print(reticuleNames, #reticuleNames)
	end

end

local function stopParticle()
	-- particles.lua already destroys all instances before a level change
	if currentParticle ~= nil and currentParticle:isValid() then
		currentParticle:destroy()
	end
	if currentParticle ~= nil then
		currentParticle = nil
	end
end

local function isParticleEmitterEnabled(name)
	if name == nil then return true end
	if particleEmitterOverrides[name] ~= nil then return particleEmitterOverrides[name] end
	if particleEmitterDefaults[name] ~= nil then return particleEmitterDefaults[name] end
	return true
end

-- Lists the asset's emitters; overrides reset when a different asset is selected
local function refreshParticleEmitters(assetName)
	if assetName ~= particleEmitterAsset then
		particleEmitterAsset = assetName
		particleEmitterOverrides = {}
	end
	local names, defaults = particles.listEmittersFromAsset(assetName)
	particleEmitterNames = names or {}
	particleEmitterDefaults = defaults or {}
	if #particleEmitterNames < 1 then
		configui.setSelections("uevr_dev_particle_emitter_list", {"None"})
		configui.setValue("uevr_dev_particle_emitter_list", 1, true)
		configui.setValue("uevr_dev_particle_emitter_enabled", true, true)
		return
	end
	configui.setSelections("uevr_dev_particle_emitter_list", particleEmitterNames)
	local index = configui.getValue("uevr_dev_particle_emitter_list") or 1
	if index < 1 or index > #particleEmitterNames then index = 1 end
	configui.setValue("uevr_dev_particle_emitter_list", index, true)
	configui.setValue("uevr_dev_particle_emitter_enabled", isParticleEmitterEnabled(particleEmitterNames[index]), true)
end

local function printParticleEmitterOverrides()
	local entries = {}
	for _, name in ipairs(particleEmitterNames) do
		local enabled = isParticleEmitterEnabled(name)
		local default = particleEmitterDefaults[name] ~= false
		if enabled ~= default then
			local key = string.match(name, "^[%a_][%w_]*$") and name or ("[\"" .. name .. "\"]")
			table.insert(entries, key .. " = " .. tostring(enabled))
		end
	end
	print("\n--lua option for particles.new\nemitterOverrides = {" .. table.concat(entries, ", ") .. "},\n")
end

local function updateParticle()
	if currentComponent ~= nil then
		uevrUtils.detachAndDestroyComponent(currentComponent, false)
		currentComponent = nil
	end
	stopParticle()
	configui.hideWidget("uevr_dev_particle_error", true)

	local assetName = particleNames[currentParticleSelectionIndex]
	if assetName == nil then
		M.print("Failed to update particle at index " .. currentParticleSelectionIndex)
		return
	end

	if particles == nil then
		local ok, result = pcall(require, "libs/particles")
		if not ok then
			M.print("Particle viewer requires libs/particles: " .. tostring(result), LogLevel.Error)
			configui.hideWidget("uevr_dev_particle_error", false)
			return
		end
		particles = result
	end

	refreshParticleEmitters(assetName)

	local scale = configui.getValue("uevr_dev_particle_scale") or 0.04
	local options = {particleSystemAsset = assetName, scale = {scale, scale, scale}, autoActivate = true, emitterOverrides = particleEmitterOverrides}
	if configui.getValue("uevr_dev_particle_loop") == true then
		options.loopStart = configui.getValue("uevr_dev_particle_loop_start")
		options.loopEnd = configui.getValue("uevr_dev_particle_loop_end")
	end
	currentParticle = particles.new(options)
	if currentParticle == nil or not currentParticle:isValid() then
		if currentParticle ~= nil then currentParticle:destroy() end
		currentParticle = nil
		configui.hideWidget("uevr_dev_particle_error", false)
		return
	end
	currentParticle:attachTo(controllers.getController(Handed.Left))
	currentParticle:setRelativeLocation({X = 50, Y = 0, Z = 0})
	currentParticle:start()
	M.print("Created particle " .. assetName, LogLevel.Critical)
end

function M.onLevelChange()
	M.print("Level changed")
	M.displayStaticMeshes(configui.getValue("uevr_dev_mesh_filter"))
	M.displayMaterials(configui.getValue("uevr_dev_material_filter"))
	M.displayWidgets(configui.getValue("uevr_dev_widget_filter"))
	M.displayReticules(configui.getValue("uevr_dev_reticule_filter"))
	M.displayParticles(configui.getValue("uevr_dev_particle_filter"))
end

function M.displayStaticMeshes(searchText)
	if searchText == nil then searchText = "" end
	local className = ""
	local typeName = ""
	local meshes = nil
	if configui.getValue("uevr_dev_mesh_type") == 1 then
		meshes = uevrUtils.find_all_instances("Class /Script/Engine.StaticMesh", false)
		typeName = " static"
	elseif configui.getValue("uevr_dev_mesh_type") == 2 then
		meshes = uevrUtils.find_all_instances("Class /Script/Engine.SkeletalMesh", false)
		typeName = " skeletal"
	end
	--print(#meshes, searchText)
	meshNames = {}
	if meshes ~= nil then
		for name, mesh in pairs(meshes) do
			--print(mesh:get_full_name())
			if searchText == nil or searchText == "" or string.find(string.lower(mesh:get_full_name()), string.lower(searchText)) then
				table.insert(meshNames, mesh:get_full_name())
			end
		end
	end
	--print(#meshNames)

	configui.setLabel("uevr_dev_mesh_total_count", "Total" .. typeName .. " meshes:" .. #meshes)
	configui.setLabel("uevr_dev_mesh_filtered_count", "Filtered" .. typeName .. " meshes:" .. #meshNames)
	configui.setSelections("uevr_dev_mesh_list", meshNames)
	local selectedIndex = configui.getValue("uevr_dev_mesh_list")
	configui.setValue("uevr_dev_mesh_selected_name", (selectedIndex and meshNames[selectedIndex]) or "")
end

function M.displayMaterials(searchText)
--	print("Searching for materials  ", searchText)
	if searchText == nil then searchText = "" end
	local materials = uevrUtils.find_all_instances("Class /Script/Engine.Material", false)
	--print(#materials, searchText)
	materialNames = {}

	if materials ~= nil then
		for name, material in pairs(materials) do
			--print(material:get_full_name())
			if searchText == nil or searchText == "" or string.find(string.lower(material:get_full_name()), string.lower(searchText)) then
				table.insert(materialNames, material:get_full_name())
			end
		end
	end
	--print(#materialNames)

	configui.setLabel("uevr_dev_material_total_count", "Total materials:" .. #materials)
	configui.setLabel("uevr_dev_material_filtered_count", "Filtered materials:" .. #materialNames)
	configui.setSelections("uevr_dev_material_list", materialNames)
end

local function toggleWidgets(value)
	local className = "Class /Script/UMG.Widget"
	if configui.getValue("uevr_dev_widget_user_only") == true then className = "Class /Script/UMG.UserWidget" end
	local widgets = uevrUtils.find_all_instances(className, false)
	if widgets ~= nil then
		for name, widget in pairs(widgets) do
			widget:SetVisibility(value and 1 or 0)
		end
	end
end

function M.displayWidgets(searchText)
--	print("Searching for widgets ", searchText)
	if searchText == nil then searchText = "" end
	local className = "Class /Script/UMG.Widget"
	if configui.getValue("uevr_dev_widget_user_only") == true then className = "Class /Script/UMG.UserWidget" end
	local widgets = uevrUtils.find_all_instances(className, false)
--	print("Widget count ", #widgets, searchText)
	widgetNames = {}

	if widgets ~= nil then
		for name, widget in pairs(widgets) do
			--print(widget:get_full_name())
			local widgetName = widget:get_full_name()
			if searchText == nil or searchText == "" or string.find(string.lower(widgetName), string.lower(searchText)) then
				table.insert(widgetNames, widgetName)
			end
		end
	end
--	print(#widgetNames)

	configui.setLabel("uevr_dev_widget_total_count", "Total widgets:" .. #widgets)
	configui.setLabel("uevr_dev_widget_filtered_count", "Filtered widgets:" .. #widgetNames)
	configui.setSelections("uevr_dev_widget_list", widgetNames)
end


function M.displayReticules(searchText)
	print("Searching for widgets ", searchText)
	local widgets = uevrUtils.find_all_instances("Class /Script/UMG.Widget", false)
	reticuleNames = {}
	--local activeWidgets = {}

	if widgets ~= nil then
		for name, widget in pairs(widgets) do
			local widgetName = widget:get_full_name()
			local widgetNameLower = string.lower(widgetName)
			if string.find(widgetNameLower, "cursor") or string.find(widgetNameLower, "reticule") or string.find(widgetNameLower, "reticle") or string.find(widgetNameLower, "crosshair") or (searchText ~= nil and searchText ~= "" and string.find(widgetNameLower, string.lower(searchText))) then
				if configui.getValue("uevr_dev_reticule_active") == true then
					local isActive = false
					if uevrUtils.getValid(pawn) ~= nil and widget.GetOwningPlayerPawn ~= nil then
						isActive = widget:GetOwningPlayerPawn() == pawn
						if isActive then
							--table.insert(activeWidgets, widget)
							table.insert(reticuleNames, widgetName)
						end
					end
					--print(widget:get_full_name(), isActive and "true" or "false")
				else
					table.insert(reticuleNames, widgetName)
				end
			end
		end
	end

	configui.setLabel("uevr_dev_reticule_total_count", "Reticule count:" .. #reticuleNames)
	configui.setSelections("uevr_dev_reticule_list", reticuleNames)
end

function M.displayParticles(searchText)
	if searchText == nil then searchText = "" end
	local systems = nil
	local typeName = ""
	if configui.getValue("uevr_dev_particle_type") == 1 then
		systems = uevrUtils.find_all_instances("Class /Script/Niagara.NiagaraSystem", false)
		typeName = " niagara"
	else
		systems = uevrUtils.find_all_instances("Class /Script/Engine.ParticleSystem", false)
		typeName = " cascade"
	end
	particleNames = {}
	local totalCount = 0
	if systems ~= nil then
		for name, system in pairs(systems) do
			totalCount = totalCount + 1
			local systemName = system:get_full_name()
			if searchText == "" or string.find(string.lower(systemName), string.lower(searchText), 1, true) then
				table.insert(particleNames, systemName)
			end
		end
	end

	configui.setLabel("uevr_dev_particle_total_count", "Total" .. typeName .. " systems:" .. totalCount)
	configui.setLabel("uevr_dev_particle_filtered_count", "Filtered" .. typeName .. " systems:" .. #particleNames)
	configui.setSelections("uevr_dev_particle_list", particleNames)
	local selectedIndex = configui.getValue("uevr_dev_particle_list")
	configui.setValue("uevr_dev_particle_selected_name", (selectedIndex and particleNames[selectedIndex]) or "")
end

function M.useCurrentReticule()
	if #reticuleNames > 0 and currentReticuleSelectionIndex > 0 and currentReticuleSelectionIndex <= #reticuleNames then
		local widget = uevrUtils.getSafeInstanceOf("Class /Script/UMG.Widget", reticuleNames[currentReticuleSelectionIndex])
		if uevrUtils.getValid(widget) ~= nil then
---@diagnostic disable-next-line: need-check-nil
			local widgetClassName = widget:get_class():get_full_name()
			--print(widgetClassName)
			--local widget = uevrUtils.getActiveWidgetByClass(widgetClassName)

			reticule.createFromWidget(widget, {removeFromViewport=false, twoSided=true, scale={X=-0.1, Y=-0.1, Z=0.1}})
			local str = "--lua code to create reticule\n"
			--str = str .. "local reticule = require(\"libs/reticule\")" .. "\n"
			--str = str .. "local widget = uevrUtils.getActiveWidgetByClass(\""..widgetClassName.."\")" .. "\n"
			--str = str .. "if uevrUtils.getValid(widget) ~= nil then" .. "\n"
			str = str .. "reticule.createFromWidget(\""..widgetClassName.."\", {removeFromViewport=false, twoSided=true, scale={X=-0.1, Y=-0.1, Z=0.1}})" .. "\n"
			--str = str .. "end" .. "\n"
			print("\n" .. str .. "\n")
		end
	end
end

configui.onUpdate("uevr_dev_mesh_filter", function(value)
	M.displayStaticMeshes(value)
end)

configui.onUpdate("uevr_dev_mesh_nativescale", function(value)
	updateMesh()
	configui.hideWidget("uevr_dev_mesh_relativescale", value)
end)

configui.onUpdate("uevr_dev_mesh_relativescale", function(value)
	setCurrentComponentScale(configui.getValue("uevr_dev_mesh_relativescale"))
end)

configui.onUpdate("uevr_dev_widget_loop_toggle", function(value)
	toggleWidgets(value)
end)


configui.onUpdate("uevr_dev_mesh_refresh_button", function(value)
	M.displayStaticMeshes(configui.getValue("uevr_dev_mesh_filter"))
end)

configui.onUpdate("uevr_dev_mesh_type", function(value)
	M.displayStaticMeshes(configui.getValue("uevr_dev_mesh_filter"))
end)

configui.onUpdate("uevr_dev_mesh_prev", function(value)
	currentSelectionIndex = currentSelectionIndex - 1
	if currentSelectionIndex < 1 then currentSelectionIndex = 1 end
	if currentSelectionIndex <= #meshNames then
		configui.setValue("uevr_dev_mesh_list", currentSelectionIndex)
	end
end)

configui.onUpdate("uevr_dev_mesh_next", function(value)
	currentSelectionIndex = currentSelectionIndex + 1
	if currentSelectionIndex > #meshNames then currentSelectionIndex = #meshNames end
	if currentSelectionIndex <= #meshNames then
		configui.setValue("uevr_dev_mesh_list", currentSelectionIndex)
	end
end)

configui.onUpdate("uevr_dev_mesh_list", function(value)
	M.print("Using mesh at index " .. value .. " - " .. meshNames[value], LogLevel.Critical)
	currentSelectionIndex = value
	configui.setValue("uevr_dev_mesh_selected_name", meshNames[value] or "")
	updateMesh()
end)



configui.onUpdate("uevr_dev_material_filter", function(value)
	M.displayMaterials(value)
end)

configui.onUpdate("uevr_dev_material_refresh_button", function(value)
	M.displayMaterials(configui.getValue("uevr_dev_material_filter"))
end)

configui.onUpdate("uevr_dev_material_prev", function(value)
	currentMaterialSelectionIndex = currentMaterialSelectionIndex - 1
	if currentMaterialSelectionIndex < 1 then currentMaterialSelectionIndex = 1 end
	if currentMaterialSelectionIndex <= #materialNames then
		configui.setValue("uevr_dev_material_list", currentMaterialSelectionIndex)
	end
end)

configui.onUpdate("uevr_dev_material_next", function(value)
	currentMaterialSelectionIndex = currentMaterialSelectionIndex + 1
	if currentMaterialSelectionIndex > #materialNames then currentMaterialSelectionIndex = #materialNames end
	if currentMaterialSelectionIndex <= #materialNames then
		configui.setValue("uevr_dev_material_list", currentMaterialSelectionIndex)
	end
end)

configui.onUpdate("uevr_dev_material_list", function(value)
	M.print("Using material at index " .. value .. " - " .. materialNames[value], LogLevel.Critical)
	currentMaterialSelectionIndex = value
	updateMaterial()
end)


configui.onUpdate("uevr_dev_widget_filter", function(value)
	M.displayWidgets(value)
end)

configui.onUpdate("uevr_dev_widget_user_only", function(value)
	M.displayWidgets(configui.getValue("uevr_dev_widget_filter"))
end)

configui.onUpdate("uevr_dev_widget_refresh_button", function(value)
	M.displayWidgets(configui.getValue("uevr_dev_widget_filter"))
	configui.hideWidget("uevr_dev_widget_error" ,true)
end)

configui.onUpdate("uevr_dev_widget_prev", function(value)
	currentWidgetSelectionIndex = currentWidgetSelectionIndex - 1
	if currentWidgetSelectionIndex < 1 then currentWidgetSelectionIndex = 1 end
	if currentWidgetSelectionIndex <= #widgetNames then
		configui.setValue("uevr_dev_widget_list", currentWidgetSelectionIndex)
	end
end)

configui.onUpdate("uevr_dev_widget_next", function(value)
	currentWidgetSelectionIndex = currentWidgetSelectionIndex + 1
	if currentWidgetSelectionIndex > #widgetNames then currentWidgetSelectionIndex = #widgetNames end
	if currentWidgetSelectionIndex <= #widgetNames then
		configui.setValue("uevr_dev_widget_list", currentWidgetSelectionIndex)
	end
end)

configui.onUpdate("uevr_dev_widget_list", function(value)
	M.print("Using widget at index " .. value .. " - " .. widgetNames[value], LogLevel.Critical)
	currentWidgetSelectionIndex = value
	updateWidget()
end)


configui.onUpdate("uevr_dev_reticule_filter", function(value)
	M.displayReticules(value)
end)

configui.onUpdate("uevr_dev_reticule_refresh_button", function(value)
	M.displayReticules(configui.getValue("uevr_dev_reticule_filter"))
	configui.hideWidget("uevr_dev_reticule_error" ,true)
end)

configui.onUpdate("uevr_dev_reticule_prev", function(value)
	currentReticuleSelectionIndex = currentReticuleSelectionIndex - 1
	if currentReticuleSelectionIndex < 1 then currentReticuleSelectionIndex = 1 end
	if currentReticuleSelectionIndex <= #reticuleNames then
		configui.setValue("uevr_dev_reticule_list", currentReticuleSelectionIndex)
	end
end)

configui.onUpdate("uevr_dev_reticule_next", function(value)
	currentReticuleSelectionIndex = currentReticuleSelectionIndex + 1
	if currentReticuleSelectionIndex > #reticuleNames then currentReticuleSelectionIndex = #reticuleNames end
	if currentReticuleSelectionIndex <= #reticuleNames then
		configui.setValue("uevr_dev_reticule_list", currentReticuleSelectionIndex)
	end
end)

configui.onUpdate("uevr_dev_reticule_list", function(value)
	if value ~= nil and reticuleNames ~= nil and reticuleNames[value] ~= nil then
		M.print("Using reticule at index " .. value .. " - " .. reticuleNames[value], LogLevel.Critical)
	end
	currentReticuleSelectionIndex = value
	updateReticule()
end)

configui.onUpdate("uevr_dev_reticule_use_button", function(value)
	M.useCurrentReticule()
end)

configui.onUpdate("uevr_dev_reticule_active", function(value)
	M.displayReticules(configui.getValue("uevr_dev_reticule_filter"))
	configui.hideWidget("uevr_dev_reticule_error" ,true)
end)


configui.onUpdate("uevr_dev_particle_filter", function(value)
	M.displayParticles(value)
end)

configui.onUpdate("uevr_dev_particle_type", function(value)
	M.displayParticles(configui.getValue("uevr_dev_particle_filter"))
end)

configui.onUpdate("uevr_dev_particle_refresh_button", function(value)
	M.displayParticles(configui.getValue("uevr_dev_particle_filter"))
	configui.hideWidget("uevr_dev_particle_error" ,true)
end)

configui.onUpdate("uevr_dev_particle_prev", function(value)
	currentParticleSelectionIndex = currentParticleSelectionIndex - 1
	if currentParticleSelectionIndex < 1 then currentParticleSelectionIndex = 1 end
	if currentParticleSelectionIndex <= #particleNames then
		configui.setValue("uevr_dev_particle_list", currentParticleSelectionIndex)
	end
end)

configui.onUpdate("uevr_dev_particle_next", function(value)
	currentParticleSelectionIndex = currentParticleSelectionIndex + 1
	if currentParticleSelectionIndex > #particleNames then currentParticleSelectionIndex = #particleNames end
	if currentParticleSelectionIndex > 0 and currentParticleSelectionIndex <= #particleNames then
		configui.setValue("uevr_dev_particle_list", currentParticleSelectionIndex)
	end
end)

configui.onUpdate("uevr_dev_particle_list", function(value)
	if value ~= nil and particleNames[value] ~= nil then
		M.print("Using particle at index " .. value .. " - " .. particleNames[value], LogLevel.Critical)
	end
	currentParticleSelectionIndex = value
	configui.setValue("uevr_dev_particle_selected_name", particleNames[value] or "")
	updateParticle()
end)

configui.onUpdate("uevr_dev_particle_scale", function(value)
	if currentParticle ~= nil then
		currentParticle:setScale({value, value, value})
	end
end)

configui.onUpdate("uevr_dev_particle_loop", function(value)
	configui.hideWidget("uevr_dev_particle_loop_settings", value == false)
	if currentParticle ~= nil then
		updateParticle()
	end
end)

local function updateParticleLoopRange()
	if currentParticle ~= nil and currentParticle.looping then
		currentParticle:setLoopRange(configui.getValue("uevr_dev_particle_loop_start"), configui.getValue("uevr_dev_particle_loop_end"))
	end
end

configui.onUpdate("uevr_dev_particle_loop_start", function(value)
	updateParticleLoopRange()
end)

configui.onUpdate("uevr_dev_particle_loop_end", function(value)
	updateParticleLoopRange()
end)

configui.onUpdate("uevr_dev_particle_emitter_list", function(value)
	configui.setValue("uevr_dev_particle_emitter_enabled", isParticleEmitterEnabled(particleEmitterNames[value]), true)
end)

configui.onUpdate("uevr_dev_particle_emitter_enabled", function(value)
	local name = particleEmitterNames[configui.getValue("uevr_dev_particle_emitter_list")]
	if name == nil then return end
	particleEmitterOverrides[name] = value == true
	if currentParticle ~= nil then
		currentParticle:setEmitterEnabled(name, value == true)
	end
	printParticleEmitterOverrides()
end)

configui.onUpdate("uevr_dev_particle_replay", function(value)
	updateParticle()
end)

configui.onUpdate("uevr_dev_particle_stop", function(value)
	stopParticle()
end)


return M