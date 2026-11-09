
local uevrUtils = require("libs/uevr_utils")
local configui = require("libs/configui")
local bodyYaw = require("libs/body_yaw")
local pawnModule = require("libs/pawn")
local inputEnums = require("libs/enums/input")

local M = {}

local configFileName = "dev/input_config_dev"
local configTabLabel = "Input Dev Config"
local widgetPrefix = "uevr_input_"

M.AimMethod = inputEnums.AimMethod
M.PawnPositionMode = inputEnums.PawnPositionMode
M.PawnRotationMode = inputEnums.PawnRotationMode
M.HeightSource = inputEnums.HeightSource
--M.MovementMethod = inputEnums.MovementMethod

local boneList = {}
local heightBoneList = {"None"}
local heightBoneMesh = nil
local pawnCameraList = {}

local paramManager = nil


--local configIDs = {"isDisabledOverride", "aimMethod", "fixSpatialAudio", "rootOffset", "useSnapTurn", "snapAngle", "smoothTurnSpeed", "pawnRotationMode", "pawnPositionMode", "pawnPositionSweepMovement", "pawnPositionAnimationScale", "headOffset", "adjustForAnimation", "adjustForEyeOffset", "eyeOffset"}
-- local configDefaults = {
--     isDisabledOverride = false,
--     useRootOffset = true,
--     aimMethod = M.AimMethod.UEVR,
--     fixSpatialAudio = true,
--     rootOffset = {X=0,Y=0,Z=0},
--     useSnapTurn = false,
--     snapAngle = 30,
--     smoothTurnSpeed = 50,
--     pawnPositionMode = M.PawnPositionMode.FOLLOWS,
--     pawnRotationMode = M.PawnRotationMode.LOCKED,
--     pawnPositionSweepMovement = true,
--     pawnPositionAnimationScale = 0.2,
--     headOffset = {X=0,Y=0,Z=0},
--     adjustForAnimation = false,
--     adjustForEyeOffset = false,
--     eyeOffset = 0
--     aimCamera = ""
--	   useControllerRotationPitch = 1
--	   useControllerRotationYaw = 1
--	   useControllerRotationRoll = 1
--     usePawnControlRotation = 1
-- }
local configDefaults = {}

local function getFirstEyeIndexSelection(params)
	if params.autoDetectEyeIndices == true then return 1 end
	return params.firstStereoViewIndex == 0 and 2 or 3
end

local helpText = "This module provides advanced input configuration options for developers. Adjust settings such as aim method, turning behavior, body orientation, and roomscale movement to fine-tune the VR experience."
local heightDefaults = {
	heightSource = M.HeightSource.ROOT_COMPONENT, heightBoneName = "",
	heightBoneUseThreshold = true, heightBoneEnterThreshold = 30,
	heightBoneExitThreshold = 15, heightBoneConfirmTime = 0.15,
	heightBoneSmoothTime = 0.12, heightBoneFollow = false,
}

local function getHeightConfigValue(key, params)
	local value = (params or configDefaults)[key]
	if value == nil then return heightDefaults[key] end
	return value
end

local function getHeightSourceWidgets()
	return {
		{widgetType = "combo", id = widgetPrefix .. "heightSource", label = "Height Source",
			selections = {"RootComponent", "Pawn Bone", "Custom"}, initialValue = getHeightConfigValue("heightSource")},
		{widgetType = "begin_group", id = widgetPrefix .. "height_bone_group", isHidden = true},
			{widgetType = "indent", width = 20 }, { widgetType = "text", label = "Pawn Bone Settings" }, { widgetType = "begin_rect" },
			{widgetType = "combo", id = widgetPrefix .. "heightBoneName", label = "Height Bone",
				selections = {"None"}, initialValue = 1},
			{ widgetType = "indent", width = 100 },{widgetType = "button", id = widgetPrefix .. "height_recalibrate", label = "Recalibrate Standing Height"}, { widgetType = "unindent", width = 100 },
			--{widgetType = "text", label = "Select a bone and recalibrate while standing. HMD offsets still apply.", wrapped = true},
			{widgetType = "checkbox", id = widgetPrefix .. "heightBoneUseThreshold", label = "Use Height Threshold Hysteresis",
				initialValue = getHeightConfigValue("heightBoneUseThreshold")},
			{widgetType = "begin_group", id = widgetPrefix .. "height_threshold_group", isHidden = false},
				{ widgetType = "indent", width = 20 },
				--{widgetType = "text", label = "Ignore small bone movements. Enter after a sustained change from standing; exit when back near standing. Exit is limited to the enter threshold.", wrapped = true},
				{widgetType = "drag_float", id = widgetPrefix .. "heightBoneEnterThreshold", label = "Enter Threshold (cm)",
					speed = 0.5, range = {0, 200}, initialValue = getHeightConfigValue("heightBoneEnterThreshold")},
				{widgetType = "drag_float", id = widgetPrefix .. "heightBoneExitThreshold", label = "Exit Threshold (cm)",
					speed = 0.5, range = {0, 200}, initialValue = getHeightConfigValue("heightBoneExitThreshold")},
				{widgetType = "drag_float", id = widgetPrefix .. "heightBoneConfirmTime", label = "Confirmation Time (s)",
					speed = 0.01, range = {0, 3}, initialValue = getHeightConfigValue("heightBoneConfirmTime")},
				{widgetType = "checkbox", id = widgetPrefix .. "heightBoneFollow", label = "Follow Bone While Active",
					initialValue = getHeightConfigValue("heightBoneFollow")},
				{ widgetType = "unindent", width = 20 },
			{widgetType = "end_group"},
			{widgetType = "drag_float", id = widgetPrefix .. "heightBoneSmoothTime", label = "Height Smoothing Time (s)",
				speed = 0.01, range = {0, 3}, initialValue = getHeightConfigValue("heightBoneSmoothTime")},
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
		{widgetType = "end_group"},
		{widgetType = "begin_group", id = widgetPrefix .. "height_custom_group", isHidden = true},
--			{widgetType = "text", label = "Uses input.registerCustomHeightCallback(). Without a valid result, uses RootComponent height.", wrapped = true},
		{widgetType = "end_group"},
	}
