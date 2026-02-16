-- Inspired by letmein's work with Stalker-2
local uevrUtils = require("libs/uevr_utils")
local controllers = require("libs/controllers")
local configui = require("libs/configui")
local paramModule = require("libs/core/params")
--local hands = require("libs/hands")

local M = {}

local callerModule = nil
-- Scope class definition
local Accessories = {}
Accessories.__index = Accessories

local parameterDefaults = {
	socket_name = "",
    attach_type = 0,
    location = {0, 0, 0},
    rotation = {0, 0, 0},

}

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[accessories] " .. text, logLevel)
	end
end

local parametersFileName = "accessories_parameters"
local parameters = {}
local paramManager = paramModule.new(parametersFileName, parameters, true)

-- Module-level parameter functions (shared by weapon type ID)
local function saveParameter(attachmentID, accessoryID, key, value, persist)
	paramManager:set({"accessories", attachmentID, accessoryID, key}, value, persist)
end

local function getParameter(attachmentID, accessoryID, key)
	local value = paramManager:get({"accessories", attachmentID, accessoryID, key})
    return value or parameterDefaults[key]
end

-- Constructor for new scope instance
function M.new(attachmentID, options)
	local instance = setmetatable({}, Accessories)

	instance.attachmentID = attachmentID or ""
	-- Auto-create the scope components
	instance:create(options)

	return instance
end

function Accessories:create(options)

end

--[[
accessories = {
    Inventory_W_J_PlasmaRifle_01_FP = {
        432988_db_498 = {
            label = "Scope",
            socket_name = "scope_socket",
            attach_type = "Keep Relative",
            location = {0.0, 0.0, 0.0},
            rotation = {0.0, 0.0, 0.0},
        },
        345243_ad_565 = {
            label = "Laser Sight",
            socket_name = "laser_socket",
            attach_type = "Snap To Target",
            location = {1.0, 0.0, 0.0},
            rotation = {0.0, 90.0, 0.0},
        }
    }
}
]]--

local animationLabels = {"None"}
local animationIDs = {""}

