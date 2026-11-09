local uevrUtils = require("libs/uevr_utils")
local configui = require("libs/configui")
--local input = require("libs/input")

local M = {}

--[[
gunstock.addAdjustment({
        id = "beretta",
        label = "Beretta M9",
        rotation_offset = {0,0,0}
})
gunstock.addAdjustment({
        id = "mossberg",
        label = "Mossberg",
        rotation_offset = {0,0,0}
})
gunstock.setActive("mossberg")
]]--
local parametersFileName = "gunstock_parameters"
local parameters = {}
local isParametersDirty = false

local configFileName = "gunstock_config"
local configTabLabel = "Gunstock Config"
local widgetPrefix = "uevr_gunstock_"


-- How gunstock offsets are applied (values are the 1-based index of the mode combo in the UI):
--   DISABLED - no gunstock rotation is applied
--   PHYSICAL - the per-weapon rotation / offhand offset configured in the gunstock UI (default)
--   VIRTUAL  - computed at runtime for two-handed aiming (accessories marked "Off Hand Aim");
--              nothing needs to be configured
M.Mode = { DISABLED = 1, PHYSICAL = 2, VIRTUAL = 3 }
local gunstockMode = M.Mode.PHYSICAL
local activeAttachmentID = nil
-- parameters["attachments"] = {
--     {
--         id = "WP_BerettaAuto9_C_Beretta_Mesh",
--         label = "Beretta M9",
--         rotation = {0,0,0}
--     }
-- }

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[gunstock] " .. text, logLevel)
	end
end

-- local function executeAimRotationOffsetChangeCallback(...)
-- 	uevrUtils.executeUEVRCallbacks("aim_rotation_offset_change", table.unpack({...}))
-- end

local function executeTransformChange(...)
	uevrUtils.executeUEVRCallbacks("gunstock_transform_change", table.unpack({...}))
end


local function getDefaultConfig(saveFileName)
    if saveFileName == nil then saveFileName = configFileName end
	return  {
		{
			panelLabel = configTabLabel,
			saveFile = saveFileName,
			layout =
			{
			}
		}
	}
end

-- Initial value of the mode combo. A config saved before the combo existed only has the old "Disable"
-- checkbox (uevr_gunstock_disable_configuration); map it so existing users keep their behaviour.
-- If the combo itself was already saved, configui restores that value and this one is ignored.
local function getInitialMode(saveFile)
    local saved = json.load_file(saveFile .. ".json")
    if type(saved) == "table" and saved[widgetPrefix .. "mode"] == nil then
        local legacyDisabled = saved[widgetPrefix .. "disable_configuration"]
        if legacyDisabled ~= nil then
            return legacyDisabled and M.Mode.DISABLED or M.Mode.PHYSICAL
        end
    end
    return gunstockMode
end

-- The mode combo, for embedding in another panel (for example expandArray(gunstock.getConfigurationWidgets)).
-- It uses the same ids as the Gunstock panel's own combo.
function M.getConfigurationWidgets(options)
    return configui.applyOptionsToConfigWidgets({
        {
            widgetType = "combo",
            id = widgetPrefix .. "mode",
            label = "Gunstock Mode",
            selections = {"Disabled", "Physical", "Virtual"},
            initialValue = gunstockMode,
        },
    }, options)
end

