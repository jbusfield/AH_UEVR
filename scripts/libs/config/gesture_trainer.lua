local uevrUtils = require('libs/uevr_utils')
local controllers = require('libs/controllers')
local paramModule = require("libs/core/params")
local configui = require("libs/configui")

local M = {}

local status = {}

local configFileName = "dev/gesture_trainer_config"
local configTabLabel = "Gesture Trainer Config"

local parametersFileName = "dev/gesture_trainer_parameters"
local parameters = {}
local paramManager = paramModule.new(parametersFileName, parameters, true)
local widgetPrefix = "uevr_gesture_trainer_"

paramManager:load(false)

local gestureList = configui.createNamedItemList({
	prefix = widgetPrefix .. "gesture_",
	paramManager = paramManager,
	paramPath = "gestures",
	comboLabel = "Gesture",
	groupLabel = "Settings",
	nameLabel = "Name",
	defaultLabel = "New Gesture",
--	width = 250,
	fields = {
		training = widgetPrefix .. "training_checkbox",
	},
})

local function getConfigWidgets(m_paramManager)
	return spliceableInlineArray {
        {
            widgetType = "tree_node",
            id = widgetPrefix .. "calibration_tree",
            initialOpen = true,
            label = "Calibration"
        },
            {
                widgetType = "text",
                id = widgetPrefix .. "calibration_instructions",
                label = "Press the calibrate button and then wave your controller around for a few seconds until calibration is complete",
                isHidden = false,
                wrapped = true
            },
            { widgetType = "new_line" },
            {
                widgetType = "text",
                id = widgetPrefix .. "calibration_mesh_name",
                label = "Mesh: ",
            },
            {
                widgetType = "text",
                id = widgetPrefix .. "calibration_socket_name",
                label = "Socket: ",
            },
            {
                widgetType = "button",
                id = widgetPrefix .. "calibration_button",
                label = "Calibrate",
                size = {100, 22},
            },
            { widgetType = "same_line" },
            {
                widgetType = "text_colored",
                id = widgetPrefix .. "calibration_status",
                label = "",
                color = "#00FF00FF",
                isHidden = false
            },
        {
            widgetType = "tree_pop"
        },
        { widgetType = "new_line" },
        {
            widgetType = "tree_node",
            id = widgetPrefix .. "training_tree",
            initialOpen = true,
            label = "Training"
        },
            expandArray(gestureList.getHeaderWidgets),
            -- custom per-gesture widgets go here
            { widgetType = "indent", width =80 },
            {
                widgetType = "text_colored",
                id = widgetPrefix .. "training_status",
                label = "            Training is Active",
                color = "#00FF00FF",
                isHidden = true
            },
            { widgetType = "button",
                id = widgetPrefix .. "start_training_button",
                label = "Start Training",
                size = {200, 22},
            },
            { widgetType = "button",
                id = widgetPrefix .. "stop_training_button",
                label = "Stop Training",
                size = {200, 22},
                isHidden = true,
            },
            { widgetType = "unindent", width = 80 },
            -- {
            --     widgetType = "checkbox",
            --     id = widgetPrefix .. "training_checkbox",
            --     label = "Training",
            --     initialValue = false,
            --     isHidden = false
            -- },
            { widgetType = "new_line" },
            expandArray(gestureList.getFooterWidgets),
        {
            widgetType = "tree_pop"
        },
     }
end

local function getMesh()
    if status.getMeshCallback ~= nil then
        return status.getMeshCallback()
    end
    return nil, nil
end

local function isCalibrated()
    --print("isCalibrated: " .. tostring(paramManager:get("calibration") ~= nil))
    return paramManager:get("calibration") ~= nil
end

local function updateCalibrationStatus()
    if isCalibrated() then
        configui.setLabel(widgetPrefix .. "calibration_status", "Calibrated")
        configui.setColor(widgetPrefix .. "calibration_status", "#00FF00FF")
    else
        configui.setLabel(widgetPrefix .. "calibration_status", "")
    end
end

local function updateTrainingStatusUI(enabled)
    configui.setHidden(widgetPrefix .. "training_status", not enabled)
    --get the currently selected traing item label
    --print("trainingItem: ",status.trainingItem)
    configui.setHidden(widgetPrefix .. "start_training_button", enabled)
    configui.setHidden(widgetPrefix .. "stop_training_button", not enabled)
end

uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)
    if status.trainingEnabled then
        uevrUtils.unpressButton(state, XINPUT_GAMEPAD_A)
    end
end)

function M.trainingEnabled(enabled)
    status.trainingEnabled = enabled
    status.trainingItem = gestureList.getSelectedId()
    updateTrainingStatusUI(enabled)
    local data = {
        enabled = enabled,
        item = status.trainingItem,
    }
    --print(json.dump_string(data))
    uevr.api:dispatch_custom_event("GestureTrain", json.dump_string(data))
