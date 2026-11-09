local uevrUtils = require('libs/uevr_utils')
local hands = require('libs/hands')
local ik = require('libs/ik')
local pawnModule = require('libs/pawn')
local input = require('libs/input')
local montage = require('libs/montage')
local configui = require('libs/configui')
local accessories = require('libs/accessories')
local remap = require('libs/remap')
local ui = require('libs/ui')
local controllers = require('libs/controllers')
local mathLib = require('libs/core/math_lib')

local M = {}

local inCar = false
local physicalDriving = false
local gripping = {}
local lastAngle = {}
local accum = {}
local refQuat = {}
local commandedSteer = 0
local steerAtGrip = 0
local gripKey = ""
local hubPos = nil --steering wheel hub in tracking space, learned from two-hand grips; valid while seated
local steeringSocketName = nil
local SWAP_THROTTLE_TRIGGERS = false --false: right trigger forward, left trigger reverse. true: the other way round
local HIGH_SPEED = 840 --cm/s at which the high-speed lock angle fully applies (half the Moskvich MaxSpeed of 1680)
-- Default IK arms "Location" used instead of the profile value while seated (dev setting car_ik_location in main.lua
-- can change it). Measured in the Moskvich: the IK tick sets Z = 2*offset.Z + the pawn's capsule half-height, which
-- is 0 for the car (86 for the character on foot), and the game camera sits 34.8 above the driver capsule centre
-- (eye height 64 on foot). -51.6 keeps the arms the same distance below the camera (138) as the Default profile's
-- -80.025 does on foot.
local CAR_IK_LOCATION = {-10, 0, -51.6}
local carIKLocation = CAR_IK_LOCATION
local cameraHeightOffset = 0 --cm added to the car camera's height while seated (dev setting car_driver_height_offset in main.lua)

local function clearGrip()
	gripping = {}
	lastAngle = {}
	accum = {}
	refQuat = {}
	commandedSteer = 0
	steerAtGrip = 0
	gripKey = ""
end


-- While driving, the view is the car's own InternalCamera, which hangs off the car's FPCameraSpringArm on the
-- vehicle mesh (123 up in the Moskvich), not off the character. The camera height offset raises it; the character
-- stays where the game seats it. Its original height is remembered so it can be put back when leaving the car,
-- on level change and on Reset Scripts.
local cameraArm = nil
local cameraArmBaseZ = nil

local function restoreCameraArm()
	local arm = uevrUtils.getValid(cameraArm)
	if arm ~= nil and cameraArmBaseZ ~= nil then
		local rel = arm.RelativeLocation
		if rel ~= nil and math.abs(rel.Z - cameraArmBaseZ) >= 0.01 then
			arm:K2_SetRelativeLocation(uevrUtils.vector(rel.X, rel.Y, cameraArmBaseZ), false, reusable_hit_result, false)
		end
	end
	cameraArm, cameraArmBaseZ = nil, nil
end

local function updateCameraArmHeight(car, offset)
	local arm = uevrUtils.getValid(car, {"FPCameraSpringArm"})
	if arm == nil or arm.RelativeLocation == nil then return end
	local current = uevrUtils.getValid(cameraArm)
	if current == nil or current:get_address() ~= arm:get_address() then
		restoreCameraArm()
		cameraArm = arm
		cameraArmBaseZ = arm.RelativeLocation.Z
	end
	local rel = arm.RelativeLocation
	local target = cameraArmBaseZ + offset
	if math.abs(rel.Z - target) < 0.01 then return end
	arm:K2_SetRelativeLocation(uevrUtils.vector(rel.X, rel.Y, target), false, reusable_hit_result, false)
end

local function applyCarVisuals()
	if physicalDriving and inCar then
		pawnModule.hideArmsBones(true)
		hands.hideHands(false)
		ik.hide(false)
	else
		pawnModule.hideArmsBones(not inCar)
		hands.hideHands(inCar)
		ik.hide(inCar)
	end
	ik.setMeshLocationOverride(inCar and carIKLocation or nil)
end

--returns a copy so a config widget using it as its initial value cannot change the default
function M.getDefaultIKLocation()
	return { CAR_IK_LOCATION[1], CAR_IK_LOCATION[2], CAR_IK_LOCATION[3] }
end