local function updateConfigUI(configDefinition)
    local attachmentList = parameters["attachments"]
    local initialMode = getInitialMode(configDefinition[1].saveFile or configFileName)
	for _, widget in ipairs(M.getConfigurationWidgets({ { id = widgetPrefix .. "mode", initialValue = initialMode } })) do
		table.insert(configDefinition[1]["layout"], widget)
	end

	-- everything below is only needed in Physical mode
	table.insert(configDefinition[1]["layout"], { widgetType = "begin_group", id = widgetPrefix .. "settings_group", isHidden = false })

	table.insert(configDefinition[1]["layout"],
		{
			widgetType = "tree_node",
			id = widgetPrefix .. "configuration",
			initialOpen = true,
			label = "Gunstock Configuration"
		}
	)

    table.insert(configDefinition[1]["layout"],
        {
            widgetType = "tree_node",
            id = widgetPrefix .. "default",
            initialOpen = true,
            label = "Default"
        }
    )
    table.insert(configDefinition[1]["layout"],
        {
            id = widgetPrefix .. "default_rotation", label = "Rotation",
            widgetType = "drag_float3", speed = .1, range = {-360, 360}, initialValue = {0,0,0}
        }
    )
    table.insert(configDefinition[1]["layout"],
        {
            id = widgetPrefix .. "default_offhand_location_offset", label = "Offhand Location Offset",
            widgetType = "drag_float3", speed = .1, range = {-100, 100}, initialValue = {0,0,0}
        }
    )
    table.insert(configDefinition[1]["layout"],
        {
            widgetType = "tree_pop"
        }
    )

    for i = 1, #attachmentList do
		local id = attachmentList[i]["id"]
		local label = attachmentList[i]["label"]
		local rot = attachmentList[i]["rotation"]
		local offhand_location_offset = attachmentList[i]["offhand_location_offset"]

        table.insert(configDefinition[1]["layout"],
            {
                widgetType = "tree_node",
                id = widgetPrefix .. id,
                initialOpen = false,
                label = label
            }
        )
		table.insert(configDefinition[1]["layout"],
            {
                id = widgetPrefix .. id .. "_use_default", label = "Use Default Rotation",
                widgetType = "checkbox", initialValue = true
            }
		)
		table.insert(configDefinition[1]["layout"],
            {
                id = widgetPrefix .. id .. "_rotation", label = "Rotation",
                widgetType = "drag_float3", speed = .1, range = {-360, 360}, initialValue = rot
            }
		)
		table.insert(configDefinition[1]["layout"],
            {
                id = widgetPrefix .. id .. "_use_default_offhand_location_offset", label = "Use Default Offhand Location Offset",
                widgetType = "checkbox", initialValue = true
            }
		)
		table.insert(configDefinition[1]["layout"],
            {
                id = widgetPrefix .. id .. "_offhand_location_offset", label = "Offhand Location Offset",
                widgetType = "drag_float3", speed = .1, range = {-100, 100}, initialValue = offhand_location_offset
            }
		)
		table.insert(configDefinition[1]["layout"],
            {
                widgetType = "tree_pop"
            }
		)

        configui.onUpdate(widgetPrefix .. id .. "_rotation", function(value)
			M.updateTransforms(id, nil, value, nil)
		end)
        configui.onUpdate(widgetPrefix .. id .. "_offhand_location_offset", function(value)
			M.updateTransforms(id, nil, nil, nil, value)
		end)
        configui.onCreateOrUpdate(widgetPrefix .. id .. "_use_default", function(value)
			configui.setHidden(widgetPrefix .. id .. "_rotation", value)
		end)
        configui.onCreateOrUpdate(widgetPrefix .. id .. "_use_default_offhand_location_offset", function(value)
			configui.setHidden(widgetPrefix .. id .. "_offhand_location_offset", value)
		end)

    end

    table.insert(configDefinition[1]["layout"],
		{
			widgetType = "tree_pop"
		}
	)
	table.insert(configDefinition[1]["layout"], { widgetType = "end_group" })
	return configDefinition
end

local function saveParameters()
	M.print("Saving gunstock parameters " .. parametersFileName)
	json.dump_file(parametersFileName .. ".json", parameters, 4)
end

local createMonitor = doOnce(function()
    uevrUtils.setInterval(1000, function()
        if isParametersDirty == true then
            saveParameters()
            isParametersDirty = false
        end
    end)
end, Once.EVER)

local function getAttachment(id)
    if id == nil then return nil end
    if parameters ~= nil and parameters["attachments"] ~= nil then
        for i = 1, #parameters["attachments"] do
            if id == parameters["attachments"][i].id then
                return parameters["attachments"][i]
            end
        end
    end
    return nil
end

function M.loadParameters(fileName)
	if fileName ~= nil then parametersFileName = fileName end
	M.print("Loading attachments parameters " .. parametersFileName)
	parameters = json.load_file(parametersFileName .. ".json")

	if parameters == nil then
		parameters = {}
		M.print("Creating attachments parameters")
	end
	if parameters["attachments"] == nil then
		parameters["attachments"] = {}
		isParametersDirty = true
	end

    createMonitor()
end

function M.showConfiguration(saveFileName, options)
	configui.create(updateConfigUI(getDefaultConfig(saveFileName)))