end

function M.calibrate(mesh, socketName)
    status.mesh = mesh
    status.socketName = socketName
    status.calibrate = true
    uevr.api:dispatch_custom_event("GestureCalibrateStart", "")
    configui.setLabel(widgetPrefix .. "calibration_status", "Calibrating...")
    configui.setColor(widgetPrefix .. "calibration_status", "#FFFFFFFF")
    delay(2000, function()
        status.calibrate = false
        uevr.api:dispatch_custom_event("GestureCalibrateStop", "")
        updateCalibrationStatus()
    end)
end


uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    if not status.calibrate then
        return
    end
    local data = {}
    local mesh = status.mesh
    if mesh ~= nil then
        if status.socketName ~= nil and mesh.GetSocketLocation ~= nil then
            local socket = uevrUtils.fname_from_string(status.socketName)
            local loc = mesh:GetSocketLocation(socket)
            local rot = mesh:GetSocketRotation(socket)
            if loc ~= nil and rot ~= nil then
                data.offset = {X=loc.X, Y=loc.Y, Z=loc.Z, Pitch=rot.Pitch, Yaw=rot.Yaw, Roll=rot.Roll}
            end
        else
            local loc = uevrUtils.getComponentLocation(mesh)
            local rot = uevrUtils.getComponentRotation(mesh)
            if loc ~= nil and rot ~= nil then
                data.offset = {X=loc.X, Y=loc.Y, Z=loc.Z, Pitch=rot.Pitch, Yaw=rot.Yaw, Roll=rot.Roll}
            end
        end
    end
    local loc = controllers.getControllerLocation(Handed.Right)
    local rot = controllers.getControllerRotation(Handed.Right)
    if loc ~= nil and rot ~= nil then
        data.controller = {X=loc.X, Y=loc.Y, Z=loc.Z, Pitch=rot.Pitch, Yaw=rot.Yaw, Roll=rot.Roll}
    end
    uevr.api:dispatch_custom_event("GestureCalibrate", json.dump_string(data))
end)

uevr.sdk.callbacks.on_lua_event(function(eventName, eventData)
    -- Plugin echoes Start/sample/Stop under the same event name; print Stop result too.
    if eventName ~= nil and string.sub(eventName, 1, 16) == "GestureCalibrate" then
        print(eventName .. " " .. tostring(eventData))
    end
    if eventName == "GestureCalibrateStop" then
        --write data to params file
        paramManager:set("calibration", json.load_string(eventData), true)
    end
    if eventName == "GestureRecognize" then
        print(eventName .. " " .. tostring(eventData))
    end
end)


local function updateMeshName(mesh)
    if mesh ~= nil then
        configui.setLabel(widgetPrefix .. "calibration_mesh_name", "Mesh: " ..uevrUtils.getShortName(mesh))
    end
end
local function updateSocketName(socketName)
    if socketName ~= nil then
        configui.setLabel(widgetPrefix .. "calibration_socket_name", "Socket: " .. socketName)
    end
end
configui.onUpdate(widgetPrefix .. "calibration_button", function()
    local mesh, socketName = getMesh()
	M.calibrate(mesh, socketName)
end)
configui.onCreate(widgetPrefix .. "calibration_mesh_name", function()
	local mesh, socketName = getMesh()
    updateMeshName(mesh)
end)
configui.onCreate(widgetPrefix .. "calibration_socket_name", function()
	local mesh, socketName = getMesh()
    updateSocketName(socketName)
end)
configui.onCreate(widgetPrefix .. "calibration_status", function()
    updateCalibrationStatus()
end)

configui.onUpdate(widgetPrefix .. "start_training_button", function()
    M.trainingEnabled(true)
end)
configui.onUpdate(widgetPrefix .. "stop_training_button", function()
    M.trainingEnabled(false)
end)

function M.getConfigurationWidgets(options)
	return configui.applyOptionsToConfigWidgets(getConfigWidgets(paramManager), options)
end

function M.showConfiguration(saveFileName, options)
	configui.createConfigPanel(configTabLabel, saveFileName, spliceableInlineArray{expandArray(M.getConfigurationWidgets, options)})
end

function M.init(isDeveloperMode, logLevel)
    if isDeveloperMode == nil and uevrUtils.getDeveloperMode() ~= nil then
        isDeveloperMode = uevrUtils.getDeveloperMode()
    end

    if isDeveloperMode then
        M.showConfiguration(configFileName)

        setInterval(2000, function()
            local mesh, socketName = getMesh()
            updateMeshName(mesh)
            updateSocketName(socketName)
            updateCalibrationStatus()
        end)
    end

    paramManager:initProfileHandler(widgetPrefix, function(profileParams)
		gestureList.refresh()
	end)
end

function M.registerGetMeshCallback(callback)
	status.getMeshCallback = callback
end

return M