local activePrefixes = {}
local accessoriesMap = {}
function M.getConfigWidgets(id, prefix, width)
    prefix = prefix or ""
    table.insert(activePrefixes, {prefix = prefix, id = id})

    local accessoryIDs = {}
    local accessoryLabels = {}
    local accessories = paramManager:get({"accessories", id})
    if accessories ~= nil then
        for accessoryID, accessoryParams in pairs(accessories) do
            table.insert(accessoryIDs, accessoryID)
            table.insert(accessoryLabels, accessoryParams["label"] or accessoryID)
        end
    end
    --add a "none" option
    if #accessoryIDs == 0 then
        table.insert(accessoryIDs, 1, "none")
        table.insert(accessoryLabels, 1, "None")
    end

    accessoriesMap[id] = {}
    accessoriesMap[id]["ids"] = accessoryIDs
    accessoriesMap[id]["labels"] = accessoryLabels

    if width == nil then width = 350 end
    
    return {
        {
            widgetType = "tree_node",
            id = prefix .. "accessory_tree",
            initialOpen = false,
            label = "Accessories"
        },
            {
                widgetType = "combo",
                id = prefix .. "accessory_picker",
                label = "Accessory",
                selections = accessoryLabels,
                initialValue = 1,
                width = width - 100
            },
            { widgetType = "same_line" },
            {
                widgetType = "button",
                id = prefix .. "accessory_new_button",
                label = "Add",
                size = {40,24},
            },
            { widgetType = "begin_group", id = prefix .. "accessory_group", isHidden = true }, { widgetType = "indent", width = 15 }, { widgetType = "text", label = "Settings" }, { widgetType = "begin_rect", },
            -- {
            --     widgetType = "begin_group",
            --     id = prefix .. "accessory_group",
            --     isHidden = true
            -- },
                {
                    widgetType = "input_text",
                    id = prefix .. "accessory_item_label",
                    label = "Label",
                    initialValue = "",
                    isHidden = false,
                    width = width - 100
                },
                { widgetType = "same_line" },
                { widgetType = "space_horizontal", space = 10 },
                {
                    widgetType = "checkbox",
                    id = prefix .. "accessory_item_test_left_hand",
                    label = "Test Left",
                    initialValue = false
                },
                { widgetType = "same_line" },
                { widgetType = "space_horizontal", space = 10 },
                {
                    widgetType = "checkbox",
                    id = prefix .. "accessory_item_test_right_hand",
                    label = "Test Right",
                    initialValue = false
                },
                {
                    widgetType = "tree_node",
                    id = prefix .. "accessory_item_socket_finder_tool",
                    initialOpen = false,
                    label = "Socket Finder"
                },
                { widgetType = "begin_group", id = prefix .. "accessory_item_socket_finder_group", isHidden = false }, { widgetType = "indent", width = 10 }, { widgetType = "text", label = "" }, { widgetType = "begin_rect", },
					{
						widgetType = "text",
						id = prefix .. "accessory_item_socket_finder_instructions",
						label = "If no sockets are listed, equip the attachment and press refresh",
						wrapped = true,
                        width = width
					},
                    {
                        widgetType = "combo",
                        id = prefix .. "accessory_item_socket_list",
                        label = "Sockets",
                        selections = {"None"},
                        initialValue = 1,
                        width = width - 100
                    },
                    { widgetType = "same_line", },
                    {
                        widgetType = "button",
                        id = prefix .. "accessory_item_socket_finder_search_button",
                        label = "Refresh",
                        size = {80,22}
                    },
        			{ widgetType = "indent", width = 100 },
                    {
                        widgetType = "button",
                        id = prefix .. "accessory_item_socket_finder_use_button",
                        label = "Use Selected",
                        size = {150,22}
                    },
				    { widgetType = "unindent", width = 100 },
                { widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 10 }, { widgetType = "new_line" }, { widgetType = "end_group", },
                {
                    widgetType = "tree_pop"
                },
                {
                    widgetType = "input_text",
                    id = prefix .. "accessory_item_socket_name",
                    label = "Socket Name",
                    initialValue = "",
                    width = width
                },
                {
                    widgetType = "combo",
                    id = prefix .. "accessory_item_attach_type",
                    label = "Attach Type",
                    selections = {"Keep Relative", "Keep World", "Snap To Target"},
                    initialValue = parameterDefaults["attach_type"] + 1,
                    width = width
                },
                {
                    widgetType = "drag_float3",
                    id = prefix .. "accessory_item_location",
                    label = "Position",
                    speed = 0.1,
                    range = {-100, 100},
                    initialValue = parameterDefaults["location"],
                    isHidden = false,
                    width = width
                },
                {
                    widgetType = "drag_float3",
                    id = prefix .. "accessory_item_rotation",
                    label = "Rotation",
                    speed = 0.1,
                    range = {-180, 180},
                    initialValue = parameterDefaults["rotation"],
                    isHidden = false,
                    width = width
                },
                {
                    widgetType = "combo",
                    id = prefix .. "accessory_item_grip_animation",
                    label = "Grip Animation",
                    selections = animationLabels,
                    initialValue = 1,
                    width = width
                },
                {
                    widgetType = "combo",
                    id = prefix .. "accessory_item_activation_hand",
                        label = "Activation Requirement",
                        selections = {"None", "Left Hand Proximity", "Right Hand Proximity", "Either Hand Proximity", "Left Hand Proximity During Montage Only", "Right Hand Proximity During Montage Only", "Either Hand Proximity During Montage Only", "Left Hand Always", "Right Hand Always", "Either Hand Always"},
                    initialValue = 1,
                    width = width
                },
				{
					widgetType = "drag_float",
					id = prefix .. "accessory_item_activation_distance",
					label = "Activation Distance",
					speed = 0.1,
					range = {0, 100},
					initialValue = 0.0,
                    isHidden = true,
                    width = width
				},
                { widgetType = "indent", width = 140 },
                {
                    widgetType = "button",
                    id = prefix .. "delete_accessory_button",
                    label = "Delete",
                    size = {100,22}
                },
                { widgetType = "same_line", },
                {
                    widgetType = "checkbox",
                    id = prefix .. "delete_accessory_override",
                    label = "Allow Delete",
                    initialValue = false,
                    isHidden = true
                },
            { widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 15 }, { widgetType = "new_line" }, { widgetType = "end_group", },
            -- {
            --     widgetType = "end_group",
            -- },
            -- {
            --     widgetType = "tree_pop"
            -- },
        {
            widgetType = "tree_pop"
        },
    }