end

function M.addAdjustment(attachment)
	if attachment ~= nil and attachment.id ~= nil and attachment.id ~= "" and parameters ~= nil then
		local exists = false
		if parameters["attachments"] == nil then parameters["attachments"] = {} end
        for i = 1, #parameters["attachments"] do
            if attachment.id == parameters["attachments"][i].id then
                exists = true
            end
        end
        if not exists then
            if attachment.label == nil then
                attachment.label = attachment.id
            end
            if attachment.rotation == nil then
                local rot = configui.getValue(widgetPrefix .. "default_rotation")
                if rot ~= nil then attachment.rotation =  {rot.x, rot.y, rot.z} end
            end
            if attachment.offhand_location_offset == nil then
                local loc = configui.getValue(widgetPrefix .. "default_offhand_location_offset")
                if loc ~= nil then attachment.offhand_location_offset =  {loc.x, loc.y, loc.z} end
            end
            table.insert(parameters["attachments"], attachment)
            isParametersDirty = true

            configui.update(updateConfigUI(getDefaultConfig()))
        end
    else
        M.print("Invalid attachment parameters", LogLevel.Warning)
	end
end

-- function M.registerUpdateCallback(func)
-- 	uevrUtils.registerUEVRCallback("gunstock_update", func)
-- end
local function broadcastUpdate(id, attachmentParams)
    local rot = attachmentParams["rotation"] or {x=0, y=0, z=0}
    local offhandLocationOffset = attachmentParams["offhand_location_offset"] or {x=0, y=0, z=0}
    if gunstockMode == M.Mode.PHYSICAL and id == activeAttachmentID then
        executeTransformChange(id, nil, uevrUtils.rotator(rot), uevrUtils.vector(offhandLocationOffset))
    end
end

function M.updateTransforms(id, pos, rot, scale, offhandLocationOffset)
	if id ~= nil then
        for i = 1, #parameters["attachments"] do
            if id == parameters["attachments"][i].id then
                if rot ~= nil then parameters["attachments"][i].rotation = {rot.x, rot.y, rot.z} end
                if offhandLocationOffset ~= nil then parameters["attachments"][i].offhand_location_offset = {offhandLocationOffset.x, offhandLocationOffset.y, offhandLocationOffset.z} end
                isParametersDirty = true

                broadcastUpdate(id, parameters["attachments"][i])
                -- if gunstockMode == M.Mode.PHYSICAL and id == activeAttachmentID then
                --     executeTransformChange(id, nil, uevrUtils.rotator(rot.x, rot.y, rot.z), uevrUtils.vector(offhandLocationOffset.x, offhandLocationOffset.y, offhandLocationOffset.z))
                -- end
                break
            end
        end
	end
end

local function updateDefaultAttachmentTransforms(pos, rot, scale, offhandLocationOffset)
    for i = 1, #parameters["attachments"] do
        local id = parameters["attachments"][i].id
        local useDefault = configui.getValue(widgetPrefix .. id .. "_use_default")
        local useDefaultOffhandOffset = configui.getValue(widgetPrefix .. id .. "_use_default_offhand_location_offset")
        if useDefault == true and rot ~= nil then
            parameters["attachments"][i].rotation = {rot.x, rot.y, rot.z}
            configui.setValue(widgetPrefix .. id .. "_rotation", parameters["attachments"][i].rotation, true)
            isParametersDirty = true
        end
        if useDefaultOffhandOffset == true and offhandLocationOffset ~= nil then
            parameters["attachments"][i].offhand_location_offset = {offhandLocationOffset.x, offhandLocationOffset.y, offhandLocationOffset.z}
            configui.setValue(widgetPrefix .. id .. "_offhand_location_offset", parameters["attachments"][i].offhand_location_offset, true)
            isParametersDirty = true
        end

        broadcastUpdate(id, parameters["attachments"][i])
            -- if gunstockMode == M.Mode.PHYSICAL and id == activeAttachmentID then
            --     executeTransformChange(id, nil, uevrUtils.rotator(rot.x, rot.y, rot.z))
            -- end
    end
end

local function updateSelectedColors(id)
	for i = 1, #parameters["attachments"] do
		local p_id = parameters["attachments"][i].id
		configui.setColor(widgetPrefix .. p_id, "#FFFFFFFF")
	end

    if id ~= nil then
	    configui.setColor(widgetPrefix .. id, "#0088FFFF")
    end