--location: {x, y, z} IK arms offset applied while seated; nil restores the measured default. Applies live.
function M.setIKLocation(location)
	carIKLocation = location or CAR_IK_LOCATION
	if inCar then
		ik.setMeshLocationOverride(carIKLocation)
	end
end

function M.isInCar()
	return inCar
end

function M.isPhysicalDriving()
	return physicalDriving
end

function M.setPhysicalDriving(value)
	local enabled = value == true
	if enabled == physicalDriving then return end
	physicalDriving = enabled
	if not enabled then
		clearGrip()
		accessories.attachHandToTargetAccessory(Handed.Left, nil)
		accessories.attachHandToTargetAccessory(Handed.Right, nil)
	end
	applyCarVisuals()
end

function M.setInCar(value)
	inCar = value
	if not inCar then
		clearGrip()
		hubPos = nil
		restoreCameraArm()
	end
	applyCarVisuals()
end

--clears the flag without touching hands/arms (used on level change)
function M.reset()
	inCar = false
	clearGrip()
	hubPos = nil
	ik.setMeshLocationOverride(nil) --rigs rebuilt after the level change must use the profile location
	restoreCameraArm()
end

local function handleMontage(montageName)
	-- --getting in and out of car
	if montageName == "AM_PlayerHandsGetInMoskvichFL" or montageName == "AM_PlayerHandsGetInMoskvichFR" then
		--catching it early with animation rather than the hook function so we can disable input 
		--during the animation and get a better player orientation in the car
		--print("Getting in car")
		M.setInCar(true)
	end
	if montageName == "AM_PlayerHandsGetOutMoskvichFL" or montageName == "AM_PlayerHandsGetOutMoskvichFR" or montageName == "AM_PlayerCharacterHands_Moskvich_JumpOutSlow" or  montageName == "AM_PlayerCharacterHands_Moskvich_JumpOutFast" then
		setTimeout(3000, function()
			--print("Getting out of car")
			M.setInCar(false)
		end) --delay to make animation look better
	end
end

local function getDrivenCar()
	local p = uevrUtils.getValid(pawn)
	if p == nil or p.VehicleMovement == nil then return nil end
	return p
end

-- Called on an interval: keeps the car camera at its offset (the game could set it again) and picks up being
-- seated when the get-in events were missed.
local function updateCarCamera()
	local car = getDrivenCar()
	if car == nil then
		if cameraArm ~= nil then restoreCameraArm() end --no longer driving
		return
	end
	if not inCar then
		--Reset Scripts or a level load while seated: the get-in montage and K2_OnDrivingVehicle have already
		--fired, so take the seated state from the pawn being the car
		M.setInCar(true)
	end
	updateCameraArmHeight(car, cameraHeightOffset)
end

--offset: cm added to the car camera's height while seated (0 = game default). Applies live.
function M.setCameraHeightOffset(offset)
	cameraHeightOffset = tonumber(offset) or 0
	updateCarCamera()
end

local CAR_ACCESSORY_KEY = "Car"
local function getCarAccessoryMesh(hand)
	if not (physicalDriving and inCar) then return nil end
	if uevrUtils.isInCutscene() then return nil end
	if hand ~= nil then
		local handsType = configui.getValue("hands_type") or 1
		if handsType == 1 and #hands.getHandComponentsForHand(hand) == 0 then return nil end
		if handsType == 2 and not ik.exists() then return nil end
	end
	local p = getDrivenCar()
	if p == nil then return nil end
	return uevrUtils.getValid(p.Mesh)
end
accessories.setTargetProvider(function(hand)
	local mesh = getCarAccessoryMesh(hand)
	if mesh ~= nil then return mesh, CAR_ACCESSORY_KEY end
end)
accessories.setSocketProvider(CAR_ACCESSORY_KEY, function(callback)
	local mesh = getCarAccessoryMesh()
	if mesh ~= nil then uevrUtils.getSocketNames(mesh, callback) else callback(nil) end
end)
accessories.createConfigCallbacks(CAR_ACCESSORY_KEY, "car_")
function M.getAccessoryWidgets()
	local widgets = accessories.getConfigWidgets(CAR_ACCESSORY_KEY, "car_", 300)
	for _, widget in ipairs(widgets) do
		if widget.id == "car_accessory_item_socket_finder_instructions" then
			widget.label = "Get in a car and press Refresh to list its sockets."
		end
	end
	return widgets
end