end

local function getConfigWidgets(m_paramManager)
    return spliceableInlineArray {
	{
		widgetType = "checkbox",
		id = widgetPrefix .. "isDisabledOverride",
		label = "Disabled",
		initialValue = configDefaults["isDisabledOverride"]
	},
	-- {
	-- 	widgetType = "tree_node",
	-- 	id = widgetPrefix .. "handedness_tree",
	-- 	initialOpen = true,
	-- 	label = "Handedness"
	-- },
	-- 	{
	-- 		widgetType = "combo",
	-- 		id = widgetPrefix .. "handedness",
	-- 		label = "Hand",
	-- 		selections = {"Left", "Right"},
	-- 		initialValue = uevrUtils.getHandedness()
	-- 	},
	-- {
	-- 	widgetType = "tree_pop"
	-- },
	expandArray(m_paramManager.getProfilePreConfigurationWidgets, widgetPrefix),
	{
		widgetType = "tree_node",
		id = widgetPrefix .. "general_tree",
		initialOpen = true,
		label = "General"
	},
		{
			widgetType = "checkbox",
			id = widgetPrefix .. "fixSpatialAudio",
			label = "Fix Spatial Audio",
			initialValue = configDefaults["fixSpatialAudio"]
		},
		{
			widgetType = "checkbox",
			id = widgetPrefix .. "useRootOffset",
			label = "Use HMD Offset",
			initialValue = configDefaults["useRootOffset"] or true
		},
		{ widgetType = "begin_group", id = widgetPrefix .. "useRootOffset_group", isHidden = true},
			{ widgetType = "indent", width = 20} ,
				expandArray(getHeightSourceWidgets),
				{
					widgetType = "drag_float3",
					id = widgetPrefix .. "rootOffset",
					label = "HMD Offset",
					speed = .1,
					range = {-200, 200},
					initialValue = {configDefaults["rootOffset"].X, configDefaults["rootOffset"].Y, configDefaults["rootOffset"].Z}
				},
				{
					widgetType = "checkbox",
					id = widgetPrefix .. "useRootOffsetLocalZ",
					label = "Use Local Z",
					initialValue = configDefaults["useRootOffsetLocalZ"] or false
				},
			{ widgetType = "unindent", width = 20} ,
		{ widgetType = "end_group"},
		{
			widgetType = "checkbox",
			id = widgetPrefix .. "overridePlayerControllerPitch",
			label = "Override Player Controller Pitch",
			initialValue = configDefaults["overridePlayerControllerPitch"] or false
		},
		{ widgetType = "same_line" },
		{
			widgetType = "input_text",
			id = widgetPrefix .. "overridePlayerControllerPitchValue",
			label = "##overridePlayerControllerPitchValue",
			initialValue = tostring(configDefaults["overridePlayerControllerPitchValue"] or 0),
			width = 50
		},
		{
			widgetType = "checkbox",
			id = widgetPrefix .. "overridePlayerControllerYaw",
			label = "Override Player Controller Yaw  ",
			initialValue = configDefaults["overridePlayerControllerYaw"] or false
		},
		{ widgetType = "same_line" },
		{
			widgetType = "input_text",
			id = widgetPrefix .. "overridePlayerControllerYawValue",
			label = "##overridePlayerControllerYawValue",
			initialValue = tostring(configDefaults["overridePlayerControllerYawValue"] or 0),
			width = 50
		},
		{
			widgetType = "checkbox",
			id = widgetPrefix .. "overridePlayerControllerRoll",
			label = "Override Player Controller Roll   ",
			initialValue = configDefaults["overridePlayerControllerRoll"] or false
		},
		{ widgetType = "same_line" },
		{
			widgetType = "input_text",
			id = widgetPrefix .. "overridePlayerControllerRollValue",
			label = "##overridePlayerControllerRollValue",
			initialValue = tostring(configDefaults["overridePlayerControllerRollValue"] or 0),
			width = 50
		},
		{
			widgetType = "combo",
			id = widgetPrefix .. "firstEyeIndex",
			label = "First Eye Index",
			selections = {"Auto", "0", "1"},
			initialValue = getFirstEyeIndexSelection(configDefaults),
			width = 100
		},
	{
		widgetType = "tree_pop"
	},

	{
		widgetType = "tree_node",
		id = widgetPrefix .. "aim_method_tree",
		initialOpen = true,
		label = "Aim Method"
	},
		{
			widgetType = "combo",
			id = widgetPrefix .. "aimMethod",
			label = "Type",
			selections = {"UEVR", "Head/HMD", "Right Controller", "Left Controller", "Right Weapon", "Left Weapon"},
			initialValue = configDefaults["aimMethod"]
		},
        {
            widgetType = "begin_group",
            id = widgetPrefix .. "advanced_aim_group",
            isHidden = false
        },
			{
				widgetType = "combo",
				id = widgetPrefix .. "aimCameraList",
				label = "Aim Camera",
				selections = {"None"},
				initialValue = 1
			},
			{ widgetType = "indent", width = 10} ,
			{
				widgetType = "combo",
				id = widgetPrefix .. "usePawnControlRotation",
				label = "camera.usePawnControlRotation",
				selections = {"Default", "True", "False"},
				initialValue = 1,
				width = 100
			},
			{
				widgetType = "combo",
				id = widgetPrefix .. "cameraResetAction",
				label = "On Camera Deactivation",
				selections = {"Do not reset location and rotation", "Set to parent's location and rotation", "Restore original relative location and rotation"}, --  "Zero location and rotation"},
				initialValue = 1,
			},
			{ widgetType = "unindent", width = 10} ,
        {
            widgetType = "end_group",
        },
	{
		widgetType = "tree_pop"
	},
	{
		widgetType = "begin_group",
		id = widgetPrefix .. "advanced_input_group",
		isHidden = false
	},
		{
			widgetType = "tree_node",
			id = widgetPrefix .. "turning_tree",
			initialOpen = true,
			label = "Turning"
		},
			{
				widgetType = "checkbox",
				id = widgetPrefix .. "useSnapTurn",
				label = "Use Snap Turn",
				initialValue = configDefaults["useSnapTurn"]
			},
			{
				widgetType = "slider_int",
				id = widgetPrefix .. "snapAngle",
				label = "Snap Turn Angle",
				speed = 1.0,
				range = {2, 180},
				initialValue = configDefaults["snapAngle"]
			},
			{
				widgetType = "slider_int",
				id = widgetPrefix .. "smoothTurnSpeed",
				label = "Smooth Turn Speed",
				speed = 1.0,
				range = {1, 200},
				initialValue = configDefaults["smoothTurnSpeed"]
			},
		{
			widgetType = "tree_pop"
		},
		{
			widgetType = "tree_node",
			id = widgetPrefix .. "movement_orientation_tree",
			initialOpen = false,
			label = "Movement Orientation"
		},
			-- {
			-- 	widgetType = "combo",
			-- 	id = widgetPrefix .. "movementMethod",
			-- 	label = "Type",
			-- 	selections = {"UEVR", "Head/HMD", "Right Controller", "Left Controller"},
			-- 	initialValue = configDefaults["movementMethod"]
			-- },
			{
				widgetType = "combo",
				id = widgetPrefix .. "orientRotationToMovement",
				label = "pawn.CharacterMovement.bOrientRotationToMovement",
				selections = {"Default", "True", "False"},
				initialValue = 1,
				width = 100
			},
			{
				widgetType = "combo",
				id = widgetPrefix .. "useControllerDesiredRotation",
				label = "pawn.CharacterMovement.bUseControllerDesiredRotation",
				selections = {"Default", "True", "False"},
				initialValue = 1,
				width = 100
			},
		{
			widgetType = "tree_pop"
		},
		{
			widgetType = "tree_node",
			id = widgetPrefix .. "movement_tree",
			initialOpen = true,
			label = "Body Orientation"
		},
				{
					widgetType = "combo",
					id = widgetPrefix .. "pawnRotationMode",
					label = "Type",
					selections = {"Game", "Right Controller", "Left Controller", "Locked Head/HMD", "Follows Head (Simple)", "Follows Head (Advanced)"},
					initialValue = configDefaults["pawnRotationMode"]
				},
				{ widgetType = "same_line"},
				{
					widgetType = "checkbox",
					id = widgetPrefix .. "optimizeBodyRotationCalculations",
					label = "Optimize",
					initialValue = configDefaults["optimizeBodyRotationCalculations"]
				},
				{
					widgetType = "checkbox",
					id = widgetPrefix .. "pawnRotationModeDisableRotation",
					label = "Disable Rotation",
					initialValue = configDefaults["pawnRotationModeDisableRotation"]
				},
				{ widgetType = "same_line"},
				{
					widgetType = "checkbox",
					id = widgetPrefix .. "pawnRotationModeDisableInEarlyUpdate",
					label = "Disable In Early Update",
					initialValue = configDefaults["pawnRotationModeDisableInEarlyUpdate"]
				},
				{ widgetType = "same_line"},
				{
					widgetType = "checkbox",
					id = widgetPrefix .. "pawnRotationModeUseRootPitchRoll",
					label = "Use Root Pitch/Roll",
					initialValue = configDefaults["pawnRotationModeUseRootPitchRoll"]
				},
				{
					widgetType = "slider_float",
					id = widgetPrefix .. "pawnRotationLockedSmoothTime",
					label = "Smoothing",
					speed = .01,
					range = {0, 1},
					initialValue = configDefaults["pawnRotationLockedSmoothTime"],
					isHidden = true
				},
				expandArray(bodyYaw.getConfigurationWidgets),
		{
			widgetType = "tree_pop"
		},
		{
			widgetType = "tree_node",
			id = widgetPrefix .. "roomscale_tree",
			initialOpen = true,
			label = "Roomscale Movement"
		},
			{
				widgetType = "combo",
				id = widgetPrefix .. "pawnPositionMode",
				label = "Type",
				selections = {"None", "Follows HMD", "Follows HMD With Animation"},
				initialValue = configDefaults["pawnPositionMode"]
			},
			{ widgetType = "same_line"},
			{
				widgetType = "checkbox",
				id = widgetPrefix .. "optimizeBodyLocationCalculations",
				label = "Optimize",
				initialValue = configDefaults["optimizeBodyLocationCalculations"]
			},
			{
				widgetType = "checkbox",
				id = widgetPrefix .. "pawnPositionSweepMovement",
				label = "Sweep Movement",
				initialValue = configDefaults["pawnPositionSweepMovement"]
			},
			{
				widgetType = "slider_float",
				id = widgetPrefix .. "pawnPositionAnimationScale",
				label = "Animation Scale",
				speed = .01,
				range = {0, 1},
				initialValue = configDefaults["pawnPositionAnimationScale"],
			},
		{
			widgetType = "tree_pop"
		},
		{
			widgetType = "tree_node",
			id = widgetPrefix .. "uevr_input_pawn_tree",
			initialOpen = true,
			label = "Player Body"
		},
			{
				widgetType = "combo",
				id = widgetPrefix .. "useControllerRotationPitch",
				label = "pawn.bUseControllerRotationPitch",
				selections = {"Default", "True", "False"},
				initialValue = 1,
				width = 100
			},
			{
				widgetType = "combo",
				id = widgetPrefix .. "useControllerRotationYaw",
				label = "pawn.bUseControllerRotationYaw",
				selections = {"Default", "True", "False"},
				initialValue = 1,
				width = 100
			},
			{
				widgetType = "combo",
				id = widgetPrefix .. "useControllerRotationRoll",
				label = "pawn.bUseControllerRotationRoll",
				selections = {"Default", "True", "False"},
				initialValue = 1,
				width = 100
			},
            {
                widgetType = "checkbox",
                id = widgetPrefix .. "adjustBodyMeshPosition",
                label = "Adjust Body Mesh Position",
                initialValue = configDefaults["adjustBodyMeshPosition"] or true
            },
			{
				widgetType = "begin_group",
				id = widgetPrefix .. "body_mesh_position_group",
				isHidden = false
			},
				{ widgetType = "indent", width = 20} ,
				{
					widgetType = "drag_float3",
					id = widgetPrefix .. "headOffset",
					label = "Mesh Offset",
					speed = .1,
					range = {-200, 200},
					initialValue = {configDefaults["headOffset"] and configDefaults["headOffset"].X or 0, configDefaults["headOffset"] and configDefaults["headOffset"].Y or 0, configDefaults["headOffset"] and configDefaults["headOffset"].Z or 0}
				},
				{
					widgetType = "checkbox",
					id = widgetPrefix .. "useMeshHeightForHeadOffset",
					label = "Use Mesh Height",
					initialValue = configDefaults["useMeshHeightForHeadOffset"]
				},
				{
					widgetType = "checkbox",
					id = widgetPrefix .. "adjustForAnimation",
					label = "Animation Movement Compensation",
					initialValue = configDefaults["adjustForAnimation"]
				},
				{
					widgetType = "combo",
					id = widgetPrefix .. "headBones",
					label = "Head Bone",
					selections = {"None"},
					initialValue = 1
				},
				{
					widgetType = "checkbox",
					id = widgetPrefix .. "adjustForEyeOffset",
					label = "Eye Offset Compensation",
					initialValue = configDefaults["adjustForEyeOffset"]
				},
				{
					widgetType = "slider_float",
					id = widgetPrefix .. "eyeOffset",
					label = "Eye Offset",
					speed = .1,
					range = {-40, 40},
					initialValue = configDefaults["eyeOffset"]
				},
				{ widgetType = "unindent", width = 20} ,
			{ widgetType = "end_group"},
		{
			widgetType = "tree_pop"
		},
	{
		widgetType = "end_group",
	},
	{ widgetType = "new_line" },
	expandArray(m_paramManager.getProfilePostConfigurationWidgets, widgetPrefix),
	{ widgetType = "new_line" },
	{
		widgetType = "tree_node",
		id = widgetPrefix .. "help_tree",
		initialOpen = true,
		label = "Help"
	},
		{
			widgetType = "text",
			id = widgetPrefix .. "help",
			label = helpText,
			wrapped = true
		},
	{
		widgetType = "tree_pop"
	},
	-- {
		-- widgetType = "slider_float",
		-- id = "neckOffset",
		-- label = "Neck Offset",
		-- speed = .1,
		-- range = {-40, 40},
		-- initialValue = 10
	-- },
    }