end

function M.setActive(id)
    updateSelectedColors(id)
    if id == nil then return end
    activeAttachmentID = id

    local rot = nil
    local offhandLocationOffset = nil
    if gunstockMode == M.Mode.PHYSICAL then
        local attachment = getAttachment(id)
        if attachment ~= nil then
            rot = uevrUtils.rotator(attachment.rotation)
            offhandLocationOffset = uevrUtils.vector(attachment.offhand_location_offset)
            --print("Setting gunstock rotation for " .. id .. " to " .. tostring(rot.Pitch) .. ", " .. tostring(rot.Yaw) .. ", " .. tostring(rot.Roll))
            --input.setAimRotationOffset(rot)
        end
    end
    if rot == nil then rot = uevrUtils.rotator(0,0,0) end
    if offhandLocationOffset == nil then offhandLocationOffset = uevrUtils.vector(0,0,0) end
    --executeAimRotationOffsetChangeCallback(rot)
    executeTransformChange(id, nil, rot, offhandLocationOffset)
    return rot
end

-- Backward compatible wrapper for the old "Disable" checkbox API.
function M.disable(val)
    M.setMode(val and M.Mode.DISABLED or M.Mode.PHYSICAL)
end

configui.onCreateOrUpdate(widgetPrefix .. "mode", function(value)
    M.setMode(value)
end)
configui.onUpdate(widgetPrefix .. "default_rotation", function(value)
    updateDefaultAttachmentTransforms(nil, value, nil)
end)
configui.onUpdate(widgetPrefix .. "default_offhand_location_offset", function(value)
    updateDefaultAttachmentTransforms(nil, nil, nil, value)
end)

uevrUtils.registerUEVRCallback("attachment_grip_changed", function(id, gripHand)
    M.addAdjustment({id = id})
	M.setActive(id)
end)

-- Virtual gunstock: two-handed aiming.
-- While an accessory with "Off Hand Aim" checked is active on the left hand, the right controller's
-- rotation is turned (about the right hand, so the weapon stays in the hand) until the weapon's aim axis
-- (measured per weapon, see readBarrelAxis) points from the right controller toward the left controller. The result is published through the
-- same gunstock_transform_change callback as a physical gunstock, so hands, ik and input apply it
-- the same way. Physical and virtual gunstocks are not meant to be used together.
-- Active only in Mode.VIRTUAL (see setMode); nothing is registered until that mode is first selected.
local mathLib = require("libs/core/math_lib")

local VIRTUAL_SMOOTHING_SECONDS = 0.06  -- time constant of the ramp in and out
local VIRTUAL_MIN_HAND_SEPARATION = 10.0 -- below this the hand-to-hand direction is unstable (hold last value)
local VIRTUAL_EMIT_EPSILON = 1e-7        -- 1 - |dot| of the quaternions; ~0.05 degrees
local VIRTUAL_RELEASE_EPSILON = 1e-6     -- ~0.16 degrees from the physical target counts as released

-- Left-hand roll: when enabled, rolling the left controller relative to the right one (about the
-- hand-to-hand line) rolls the weapon about that line by VIRTUAL_ROLL_GAIN of the change, measured from
-- the pose at engage. Set VIRTUAL_ROLL_ENABLED to false for the plain aim-only solve.
local VIRTUAL_ROLL_ENABLED = true
local VIRTUAL_ROLL_GAIN = 0.5            -- 0 = ignore left roll, 1 = left hand fully drives the roll
local VIRTUAL_ROLL_MAX_DEGREES = 35.0    -- clamp on the applied roll

local virtualEnabled = false
local virtualRegistered = false
---@type any
local virtualAccessories = nil
---@type any
local virtualControllers = nil
local virtualState = { active = false, current = nil, lastEmit = nil }