end

local socketCache = {}
local function refreshSocketList(id, prefix)
    if socketCache[id] ~= nil then
        configui.setSelections(prefix .. "accessory_item_socket_list", socketCache[id])
    else
       --need to get all the sockets for the mesh represented by id
        if callerModule ~= nil then
            print("Requesting sockets for attachment ID: " .. tostring(id))
            callerModule.getSocketsForAttachmentID(id, function(names)
                print(names)
                local socketList = {}
                if names == nil or #names == 0 then
                    M.print("No socket names received", LogLevel.Warning)
                    socketList = {"None"}
                else
                    socketList = names
                    socketCache[id] = socketList
                end
                configui.setSelections(prefix .. "accessory_item_socket_list", socketList)
            end)
        end
    end
end

local function setUIForAccessory(id, prefix, accessoryID)
    --print("Setting UI for accessory ID: " .. tostring(accessoryID))
    configui.setHidden(prefix .. "accessory_group", accessoryID == "none")
    if accessoryID ~= "none" then
        refreshSocketList(id, prefix)

        configui.setValue(prefix .. "accessory_item_label", getParameter(id, accessoryID, "label") or "", true)
        configui.setValue(prefix .. "accessory_item_socket_name", getParameter(id, accessoryID, "socket_name") or "", true)
        configui.setValue(prefix .. "accessory_item_attach_type", (getParameter(id, accessoryID, "attach_type") or 0) + 1, true)
        configui.setValue(prefix .. "accessory_item_location", getParameter(id, accessoryID, "location") or {0.0, 0.0, 0.0}, true)
        configui.setValue(prefix .. "accessory_item_rotation", getParameter(id, accessoryID, "rotation") or {0.0, 0.0, 0.0}, true)
        configui.setValue(prefix .. "accessory_item_activation_hand", getParameter(id, accessoryID, "activation_hand") or 1, true)
        configui.setValue(prefix .. "accessory_item_activation_distance", getParameter(id, accessoryID, "activation_distance") or 0.0, true)
        configui.setHidden(prefix .. "accessory_item_activation_distance", (getParameter(id, accessoryID, "activation_hand") or 1) == 1)
        
        -- Set grip animation combo to the stored value
        local gripAnimationID = getParameter(id, accessoryID, "grip_animation") or ""
        local index = 1  -- Default to "None" (index 1)
        for i, idx in ipairs(animationIDs) do
            if idx == gripAnimationID then
                index = i
                break
            end
        end
        configui.setValue(prefix .. "accessory_item_grip_animation", index, true)
    end
end

local function getAccessoryID(id, prefix)
    local value = configui.getValue(prefix .. "accessory_picker")
    local accessoryID = accessoriesMap[id]["ids"][value]
    if accessoryID == "none" then
        accessoryID = nil
    end
    return accessoryID
end