-- Steering is measured from the raw VR controller poses (tracking space, relative to the player's body).
-- World-space controller positions cannot be used: the in-car camera has position and rotation lag and
-- follows the control rotation, so world hand positions shift against the car whenever it accelerates or turns.
-- For a hand rigidly gripping a wheel, the hand's twist about the column equals the wheel's rotation.
local columnAxis = nil
---@type any
local poseVec = nil
---@type any
local poseQuat = nil
-- reads a tracking-space pose into poseVec/poseQuat; false when tracking is lost
local function readPose(index)
	if poseVec == nil then
		poseVec = Vector3f.new(0, 0, 0)
		poseQuat = Quaternionf.new(0, 0, 0, 0)
	end
	uevr.params.vr.get_pose(index, poseVec, poseQuat)
	--lost tracking reports the origin
	return poseVec.X * poseVec.X + poseVec.Y * poseVec.Y + poseVec.Z * poseVec.Z >= 1e-8
end

-- returns position {x,y,z} and rotation {x,y,z,w} in tracking space, or nil when tracking is lost
local function getRawPose(index)
	if not readPose(index) then return nil, nil end
	return { x = poseVec.X, y = poseVec.Y, z = poseVec.Z }, { x = poseQuat.X, y = poseQuat.Y, z = poseQuat.Z, w = poseQuat.W }
end

local function getHandIndex(hand)
	local vr = uevr.params.vr
	return hand == Handed.Left and vr.get_left_controller_index() or vr.get_right_controller_index()
end

local function getHandPose(hand)
	return getRawPose(getHandIndex(hand))
end

-- per-frame steering path: rotation only, as four numbers, so nothing is allocated; nil when tracking is lost
local function getHandRotation(hand)
	if not readPose(getHandIndex(hand)) then return nil end
	return poseQuat.X, poseQuat.Y, poseQuat.Z, poseQuat.W
end

-- Steering column axis in tracking space, pointing away from the driver: the direction from the head to the wheel hub.
-- Preferred source: the steering_wheel socket (the wheel hub), converted into tracking space.
-- The HMD component's world axes and the HMD's raw tracking-space axes describe the same orientation, so expressing
-- the world direction in the HMD's world axes and rebuilding it from the tracking axes converts it without mixing
-- world positions with tracking positions (only the direction is taken from world space, once, at grip time).
local function getColumnAxisFromSocket(mesh)
	local hmd = controllers.getController(2, true)
	if mesh == nil or hmd == nil then return nil end
	if steeringSocketName == nil then
		steeringSocketName = uevrUtils.fname_from_string("steering_wheel")
	end
	local hub = mesh:GetSocketLocation(steeringSocketName)
	local head = hmd:K2_GetComponentLocation()
	local wf, wr, wu = hmd:GetForwardVector(), hmd:GetRightVector(), hmd:GetUpVector()
	local _, q = getRawPose(uevr.params.vr.get_hmd_index())
	if hub == nil or head == nil or wf == nil or wr == nil or wu == nil or q == nil then return nil end
	local dx, dy, dz = hub.X - head.X, hub.Y - head.Y, hub.Z - head.Z
	if dx * dx + dy * dy + dz * dz < 25 then return nil end --closer than 5 cm: no usable direction
	local a = dx * wf.X + dy * wf.Y + dz * wf.Z
	local b = dx * wr.X + dy * wr.Y + dz * wr.Z
	local c = dx * wu.X + dy * wu.Y + dz * wu.Z
	--HMD axes in tracking space: forward is -Z, right is +X, up is +Y
	local bx, by, bz = mathLib.quatAxisVector_Components(q.x, q.y, q.z, q.w, "Z")
	local fx, fy, fz = -bx, -by, -bz
	local rx, ry, rz = mathLib.quatAxisVector_Components(q.x, q.y, q.z, q.w, "X")
	local ux, uy, uz = mathLib.quatAxisVector_Components(q.x, q.y, q.z, q.w, "Y")
	local ax, ay, az = mathLib.vectorSafeNormalize_Components(a * fx + b * rx + c * ux, a * fy + b * ry + c * uy, a * fz + b * rz + c * uz)
	if ax == 0 and ay == 0 and az == 0 then return nil end --no usable direction
	return { x = ax, y = ay, z = az }
end

local function getColumnAxis(handPos, mesh)
	--preferred: head to the steering_wheel socket
	local socketAxis = getColumnAxisFromSocket(mesh)
	if socketAxis ~= nil then return socketAxis end
	--fallback when the socket or HMD component is unavailable: the hub is learned from the hands. With both hands on
	--the wheel their midpoint is close to the hub; the player is seated, so it is reused for one-hand grips. Before the
	--first two-hand grip, a one-hand grip aims at that hand (up to ~17 degrees off at 9 or 3 o'clock).
	local head = getRawPose(uevr.params.vr.get_hmd_index())
	if head == nil then return nil end
	local target = nil
	local left, right = handPos[Handed.Left], handPos[Handed.Right]
	if left ~= nil and right ~= nil then
		hubPos = { x = (left.x + right.x) * 0.5, y = (left.y + right.y) * 0.5, z = (left.z + right.z) * 0.5 }
		target = hubPos
	elseif hubPos ~= nil then
		target = hubPos
	else
		target = left or right
	end
	if target == nil then return nil end
	local ax, ay, az = target.x - head.x, target.y - head.y, target.z - head.z
	if ax * ax + ay * ay + az * az < 0.0025 then return nil end --hands closer than 5 cm to the head give no direction
	ax, ay, az = mathLib.vectorSafeNormalize_Components(ax, ay, az)
	return { x = ax, y = ay, z = az }
end

-- Rotation (qx, qy, qz, qw) relative to ref about axis, in degrees, all in tracking space.
-- Positive is clockwise as the driver sees it (steer right).
local function twistDegrees(qx, qy, qz, qw, ref, axis)
	return mathLib.computeParentSpaceTwistDegAroundAxis_Components(ref.x, ref.y, ref.z, ref.w, qx, qy, qz, qw, axis.x, axis.y, axis.z)
end

local HANDS = { Handed.Left, Handed.Right }
local angles = {} --reused every frame
local function steeringThumb(mesh)
	local left, right = gripping[Handed.Left], gripping[Handed.Right]
	local key = left and (right and "LR" or "L") or (right and "R" or "")
	if key == "" then
		commandedSteer = 0
		gripKey = ""
		return 0
	end
	if key ~= gripKey then
		--(re)base when a hand grabs or lets go: new reference pose per gripping hand and a fresh column axis
		local refs = {}
		local positions = {}
		local ready = true
		for _, hand in ipairs(HANDS) do
			if gripping[hand] then
				positions[hand], refs[hand] = getHandPose(hand)
				if refs[hand] == nil then ready = false end
			end
		end
		local axis = ready and getColumnAxis(positions, mesh) or nil
		if axis == nil then ready = false end
		if ready then
			gripKey = key
			steerAtGrip = commandedSteer
			columnAxis = axis
			refQuat = {}
			for _, hand in ipairs(HANDS) do
				if gripping[hand] then
					refQuat[hand] = refs[hand]
					accum[hand] = 0
					lastAngle[hand] = 0
				end
			end
		end
	end
	angles[Handed.Left], angles[Handed.Right] = nil, nil
	if gripKey == key and columnAxis ~= nil then
		for _, hand in ipairs(HANDS) do
			if gripping[hand] and refQuat[hand] ~= nil then
				local qx, qy, qz, qw = getHandRotation(hand)
				if qx ~= nil then
					angles[hand] = twistDegrees(qx, qy, qz, qw, refQuat[hand], columnAxis)
				end
			end
		end
	end
	local count = 0
	local deltaSum = 0
	for _, hand in ipairs(HANDS) do
		if angles[hand] ~= nil and lastAngle[hand] ~= nil then
			accum[hand] = (accum[hand] or 0) + mathLib.normalizeDeg180(angles[hand] - lastAngle[hand])
			lastAngle[hand] = angles[hand]
			deltaSum = deltaSum + accum[hand]
			count = count + 1
		end
	end
	if count == 0 then return math.floor(commandedSteer * 32767) end
	--blend the lock angle with speed: small hand movements are fine when slow but too sensitive when fast
	local lockSlow = configui.getValue("car_steering_lock_angle") or 30
	local lockFast = configui.getValue("car_steering_lock_angle_fast") or 90
	local speed = 0
	local car = getDrivenCar()
	local movement = car ~= nil and car.VehicleMovement or nil
	if movement ~= nil then
		speed = math.abs(movement:GetForwardSpeed() or 0)
	end
	local t = speed / HIGH_SPEED
	if t > 1 then t = 1 end
	local lockAngle = lockSlow + (lockFast - lockSlow) * t
	local steer = steerAtGrip + (deltaSum / count) / lockAngle
	if steer > 1 or steer < -1 then
		--at full lock, discard the extra hand rotation (the wheel hits its stop and slips in the hands)
		--otherwise the overshoot has to be unwound before the wheel moves again and steering feels locked
		steer = steer > 1 and 1 or -1
		steerAtGrip = steer
		for _, hand in ipairs(HANDS) do
			if accum[hand] ~= nil then accum[hand] = 0 end
		end
	end
	commandedSteer = steer
	return math.floor(steer * 32767)
end

function M.init()
	uevrUtils.setInterval(500, updateCarCamera)
	--put the car camera back before the scripts reload, otherwise the reloaded script would take the raised height as the base
	uevr.params.sdk.callbacks.on_script_reset(function()
		restoreCameraArm()
	end)

	--return true if input should be disabled, second param is priority
	input.registerIsDisabledCallback(function()
		if inCar then return true, 0 end
		return nil, 0 --no opinion; a false here would override other modules' true
	end)

	--the button remap turns physical grips into game buttons (left grip becomes RB = get out),
	--so while physically driving the game must see the physical buttons unchanged
	remap.registerIsDisabledCallback(function()
		if physicalDriving and inCar and getDrivenCar() ~= nil then return true, 0 end
		return nil, 0
	end)

	uevrUtils.registerUEVRCallback("on_accessory_attach", function(handed, parent)
		if not physicalDriving or not inCar then return end
		local mesh = getCarAccessoryMesh()
		if mesh == nil or parent == nil or parent:get_address() ~= mesh:get_address() then return end
		gripping[handed] = true
	end)
	uevrUtils.registerUEVRCallback("on_accessory_detach", function(handed)
		gripping[handed] = nil
		lastAngle[handed] = nil
		accum[handed] = nil
		refQuat[handed] = nil
	end)

	uevrUtils.registerOnPostInputGetStateCallback(function(retval, user_index, state)
		if not physicalDriving or not inCar or user_index ~= 0 then return end
		if getDrivenCar() == nil then return end
		--menus (inventory, map, main menu) must get the controls untouched
		if ui.isRemapDisabled() == true then
			gripKey = "" --rebase steering when the menu closes so hand movement during the menu does not jump the wheel
			return
		end
		--game RT is throttle and game LT is reverse. With the remap off the physical triggers reach the game
		--unchanged, so by default they pass through; SWAP_THROTTLE_TRIGGERS exchanges them.
		if SWAP_THROTTLE_TRIGGERS then
			state.Gamepad.bRightTrigger, state.Gamepad.bLeftTrigger = state.Gamepad.bLeftTrigger, state.Gamepad.bRightTrigger
		end
		--game RB is get out, so neither grip may reach the game
		uevrUtils.unpressButton(state, XINPUT_GAMEPAD_RIGHT_SHOULDER)
		uevrUtils.unpressButton(state, XINPUT_GAMEPAD_LEFT_SHOULDER)
		state.Gamepad.sThumbLY = 0
		--right stick left/right would rotate the view while seated; the player looks around with the headset
		state.Gamepad.sThumbRX = 0
		if not gripping[Handed.Left] and not gripping[Handed.Right] then
			commandedSteer = 0
			gripKey = ""
			state.Gamepad.sThumbLX = 0
		else
			local mesh = getCarAccessoryMesh()
			if mesh == nil then
				state.Gamepad.sThumbLX = 0
			else
				state.Gamepad.sThumbLX = steeringThumb(mesh)
			end
		end
	end)

	montage.registerMontageChangeCallback(function(montageObject, montageName)
		handleMontage(montageName)
	end)

	uevrUtils.registerLevelChangeCallback(function()
		M.reset()
	end)

	--BlueprintGeneratedClass hooks generally need to be registered whenever the level changes
	uevrUtils.registerLevelChangeCallback(function()
		hook_function("BlueprintGeneratedClass /Game/Core/Player/BP_PlayerCharacter.BP_PlayerCharacter_C", "K2_OnDrivingVehicle", false, nil,
			function(fn, obj, locals, result)
				--print("K2_OnDrivingVehicle called", locals, result, locals.IsDriving)
				M.setInCar(locals.IsDriving)
			end
		, true)
	end)
end

return M