-- The weapon's aim axis in the right hand's own frame is a constant per weapon; it is measured in the
-- background while two-hand aim is idle and latched here, keyed by attachment id.
local MEASURE_SETTLE_SECONDS = 0.3  -- wait after a weapon change before the first reading
local MEASURE_INTERVAL_SECONDS = 5.0 -- safety-net refresh
local MEASURE_RETRY_SECONDS = 0.5   -- retry delay after a skipped or failed reading
local MEASURE_SAMPLES = 5           -- consecutive readings averaged per measurement
---@type any
local virtualAttachments = nil
local virtualClock = 0.0
local virtualAxes = {}
local virtualLastID = nil -- attachment id seen on the previous virtual tick, to detect weapon switches
local measure = { id = nil, count = 0, sx = 0.0, sy = 0.0, sz = 0.0, nextAt = 0.0 }

-- Quaternion (x, y, z, w) of a rotator-like table.
local function quatOfRotator(rotation)
    return mathLib.quatFromRotator_Components(rotation.Pitch or 0, rotation.Yaw or 0, rotation.Roll or 0)
end

-- The weapon's aim axis expressed in the right controller's own frame. The hand's end-bone offset and
-- the weapon's attach rotation are fixed, so this is constant per weapon and can be measured whenever
-- the hand is at rest. In Virtual mode no gunstock offset is applied while idle, so the hand frame is
-- the controller frame. The aim axis is the forward axis of attachments.getActiveAttachmentTransforms,
-- which is what input.lua aims along for RIGHT_WEAPON. Returns x, y, z (unit length) or nil.
local GRIP_AXIS_MIN_DISTANCE = 3.0 -- below this the right-hand-to-grip direction is too noisy to use

-- The direction from the right controller to the off-hand grip point, in the right controller's frame.
-- The off-hand grip can sit well off the barrel line (the left hand is physically at the grip, not on the
-- barrel), so the vector that must follow the hand-to-hand line is this one, not the barrel axis.
-- Constant per weapon. Returns x, y, z (unit length) or nil when the grip point isn't available.
local function readGripAxis(id)
    local gripLocation = virtualAccessories.getOffhandAimGripLocation(id)
    local rightLocation = virtualControllers.getControllerLocation(Handed.Right)
    local controllerRotation = virtualControllers.getControllerRotation(Handed.Right)
    if gripLocation == nil or rightLocation == nil or controllerRotation == nil then return nil end

    local dx, dy, dz = gripLocation.X - rightLocation.X, gripLocation.Y - rightLocation.Y, gripLocation.Z - rightLocation.Z
    if ((dx * dx) + (dy * dy) + (dz * dz)) < (GRIP_AXIS_MIN_DISTANCE * GRIP_AXIS_MIN_DISTANCE) then return nil end
    local cx, cy, cz, cw = quatOfRotator(controllerRotation)
    local nx, ny, nz = mathLib.vectorSafeNormalize_Components(mathLib.vectorRotate_Components(-cx, -cy, -cz, cw, dx, dy, dz))
    if nx == 0.0 and ny == 0.0 and nz == 0.0 then return nil end
    return nx, ny, nz
end

local function readBarrelAxis(id)
    local gx, gy, gz = readGripAxis(id)
    if gx ~= nil then return gx, gy, gz, true end

    local controllerRotation = virtualControllers.getControllerRotation(Handed.Right)
    local _, aimRotation = virtualAttachments.getActiveAttachmentTransforms(Handed.Right)
    if controllerRotation == nil or aimRotation == nil then return nil end

    local cx, cy, cz, cw = quatOfRotator(controllerRotation)
    local ax, ay, az, aw = quatOfRotator(aimRotation)
    local bx, by, bz = mathLib.quatAxisVector_Components(ax, ay, az, aw, "X")
    local nx, ny, nz = mathLib.vectorSafeNormalize_Components(mathLib.vectorRotate_Components(-cx, -cy, -cz, cw, bx, by, bz))
    if nx == 0.0 and ny == 0.0 and nz == 0.0 then return nil end
    return nx, ny, nz
end

local function isRightHandAnimating()
    return (uevrUtils.executeUEVRCallbacksWithPriorityBooleanResult("is_hands_animating_from_mesh", Handed.Right)) == true
end

local function resetMeasureSamples()
    measure.count = 0
    measure.sx, measure.sy, measure.sz = 0.0, 0.0, 0.0
end