local function deleteCurrentAccessory(id, prefix)
    local accessoryID = getAccessoryID(id, prefix)
    if accessoryID == nil then
        M.print("No accessory selected to delete.", LogLevel.Warning)
        return false
    end
    paramManager:set({"accessories", id, accessoryID}, nil, true)

    -- Properly remove from arrays
    local ids = accessoriesMap[id]["ids"]
    local labels = accessoriesMap[id]["labels"]
    for i = #ids, 1, -1 do
        if ids[i] == accessoryID then
            table.remove(ids, i)
            table.remove(labels, i)
            break
        end
    end

    -- If no accessories left, add "none" option
    if #ids == 0 then
        table.insert(ids, 1, "none")
        table.insert(labels, 1, "None")
    end

    configui.setSelections(prefix .. "accessory_picker", labels)
    configui.setValue(prefix .. "accessory_picker", 1)  -- Select "None" or first item

    return true
end

local function updateGripAnimationUI()
    -- Update all existing grip animation combos
    for _, param in ipairs(activePrefixes) do
        configui.setSelections(param.prefix .. "accessory_item_grip_animation", animationLabels)
        --get the current stored value and re-set it to update index
        local accessoryID = getAccessoryID(param.id, param.prefix)
        if accessoryID ~= nil then
            local gripAnimationID = getParameter(param.id, accessoryID, "grip_animation") or ""
            local index = -1
            for i, id in ipairs(animationIDs) do
                if id == gripAnimationID then
                    index = i
                    break
                end
            end
            if index ~= -1 then
                configui.setValue(param.prefix .. "accessory_item_grip_animation", index, true)
            end
        end
    end
end

-- Preview functionality
local PREVIEW_PRIORITY = 1000000
local preview = {
    enabled = false,
    handed = Handed.Right,   -- choose which hand to preview
    accessoryID = nil,       -- GUID string
}

-- Register once (module scope). This makes preview “win” by returning a huge priority.
uevrUtils.registerUEVRCallback("active_right_accessory", function()
    if preview.enabled and preview.handed == Handed.Right and preview.accessoryID ~= nil then
        return preview.accessoryID, PREVIEW_PRIORITY
    end
    -- return nil => no opinion
end)

uevrUtils.registerUEVRCallback("active_left_accessory", function()
    if preview.enabled and preview.handed == Handed.Left and preview.accessoryID ~= nil then
        return preview.accessoryID, PREVIEW_PRIORITY
    end
end)

local function pokePreviewChanged()
    -- hands.lua listens for this and re-applies attachments (even if GUID didn’t change)
    uevrUtils.executeUEVRCallbacks("on_accessory_preview_changed", preview.handed, preview.accessoryID, preview.enabled)
end