end
local function updateSetting(key, value)
    uevrUtils.executeUEVRCallbacks("on_input_config_param_change", key, value, true)
end

-- The height selector is independent of the animation-correction bone selector.
-- Store names in profiles and only translate to indices for display.
local function setHeightBoneSelection(name)
	configui.setValue(widgetPrefix .. "heightBoneName", uevrUtils.indexOf(heightBoneList, name) or 1, true)
end

local function setHeightBoneNames(force)
	local source = configui.getValue(widgetPrefix .. "heightSource") or M.HeightSource.ROOT_COMPONENT
	if source ~= M.HeightSource.PAWN_BONE then return end
	local mesh = uevrUtils.getValid(pawnModule.getBodyMesh())
	if not force and mesh == heightBoneMesh then return end
	heightBoneMesh = mesh
	heightBoneList = {"None"}
	if mesh ~= nil then
		for _, name in ipairs(uevrUtils.getBoneNames(mesh) or {}) do table.insert(heightBoneList, name) end
	end
	configui.setSelections(widgetPrefix .. "heightBoneName", heightBoneList)
	local params = paramManager and paramManager:getAllActiveProfileParams() or configDefaults
	setHeightBoneSelection(getHeightConfigValue("heightBoneName", params))
end

local function updateHeightUIState()
	local source = configui.getValue(widgetPrefix .. "heightSource") or M.HeightSource.ROOT_COMPONENT
	configui.hideWidget(widgetPrefix .. "height_bone_group", source ~= M.HeightSource.PAWN_BONE)
	configui.hideWidget(widgetPrefix .. "height_custom_group", source ~= M.HeightSource.CUSTOM)
	configui.hideWidget(widgetPrefix .. "height_threshold_group", configui.getValue(widgetPrefix .. "heightBoneUseThreshold") == false)