-- Background measurement of the aim axis, run only while two-hand aim is idle (not engaged or ramping).
-- After a weapon change it waits for the hand to settle, averages a few consecutive readings and latches
-- the result for that weapon, then refreshes every MEASURE_INTERVAL_SECONDS. Weapons without an
-- "Off Hand Aim" accessory are never measured and nothing is read while the hand is animating.
local function updateAxisMeasurement(id)
    if measure.id ~= id then
        measure.id = id
        resetMeasureSamples()
        measure.nextAt = virtualClock + (virtualAxes[id] == nil and MEASURE_SETTLE_SECONDS or MEASURE_INTERVAL_SECONDS)
    end
    if measure.count == 0 and virtualClock < measure.nextAt then return end

    if measure.count == 0 and not virtualAccessories.hasOffhandAimAccessory(id) then
        measure.nextAt = virtualClock + MEASURE_INTERVAL_SECONDS
        return
    end
    if isRightHandAnimating() then
        resetMeasureSamples()
        measure.nextAt = virtualClock + MEASURE_RETRY_SECONDS
        return
    end

    local hx, hy, hz, isGrip = readBarrelAxis(id)
    local latched = virtualAxes[id]
    -- a latched grip axis is constant per weapon: never refresh it (reload/animation moves the weapon and
    -- would corrupt it), and never replace it with the barrel fallback
    if latched ~= nil and latched[4] == true then
        resetMeasureSamples()
        measure.nextAt = virtualClock + MEASURE_INTERVAL_SECONDS
        return
    end
    -- samples must agree, otherwise the weapon/hand is moving (e.g. reload): start over
    if hx ~= nil and measure.count > 0 then
        -- angle between the running sum and the new unit reading, compared without a square root:
        -- cos < 0.9994  <=>  dot < 0 or dot^2 < 0.9994^2 * |sum|^2
        local sumLen2 = (measure.sx * measure.sx) + (measure.sy * measure.sy) + (measure.sz * measure.sz)
        local dot = (measure.sx * hx) + (measure.sy * hy) + (measure.sz * hz)
        if sumLen2 > 1e-12 and (dot < 0.0 or (dot * dot) < (0.9994 * 0.9994 * sumLen2)) then
            resetMeasureSamples()
            measure.nextAt = virtualClock + MEASURE_RETRY_SECONDS
            return
        end
    end
    if hx == nil then
        resetMeasureSamples()
        measure.nextAt = virtualClock + MEASURE_RETRY_SECONDS
        return
    end
    measure.sx, measure.sy, measure.sz = measure.sx + hx, measure.sy + hy, measure.sz + hz
    measure.count = measure.count + 1
    if measure.count >= MEASURE_SAMPLES then
        local ax, ay, az = mathLib.vectorSafeNormalize_Components(measure.sx, measure.sy, measure.sz)
        if ax ~= 0.0 or ay ~= 0.0 or az ~= 0.0 then
            virtualAxes[id] = { ax, ay, az, isGrip == true }
        end
        resetMeasureSamples()
        measure.nextAt = virtualClock + MEASURE_INTERVAL_SECONDS
    end
end

-- Roll (degrees) to apply about the hand-to-hand line, from how far the left controller has rolled
-- relative to the right one since engage. Holds the last value when it can't be measured.
local function computeVirtualRoll(dx, dy, dz, rightRotation)
    local leftRotation = virtualControllers.getControllerRotation(Handed.Left, true)
    if leftRotation == nil or rightRotation == nil then return virtualState.roll or 0.0 end

    -- twist of the left controller's rotation relative to the right one, about the hand-to-hand line
    local rx, ry, rz, rw = quatOfRotator(rightRotation)
    local lx, ly, lz, lw = quatOfRotator(leftRotation)
    local twist = mathLib.computeSwingTwistAroundAxis_Components(rx, ry, rz, rw, lx, ly, lz, lw, dx, dy, dz, true)
    if twist == nil then return virtualState.roll or 0.0 end

    local relative = mathLib.normalizeDeg180(twist)
    if virtualState.rollRef == nil then virtualState.rollRef = relative end
    local roll = VIRTUAL_ROLL_GAIN * mathLib.normalizeDeg180(relative - virtualState.rollRef)
    if roll > VIRTUAL_ROLL_MAX_DEGREES then roll = VIRTUAL_ROLL_MAX_DEGREES
    elseif roll < -VIRTUAL_ROLL_MAX_DEGREES then roll = -VIRTUAL_ROLL_MAX_DEGREES end
    virtualState.roll = roll
    return roll
