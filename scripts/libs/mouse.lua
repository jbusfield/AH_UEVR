local uevrUtils = require('libs/uevr_utils')
local controllers = require('libs/controllers')
local mathLib = require('libs/core/math_lib')
local plugin = require('libs/core/plugin')


local M = {}

local status = {}
local overrideEnable = true
function M.setOverrideEnable(state)
    overrideEnable = state
end

local function getViewportSize()
    local w = uevr.params.vr.get_ui_width()
    local h = uevr.params.vr.get_ui_height()
    if w ~= 0 and h ~= 0 then return w, h end

    if WidgetLayoutLibrary ~= nil then
        local size = WidgetLayoutLibrary:GetViewportSize(uevrUtils.get_world())
        if size ~= nil and size.X ~= 0 and size.Y ~= 0 then
            return size.X, size.Y
        end
    end
    local settings = (game_engine and game_engine.GameUserSettings) or GameUserSettings
    w = (settings and settings.ResolutionSizeX) or 0
    h = (settings and settings.ResolutionSizeY) or 0
    return w, h
end

local function projectWorldToScreen(worldLocation)
    local viewportWidth , viewportHeight = getViewportSize()
    if viewportWidth == 0 or viewportHeight == 0 then return false, 0, 0 end

    local camLocation = status.worldPosition or controllers.getControllerLocation(2)
    local camRotation = status.worldRotation or controllers.getControllerRotation(2)
    local camFOV = 45 --seems to work best

    local delta = worldLocation - camLocation
    local forward = mathLib.getForwardVector(camRotation, true)
    local right = mathLib.vectorRotate({ X = 0, Y = 1, Z = 0 }, camRotation, true)
    local up = mathLib.vectorRotate({ X = 0, Y = 0, Z = 1 }, camRotation, true)

    local finalX = mathLib.vectorDot(delta, forward, true)
    local finalY = mathLib.vectorDot(delta, right, true)
    local finalZ = mathLib.vectorDot(delta, up, true)

    if finalX <= 0 then
        return false, 0, 0
    end

    local aspectRatio = viewportWidth / viewportHeight
    local halfFOV = math.rad(camFOV / 2)
    local tanHalfFOV = math.tan(halfFOV)

    local screenX = finalY / (finalX * tanHalfFOV * aspectRatio)
    local screenY = finalZ / (finalX * tanHalfFOV)

    local pixelX = (screenX + 1.0) * 0.5 * viewportWidth
    local pixelY = (1.0 - screenY) * 0.5 * viewportHeight

    return true, pixelX, pixelY
end

function M.setWorldRotation(rotator)
    status.worldRotation = rotator
end
function M.setWorldPosition(position)
    status.worldPosition = position
end

local useRawControllers = true
---@type table
local rawPosePos = nil
---@type table
local rawPoseQuat = nil
local rawAimOffset = nil
local rawAimRetryTime = 0
local RAW_AIM_RETRY_SECONDS = 2.0

function M.useRawControllers(val)
    useRawControllers = val == true
    rawAimOffset = nil
    rawAimRetryTime = 0
    -- Makes the tick re-anchor the world camera when switching back to the world implementation.
    status.active = nil
end

local function getModFloat(name)
    return tonumber(string.match(uevr.params.vr:get_mod_value(name) or "", "[%-%d%.]+")) or 0
end

-- Lost tracking reports identity pose at (0,0,0).
local function getRawPose(index)
    uevr.params.vr.get_pose(index, rawPosePos, rawPoseQuat)
    local x, y, z = rawPosePos.X, rawPosePos.Y, rawPosePos.Z
    if (x * x + y * y + z * z) < 1e-8 then return nil end
    return x, y, z, rawPoseQuat.X, rawPoseQuat.Y, rawPoseQuat.Z, rawPoseQuat.W
end

-- get_pose only exposes the grip, which points well above the aim ray. The aim offset is only available through the plugin.
local function updateRawAimOffset()
    if rawAimOffset ~= nil or os.clock() < rawAimRetryTime then return end
    rawAimRetryTime = os.clock() + RAW_AIM_RETRY_SECONDS
    local offset = plugin.getControllerAimOffset("right")
    if type(offset) ~= "table" then return end
    local x, y, z, w = offset.X, offset.Y, offset.Z, offset.W
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" or type(w) ~= "number" then return end
    local norm = x * x + y * y + z * z + w * w
    if norm > 0.98 and norm < 1.02 then
        rawAimOffset = offset
    end
end