end

configui.onUpdate(widgetPrefix .. "heightSource", function(value)
	updateSetting("heightSource", value)
	setHeightBoneNames(true)
	updateHeightUIState()
end)
configui.onCreate(widgetPrefix .. "heightSource", function() updateHeightUIState() end)
configui.onUpdate(widgetPrefix .. "heightBoneName", function(value)
	if heightBoneList[value] ~= nil then updateSetting("heightBoneName", value == 1 and "" or heightBoneList[value]) end
end)
configui.onUpdate(widgetPrefix .. "height_recalibrate", function()
	uevrUtils.executeUEVRCallbacks("reset_input_height_source")
end)
for _, key in ipairs({"heightBoneUseThreshold", "heightBoneEnterThreshold", "heightBoneExitThreshold",
	"heightBoneConfirmTime", "heightBoneSmoothTime", "heightBoneFollow"}) do
	configui.onUpdate(widgetPrefix .. key, function(value)
		updateSetting(key, value)
		updateHeightUIState()
	end)
end
configui.onCreate(widgetPrefix .. "heightBoneUseThreshold", function() updateHeightUIState() end)

local function syncHeightUI(params)
	for key in pairs(heightDefaults) do
		if key ~= "heightBoneName" then configui.setValue(widgetPrefix .. key, getHeightConfigValue(key, params), true) end
	end
	setHeightBoneNames(true)
	setHeightBoneSelection(getHeightConfigValue("heightBoneName", params))
	updateHeightUIState()