end

-- Controller-local rotation that turns the weapon's aim axis (`axis`, in the hand's frame) onto the
-- direction from the right controller to the left controller. Returns x, y, z, w or nil when it
-- can't be computed.
local function computeVirtualTarget(axis)
    -- fast reads: this runs every engaged tick, so skip the per-call validity checks
    local rightLocation = virtualControllers.getControllerLocation(Handed.Right, true)
    local leftLocation = virtualControllers.getControllerLocation(Handed.Left, true)
    local rightRotation = virtualControllers.getControllerRotation(Handed.Right, true)
    if rightLocation == nil or leftLocation == nil or rightRotation == nil then return nil end

    local dx, dy, dz = leftLocation.X - rightLocation.X, leftLocation.Y - rightLocation.Y, leftLocation.Z - rightLocation.Z
    local lengthSquared = (dx * dx) + (dy * dy) + (dz * dz)
    if lengthSquared < (VIRTUAL_MIN_HAND_SEPARATION * VIRTUAL_MIN_HAND_SEPARATION) then return nil end
    -- the one square root left: normalizing the hand-to-hand direction
    local invLength = 1.0 / math.sqrt(lengthSquared)
    dx, dy, dz = dx * invLength, dy * invLength, dz * invLength

    -- the offset is applied in controller-local space (ComposeRotators(offset, controllerRotation))
    local qx, qy, qz, qw = mathLib.quatFromRotator_Components(rightRotation.Pitch, rightRotation.Yaw, rightRotation.Roll)
    local lx, ly, lz = mathLib.vectorRotate_Components(-qx, -qy, -qz, qw, dx, dy, dz)

    -- shortest arc from the weapon's aim axis to the local direction of the left hand
    local sx, sy, sz, w = mathLib.quatFromUnitVectors_Components(axis[1], axis[2], axis[3], lx, ly, lz)
    if sx == nil then return nil end

    if VIRTUAL_ROLL_ENABLED then
        -- roll about the (now aligned) line, in controller-local space, after the swing
        local roll = computeVirtualRoll(dx, dy, dz, rightRotation)
        if roll ~= 0.0 then
            local rx, ry, rz, rw = mathLib.quatFromAxisAngle_Components(lx, ly, lz, roll)
            sx, sy, sz, w = mathLib.quatMultiply_Components(rx, ry, rz, rw, sx, sy, sz, w)
        end
    end
    return sx, sy, sz, w
end

local function releaseVirtual()
    local wasActive = virtualState.active
    virtualState.active = false
    virtualState.current = nil
    virtualState.lastEmit = nil
    virtualState.rollRef = nil
    virtualState.roll = nil
    if wasActive and activeAttachmentID ~= nil then
        M.setActive(activeAttachmentID) -- re-emits the mode's resting value (zero rotation in Virtual mode)
    end
end