function M.createConfigCallbacks(id, prefix)
    -- If user tweaks the transform/socket while preview is on, force re-apply:
    local function pokeIfPreviewingThisAccessory()
        if preview.enabled then
            local current = getAccessoryID(id, prefix)
            if current == preview.accessoryID then
                pokePreviewChanged()
            end
        end
    end

    prefix = prefix or ""
    configui.onUpdate(prefix .. "accessory_item_label", function(value)
        local accessoryID = getAccessoryID(id, prefix)
        if accessoryID ~= nil then saveParameter(id, accessoryID, "label", value, true) end

        accessoriesMap[id]["labels"][configui.getValue(prefix .. "accessory_picker")] = value
        configui.setSelections(prefix .. "accessory_picker", accessoriesMap[id]["labels"])
	end)

    configui.onUpdate(prefix .. "accessory_item_socket_name", function(value)
        local accessoryID = getAccessoryID(id, prefix)
        if accessoryID ~= nil then saveParameter(id, accessoryID, "socket_name", value, true) end
        pokeIfPreviewingThisAccessory()
	end)

    configui.onUpdate(prefix .. "accessory_item_attach_type", function(value)
        local accessoryID = getAccessoryID(id, prefix)
        if accessoryID ~= nil then saveParameter(id, accessoryID, "attach_type", value - 1, true) end
        pokeIfPreviewingThisAccessory()
	end)

    configui.onUpdate(prefix .. "accessory_item_location", function(value)
        local accessoryID = getAccessoryID(id, prefix)
        if accessoryID ~= nil then saveParameter(id, accessoryID, "location", {value.X, value.Y, value.Z}, true) end
        pokeIfPreviewingThisAccessory()
    end)

    configui.onUpdate(prefix .. "accessory_item_rotation", function(value)
        local accessoryID = getAccessoryID(id, prefix)
        if accessoryID ~= nil then saveParameter(id, accessoryID, "rotation", {value.Pitch, value.Yaw, value.Roll}, true) end
        pokeIfPreviewingThisAccessory()
    end)

    configui.onUpdate(prefix .. "accessory_item_activation_hand", function(value)
        local accessoryID = getAccessoryID(id, prefix)
        if accessoryID ~= nil then saveParameter(id, accessoryID, "activation_hand", value, true) end
        configui.setHidden(prefix .. "accessory_item_activation_distance", value == 1 or value == 8 or value == 9 or value == 10)
    end)

    configui.onUpdate(prefix .. "accessory_item_activation_distance", function(value)
        local accessoryID = getAccessoryID(id, prefix)
        if accessoryID ~= nil then saveParameter(id, accessoryID, "activation_distance", value, true) end
    end)

    configui.onCreateOrUpdate(prefix .. "accessory_picker", function(value)
		local accessoryID = accessoriesMap[id]["ids"][value]
        M.print("Selected accessory ID: " .. tostring(accessoryID), LogLevel.Debug)
        setUIForAccessory(id, prefix, accessoryID)

        if preview.enabled then
            preview.accessoryID = (accessoryID ~= "none") and accessoryID or nil
            pokePreviewChanged()
        end

	end)

    configui.onUpdate(prefix .. "accessory_new_button", function()
        -- Remove "none" if present, since we're adding a real accessory
        local ids = accessoriesMap[id]["ids"]
        local labels = accessoriesMap[id]["labels"]
        if #ids > 0 and ids[1] == "none" then
            table.remove(ids, 1)
            table.remove(labels, 1)
        end

        local newAccessoryID = uevrUtils.guid()

        -- Guarantee a unique label by checking existing labels and appending a number if needed
        local baseLabel = "New Accessory"
        local label = baseLabel
        local counter = 1
        while true do
            local exists = false
            for _, existingLabel in ipairs(accessoriesMap[id]["labels"]) do
                if existingLabel == label then
                    exists = true
                    break
                end
            end
            if not exists then break end
            counter = counter + 1
            label = baseLabel .. " " .. counter
        end

        local params = {
            label = label,
            socket_name = "",
            attach_type = 0,
            location = {0.0, 0.0, 0.0},
            rotation = {0.0, 0.0, 0.0},
        }
        paramManager:set({"accessories", id, newAccessoryID}, params, true)

        accessoriesMap[id]["ids"][#accessoriesMap[id]["ids"] + 1] = newAccessoryID
        accessoriesMap[id]["labels"][#accessoriesMap[id]["labels"] + 1] = label
        configui.setSelections(prefix .. "accessory_picker", accessoriesMap[id]["labels"])

        --change selection to new accessory
        configui.setValue(prefix .. "accessory_picker", #accessoriesMap[id]["ids"])
        setUIForAccessory(id, prefix, newAccessoryID)

        M.print("Created new accessory with ID: " .. newAccessoryID, LogLevel.Debug)
    end)

    configui.onUpdate(prefix .. "delete_accessory_button", function()
        if configui.getValue(prefix .. "delete_accessory_override") == true then
            if deleteCurrentAccessory(id, prefix) then
                configui.setValue(prefix .. "accessory_picker", 1)
            end
            configui.hideWidget(prefix .. "delete_accessory_override", true)
            configui.setValue(prefix .. "delete_accessory_override", false)
        else
            configui.hideWidget(prefix .. "delete_accessory_override", false)
            configui.setValue(prefix .. "delete_accessory_override", false)
        end
    end)

    configui.onUpdate(prefix .. "accessory_item_socket_finder_search_button", function()
        local accessoryID = getAccessoryID(id, prefix)
        if accessoryID ~= nil then
            refreshSocketList(id, prefix)
        end
    end)

    configui.onUpdate(prefix .. "accessory_item_socket_finder_use_button", function()
        local socketValue = configui.getValue(prefix .. "accessory_item_socket_list")
        local socketName = socketCache[id][socketValue]
        configui.setValue(prefix .. "accessory_item_socket_name", socketName)
        --configui.setHidden(prefix .. "accessory_item_socket_finder_tool", true)
    end)

    configui.onUpdate(prefix .. "accessory_item_grip_animation", function(value)
        local gripAnimationID = animationIDs[value] or ""
        local accessoryID = getAccessoryID(id, prefix)
        if accessoryID ~= nil then saveParameter(id, accessoryID, "grip_animation", gripAnimationID, true) end
    end)

    -- Preview handlers
    configui.onUpdate(prefix .. "accessory_item_test_left_hand", function(checked)
        local accessoryID = getAccessoryID(id, prefix) -- your existing helper (returns GUID or nil)
        preview.handed = Handed.Left
        preview.enabled = (checked == true) and (accessoryID ~= nil)
        preview.accessoryID = accessoryID

        pokePreviewChanged()
    end)

    configui.onUpdate(prefix .. "accessory_item_test_right_hand", function(checked)
        local accessoryID = getAccessoryID(id, prefix) -- your existing helper (returns GUID or nil)
        preview.handed = Handed.Right
        preview.enabled = (checked == true) and (accessoryID ~= nil)
        preview.accessoryID = accessoryID

        pokePreviewChanged()
    end)

end

--returns {333_da_344: "attachment_shotgun_game_name Scope", 432_dd_123: "some_attachment_long_name Laser Sight"}
function M.getAccessories()
    local result = {}
    local accessoriesList = paramManager:get("accessories") or {}
    for attachmentID, accessories in pairs(accessoriesList) do
        for accessoryID, accessoryParams in pairs(accessories) do
            M.print("Attachment ID: " .. tostring(attachmentID) .. " Accessory ID: " .. tostring(accessoryID), LogLevel.Debug)
            result[accessoryID] = attachmentID .. " " .. accessoryParams.label
        end
    end
    return result
end
function M.getAccessoryParams(accessoryID)
    local accessoriesList = paramManager:get("accessories") or {}
    for attachmentID, accessories in pairs(accessoriesList) do
        for aID, accessoryParams in pairs(accessories) do
            if aID == accessoryID then
                return accessoryParams
            end
        end
    end
    return nil
end

function M.getAccessoriesForAttachment(attachmentID)
    if attachmentID == nil or attachmentID == "" then
        return {}
    end
    return paramManager:get({"accessories", attachmentID}) or {}
end

function M.getAccessoryParamsForAttachment(attachmentID, accessoryID)
    if attachmentID == nil or accessoryID == nil then
        return nil
    end
    local list = paramManager:get({"accessories", attachmentID})
    return list and list[accessoryID] or nil
end


local function getAnimationLabelsArray(animationIDList)
	local labels = {"None"}
	for id, data in pairs(animationIDList) do
		table.insert(labels, data["label"])
	end
	return labels
end

local function getAnimationIDsArray(animationIDList)
	local ids = {""}
	for id, data in pairs(animationIDList) do
		table.insert(ids, id)
	end
	return ids
end

--called from hands to set available grip animations
function M.setAnimationIDs(animationIDList)
	if animationIDList ~= nil then
		animationLabels = getAnimationLabelsArray(animationIDList)
		animationIDs = getAnimationIDsArray(animationIDList)
	end
    updateGripAnimationUI()
end

function M.init(isDeveloperMode, logLevel, caller)
    paramManager:load()
    --need this to get the attachment sockets but is there a better way?
    callerModule = caller
end





return M