-- Intersects the raw right controller aim ray with UEVR's UI quad. With UI Follows View on the quad is fixed in the
-- HMD's local space; with it off the quad is fixed relative to the standing origin and rotation offset.
local function updateRawMousePosition()
    local playerController = uevr.api:get_player_controller(0)
    if playerController == nil then return end
    local viewportWidth, viewportHeight = getViewportSize()
    if viewportWidth == 0 or viewportHeight == 0 then return end

    if rawPosePos == nil then
        rawPosePos = Vector3f.new(0, 0, 0)
        rawPoseQuat = Quaternionf.new(0, 0, 0, 0)
    end
    local vr = uevr.params.vr
    local px, py, pz, qx, qy, qz, qw = getRawPose(vr.get_right_controller_index())
    if px == nil then
        -- A controller can change while untracked; fetch its offset again once it returns.
        rawAimOffset, rawAimRetryTime = nil, 0
        return
    end

    updateRawAimOffset()
    if rawAimOffset ~= nil then
        -- aim = grip * offset
        local ox, oy, oz, ow = rawAimOffset.X, rawAimOffset.Y, rawAimOffset.Z, rawAimOffset.W
        qx, qy, qz, qw = qw * ox + qx * ow + qy * oz - qz * oy,
            qw * oy - qx * oz + qy * ow + qz * ox,
            qw * oz + qx * oy - qy * ox + qz * ow,
            qw * ow - qx * ox - qy * oy - qz * oz
    end
    -- The controller points along the aim pose's -Z.
    local dx, dy, dz = -2 * (qx * qz + qw * qy), -2 * (qy * qz - qw * qx), 2 * (qx * qx + qy * qy) - 1

    local originX, originY, originZ, rx, ry, rz, rw
    if string.find(vr:get_mod_value("UI_FollowView") or "", "true", 1, true) ~= nil then
        local hx, hy, hz, hqx, hqy, hqz, hqw = getRawPose(vr.get_hmd_index())
        if hx == nil then return end
        originX, originY, originZ = hx, hy, hz
        rx, ry, rz, rw = -hqx, -hqy, -hqz, hqw
    else
        vr.get_standing_origin(rawPosePos)
        vr.get_rotation_offset(rawPoseQuat)
        originX, originY, originZ = rawPosePos.X, rawPosePos.Y, rawPosePos.Z
        rx, ry, rz, rw = rawPoseQuat.X, rawPoseQuat.Y, rawPoseQuat.Z, rawPoseQuat.W
    end
    px, py, pz = mathLib.vectorRotate_Components(rx, ry, rz, rw, px - originX, py - originY, pz - originZ)
    dx, dy, dz = mathLib.vectorRotate_Components(rx, ry, rz, rw, dx, dy, dz)
    if dz == 0 then return end

    local t = -(pz + getModFloat("UI_Distance")) / dz
    if t <= 0 then return end
    local height = getModFloat("UI_Size")
    if height == 0 then return end
    local width = height * viewportWidth / viewportHeight
    local u = (px - getModFloat("UI_X_Offset") + dx * t) / width + 0.5
    local v = 0.5 - (py - getModFloat("UI_Y_Offset") + dy * t) / height
    if u < 0 or u > 1 or v < 0 or v > 1 then return end
    playerController:SetMouseLocation(u * viewportWidth, v * viewportHeight)
end

function M.updateMousePosition()
    if useRawControllers then
        updateRawMousePosition()
        return
    end
	local playerController = uevr.api:get_player_controller(0)
	if playerController ~= nil then
        local controllerDir = controllers.getControllerDirection(Handed.Right)
        local controllerLoc = controllers.getControllerLocation(Handed.Right)
        if controllerDir == nil or controllerLoc == nil then return end
        controllerLoc = controllerLoc + controllerDir * 300
        local result, x, y = projectWorldToScreen(controllerLoc)
        if result then
            playerController:SetMouseLocation(x, y)
        end
    end
end

function M.enable(state)
    status.enabled = state
    status.lastShowCursor = nil
    if state == true then
        M.initCameraPosition()
    end
end

function M.initCameraPosition()
    if useRawControllers then return end
    local hmdLoc = controllers.getControllerLocation(2)
    local hmdRot = controllers.getControllerRotation(2)
    if hmdLoc == nil or hmdRot == nil then return end
    if math.abs(hmdLoc.X) + math.abs(hmdLoc.Y) + math.abs(hmdLoc.Z) < 1.0 then return end
    M.setWorldRotation(hmdRot)
    M.setWorldPosition(hmdLoc)
end

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    if overrideEnable == false then return end

    local uiEnabled = uevrUtils.executeUEVRCallbacksWithPriorityResult("is_controller_mouse_enabled")
    local active = uiEnabled == nil and status.enabled == true or uiEnabled == true
    if active and not status.active then
        M.initCameraPosition()
    end
    status.active = active
    if active then
        -- Mount UI enables before the HMD yaw settles; re-anchor when the cursor appears.
        local pc = uevr.api:get_player_controller(0)
        local show = pc ~= nil and pc.bShowMouseCursor == true
        if status.lastShowCursor == false and show then
            M.initCameraPosition()
        end
        status.lastShowCursor = show

        M.updateMousePosition()
    end
end)

setInterval(1000, function()
    if overrideEnable == false then return end

    if status.active and not useRawControllers then
        local pos = controllers.getControllerLocation(2)
        if pos ~= nil and status.worldPosition ~= nil and mathLib.vectorDistanceSquared(pos, status.worldPosition, false) > 5000 then
            M.initCameraPosition()
        end
    end
end)

return M