local function virtualTick(engine, delta)
    if not virtualEnabled then return end
    virtualClock = virtualClock + (delta or 0.0)
    local id = activeAttachmentID
    if id == nil then
        virtualLastID = nil
        releaseVirtual()
        return
    end
    -- A latched axis can be wrong (measured mid-animation); drop it whenever the weapon is switched to so it
    -- is measured afresh (settle delay + sample agreement) instead of staying wrong until scripts reset.
    if id ~= virtualLastID then
        virtualLastID = id
        virtualAxes[id] = nil
        measure.id = nil
    end

    local engaged = virtualAccessories.getOffhandAimState(Handed.Left) ~= nil
    if not engaged and not virtualState.active then
        updateAxisMeasurement(id)
        return
    end

    -- Virtual and physical gunstocks are mutually exclusive, so the resting rotation is zero.
    local tx, ty, tz, tw
    if engaged then
        local axis = virtualAxes[id]
        if axis == nil and not virtualState.active and not isRightHandAnimating() then
            -- first engage on this weapon before the background measurement finished: take one reading now
            local hx, hy, hz = readBarrelAxis(id)
            if hx ~= nil then
                axis = { hx, hy, hz }
                virtualAxes[id] = axis
            end
        end
        if axis == nil then return end -- no axis yet: hold
        tx, ty, tz, tw = computeVirtualTarget(axis)
        if tx == nil then return end -- hold the last emitted value
    else
        tx, ty, tz, tw = 0.0, 0.0, 0.0, 1.0
    end

    if not virtualState.active then
        virtualState.active = true
        virtualState.current = { 0.0, 0.0, 0.0, 1.0 }
    end

    local cur = virtualState.current
    if cur == nil then return end
    local alpha = 1.0 - math.exp(-(delta or 0.016) / VIRTUAL_SMOOTHING_SECONDS)
    if alpha < 0.0 then alpha = 0.0 elseif alpha > 1.0 then alpha = 1.0 end
    local nx, ny, nz, nw = mathLib.quatSlerp_Components(cur[1], cur[2], cur[3], cur[4], tx, ty, tz, tw, alpha)
    virtualState.current = { nx, ny, nz, nw }

    if not engaged and (1.0 - mathLib.quatAbsDot_Components(nx, ny, nz, nw, tx, ty, tz, tw)) < VIRTUAL_RELEASE_EPSILON then
        releaseVirtual()
        return
    end

    local last = virtualState.lastEmit
    if last == nil or (1.0 - mathLib.quatAbsDot_Components(nx, ny, nz, nw, last[1], last[2], last[3], last[4])) > VIRTUAL_EMIT_EPSILON then
        virtualState.lastEmit = { nx, ny, nz, nw }
        local pitch, yaw, roll = mathLib.eulerFromQuat_Components(nx, ny, nz, nw)
        -- the offhand location offset is not used in Virtual mode (same zero vector setActive emits)
        executeTransformChange(id, nil, uevrUtils.rotator(pitch, yaw, roll), uevrUtils.vector(0,0,0))
    end
end

-- Profiling (off until uevrUtils.profiler:toggle(true); a passthrough otherwise). Names start with "VGS:".
isRightHandAnimating = uevrUtils.profiler:wrap("VGS: isRightHandAnimating", isRightHandAnimating)
computeVirtualRoll = uevrUtils.profiler:wrap("VGS: computeVirtualRoll", computeVirtualRoll)
computeVirtualTarget = uevrUtils.profiler:wrap("VGS: computeVirtualTarget", computeVirtualTarget)
readGripAxis = uevrUtils.profiler:wrap("VGS: readGripAxis", readGripAxis)
readBarrelAxis = uevrUtils.profiler:wrap("VGS: readBarrelAxis", readBarrelAxis)
updateAxisMeasurement = uevrUtils.profiler:wrap("VGS: updateAxisMeasurement", updateAxisMeasurement)
releaseVirtual = uevrUtils.profiler:wrap("VGS: releaseVirtual", releaseVirtual)
virtualTick = uevrUtils.profiler:wrap("VGS: virtualTick (total)", virtualTick)

-- Selects how gunstock offsets are applied: M.Mode.DISABLED, M.Mode.PHYSICAL or M.Mode.VIRTUAL.
-- Updates the combo in the configuration UI (hiding the per-weapon settings unless Physical) and
-- re-emits the resting value for the new mode.
function M.setMode(newMode)
    if newMode ~= M.Mode.DISABLED and newMode ~= M.Mode.PHYSICAL and newMode ~= M.Mode.VIRTUAL then
        M.print("setMode: invalid mode " .. tostring(newMode), LogLevel.Warning)
        return false
    end
    gunstockMode = newMode
    configui.setValue(widgetPrefix .. "mode", newMode, true)
    configui.setHidden(widgetPrefix .. "settings_group", newMode ~= M.Mode.PHYSICAL)

    local wantVirtual = (newMode == M.Mode.VIRTUAL)
    if wantVirtual ~= virtualEnabled then
        virtualEnabled = wantVirtual
        if wantVirtual then
            virtualAccessories = require("libs/accessories")
            virtualControllers = require("libs/controllers")
            virtualAttachments = require("libs/attachments")
            if not virtualRegistered then
                virtualRegistered = true
                uevr.sdk.callbacks.on_pre_engine_tick(virtualTick)
            end
        else
            releaseVirtual()
        end
    end
    M.setActive(activeAttachmentID)
    uevrUtils.executeUEVRCallbacks("gunstock_mode_change", newMode)
    return true
end

function M.getMode()
    return gunstockMode
end

M.loadParameters()

return M