end

setInterval(1000, function() setHeightBoneNames(false) end)
uevrUtils.registerUEVRCallback("on_pawn_param_change", function(name)
	if name == "bodyMeshName" or name == "profile" then setHeightBoneNames(true) end
end)

local function setCurrentHeadBone(value)
	print("Setting current head bone to index " .. value)
	if #boneList < value then
		print("Invalid head bone index")
		return
	end
	local headBoneName = boneList[value]
    updateSetting("headBoneName", headBoneName)
	local mesh = pawnModule.getBodyMesh()
	if mesh ~= nil then
		local rootBoneFName = uevrUtils.getRootBoneOfBone(mesh, headBoneName)
		if rootBoneFName ~= nil then
			local rootBoneName = rootBoneFName:to_string()
            updateSetting("rootBoneName", rootBoneName)
		end
	end
end

-- Like the height bone list: follow the body mesh, which can be missing right after a reset or a profile change, and
-- select the profile's saved head bone by name. Writing the name at the saved index would take a bone from whatever
-- skeleton is current (e.g. the hippogriff's) and save it into the profile.
local headBoneMesh = nil
local function setBoneNames(force)
	local mesh = uevrUtils.getValid(pawnModule.getBodyMesh())
	if not force and mesh == headBoneMesh then return end
	headBoneMesh = mesh
	if mesh == nil then return end
	boneList = uevrUtils.getBoneNames(mesh) or {}
	if #boneList == 0 then return end
	configui.setSelections(widgetPrefix .. "headBones", boneList)
	local params = paramManager and paramManager:getAllActiveProfileParams() or configDefaults
	for i, name in ipairs(boneList) do
		if name == params.headBoneName then
			configui.setValue(widgetPrefix .. "headBones", i, true)
			break
		end
	end
end

setInterval(1000, function() setBoneNames(false) end)
uevrUtils.registerUEVRCallback("on_pawn_param_change", function(name)
	if name == "bodyMeshName" or name == "profile" then setBoneNames(true) end
end)

local function updateUIState(key)
    local exKey = widgetPrefix .. key
    if key == "aimMethod" then
       -- configui.hideWidget(widgetPrefix .. "advanced_input_group", configui.getValue(exKey) == M.AimMethod.UEVR)
        configui.hideWidget(widgetPrefix .. "advanced_aim_group", configui.getValue(exKey) == M.AimMethod.UEVR)
    elseif key == "useSnapTurn" then
        configui.hideWidget(widgetPrefix .. "snapAngle", not configui.getValue(exKey))
        configui.hideWidget(widgetPrefix .. "smoothTurnSpeed", configui.getValue(exKey))
    elseif key == "pawnRotationMode" then
        configui.hideWidget("minAngularDeviation", not (configui.getValue(exKey) == M.PawnRotationMode.SIMPLE or configui.getValue(exKey) == M.PawnRotationMode.ADVANCED))
        configui.hideWidget("alignConfidenceThreshold",  configui.getValue(exKey) ~= M.PawnRotationMode.ADVANCED)
        configui.hideWidget(widgetPrefix .. "pawnRotationLockedSmoothTime",  configui.getValue(exKey) == M.PawnRotationMode.NONE)
    elseif key == "pawnPositionMode" then
        configui.hideWidget(widgetPrefix .. "pawnPositionAnimationScale", configui.getValue(exKey) ~= M.PawnPositionMode.ANIMATED)
        configui.hideWidget(widgetPrefix .. "pawnPositionSweepMovement", configui.getValue(exKey) ~= M.PawnPositionMode.FOLLOWS)
    elseif key == "adjustForAnimation" then
        configui.hideWidget(widgetPrefix .. "headBones", not configui.getValue(exKey))
    elseif key == "adjustForEyeOffset" then
        configui.hideWidget(widgetPrefix .. "eyeOffset", not configui.getValue(exKey))
	elseif key == "aimCameraList" then
		configui.hideWidget(widgetPrefix .. "usePawnControlRotation", configui.getValue(exKey) == 1)
		configui.hideWidget(widgetPrefix .. "cameraResetAction", configui.getValue(exKey) == 1)
	elseif key == "adjustBodyMeshPosition" then
		configui.setHidden(widgetPrefix .. "body_mesh_position_group", not configui.getValue(exKey))
    end
end

local function setSelectedPawnCamera(currentCameraName, noCallbacks)
	local selectedIndex = 1
	for i = 1, #pawnCameraList do
		if pawnCameraList[i] == currentCameraName then
			selectedIndex = i
			break
		end
	end
	configui.setValue(widgetPrefix .. "aimCameraList", selectedIndex, noCallbacks)
end


local function setPawnCameraList(currentCameraName, noCallbacks)
	--print("Setting pawn camera list")
    pawnCameraList = uevrUtils.getObjectPropertyDescriptors(pawn, "Pawn", "Class /Script/Engine.CameraComponent", true)
	--print("Found " .. #pawnCameraList .. " cameras")
	table.insert(pawnCameraList, 1, "None")
	-- for i, name in ipairs(pawnCameraList) do
	-- 	print("Camera " .. i .. ": " .. name)
	-- end

	local listName = "aimCameraList"
	--print("Updating camera list UI", widgetPrefix .. listName)
	configui.setSelections(widgetPrefix .. listName, pawnCameraList)
	-- local selectedIndex = 1
	-- for i = 1, #pawnCameraList do
	-- 	if pawnCameraList[i] == currentCameraName then
	-- 		selectedIndex = i
	-- 		break
	-- 	end
	-- end
	-- configui.setValue(widgetPrefix .. listName, selectedIndex, noCallbacks)
	setSelectedPawnCamera(currentCameraName, noCallbacks)
end

configui.onCreateOrUpdate(widgetPrefix .. "isDisabledOverride", function(value)
    updateSetting("isDisabledOverride", value)
end)

configui.onUpdate(widgetPrefix .. "headOffset", function(value)
	local arr = uevrUtils.getNativeValue(value)
    updateSetting("headOffset", {X=arr[1],Y=arr[2],Z=arr[3]})
end)

configui.onUpdate(widgetPrefix .. "useRootOffset", function(value)
	updateSetting("useRootOffset", value)
	configui.hideWidget(widgetPrefix .. "useRootOffset_group", not value)
end)

configui.onCreate(widgetPrefix .. "useRootOffset", function(value)
	configui.hideWidget(widgetPrefix .. "useRootOffset_group", not value)
end)

configui.onUpdate(widgetPrefix .. "rootOffset", function(value)
    --updateSetting("rootOffset", {X=value[1],Y=value[2],Z=value[3]})
	local arr = uevrUtils.getNativeValue(value)
    updateSetting("rootOffset", {X=arr[1],Y=arr[2],Z=arr[3]})
end)

configui.onUpdate(widgetPrefix .. "useRootOffsetLocalZ", function(value)
    updateSetting("useRootOffsetLocalZ", value)
end)

configui.onUpdate(widgetPrefix .. "overridePlayerControllerPitch", function(value)
	updateSetting("overridePlayerControllerPitch", value)
end)

configui.onUpdate(widgetPrefix .. "overridePlayerControllerPitchValue", function(value)
	updateSetting("overridePlayerControllerPitchValue", tonumber(value) or 0)
end)

configui.onUpdate(widgetPrefix .. "overridePlayerControllerYaw", function(value)
	updateSetting("overridePlayerControllerYaw", value)
end)

configui.onUpdate(widgetPrefix .. "overridePlayerControllerYawValue", function(value)
	updateSetting("overridePlayerControllerYawValue", tonumber(value) or 0)
end)

configui.onUpdate(widgetPrefix .. "overridePlayerControllerRoll", function(value)
	updateSetting("overridePlayerControllerRoll", value)
end)

configui.onUpdate(widgetPrefix .. "overridePlayerControllerRollValue", function(value)
	updateSetting("overridePlayerControllerRollValue", tonumber(value) or 0)
end)

configui.onUpdate(widgetPrefix .. "firstEyeIndex", function(value)
	if value ~= 1 and value ~= 2 and value ~= 3 then return end
	if value ~= 1 then
		updateSetting("firstStereoViewIndex", value - 2)
	end
	updateSetting("autoDetectEyeIndices", value == 1)
end)

configui.onUpdate(widgetPrefix .. "headBones", function(value)
	setCurrentHeadBone(value)
end)

configui.onUpdate(widgetPrefix .. "aimMethod", function(value)
	updateSetting("aimMethod", value)
    updateUIState("aimMethod")
end)

-- configui.onUpdate(widgetPrefix .. "movementMethod", function(value)
-- 	updateSetting("movementMethod", value)
--     updateUIState("movementMethod")
-- end)

configui.onCreate(widgetPrefix .. "aimMethod", function(value)
	updateUIState("aimMethod")
end)

configui.onUpdate(widgetPrefix .. "useSnapTurn", function(value)
	updateSetting("useSnapTurn", value)
    updateUIState("useSnapTurn")
end)

configui.onCreate(widgetPrefix .. "useSnapTurn", function(value)
    updateUIState("useSnapTurn")
end)

configui.onUpdate(widgetPrefix .. "snapAngle", function(value)
	updateSetting("snapAngle", value)
end)

configui.onUpdate(widgetPrefix .. "optimizeBodyRotationCalculations", function(value)
	updateSetting("optimizeBodyRotationCalculations", value)
end)

configui.onUpdate(widgetPrefix .. "pawnRotationModeDisableRotation", function(value)
	updateSetting("pawnRotationModeDisableRotation", value)
end)

configui.onUpdate(widgetPrefix .. "pawnRotationModeDisableInEarlyUpdate", function(value)
	updateSetting("pawnRotationModeDisableInEarlyUpdate", value)
end)

configui.onUpdate(widgetPrefix .. "pawnRotationModeUseRootPitchRoll", function(value)
	updateSetting("pawnRotationModeUseRootPitchRoll", value)
end)

configui.onUpdate(widgetPrefix .. "optimizeBodyLocationCalculations", function(value)
	updateSetting("optimizeBodyLocationCalculations", value)
end)

configui.onUpdate(widgetPrefix .. "smoothTurnSpeed", function(value)
	updateSetting("smoothTurnSpeed", value)
end)

configui.onUpdate(widgetPrefix .. "pawnRotationMode", function(value)
	updateSetting("pawnRotationMode", value)
    updateUIState("pawnRotationMode")
end)

configui.onUpdate(widgetPrefix .. "pawnRotationLockedSmoothTime", function(value)
	updateSetting("pawnRotationLockedSmoothTime", value)
end)

configui.onCreate(widgetPrefix .. "pawnRotationMode", function(value)
    updateUIState("pawnRotationMode")
end)

configui.onUpdate(widgetPrefix .. "pawnPositionMode", function(value)
	updateSetting("pawnPositionMode", value)
    updateUIState("pawnPositionMode")
end)

configui.onCreate(widgetPrefix .. "pawnPositionMode", function(value)
    updateUIState("pawnPositionMode")
end)

configui.onUpdate(widgetPrefix .. "pawnPositionAnimationScale", function(value)
	updateSetting("pawnPositionAnimationScale", value)
end)

configui.onUpdate(widgetPrefix .. "adjustForAnimation", function(value)
	updateSetting("adjustForAnimation", value)
    updateUIState("adjustForAnimation")
end)

configui.onCreate(widgetPrefix .. "adjustForAnimation", function(value)
    updateUIState("adjustForAnimation")
end)

configui.onUpdate(widgetPrefix .. "useMeshHeightForHeadOffset", function(value)
    updateSetting("useMeshHeightForHeadOffset", value)
end)


configui.onUpdate(widgetPrefix .. "adjustForEyeOffset", function(value)
	updateSetting("adjustForEyeOffset", value)
    updateUIState("adjustForEyeOffset")
end)

configui.onCreate(widgetPrefix .. "adjustForEyeOffset", function(value)
    updateUIState("adjustForEyeOffset")
end)

configui.onUpdate(widgetPrefix .. "eyeOffset", function(value)
	updateSetting("eyeOffset", value)
end)

configui.onUpdate(widgetPrefix .. "pawnPositionSweepMovement", function(value)
	updateSetting("pawnPositionSweepMovement", value)
end)

configui.onUpdate(widgetPrefix .. "fixSpatialAudio", function(value)
	updateSetting("fixSpatialAudio", value)
end)

configui.onUpdate(widgetPrefix .. "useControllerRotationPitch", function(value)
	updateSetting("useControllerRotationPitch", value)
end)

configui.onUpdate(widgetPrefix .. "useControllerRotationYaw", function(value)
	updateSetting("useControllerRotationYaw", value)
end)

configui.onUpdate(widgetPrefix .. "useControllerRotationRoll", function(value)
	updateSetting("useControllerRotationRoll", value)
end)

configui.onUpdate(widgetPrefix .. "orientRotationToMovement", function(value)
	updateSetting("orientRotationToMovement", value)
end)

configui.onUpdate(widgetPrefix .. "useControllerDesiredRotation", function(value)
	updateSetting("useControllerDesiredRotation", value)
end)

configui.onUpdate(widgetPrefix .. "usePawnControlRotation", function(value)
	updateSetting("usePawnControlRotation", value)
end)

configui.onUpdate(widgetPrefix .. "cameraResetAction", function(value)
	updateSetting("cameraResetAction", value)
end)

configui.onUpdate(widgetPrefix .. "adjustBodyMeshPosition", function(value)
	updateSetting("adjustBodyMeshPosition", value)
	updateUIState("adjustBodyMeshPosition")
end)
configui.onCreate(widgetPrefix .. "adjustBodyMeshPosition", function(value)
	configui.setHidden(widgetPrefix .. "body_mesh_position_group", not value)
end)

configui.onUpdate(widgetPrefix .. "aimCameraList", function(value)
	--get the camera name from the selection
	local cameraName = pawnCameraList[value]
	updateSetting("aimCamera", cameraName)
	updateUIState("aimCameraList")
end)

configui.onCreate(widgetPrefix .. "aimCameraList", function(value)
	configui.hideWidget(widgetPrefix .. "usePawnControlRotation", value == 1)
	configui.hideWidget(widgetPrefix .. "cameraResetAction", value == 1)
end)

-- configui.onUpdate(widgetPrefix .. "handedness", function(value)
-- 	uevrUtils.setHandedness(value-1)
-- end)

uevrUtils.registerLevelChangeCallback(function(level)
	setBoneNames(true)
	setHeightBoneNames(true)
end)

function M.getConfigurationWidgets(options)
	return configui.applyOptionsToConfigWidgets(getConfigWidgets(paramManager), options)
end

function M.showConfiguration(saveFileName, options)
	local configDefinition = {
		{
			panelLabel = configTabLabel,
			saveFile = saveFileName,
			layout = spliceableInlineArray{
				expandArray(M.getConfigurationWidgets, options)
			}
		}
	}
	configui.create(configDefinition)
end

local function setUIValue(key, value)
	if key == "autoDetectEyeIndices" or key == "firstStereoViewIndex" then
		configDefaults[key] = value
		configui.setValue(widgetPrefix .. "firstEyeIndex", getFirstEyeIndexSelection(configDefaults), true)
	elseif key == "heightBoneName" then
		setHeightBoneSelection(value)
	elseif key == "aimCamera" then
		--select from the list
		--setPawnCameraList(value, true)
		setSelectedPawnCamera(value, true)
		--configui.setValue(widgetPrefix .. "aimCameraList", 1, true)
	else
		configui.setValue(widgetPrefix .. key, value, true)
	end
	updateUIState(key)
	if heightDefaults[key] ~= nil then updateHeightUIState() end
end

local function updateUI(params)
	configDefaults = params
	for key, value in pairs(params) do
		setUIValue(key, value)
	end
	configui.setValue(widgetPrefix .. "firstEyeIndex", getFirstEyeIndexSelection(params), true)
end

function M.init(m_paramManager)
    --M.loadParameters(parametersFileName)
    configDefaults = m_paramManager and m_paramManager:getAllActiveProfileParams() or {}
	paramManager = m_paramManager
    M.showConfiguration(configFileName)
	configui.setValue(widgetPrefix .. "firstEyeIndex", getFirstEyeIndexSelection(configDefaults), true)
	syncHeightUI(configDefaults)

	paramManager:initProfileHandler(widgetPrefix, function(profileParams)
		updateUI(profileParams)
		syncHeightUI(profileParams)
		setBoneNames(true)
		setPawnCameraList(profileParams["aimCamera"], true)
	end)

	--updateUI(parameters)
end

uevrUtils.registerUEVRCallback("on_input_config_param_change", function(key, value)
	setUIValue(key, value)
end)

-- function M.registerParameterChangedCallback(callback)
--     uevrUtils.registerUEVRCallback("on_input_config_param_change", callback)
-- end

-- uevrUtils.registerHandednessChangeCallback(function(handed)
-- 	configui.setValue(widgetPrefix .. "handedness", handed + 1, true)
-- end)

return M
