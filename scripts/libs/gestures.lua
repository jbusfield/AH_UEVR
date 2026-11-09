local uevrUtils = require("libs/uevr_utils")
local controllers = require("libs/controllers")
local paramModule = require("libs/core/params")
local plugin = require("libs/core/plugin")

--[[
Usage
	local gestures = require("libs/gestures")
	gestures.init()
	gestures.setUseRawControllers(true) -- Optional: tracking-space flicks, unaffected by game teleports.
	-- World-space flicks remain the default. Both methods use the same config UI parameters.
	-- Raw mode detects directional strokes immediately; world mode retains peak-then-release detection.
	In developer mode, gestures.init(true) also loads the in-game gesture configuration tool.
	Parameters are stored in gesture_parameters.json (profiles supported).

Punch settings (forward strike — what each value means for your arm)
	minThresholdSpeed
		How fast your hand must move before a punch counts.
		Higher = ignore slow reaches and nudges; lower = easier to trigger with a light jab.

	maxThresholdSpeed
		Caps how hard a punch feels for strength (0-1). Does not block detection.
		Higher = need a faster punch to reach full strength; lower = even moderate punches report as strong.

	forwardDotThreshold
		How strongly the hand must be moving in the direction the controller is pointing.
		Higher = must punch more straight along the controller aim; lower = allow glancing / off-axis hits.

	cooldownTime
		How long after a punch before another can fire.
		Higher = fewer rapid repeats; lower = can chain punches sooner.

Block settings (sustained guard pose — what each value means for your arm)
	maxDropCm
		How far below your head the hand may sit and still count as a block.
		Higher = allow a lower guard (toward chest); lower = hand must stay up near face height.

	maxRaiseCm
		How far above your head the hand may sit.
		Higher = allow an overhead / high guard; lower = hand must stay at or below head height.

	inFront
		How directly in front of your face/chest the hand must be (not out beside your ear).
		Higher = hand must be more centered in front of you; lower = allow a wider/side guard.
		Also tightens how far out to either side the hand may drift.

	maxPointForward
		Whether your forearm is laid across your body vs aimed out at what you're looking at.
		Lower = more "guard bar across me" (tip pointing left/right); higher = allow pointing
		forward a bit while still counting as a block (more reach/punch-like).

	maxTiltDeg
		How much the controller may tip up or down from horizontal (wrist / forearm pitch).
		Higher = allow a steeper forearm; lower = forearm must stay more level.

	palmFacing
		How strongly the palm must face away from you (toward the threat), not down or toward you.
		Higher = stricter "shield facing out"; lower = allow a lazier / more rotated wrist.

	releaseSlack
		How sticky the pose is when leaving it (hysteresis on all checks).
		Higher = stays active longer as you drift out of the ideal pose; lower = snaps off quickly.

Swipe / Snatch settings (fast hand motion — what each value means for your arm)
	minThresholdSpeed
		How fast your hand must move before a swipe/snatch counts.
		Higher = ignore slow waves and twitches; lower = easier to trigger with a light flick.

	maxThresholdSpeed
		Caps how hard a swipe feels for strength (0-1). Does not block detection.
		Higher = need a faster swing to reach full strength; lower = even moderate swings report as strong.

	directionThreshold
		How clearly the motion must favor one axis (left/right/up/down/pull-in) to pick that swipe type.
		Higher = stricter direction; lower = looser classification (more accidental directions).

	cooldownTime
		How long after a swipe before another can fire.
		Higher = fewer rapid repeats; lower = can chain swipes sooner.

	snapTurnYawThreshold
		Ignores hand motion when your view/yaw jumps this much (e.g. snap turn).
		Higher = tolerate bigger yaw jumps without canceling; lower = treat smaller turns as "not a swipe".

Swing settings (one stroke — finish after rest or a deliberate reversal)
	minThresholdSpeed
		How fast your hand must move before a swing begins.
		Higher = ignore slow waves; lower = easier to start a swing.

	maxThresholdSpeed
		Caps how hard a swing feels for strength (0-1). Does not block detection.

	stopThresholdSpeed / stopHoldTime
		Finish after staying below Stop Speed for Stop Hold Time seconds.
		Brief speed dips during the same stroke do not open another swing.

	reversalDotThreshold / reversalMinDistance
		Finish when movement reverses far enough along the previous path.
		Gradual changes along a curved stroke remain part of the same swing.

	snapTurnYawThreshold
		Cancels an active swing (and ignores motion) when view yaw jumps this much.

Wrist flick settings (quick wand/controller orientation snap — not arm translation)
	minThresholdAngleSpeed
		How fast the controller must rotate (deg/s) before a flick counts.
		Higher = ignore slow tip tilts; lower = easier to trigger with a light wrist snap.
		Raw mode uses full quaternion rotation averaged over 50 ms; raw hand movement supplies direction.

	maxThresholdAngleSpeed
		Caps how hard a flick feels for strength (0-1). Does not block detection.
		Higher = need a faster snap to reach full strength; lower = moderate snaps report as strong.

	upMinThresholdAngleSpeed / upMaxThresholdAngleSpeed
		Same as above, but used for flick-up.

	minAngleDelta
		Minimum orientation change (deg) across the motion. Raw uses the full quaternion change.
		Higher = require a bigger wrist turn; lower = allow smaller snaps.

	upDotThreshold
		World: how closely the tip must point upward. Raw: how closely hand movement must align with up.
		Higher = a narrower upward cone; lower = allow more diagonal up-flicks.
		Raw direction uses controller movement only; no headset pose or endpoint pointing cone is used.

	cooldownTime
		How long after a flick before another can fire.
		Higher = fewer rapid repeats; lower = can chain flicks sooner.
]]

local M = {}

M.Gesture =
{
	PUNCH = 0,
	HOLSTER = 1,
	RELOAD = 2,
	EARGRAB = 3,
	EAT = 4,
	GLASSESGRAB = 5,
	HATGRAB = 6,
	EARSCRATCH = 7,
	HEADSCRATCH = 8,
	LIPSCRATCH = 9,
	EYESCRATCH = 10,
	SWIPE_LEFT = 11,
	SWIPE_RIGHT = 12,
	SWIPE_UP = 13,
	SWIPE_DOWN = 14,
	SNATCH = 15,
	GRIP_COMPONENT = 16,
	CHESTGRAB = 17,
	BLOCK = 18,
	STOP = 19,
	STOP_TWO_HANDED = 20,
	PUSH = 21,
	PUSH_TWO_HANDED = 22,
	FLICK = 23,
	FLICK_UP = 24,
	SWING = 25,
}

local parametersFileName = "gesture_parameters"
local parameters = {
	punch = {
		minThresholdSpeed = 180,       -- min hand speed to count as a punch
		maxThresholdSpeed = 320,       -- speed that maps to full strength (0-1); not a gate
		forwardDotThreshold = 0.75,    -- how strongly motion must align with controller aim
		cooldownTime = 0.8,            -- seconds before another punch can fire
	},
	swipe = {
		minThresholdSpeed = 180,       -- min hand speed to count as a swipe/snatch
		maxThresholdSpeed = 320,       -- speed that maps to full strength (0-1); not a gate
		directionThreshold = 0.001,    -- how strongly motion must favor one swipe axis
		cooldownTime = 0.5,            -- seconds before another swipe can fire
		snapTurnYawThreshold = 45.0,   -- ignore motion if view yaw jumps more than this (deg)
	},
	-- A stroke ends at sustained rest or deliberate reversal, not at a start-speed dip.
	swing = {
		minThresholdSpeed = 180,
		maxThresholdSpeed = 320,
		stopThresholdSpeed = 50,
		stopHoldTime = 0.08,
		reversalDotThreshold = -0.5,
		reversalMinDistance = 5,
		snapTurnYawThreshold = 45.0,
	},
	-- Rapid tip-direction change (wrist snap). Strength from peak angular speed.
	flick = {
		minThresholdAngleSpeed = 400,
		maxThresholdAngleSpeed = 900,
		upMinThresholdAngleSpeed = 400,
		upMaxThresholdAngleSpeed = 900,
		minAngleDelta = 40.0,
		upDotThreshold = 0.75,
		cooldownTime = 0.5,
	},
	holster = {
		triggerAngle = -60.0,
	},
	reload = {
		triggerDistance = 20.0,
	},
	chest = {
		triggerDistance = 15.0,
		offsetZ = -35.0,
		offsetForward = 5.0,
		triggerThreshold = 128,
	},
	-- Sustained pose: arm raised in front, forearm across body, palm facing away.
	-- releaseSlack loosens all checks when leaving the pose (hysteresis).
	-- Defaults tuned from a live ideal left-hand block sample.
	block = {
		maxDropCm = 45.0,       -- hand may be this far below the head
		maxRaiseCm = 10.0,      -- hand may be this far above the head
		inFront = 0.75,        -- 0 = anywhere, 1 = straight ahead of head
		maxPointForward = 0.6,  -- how much the controller may aim at the view (lower = more across-body)
		maxTiltDeg = 58.0,      -- max controller pitch from horizontal (wrist tilt OK)
		palmFacing = 0.5,       -- palm-out = controller right · look (left); mirrored on right
		releaseSlack = 0.25,    -- 0 = snap off, 1 = very sticky release
	},
	-- Palm-out halt: hand in front within reach, palm facing out (looser than block).
	stop = {
		maxDropCm = 45.0,
		maxRaiseCm = 10.0,
		inFront = 0.65,
		minDistanceCm = 15.0,
		maxDistanceCm = 85.0,
		palmFacing = 0.45,
		maxTiltDeg = 65.0,
		releaseSlack = 0.25,
	},
	-- Stop pose + shove along look-forward (not controller aim).
	push = {
		minThresholdSpeed = 180,
		maxThresholdSpeed = 320,
		awayDotThreshold = 0.65,
		cooldownTime = 0.8,
		twoHandedSyncWindow = 0.35,
	},
	face = {
		triggerThreshold = 128,
		mouth = {
			triggerDistance = 25.0,
			forwardDotMaxThreshold = 0.65,
			forwardDotMinThreshold = 0.35,
		},
		head = {
			triggerDistance = 25.0,
			forwardDotMaxThreshold = 0.65,
			forwardDotMinThreshold = 0.0,
		},
		eyes = {
			triggerDistance = 23.0,
			forwardDotThreshold = 0.85,
		},
		ear = {
			triggerDistance = 25.0,
			forwardDotThreshold = 0.8,
		},
	},
	componentGrab = {
		maxDistance = 10.0,
	},
}

local paramManager = paramModule.new(parametersFileName, parameters, true)
local gestureConfig = nil
local gestureConfigDev = nil

local currentLogLevel = LogLevel.Error
-- Set while Dev Config Test is active; used to gate test-only input fallbacks.
local gestureTestId = nil
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[gestures] " .. text, logLevel)
	end
end

local function getParameter(key)
	return paramManager:getFromActiveProfile(key)
end

local function setParameter(key, value, persist)
	return paramManager:setInActiveProfile(key, value, persist)
end

local function getNestedDefault(path)
	local cur = parameters
	for i = 1, #path do
		if cur == nil then return nil end
		cur = cur[path[i]]
	end
	return cur
end

local function getParam(path)
	local value = getParameter(path)
	if value == nil then
		return getNestedDefault(path)
	end
	return value
end

local holsterMinDownDot = math.sin(math.rad(math.abs(parameters.holster.triggerAngle)))

local autoDetect = {}
local hasPunchGesture = false
local punchStrengthPercent = 0
local hasSwipeLeft = false
local hasSwipeRight = false
local hasSwipeUp = false
local hasSwipeDown = false
local hasSnatch = false
local swipeStrengthPercent = 0
local hasFlick = false
local hasFlickUp = false
local flickStrengthPercent = 0
local useRawControllers = false

local function createPunchDetector()
	return {
		prevLocalPos = nil,
		cooldown = 0,
		minThresholdSpeed = parameters.punch.minThresholdSpeed,
		maxThresholdSpeed = parameters.punch.maxThresholdSpeed,
		forwardDotThreshold = parameters.punch.forwardDotThreshold,
		cooldownTime = parameters.punch.cooldownTime,
		currentPunchSpeed = 0.0
	}
end

-- Per-hand detectors (shared state mixes left/right motion when both are polled).
local punchDetectors = {
	[Handed.Left] = createPunchDetector(),
	[Handed.Right] = createPunchDetector(),
}

local function createPushDetector()
	return {
		prevControllerPos = nil,
		prevPawnPos = nil,
		cooldown = 0,
		peakSpeed = 0,
		minThresholdSpeed = parameters.push.minThresholdSpeed,
		maxThresholdSpeed = parameters.push.maxThresholdSpeed,
		awayDotThreshold = parameters.push.awayDotThreshold,
		cooldownTime = parameters.push.cooldownTime,
	}
end

local pushDetectors = {
	[Handed.Left] = createPushDetector(),
	[Handed.Right] = createPushDetector(),
}
local pushTwoHandedClock = 0
local pendingTwoHandPush = {
	[Handed.Left] = nil,
	[Handed.Right] = nil,
}

local swipeDetectors = {
	[Handed.Left] = {
		prevLocalPos = nil,
		prevPawnYaw = nil,
		cooldown = 0,
		minThresholdSpeed = parameters.swipe.minThresholdSpeed,
		maxThresholdSpeed = parameters.swipe.maxThresholdSpeed,
		directionThreshold = parameters.swipe.directionThreshold,
		cooldownTime = parameters.swipe.cooldownTime,
		peakMotionVector = nil,
		peakSpeed = 0
	},
	[Handed.Right] = {
		prevLocalPos = nil,
		prevPawnYaw = nil,
		cooldown = 0,
		minThresholdSpeed = parameters.swipe.minThresholdSpeed,
		maxThresholdSpeed = parameters.swipe.maxThresholdSpeed,
		directionThreshold = parameters.swipe.directionThreshold,
		cooldownTime = parameters.swipe.cooldownTime,
		peakMotionVector = nil,
		peakSpeed = 0
	}
}

local function createSwingDetector()
	return {
		prevPawnYaw = nil,
		active = false,
		peakSpeed = 0,
		stopElapsed = 0,
		reverseDistance = 0,
		reversePeakSpeed = 0,
		minThresholdSpeed = parameters.swing.minThresholdSpeed,
		maxThresholdSpeed = parameters.swing.maxThresholdSpeed,
		stopThresholdSpeed = parameters.swing.stopThresholdSpeed,
		stopHoldTime = parameters.swing.stopHoldTime,
		reversalDotThreshold = parameters.swing.reversalDotThreshold,
		reversalMinDistance = parameters.swing.reversalMinDistance,
		snapTurnYawThreshold = parameters.swing.snapTurnYawThreshold,
	}
end

local swingDetectors = {
	[Handed.Left] = createSwingDetector(),
	[Handed.Right] = createSwingDetector(),
}

local function createFlickDetector()
	return {
		prevForward = nil,
		cooldown = 0,
		peakAngleSpeed = 0,
		accumulatedAngle = 0,
		endFZ = nil,
		minThresholdAngleSpeed = parameters.flick.minThresholdAngleSpeed,
		maxThresholdAngleSpeed = parameters.flick.maxThresholdAngleSpeed,
		upMinThresholdAngleSpeed = parameters.flick.upMinThresholdAngleSpeed,
		upMaxThresholdAngleSpeed = parameters.flick.upMaxThresholdAngleSpeed,
		minAngleDelta = parameters.flick.minAngleDelta,
		upDotThreshold = parameters.flick.upDotThreshold,
		cooldownTime = parameters.flick.cooldownTime,
	}
end

local flickDetectors = {
	[Handed.Left] = createFlickDetector(),
	[Handed.Right] = createFlickDetector(),
}

-- Raw detection has independent history and stroke state; parameters are shared.
local rawFlickDetectors = {
	[Handed.Left] = createFlickDetector(),
	[Handed.Right] = createFlickDetector(),
}

local function resetRawFlickMotion(detector, requireRest)
	detector.prevForward = nil
	detector.stroke = nil
	detector.prevRawQuat, detector.prevRawPos, detector.rawWindow = nil, nil, nil
	detector.awaitRest = requireRest == true
	detector.pendingUp = nil
	detector.restAnchor = nil
	detector.debugHistory, detector.debugPrevTime = nil, nil
end

local function resetFlickMotion(detector)
	detector.prevForward = nil
	detector.peakAngleSpeed = 0
	detector.accumulatedAngle = 0
	detector.endFZ = nil
	detector.flickDebug = nil
	detector.debugPrevRawForward = nil
	detector.debugPrevTime = nil
	detector.debugHistory = nil
end

-- Only flick detection changes source; all other gestures retain their world-space input.
function M.setUseRawControllers(enabled)
	enabled = enabled == true
	if useRawControllers == enabled then return end
	useRawControllers = enabled
	for _, detector in pairs(flickDetectors) do
		resetFlickMotion(detector)
	end
	for _, detector in pairs(rawFlickDetectors) do
		resetRawFlickMotion(detector, false)
	end
	hasFlick, hasFlickUp, flickStrengthPercent = false, false, 0
end

local function applyDetectorParameters()
	local punchMin = getParam({"punch", "minThresholdSpeed"})
	local punchMax = getParam({"punch", "maxThresholdSpeed"})
	local punchFwd = getParam({"punch", "forwardDotThreshold"})
	local punchCooldown = getParam({"punch", "cooldownTime"})
	for _, detector in pairs(punchDetectors) do
		detector.minThresholdSpeed = punchMin
		detector.maxThresholdSpeed = punchMax
		detector.forwardDotThreshold = punchFwd
		detector.cooldownTime = punchCooldown
	end

	local swipeMin = getParam({"swipe", "minThresholdSpeed"})
	local swipeMax = getParam({"swipe", "maxThresholdSpeed"})
	local swipeDir = getParam({"swipe", "directionThreshold"})
	local swipeCooldown = getParam({"swipe", "cooldownTime"})
	for _, detector in pairs(swipeDetectors) do
		detector.minThresholdSpeed = swipeMin
		detector.maxThresholdSpeed = swipeMax
		detector.directionThreshold = swipeDir
		detector.cooldownTime = swipeCooldown
	end

	local swingMin = getParam({"swing", "minThresholdSpeed"})
	local swingMax = getParam({"swing", "maxThresholdSpeed"})
	for _, detector in pairs(swingDetectors) do
		detector.minThresholdSpeed = swingMin
		detector.maxThresholdSpeed = swingMax
		detector.stopThresholdSpeed = getParam({"swing", "stopThresholdSpeed"})
		detector.stopHoldTime = getParam({"swing", "stopHoldTime"})
		detector.reversalDotThreshold = getParam({"swing", "reversalDotThreshold"})
		detector.reversalMinDistance = getParam({"swing", "reversalMinDistance"})
		detector.snapTurnYawThreshold = getParam({"swing", "snapTurnYawThreshold"})
	end

	local flickMin = getParam({"flick", "minThresholdAngleSpeed"})
	local flickMax = getParam({"flick", "maxThresholdAngleSpeed"})
	local flickUpMin = getParam({"flick", "upMinThresholdAngleSpeed"})
	local flickUpMax = getParam({"flick", "upMaxThresholdAngleSpeed"})
	local flickAngle = getParam({"flick", "minAngleDelta"})
	local flickUp = getParam({"flick", "upDotThreshold"})
	local flickCooldown = getParam({"flick", "cooldownTime"})
	for _, detectors in ipairs({flickDetectors, rawFlickDetectors}) do
		for _, detector in pairs(detectors) do
			detector.minThresholdAngleSpeed = flickMin
			detector.maxThresholdAngleSpeed = flickMax
			detector.upMinThresholdAngleSpeed = flickUpMin
			detector.upMaxThresholdAngleSpeed = flickUpMax
			detector.minAngleDelta = flickAngle
			detector.upDotThreshold = flickUp
			detector.cooldownTime = flickCooldown
		end
	end

	local pushMin = getParam({"push", "minThresholdSpeed"})
	local pushMax = getParam({"push", "maxThresholdSpeed"})
	local pushAway = getParam({"push", "awayDotThreshold"})
	local pushCooldown = getParam({"push", "cooldownTime"})
	for _, detector in pairs(pushDetectors) do
		detector.minThresholdSpeed = pushMin
		detector.maxThresholdSpeed = pushMax
		detector.awayDotThreshold = pushAway
		detector.cooldownTime = pushCooldown
	end

	local holsterAngle = getParam({"holster", "triggerAngle"})
	---@diagnostic disable-next-line: param-type-mismatch
	holsterMinDownDot = math.sin(math.rad(math.abs(holsterAngle)))
end

local function saveParameter(key, value, persist, noCallbacks)
	setParameter(key, value, persist)
	applyDetectorParameters()
	if not (noCallbacks == true) then
		uevrUtils.executeUEVRCallbacks("on_gesture_config_param_change", key, value, persist)
	end
end

local createConfigMonitor = doOnce(function()
	uevrUtils.registerUEVRCallback("on_gesture_config_param_change", function(key, value, persist)
		saveParameter(key, value, persist, true)
	end)
end, Once.EVER)

local function rotationToForwardVector(rot)
	local pitchRad = math.rad(rot.Pitch)
	local yawRad = math.rad(rot.Yaw)
	return {
		X = math.cos(pitchRad) * math.cos(yawRad),
		Y = math.cos(pitchRad) * math.sin(yawRad),
		Z = math.sin(pitchRad)
	}
end

local function subtract(a, b)
	return { X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }
end

local function magnitude(v)
	return math.sqrt(v.X*v.X + v.Y*v.Y + v.Z*v.Z)
end

local function normalize(v)
	local mag = magnitude(v)
	if mag == 0 then return {X=0, Y=0, Z=0} end
	return { X = v.X / mag, Y = v.Y / mag, Z = v.Z / mag }
end

local function dot(a, b)
	return a.X*b.X + a.Y*b.Y + a.Z*b.Z
end

-- Rotate a vector by negative yaw to get local space
local function rotateVectorInverseYaw(vec, yawDeg)
	local yawRad = -math.rad(yawDeg)
	local cosY = math.cos(yawRad)
	local sinY = math.sin(yawRad)
	return {
		X = vec.X * cosY - vec.Y * sinY,
		Y = vec.X * sinY + vec.Y * cosY,
		Z = vec.Z -- Z remains unchanged for yaw-only
	}
end

local function getLocalForwardVector(controllerRot, pawnRot)
	return rotationToForwardVector({
		Pitch = controllerRot.Pitch,
		Yaw = controllerRot.Yaw - pawnRot.Yaw,
		Roll = controllerRot.Roll
	})
end

-- Get controller position relative to pawn
local function getLocalControllerPos(controllerPos, pawnPos, pawnRot)
	local offset = subtract(controllerPos, pawnPos)
	return rotateVectorInverseYaw(offset, pawnRot.Yaw)
end

local function getSpeedPercent(speed, minThresholdSpeed, maxThresholdSpeed)
	if maxThresholdSpeed == minThresholdSpeed then
		return 0 -- avoid division by zero
	end
	local clampedSpeed = math.max(minThresholdSpeed, math.min(speed, maxThresholdSpeed))
	return (clampedSpeed - minThresholdSpeed) / (maxThresholdSpeed - minThresholdSpeed)
end

local function updatePunchDetector(self, controllerPos, controllerRot, pawnPos, pawnRot, deltaTime)
	if self.cooldown > 0 then
		self.cooldown = self.cooldown - deltaTime
		self.prevLocalPos = getLocalControllerPos(controllerPos, pawnPos, pawnRot)
		return false, 0, 0
	end

	if not self.prevLocalPos then
		self.prevLocalPos = getLocalControllerPos(controllerPos, pawnPos, pawnRot)
		return false, 0, 0
	end

	local localPos = getLocalControllerPos(controllerPos, pawnPos, pawnRot)

	local localDelta = subtract(localPos, self.prevLocalPos)
	local speed = magnitude(localDelta) / deltaTime
	local forward = getLocalForwardVector(controllerRot, pawnRot)
	local motionDir = normalize(localDelta)
	local forwardDot = dot(forward, motionDir)

	local isPunch = false
	local punchSpeed = 0
	local punchSpeedPercent = 0
	local punchDetected = speed > self.minThresholdSpeed and forwardDot > self.forwardDotThreshold
	if self.currentPunchSpeed > 0 or punchDetected then
		if speed > self.currentPunchSpeed then
			self.currentPunchSpeed = speed
		else
			isPunch = true
			punchSpeed = self.currentPunchSpeed
			punchSpeedPercent = getSpeedPercent(punchSpeed, self.minThresholdSpeed, self.maxThresholdSpeed)
			self.currentPunchSpeed = 0
		end
	end

	if isPunch then
		self.cooldown = self.cooldownTime
	end

	self.prevLocalPos = localPos

	return isPunch, punchSpeedPercent, punchSpeed
end

local function updateSwipeDetector(self, controllerPos, controllerRot, pawnPos, pawnRot, deltaTime)
	local localPos = getLocalControllerPos(controllerPos, pawnPos, pawnRot)

	if self.cooldown > 0 then
		self.cooldown = self.cooldown - deltaTime
		self.prevLocalPos = localPos
		self.prevPawnYaw = pawnRot.Yaw
		return false, false, false, false, false, false, 0
	end

	if not self.prevLocalPos or self.prevPawnYaw == nil then
		self.prevLocalPos = localPos
		self.prevPawnYaw = pawnRot.Yaw
		return false, false, false, false, false, false, 0
	end

	-- Reset on large yaw jumps (teleport / wrap glitch); stick turns are handled by local space
	local yawDeltaRaw = pawnRot.Yaw - self.prevPawnYaw
	local yawDeltaWrapped = math.abs(((yawDeltaRaw + 180) % 360) - 180)
	local snapTurnYawThreshold = getParam({"swipe", "snapTurnYawThreshold"})
	if yawDeltaWrapped > snapTurnYawThreshold then
		self.prevLocalPos = localPos
		self.prevPawnYaw = pawnRot.Yaw
		self.peakSpeed = 0
		self.peakMotionVector = nil
		return false, false, false, false, false, false, 0
	end

	local localDelta = subtract(localPos, self.prevLocalPos)
	local speed = magnitude(localDelta) / deltaTime
	local motionDir = normalize(localDelta)

	local isSwipeLeft = false
	local isSwipeRight = false
	local isSwipeUp = false
	local isSwipeDown = false
	local isPunch = false
	local isSnatch = false

	local swipeSpeedPercent = 0

	-- Track peak motion during acceleration
	local swipeDetected = false
	if speed > self.minThresholdSpeed then
		if speed > self.peakSpeed then
			self.peakSpeed = speed
			self.peakMotionVector = motionDir
		end
		swipeDetected = true
	end

	-- Check if movement has peaked and is now slowing down
	if not swipeDetected and self.peakSpeed > 0 and self.peakMotionVector then
		local peakVector = self.peakMotionVector

		if peakVector and peakVector.Y < -self.directionThreshold then
			isSwipeLeft = true
		else
			isSwipeRight = true
		end

		if peakVector and peakVector.Z > self.directionThreshold then
			isSwipeUp = true
		else
			isSwipeDown = true
		end

		if peakVector and math.abs(peakVector.X) > self.directionThreshold then
			if peakVector.X > 0 then
				isPunch = true
			else
				isSnatch = true
			end
		end

		swipeSpeedPercent = getSpeedPercent(self.peakSpeed, self.minThresholdSpeed, self.maxThresholdSpeed)

		self.peakSpeed = 0
		self.peakMotionVector = nil
	end

	if isSwipeLeft or isSwipeRight or isSwipeUp or isSwipeDown or isPunch or isSnatch then
		self.cooldown = self.cooldownTime
	end

	self.prevLocalPos = localPos
	self.prevPawnYaw = pawnRot.Yaw

	return isSwipeLeft, isSwipeRight, isSwipeUp, isSwipeDown, isPunch, isSnatch, swipeSpeedPercent
end

local function clearSwingMotion(self)
	self.active = false
	self.peakSpeed = 0
	self.directionX, self.directionY, self.directionZ = nil, nil, nil
	self.stopElapsed = 0
	self.reverseDistance = 0
	self.reversePeakSpeed = 0
end

-- Start speed arms a stroke. Only sustained rest or confirmed reverse travel
-- ends it, so speed fluctuations cannot split one continuing stroke.
local function updateSwingDetector(self, controllerPos, pawnPos, pawnRot, deltaTime)
	-- Scalar pose history avoids allocating vectors/tables on every engine tick.
	local offsetX, offsetY = controllerPos.X - pawnPos.X, controllerPos.Y - pawnPos.Y
	local yaw = pawnRot.Yaw
	local yawRad = -yaw * math.pi / 180
	local cosYaw, sinYaw = math.cos(yawRad), math.sin(yawRad)
	local x = offsetX * cosYaw - offsetY * sinYaw
	local y = offsetX * sinYaw + offsetY * cosYaw
	local z = controllerPos.Z - pawnPos.Z
	local prevX, prevY, prevZ, prevYaw = self.prevLocalX, self.prevLocalY, self.prevLocalZ, self.prevPawnYaw
	self.prevLocalX, self.prevLocalY, self.prevLocalZ, self.prevPawnYaw = x, y, z, yaw
	local began, ended = false, false
	local endedStrength
	if deltaTime <= 0 or deltaTime > 0.1 then
		ended = self.active
		endedStrength = getSpeedPercent(self.peakSpeed, self.minThresholdSpeed, self.maxThresholdSpeed)
		clearSwingMotion(self)
		return false, ended, endedStrength, false, endedStrength
	end

	if prevX == nil or prevYaw == nil then
		return false, false, 0, self.active
	end

	local yawDeltaRaw = yaw - prevYaw
	local yawDeltaWrapped = math.abs(((yawDeltaRaw + 180) % 360) - 180)
	if yawDeltaWrapped > self.snapTurnYawThreshold then
		ended = self.active
		endedStrength = getSpeedPercent(self.peakSpeed, self.minThresholdSpeed, self.maxThresholdSpeed)
		clearSwingMotion(self)
		return false, ended, endedStrength, false, endedStrength
	end

	local dx, dy, dz = x - prevX, y - prevY, z - prevZ
	local distanceSquared = dx * dx + dy * dy + dz * dz
	local stopSpeed = math.min(self.stopThresholdSpeed, self.minThresholdSpeed)
	-- Idle and rest frames need no square root or direction normalization.
	if not self.active and distanceSquared <= (self.minThresholdSpeed * deltaTime) ^ 2 then
		return false, false, 0, false
	end
	if self.active and distanceSquared <= (stopSpeed * deltaTime) ^ 2 then
		self.stopElapsed = self.stopElapsed + deltaTime
		if self.stopElapsed >= self.stopHoldTime then
			ended = true
			endedStrength = getSpeedPercent(self.peakSpeed, self.minThresholdSpeed, self.maxThresholdSpeed)
			clearSwingMotion(self)
		end
		local strength = endedStrength or getSpeedPercent(self.peakSpeed, self.minThresholdSpeed, self.maxThresholdSpeed)
		return false, ended, strength, self.active, endedStrength
	end

	local distance = math.sqrt(distanceSquared)
	local speed = distance / deltaTime
	local directionX, directionY, directionZ = dx / distance, dy / distance, dz / distance
	if not self.active then
		self.active = true
		self.peakSpeed = speed
		self.directionX, self.directionY, self.directionZ = directionX, directionY, directionZ
		self.strokeStartX, self.strokeStartY, self.strokeStartZ = prevX, prevY, prevZ
		self.farthestDistanceSquared = distanceSquared
		self.stopElapsed, self.reverseDistance, self.reversePeakSpeed = 0, 0, 0
		began = true
	else
		self.stopElapsed = 0
		local projection = dx * self.directionX + dy * self.directionY + dz * self.directionZ
		if projection / distance <= self.reversalDotThreshold then
			if self.reverseDistance == 0 then
				self.reverseStartX, self.reverseStartY, self.reverseStartZ = prevX, prevY, prevZ
			end
			self.reverseDistance = self.reverseDistance + math.max(0, -projection)
			self.reversePeakSpeed = math.max(self.reversePeakSpeed, speed)
			if self.reverseDistance >= self.reversalMinDistance then
				ended = true
				endedStrength = getSpeedPercent(self.peakSpeed, self.minThresholdSpeed, self.maxThresholdSpeed)
				local reversePeak = self.reversePeakSpeed
				clearSwingMotion(self)
				-- A fast backswing can open immediately after the old stroke closes.
				if speed > self.minThresholdSpeed then
					began = true
					self.active = true
					self.peakSpeed = reversePeak
					self.strokeStartX, self.strokeStartY, self.strokeStartZ = self.reverseStartX, self.reverseStartY, self.reverseStartZ
					local sx, sy, sz = x - self.strokeStartX, y - self.strokeStartY, z - self.strokeStartZ
					self.farthestDistanceSquared = sx * sx + sy * sy + sz * sz
					if self.farthestDistanceSquared > 0 then
						local extent = math.sqrt(self.farthestDistanceSquared)
						self.directionX, self.directionY, self.directionZ = sx / extent, sy / extent, sz / extent
					else
						self.directionX, self.directionY, self.directionZ = directionX, directionY, directionZ
					end
				end
			end
		else
			-- Extend the stroke's outward direction as its reach grows. Following
			-- frame-to-frame tangents would follow a turnaround and hide backswings.
			local sx, sy, sz = x - self.strokeStartX, y - self.strokeStartY, z - self.strokeStartZ
			local extentSquared = sx * sx + sy * sy + sz * sz
			if extentSquared > self.farthestDistanceSquared then
				local extent = math.sqrt(extentSquared)
				self.directionX, self.directionY, self.directionZ = sx / extent, sy / extent, sz / extent
				self.farthestDistanceSquared = extentSquared
			end
			self.reverseDistance = 0
			self.reversePeakSpeed = 0
			self.peakSpeed = math.max(self.peakSpeed, speed)
		end
	end

	local strength = self.active and getSpeedPercent(self.peakSpeed, self.minThresholdSpeed, self.maxThresholdSpeed)
		or endedStrength or 0
	return began, ended, strength, self.active, endedStrength
end

-- Wrist flick: tip angular speed, peak-then-release. Up = tip · world-up at peak.
local function angleBetweenDirections(a, b)
	return math.deg(math.acos(math.max(-1, math.min(1, a.X * b.X + a.Y * b.Y + a.Z * b.Z))))
end

local function updateFlickDetector(self, forward, deltaTime, hand, rawForward)
	local debugEnabled = gestureTestId == M.Gesture.FLICK or gestureTestId == M.Gesture.FLICK_UP
	local rawAngle, clockDelta
	if debugEnabled then
		local now = os.clock()
		clockDelta = self.debugPrevTime and now - self.debugPrevTime or nil
		rawAngle = rawForward and self.debugPrevRawForward and angleBetweenDirections(rawForward, self.debugPrevRawForward) or nil
		self.debugPrevTime, self.debugPrevRawForward = now, rawForward
	else
		self.flickDebug, self.debugPrevTime, self.debugPrevRawForward = nil, nil, nil
		self.debugHistory = nil
	end
	if self.cooldown > 0 then
		self.cooldown = self.cooldown - deltaTime
		self.prevForward = forward
		self.peakAngleSpeed = 0
		self.accumulatedAngle = 0
		self.endFZ = nil
		self.flickDebug = nil
		self.debugHistory = nil
		return false, false, 0
	end

	if self.prevForward == nil then
		self.prevForward = forward
		self.flickDebug = nil
		self.debugHistory = nil
		return false, false, 0
	end

	local d = self.prevForward.X * forward.X + self.prevForward.Y * forward.Y + self.prevForward.Z * forward.Z
	if d > 1 then d = 1 elseif d < -1 then d = -1 end
	local angleDelta = 0
	local angleSpeed = 0
	if deltaTime > 0 then
		angleDelta = math.deg(math.acos(d))
		angleSpeed = angleDelta / deltaTime
	end
	-- Keep every frame, including quiet gaps that currently split a hand movement
	-- into several candidates. Only accepted flicks write this bounded history.
	if debugEnabled then
		local history = self.debugHistory
		if history == nil then
			history = {frames = {}, next = 1, count = 0}
			self.debugHistory = history
		end
		history.frames[history.next] = {
			delta = deltaTime, clockDelta = clockDelta, angle = angleDelta,
			rawAngle = rawAngle, speed = angleSpeed, upDot = forward.Z,
		}
		history.next = history.next % 64 + 1
		history.count = math.min(history.count + 1, 64)
	end

	local isFlick = false
	local isFlickUp = false
	local strengthPercent = 0

	if angleSpeed > math.min(self.minThresholdAngleSpeed, self.upMinThresholdAngleSpeed) then
		if debugEnabled then
			if self.flickDebug == nil then
				self.flickDebug = {startForward = self.prevForward, frames = 0, elapsed = 0}
			end
			local debug = self.flickDebug
			debug.frames, debug.elapsed = debug.frames + 1, debug.elapsed + deltaTime
			if angleSpeed > self.peakAngleSpeed then
				debug.peakFrameAngle, debug.peakFrameDelta = angleDelta, deltaTime
				debug.peakRawAngle, debug.peakClockDelta = rawAngle, clockDelta
			end
		end
		if angleSpeed > self.peakAngleSpeed then
			self.peakAngleSpeed = angleSpeed
			self.endFZ = forward.Z
		end
		self.accumulatedAngle = self.accumulatedAngle + angleDelta
	elseif self.peakAngleSpeed > 0 then
		local up = self.endFZ >= self.upDotThreshold
		local minSpeed = up and self.upMinThresholdAngleSpeed or self.minThresholdAngleSpeed
		local maxSpeed = up and self.upMaxThresholdAngleSpeed or self.maxThresholdAngleSpeed
		if self.accumulatedAngle >= self.minAngleDelta then
			if self.peakAngleSpeed > minSpeed then
				strengthPercent = getSpeedPercent(self.peakAngleSpeed, minSpeed, maxSpeed)
				isFlickUp = up
				isFlick = not up
			end
		end
		-- One report per completed candidate, only while the dev flick test is enabled.
		if debugEnabled then
			local debug = self.flickDebug
			if debug then debug.netAngle = angleBetweenDirections(debug.startForward, self.prevForward) end
			local frames
			if isFlick or isFlickUp then
				frames = {}
				local history = self.debugHistory
				for i = 1, history.count do
					frames[i] = history.frames[(history.next - history.count + i - 2) % 64 + 1]
				end
			end
			uevrUtils.executeUEVRCallbacks("on_gesture_flick_sample", {
				source = useRawControllers and "Raw" or "World",
				up = up,
				accepted = isFlick or isFlickUp,
				peakSpeed = self.peakAngleSpeed,
				minSpeed = minSpeed,
				angle = self.accumulatedAngle,
				minAngle = self.minAngleDelta,
				details = debug,
				frames = frames,
			}, hand)
		end
		self.peakAngleSpeed = 0
		self.accumulatedAngle = 0
		self.endFZ = nil
		self.flickDebug = nil
	end

	if isFlick or isFlickUp then
		self.cooldown = self.cooldownTime
	end

	self.prevForward = forward
	return isFlick, isFlickUp, strengthPercent
end

-- Raw wrist strokes: full quaternion rotation and tracking-space hand movement.
-- Tracking Y is up. There is no headset, pawn, or world-component dependency.
local RAW_FLICK_WINDOW = 0.05
local RAW_FLICK_REARM_SPEED = 250 -- deg/s, independent of the sensitivity setting
local RAW_FLICK_MAX_TIME = 0.4
local RAW_FLICK_GAP = 0.04
-- Up flicks are not time sensitive; they wait this long for a down flick that would
-- show them to be the wind-up before it.
local RAW_FLICK_UP_CONFIRM = 0.5
-- A down stroke this much weaker than a pending up flick is that flick's recovery.
local RAW_FLICK_RECOVERY_RATIO = 0.75
-- Seconds between aim offset requests while the plugin cannot supply one.
local RAW_FLICK_AIM_RETRY = 2.0

local function rawRotationStep(previous, current)
	-- current * inverse(previous), expressed in the fixed tracking frame.
	local x, y, z, w = current.X, current.Y, current.Z, current.W
	local px, py, pz, pw = previous.X, previous.Y, previous.Z, previous.W
	local dx = -w*px + x*pw - y*pz + z*py
	local dy = -w*py + x*pz + y*pw - z*px
	local dz = -w*pz - x*py + y*px + z*pw
	local dw = w*pw + x*px + y*py + z*pz
	if dw < 0 then dx, dy, dz, dw = -dx, -dy, -dz, -dw end
	local length = math.sqrt(dx*dx + dy*dy + dz*dz)
	if length < 1e-10 then return 0, 0, 0, 0 end
	local angle = math.deg(2 * math.atan(length, dw))
	local scale = angle / length
	return dx*scale, dy*scale, dz*scale, angle
end

local function getRawAimAxis(grip, offset)
	-- The controller points along the aim pose's -Z; aim = grip * offset.
	local x, y, z, w = grip.X, grip.Y, grip.Z, grip.W
	local ox, oy, oz, ow = offset.X, offset.Y, offset.Z, offset.W
	local ax = w*ox + x*ow + y*oz - z*oy
	local ay = w*oy - x*oz + y*ow + z*ox
	local az = w*oz + x*oy - y*ox + z*ow
	local aw = w*ow - x*ox - y*oy - z*oz
	return -2 * (ax*az + aw*ay), -2 * (ay*az - aw*ax), 2 * (ax*ax + ay*ay) - 1
end

local function removeRawRoll(kx, ky, kz, ax, ay, az)
	-- Rotation about the pointing axis is a roll, not a flick.
	local d = ax*kx + ay*ky + az*kz
	ax, ay, az = ax - d*kx, ay - d*ky, az - d*kz
	return ax, ay, az, math.sqrt(ax*ax + ay*ay + az*az)
end

local function rawSwingAngle(start, current, kx, ky, kz)
	-- current * inverse(start) with its twist about the start pointing axis removed;
	-- the remaining swing's scalar part is |(w, p)|.
	local x, y, z, w = current.X, current.Y, current.Z, current.W
	local px, py, pz, pw = start.X, start.Y, start.Z, start.W
	local dx = -w*px + x*pw - y*pz + z*py
	local dy = -w*py + x*pz + y*pw - z*px
	local dz = -w*pz - x*py + y*px + z*pw
	local dw = w*pw + x*px + y*py + z*pz
	local p = dx*kx + dy*ky + dz*kz
	return math.deg(2 * math.acos(math.min(1, math.sqrt(dw*dw + p*p))))
end

local function rawImpulseWindow(self, frame)
	local window = self.rawWindow or {frames = {}, next = 1, count = 0}
	self.rawWindow = window
	window.frames[window.next] = frame
	window.next, window.count = window.next % 64 + 1, math.min(window.count + 1, 64)
	local remaining, elapsed, ax, ay, az, dx, dy, dz = RAW_FLICK_WINDOW, 0, 0, 0, 0, 0, 0, 0
	for i = 1, window.count do
		local f = window.frames[(window.next - i - 1) % 64 + 1]
		local duration = math.min(f.delta, remaining)
		local weight = duration / f.delta
		ax, ay, az = ax + f.ax*weight, ay + f.ay*weight, az + f.az*weight
		dx, dy, dz = dx + f.dx*weight, dy + f.dy*weight, dz + f.dz*weight
		elapsed, remaining = elapsed + duration, remaining - duration
		if remaining < 1e-6 then break end
	end
	local distance = math.sqrt(dx*dx + dy*dy + dz*dz)
	return math.sqrt(ax*ax + ay*ay + az*az) / elapsed, dy / elapsed, elapsed,
		distance > 1e-8 and dy / distance or 0
end

local function reportRawFlick(self, stroke, speed, minSpeed, windowTime, alignment, hand)
	if gestureTestId ~= M.Gesture.FLICK and gestureTestId ~= M.Gesture.FLICK_UP then return end
	local frames, history = {}, self.debugHistory
	if history then
		for i = 1, history.count do
			frames[i] = history.frames[(history.next - history.count + i - 2) % 64 + 1]
		end
	end
	uevrUtils.executeUEVRCallbacks("on_gesture_flick_sample", {
		source = "Raw", speedLabel = "rotation window peak", up = stroke.direction > 0, accepted = true,
		peakSpeed = speed, minSpeed = minSpeed, angle = stroke.netAngle, minAngle = self.minAngleDelta,
		details = {
			peakFrameAngle = stroke.peakFrameAngle, peakFrameDelta = stroke.peakFrameDelta,
			peakRawAngle = stroke.peakFrameAngle, peakClockDelta = stroke.peakClockDelta,
			frames = stroke.frames, elapsed = stroke.elapsed, netAngle = stroke.netAngle,
			pathAngle = stroke.pathAngle, qualifiedAngle = stroke.netAngle,
			windowSpeed = speed, windowTime = windowTime, alignment = alignment,
			verticalTravelCm = stroke.dy * 100, verticalSpeedCm = stroke.verticalSpeed * 100,
			motionUpDot = stroke.motionUpDot,
		}, frames = frames,
	}, hand)
end

local function confirmRawFlickUp(self, hand)
	local pending = self.pendingUp
	self.pendingUp, self.stroke, self.awaitRest = nil, nil, true
	self.cooldown = self.cooldownTime
	reportRawFlick(self, pending.stroke, pending.stroke.peakSpeed, pending.minSpeed, pending.windowTime, pending.alignment, hand)
	return false, true, pending.strength
end

local function updateRawFlickDetector(self, position, quat, deltaTime, hand)
	if type(deltaTime) ~= "number" or not (deltaTime > 0 and deltaTime <= 0.1) then
		resetRawFlickMotion(self, true)
		return false, false, 0
	end
	self.cooldown = math.max(0, self.cooldown - deltaTime)
	local qnorm = math.sqrt(quat.X*quat.X + quat.Y*quat.Y + quat.Z*quat.Z + quat.W*quat.W)
	if not (qnorm > 1e-8 and qnorm < math.huge)
		or not (math.abs(position.X) < math.huge and math.abs(position.Y) < math.huge and math.abs(position.Z) < math.huge) then
		resetRawFlickMotion(self, true)
		return false, false, 0
	end
	local current = {X = quat.X/qnorm, Y = quat.Y/qnorm, Z = quat.Z/qnorm, W = quat.W/qnorm}
	local previous, previousPos = self.prevRawQuat, self.prevRawPos
	-- Copy the get_pose out-arguments: they are reused for both hands on the next call.
	self.prevRawQuat = current
	self.prevRawPos = {X = position.X, Y = position.Y, Z = position.Z}
	if previous == nil or previousPos == nil then return false, false, 0 end
	local ax, ay, az, angle = rawRotationStep(previous, current)
	local dx, dy, dz = position.X-previousPos.X, position.Y-previousPos.Y, position.Z-previousPos.Z
	if angle > 120 or dx*dx + dy*dy + dz*dz > 0.25 then
		-- Tracking discontinuities cannot finish an existing stroke.
		resetRawFlickMotion(self, true)
		return false, false, 0
	end
	local offset = self.aimOffset
	if offset then
		local kx, ky, kz = getRawAimAxis(current, offset)
		ax, ay, az, angle = removeRawRoll(kx, ky, kz, ax, ay, az)
	end
	if self.rawMin ~= self.minThresholdAngleSpeed or self.rawUpMin ~= self.upMinThresholdAngleSpeed
		or self.rawAngle ~= self.minAngleDelta or self.rawUpDot ~= self.upDotThreshold then
		self.stroke, self.rawWindow = nil, nil
		self.rawMin, self.rawUpMin = self.minThresholdAngleSpeed, self.upMinThresholdAngleSpeed
		self.rawAngle, self.rawUpDot = self.minAngleDelta, self.upDotThreshold
	end
	local speed, verticalSpeed, windowTime, motionUpDot = rawImpulseWindow(self, {
		ax = ax, ay = ay, az = az, dx = dx, dy = dy, dz = dz, delta = deltaTime,
	})
	local clockDelta
	if gestureTestId == M.Gesture.FLICK or gestureTestId == M.Gesture.FLICK_UP then
		local now = os.clock()
		clockDelta, self.debugPrevTime = self.debugPrevTime and now - self.debugPrevTime or nil, now
		local history = self.debugHistory or {frames = {}, next = 1, count = 0}
		self.debugHistory = history
		history.frames[history.next] = {
			delta = deltaTime, clockDelta = clockDelta, angle = angle, rawAngle = angle,
			speed = speed, upDot = motionUpDot, verticalSpeedCm = verticalSpeed * 100,
		}
		history.next, history.count = history.next % 64 + 1, math.min(history.count + 1, 64)
	else
		self.debugHistory, self.debugPrevTime = nil, nil
	end
	-- Suppress the whole recovery after recognition. Sensitivity must not define rearming.
	-- Rapid flicks rarely come to a full rest, so rearm once the hand slows or rises;
	-- a rising wind-up can only start a pending up flick, which a down flick overrides.
	if self.awaitRest then
		if self.cooldown <= 0 and (speed < RAW_FLICK_REARM_SPEED or verticalSpeed > 0) then
			self.awaitRest, self.stroke, self.rawWindow = false, nil, nil
		end
		return false, false, 0
	end
	local pending = self.pendingUp
	if pending then
		pending.age = pending.age + deltaTime
		if pending.age > RAW_FLICK_UP_CONFIRM then
			return confirmRawFlickUp(self, hand)
		end
	end
	local direction = verticalSpeed > 0 and 1 or -1
	local minSpeed = direction > 0 and self.upMinThresholdAngleSpeed or self.minThresholdAngleSpeed
	local stroke = self.stroke
	if speed <= minSpeed then
		if stroke then
			stroke.gap = stroke.gap + deltaTime
			if stroke.gap > RAW_FLICK_GAP then self.stroke = nil end
		end
		return false, false, 0
	end
	if stroke == nil or stroke.direction ~= direction then
		stroke = {direction = direction, elapsed = 0, gap = 0, frames = 0, startQuat = previous,
			ax = 0, ay = 0, az = 0, dx = 0, dy = 0, dz = 0, pathAngle = 0, peakSpeed = 0}
		if offset then
			stroke.rollX, stroke.rollY, stroke.rollZ = getRawAimAxis(previous, offset)
		end
		self.stroke = stroke
	end
	stroke.gap, stroke.elapsed = 0, stroke.elapsed + deltaTime
	if stroke.elapsed > RAW_FLICK_MAX_TIME then
		self.stroke = nil
		return false, false, 0
	end
	stroke.ax, stroke.ay, stroke.az = stroke.ax+ax, stroke.ay+ay, stroke.az+az
	stroke.dx, stroke.dy, stroke.dz = stroke.dx+dx, stroke.dy+dy, stroke.dz+dz
	stroke.pathAngle = stroke.pathAngle + angle
	if angle > 0.25 then stroke.frames = stroke.frames + 1 end
	if stroke.rollX then
		stroke.netAngle = rawSwingAngle(stroke.startQuat, current, stroke.rollX, stroke.rollY, stroke.rollZ)
	else
		local _, _, _, netAngle = rawRotationStep(stroke.startQuat, current)
		stroke.netAngle = netAngle
	end
	local directedAngle = math.sqrt(stroke.ax*stroke.ax + stroke.ay*stroke.ay + stroke.az*stroke.az)
	local alignment = stroke.pathAngle > 0 and directedAngle / stroke.pathAngle or 0
	local distance = math.sqrt(stroke.dx*stroke.dx + stroke.dy*stroke.dy + stroke.dz*stroke.dz)
	stroke.motionUpDot = distance > 1e-8 and stroke.dy / distance or 0
	stroke.verticalSpeed = verticalSpeed
	if windowTime >= RAW_FLICK_WINDOW - 1e-6 and speed > stroke.peakSpeed then
		stroke.peakSpeed, stroke.peakFrameAngle = speed, angle
		stroke.peakFrameDelta, stroke.peakClockDelta = deltaTime, clockDelta
	end
	-- Translation supplies direction, not flick strength. A small displacement
	-- floor excludes stationary-controller rotation and submillimetre pose jitter.
	local motionAllowed = stroke.dy * direction >= 0.005
	local upAllowed = direction < 0 or stroke.motionUpDot >= self.upDotThreshold
	if windowTime >= RAW_FLICK_WINDOW - 1e-6
		and stroke.frames >= 2 and stroke.netAngle >= self.minAngleDelta and alignment >= 0.65
		and motionAllowed and upAllowed and self.cooldown <= 0 then
		local maxSpeed = direction > 0 and self.upMaxThresholdAngleSpeed or self.maxThresholdAngleSpeed
		local strength = maxSpeed <= minSpeed and 1 or getSpeedPercent(stroke.peakSpeed, minSpeed, maxSpeed)
		if direction > 0 then
			if pending == nil or stroke.peakSpeed > pending.stroke.peakSpeed then
				self.pendingUp = {stroke = stroke, strength = strength, minSpeed = minSpeed,
					windowTime = windowTime, alignment = alignment, age = pending and pending.age or 0}
			end
			self.stroke = nil
			return false, false, 0
		end
		if pending and stroke.peakSpeed < pending.stroke.peakSpeed * RAW_FLICK_RECOVERY_RATIO then
			return confirmRawFlickUp(self, hand)
		end
		-- Down flicks are time sensitive and report immediately, discarding a pending wind-up.
		self.pendingUp = nil
		reportRawFlick(self, stroke, stroke.peakSpeed, minSpeed, windowTime, alignment, hand)
		self.stroke, self.awaitRest = nil, true
		self.cooldown = self.cooldownTime
		return true, false, strength
	end
	return false, false, 0
end


local holsterGripOn = false
local function detectHolster(state, hand, continuous)
	local gripButton = XINPUT_GAMEPAD_RIGHT_SHOULDER
	if hand == Handed.Left then
		gripButton = XINPUT_GAMEPAD_LEFT_SHOULDER
	end
	if (continuous == true or not holsterGripOn) and uevrUtils.isButtonPressed(state, gripButton) then
		holsterGripOn = true
		-- World-space forward·down is stable under yaw/roll; Euler Pitch alone is not.
		local forward = controllers.getControllerDirection(hand)
		if forward ~= nil and -forward.Z >= holsterMinDownDot then
			return true
		end
	elseif holsterGripOn and uevrUtils.isButtonNotPressed(state, gripButton)  then
		holsterGripOn = false
	end
	return false
end

local reloadGripOn = false
local function detectReload(state, hand, continuous)
	local gripButton = XINPUT_GAMEPAD_LEFT_SHOULDER
	if hand == Handed.Left then
		gripButton = XINPUT_GAMEPAD_RIGHT_SHOULDER
	end
	if (continuous == true or not reloadGripOn) and uevrUtils.isButtonPressed(state, gripButton) then
		reloadGripOn = true
		local gripLocation = controllers.getControllerLocation(1-hand)
		local targetLocation = controllers.getControllerLocation(hand)
		if gripLocation ~= nil and targetLocation ~= nil then
			local distance = magnitude(subtract(gripLocation, targetLocation))
			if distance < getParam({"reload", "triggerDistance"}) then
				return true
			end
		end
	elseif reloadGripOn and uevrUtils.isButtonNotPressed(state, gripButton) then
		reloadGripOn = false
	end
	return false
end

local blockActive = {
	[Handed.Left] = false,
	[Handed.Right] = false,
}
local blockCallbackActive = {
	[Handed.Left] = false,
	[Handed.Right] = false,
}
local chestCallbackActive = {
	[Handed.Left] = false,
	[Handed.Right] = false,
}
local faceCallbackActive = {
	[Handed.Left] = {},
	[Handed.Right] = {},
}
local faceGestureCallbackNames = {
	[M.Gesture.EARGRAB] = "on_gesture_eargrab",
	[M.Gesture.EAT] = "on_gesture_eat",
	[M.Gesture.GLASSESGRAB] = "on_gesture_glassesgrab",
	[M.Gesture.HATGRAB] = "on_gesture_hatgrab",
	[M.Gesture.EARSCRATCH] = "on_gesture_earscratch",
	[M.Gesture.HEADSCRATCH] = "on_gesture_headscratch",
	[M.Gesture.LIPSCRATCH] = "on_gesture_lipscratch",
	[M.Gesture.EYESCRATCH] = "on_gesture_eyescratch",
}

-- Continuous pose: arm raised in front, forearm across body, palm facing away.
local function detectBlock(hand)
	if hand == nil then hand = Handed.Right end

	local headLocation = controllers.getControllerLocation(2)
	local handLocation = controllers.getControllerLocation(hand)
	local headForward = controllers.getControllerDirection(2)
	local handForward = controllers.getControllerDirection(hand)
	local handRight = controllers.getControllerRightVector(hand)
	if headLocation == nil or handLocation == nil or headForward == nil or handForward == nil or handRight == nil then
		blockActive[hand] = false
		return false
	end

	local flatHeadForward = { X = headForward.X, Y = headForward.Y, Z = 0 }
	local flatMag = magnitude(flatHeadForward)
	if flatMag > 0.001 then
		flatHeadForward = { X = flatHeadForward.X / flatMag, Y = flatHeadForward.Y / flatMag, Z = 0 }
	else
		flatHeadForward = headForward
	end

	local maxDropCm = getParam({"block", "maxDropCm"})
	local maxRaiseCm = getParam({"block", "maxRaiseCm"})
	local inFront = getParam({"block", "inFront"})
	local maxPointForward = getParam({"block", "maxPointForward"})
	local maxTiltDeg = getParam({"block", "maxTiltDeg"})
	local palmFacing = getParam({"block", "palmFacing"})
	local slack = math.max(0, math.min(1, getParam({"block", "releaseSlack"}) or 0.25))

	local handOffsetZ = handLocation.Z - headLocation.Z
	local headToHand = normalize(subtract(handLocation, headLocation))
	local frontDot = dot(flatHeadForward, headToHand)
	local headRight = { X = -flatHeadForward.Y, Y = flatHeadForward.X, Z = 0 }
	local sideDot = math.abs(dot(headRight, headToHand))
	local aimDot = math.abs(dot(handForward, flatHeadForward))
	local verticalDot = math.abs(handForward.Z)
	-- Palm facing away: ideal left block has controller-right aligned with look.
	-- Right hand is mirrored (-right · look).
	local palmDot = dot(handRight, flatHeadForward)
	if hand == Handed.Right then
		palmDot = -palmDot
	end
	local maxVerticalDot = math.sin(math.rad(maxTiltDeg or 0))
	-- Keep the hand from sitting out to the side (not exposed in UI; derived from inFront).
	local maxSide = math.sqrt(math.max(0.0, 1.0 - inFront * inFront))

	if not blockActive[hand] then
		if handOffsetZ > -maxDropCm
			and handOffsetZ < maxRaiseCm
			and frontDot > inFront
			and sideDot < maxSide
			and aimDot < maxPointForward
			and verticalDot < maxVerticalDot
			and palmDot > palmFacing then
			blockActive[hand] = true
			return true
		end
		return false
	end

	local heightSlack = 10.0 + slack * 30.0
	local dotSlack = 0.05 + slack * 0.35
	local tiltSlackDeg = 5.0 + slack * 20.0
	if handOffsetZ < -(maxDropCm + heightSlack)
		or handOffsetZ > maxRaiseCm + heightSlack
		or frontDot < inFront - dotSlack
		or sideDot > maxSide + dotSlack
		or aimDot > maxPointForward + dotSlack
		or verticalDot > math.sin(math.rad(maxTiltDeg + tiltSlackDeg))
		or palmDot < palmFacing - dotSlack then
		blockActive[hand] = false
		return false
	end
	return true
end

local stopActive = {
	[Handed.Left] = false,
	[Handed.Right] = false,
}
local stopCallbackActive = {
	[Handed.Left] = false,
	[Handed.Right] = false,
}
local stopTwoHandedCallbackActive = false

local function buildHeadFrame()
	local headLocation = controllers.getControllerLocation(2)
	local headForward = controllers.getControllerDirection(2)
	if headLocation == nil or headForward == nil then
		return nil
	end
	local flatLook = { X = headForward.X, Y = headForward.Y, Z = 0 }
	local flatMag = magnitude(flatLook)
	if flatMag > 0.001 then
		flatLook = { X = flatLook.X / flatMag, Y = flatLook.Y / flatMag, Z = 0 }
	else
		flatLook = headForward
	end
	return {
		head = headLocation,
		look = flatLook,
		right = { X = -flatLook.Y, Y = flatLook.X, Z = 0 },
	}
end

local function stopPoseOk(hand, frame, active)
	if frame == nil then
		return false
	end
	local handLocation = controllers.getControllerLocation(hand)
	local handForward = controllers.getControllerDirection(hand)
	local handRight = controllers.getControllerRightVector(hand)
	if handLocation == nil or handForward == nil or handRight == nil then
		return false
	end

	local maxDropCm = getParam({"stop", "maxDropCm"})
	local maxRaiseCm = getParam({"stop", "maxRaiseCm"})
	local inFront = getParam({"stop", "inFront"})
	local minDistanceCm = getParam({"stop", "minDistanceCm"})
	local maxDistanceCm = getParam({"stop", "maxDistanceCm"})
	local palmFacing = getParam({"stop", "palmFacing"})
	local maxTiltDeg = getParam({"stop", "maxTiltDeg"})
	local slack = math.max(0, math.min(1, getParam({"stop", "releaseSlack"}) or 0.25))

	local handOffsetZ = handLocation.Z - frame.head.Z
	local toHand = subtract(handLocation, frame.head)
	local headToHand = normalize(toHand)
	local forwardDist = dot(frame.look, toHand)
	local frontDot = dot(frame.look, headToHand)
	local sideDot = math.abs(dot(frame.right, headToHand))
	local maxSide = math.sqrt(math.max(0.0, 1.0 - inFront * inFront))
	local verticalDot = math.abs(handForward.Z)
	local maxVerticalDot = math.sin(math.rad(maxTiltDeg or 0))
	local palmDot = dot(handRight, frame.look)
	if hand == Handed.Right then
		palmDot = -palmDot
	end

	if not active then
		return handOffsetZ > -maxDropCm
			and handOffsetZ < maxRaiseCm
			and forwardDist >= minDistanceCm
			and forwardDist <= maxDistanceCm
			and frontDot > inFront
			and sideDot < maxSide
			and verticalDot < maxVerticalDot
			and palmDot > palmFacing
	end

	local heightSlack = 10.0 + slack * 30.0
	local dotSlack = 0.05 + slack * 0.35
	local distSlack = 5.0 + slack * 15.0
	local tiltSlackDeg = 5.0 + slack * 20.0
	return handOffsetZ >= -(maxDropCm + heightSlack)
		and handOffsetZ <= maxRaiseCm + heightSlack
		and forwardDist >= minDistanceCm - distSlack
		and forwardDist <= maxDistanceCm + distSlack
		and frontDot >= inFront - dotSlack
		and sideDot <= maxSide + dotSlack
		and verticalDot <= math.sin(math.rad(maxTiltDeg + tiltSlackDeg))
		and palmDot >= palmFacing - dotSlack
end

local function detectStop(hand, frame)
	if hand == nil then hand = Handed.Right end
	if frame == nil then frame = buildHeadFrame() end
	if frame == nil then
		stopActive[hand] = false
		return false
	end
	local active = stopActive[hand] == true
	if stopPoseOk(hand, frame, active) then
		stopActive[hand] = true
		return true
	end
	stopActive[hand] = false
	return false
end

local function updatePushDetector(self, controllerPos, pawnPos, frame, deltaTime, inStopPose)
	if frame == nil or inStopPose ~= true then
		self.prevControllerPos = controllerPos
		self.prevPawnPos = pawnPos
		self.peakSpeed = 0
		return false, 0
	end
	if self.cooldown > 0 then
		self.cooldown = self.cooldown - deltaTime
		self.prevControllerPos = controllerPos
		self.prevPawnPos = pawnPos
		self.peakSpeed = 0
		return false, 0
	end
	if not self.prevControllerPos or not self.prevPawnPos then
		self.prevControllerPos = controllerPos
		self.prevPawnPos = pawnPos
		return false, 0
	end

	local localDelta = subtract(subtract(controllerPos, self.prevControllerPos), subtract(pawnPos, self.prevPawnPos))
	local speed = magnitude(localDelta) / deltaTime
	local motionDir = normalize(localDelta)
	local awayDot = dot(motionDir, frame.look)

	local isPush = false
	local pushStrength = 0
	local pushing = speed > self.minThresholdSpeed and awayDot > self.awayDotThreshold
	if self.peakSpeed > 0 or pushing then
		if pushing and speed > self.peakSpeed then
			self.peakSpeed = speed
		else
			isPush = self.peakSpeed > self.minThresholdSpeed
			pushStrength = getSpeedPercent(self.peakSpeed, self.minThresholdSpeed, self.maxThresholdSpeed)
			self.peakSpeed = 0
		end
	end
	if isPush then
		self.cooldown = self.cooldownTime
	end

	self.prevControllerPos = controllerPos
	self.prevPawnPos = pawnPos
	return isPush, pushStrength
end

local bodyGripOn = false

local function isVrActionActive(actionPath, hand)
	local vr = uevr and uevr.params and uevr.params.vr
	if vr == nil or vr.get_action_handle == nil or vr.is_action_active == nil then
		return false
	end
	local handle = vr.get_action_handle(actionPath)
	if handle == nil then
		return false
	end

	local source = hand == Handed.Right
		and (vr.get_right_joystick_source and vr.get_right_joystick_source() or nil)
		or (vr.get_left_joystick_source and vr.get_left_joystick_source() or nil)

	-- OpenXR encodes Hand::LEFT as nullptr (Lua nil). Passing numeric 0 crashes;
	-- passing nil lets Sol convert to nullptr = LEFT.
	if source == nil and hand ~= Handed.Left then
		return false
	end

	local ok, active = pcall(function()
		return vr.is_action_active(handle, source)
	end)
	return ok and active == true
end

-- Prefer XInput. During Dev Config Test only, also read OpenXR actions so grip/trigger
-- still work while the UEVR UI has captured gamepad input.
local function getHandGripTrigger(state, hand, triggerThreshold)
	local isGripped, isTriggerred = false, false
	if state ~= nil and state.Gamepad ~= nil then
		if hand == Handed.Right then
			isGripped = uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_RIGHT_SHOULDER)
			isTriggerred = state.Gamepad.bRightTrigger > triggerThreshold
		else
			isGripped = uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_LEFT_SHOULDER)
			isTriggerred = state.Gamepad.bLeftTrigger > triggerThreshold
		end
	end

	if gestureTestId ~= nil then
		if not isGripped then
			isGripped = isVrActionActive("/actions/default/in/Grip", hand)
		end
		if not isTriggerred then
			isTriggerred = isVrActionActive("/actions/default/in/Trigger", hand)
		end
	end
	return isGripped, isTriggerred
end

local function detectBody(state, hand, continuous)
	local gripChest = false

	local triggerThreshold = getParam({"chest", "triggerThreshold"})
	local isGripped, isTriggerred = getHandGripTrigger(state, hand, triggerThreshold)

	if (continuous == true or not bodyGripOn) and (isGripped or isTriggerred) then
		bodyGripOn = true
		local headLocation = controllers.getControllerLocation(2)
		local handLocation = controllers.getControllerLocation(hand)
		if headLocation ~= nil and handLocation ~= nil then
			local headForward = controllers.getControllerDirection(2)
			if headForward ~= nil then
				local chestOffsetForward = getParam({"chest", "offsetForward"})
				local chestOffsetZ = getParam({"chest", "offsetZ"})
				local chestLocation = {
					X = headLocation.X + headForward.X * chestOffsetForward,
					Y = headLocation.Y + headForward.Y * chestOffsetForward,
					Z = headLocation.Z + chestOffsetZ
				}
				local distance = magnitude(subtract(handLocation, chestLocation))
				if distance < getParam({"chest", "triggerDistance"}) then
					gripChest = isGripped
				end
			end
		end
	elseif bodyGripOn and not (isGripped or isTriggerred) then
		bodyGripOn = false
	end
	return gripChest
end

-- Per hand (was one flag for both), so one hand's held grip doesn't block the other hand's "grip started at the head" check.
local headGripOn = {}
local function detectFace(state, hand, continuous)
	local gripMouth, gripEyes, gripHead, gripEar = false, false, false, false
	local triggerMouth, triggerEyes, triggerHead, triggerEar = false, false, false, false

	local triggerThreshold = getParam({"face", "triggerThreshold"})
	local isGripped, isTriggerred = getHandGripTrigger(state, hand, triggerThreshold)

	if (continuous == true or not headGripOn[hand]) and (isGripped or isTriggerred)  then
		headGripOn[hand] = true
		local headLocation = controllers.getControllerLocation(2)
		local handLocation = controllers.getControllerLocation(hand)
		if headLocation ~= nil and handLocation ~= nil then
			local headForwardVector = controllers.getControllerDirection(2)
			local headToHandForwardVector = normalize(subtract(handLocation, headLocation))
			local forwardDot = dot(headForwardVector, headToHandForwardVector)
			local distance = magnitude(subtract(handLocation, headLocation))

			local mouthTriggerDistance = getParam({"face", "mouth", "triggerDistance"})
			local mouthForwardDotMinThreshold = getParam({"face", "mouth", "forwardDotMinThreshold"})
			local mouthForwardDotMaxThreshold = getParam({"face", "mouth", "forwardDotMaxThreshold"})
			local headTriggerDistance = getParam({"face", "head", "triggerDistance"})
			local headForwardDotMinThreshold = getParam({"face", "head", "forwardDotMinThreshold"})
			local headForwardDotMaxThreshold = getParam({"face", "head", "forwardDotMaxThreshold"})
			local eyesTriggerDistance = getParam({"face", "eyes", "triggerDistance"})
			local eyesForwardDotThreshold = getParam({"face", "eyes", "forwardDotThreshold"})
			local earGripTriggerDistance = getParam({"face", "ear", "triggerDistance"})
			local earGripForwardDotThreshold = getParam({"face", "ear", "forwardDotThreshold"})

			if distance < mouthTriggerDistance and forwardDot > mouthForwardDotMinThreshold and forwardDot < mouthForwardDotMaxThreshold and headLocation.Z-handLocation.Z > 0 then
				gripMouth = isGripped
				triggerMouth = isTriggerred
			elseif distance < headTriggerDistance and forwardDot > headForwardDotMinThreshold and forwardDot < headForwardDotMaxThreshold and headLocation.Z-handLocation.Z < 0 then
				gripHead = isGripped
				triggerHead = isTriggerred
			elseif distance < eyesTriggerDistance and forwardDot > eyesForwardDotThreshold then
				gripEyes = isGripped
				triggerEyes = isTriggerred
			end

			local headRightVector = controllers.getControllerRightVector(2)
			forwardDot = dot(headRightVector, headToHandForwardVector) * (hand == Handed.Left and -1 or 1)
			if distance < earGripTriggerDistance and forwardDot > earGripForwardDotThreshold then
				gripEar = isGripped
				triggerEar = isTriggerred
			end

		end
	elseif headGripOn[hand] and not (isGripped or isTriggerred) then
		headGripOn[hand] = false
	end
	return gripMouth, gripEyes, gripHead, gripEar, triggerMouth, triggerEyes, triggerHead, triggerEar
end

function M.getGesture(id)
	if id == M.Gesture.PUNCH then
		 return hasPunchGesture, punchStrengthPercent
	elseif id == M.Gesture.SWIPE_LEFT then
		return hasSwipeLeft, swipeStrengthPercent
	elseif id == M.Gesture.SWIPE_RIGHT then
		return hasSwipeRight, swipeStrengthPercent
	elseif id == M.Gesture.SWIPE_UP then
		return hasSwipeUp, swipeStrengthPercent
	elseif id == M.Gesture.SWIPE_DOWN then
		return hasSwipeDown, swipeStrengthPercent
	elseif id == M.Gesture.SNATCH then
		return hasSnatch, swipeStrengthPercent
	elseif id == M.Gesture.FLICK then
		return hasFlick, flickStrengthPercent
	elseif id == M.Gesture.FLICK_UP then
		return hasFlickUp, flickStrengthPercent
	end
end

function M.detectGesture(id, deltaTime, hand, currentPos, currentRot, pawnPos, pawnRot )
	if hand == nil then hand = Handed.Right end
	if id == M.Gesture.BLOCK then
		return detectBlock(hand)
	elseif id == M.Gesture.STOP then
		return detectStop(hand)
	elseif id == M.Gesture.STOP_TWO_HANDED then
		return detectStop(Handed.Left) and detectStop(Handed.Right)
	elseif id == M.Gesture.PUSH then
		local frame = buildHeadFrame()
		local controllerPos = controllers.getControllerLocation(hand)
		local pawnPos = controllers.getControllerLocation(2)
		if frame == nil or controllerPos == nil or pawnPos == nil then
			return false
		end
		return updatePushDetector(pushDetectors[hand], controllerPos, pawnPos, frame, deltaTime, detectStop(hand, frame))
	end
	if currentPos == nil then
		currentPos = controllers.getControllerLocation(hand)
	end
	if currentRot == nil then
		currentRot = controllers.getControllerRotation(hand)
	end
	if pawnPos == nil then
		pawnPos = controllers.getControllerLocation(2)
	end
	if pawnRot == nil then
		pawnRot = controllers.getControllerRotation(2)
	end
	if currentPos == nil or currentRot == nil or pawnPos == nil or pawnRot == nil then
		M.print("Call to detectGesture() failed because controller was invalid")
		return false
	else
		if id == M.Gesture.PUNCH then
			 hasPunchGesture, punchStrengthPercent = updatePunchDetector(punchDetectors[hand], currentPos, currentRot, pawnPos, pawnRot, deltaTime)
			 return hasPunchGesture, punchStrengthPercent
		elseif id == M.Gesture.SWIPE_LEFT or id == M.Gesture.SWIPE_RIGHT or id == M.Gesture.SWIPE_UP or
		       id == M.Gesture.SWIPE_DOWN or id == M.Gesture.SNATCH then
			hasSwipeLeft, hasSwipeRight, hasSwipeUp, hasSwipeDown, _, hasSnatch, swipeStrengthPercent = updateSwipeDetector(swipeDetectors[hand], currentPos, currentRot, pawnPos, pawnRot, deltaTime)
			if id == M.Gesture.SWIPE_LEFT then
				return hasSwipeLeft, swipeStrengthPercent
			elseif id == M.Gesture.SWIPE_RIGHT then
				return hasSwipeRight, swipeStrengthPercent
			elseif id == M.Gesture.SWIPE_UP then
				return hasSwipeUp, swipeStrengthPercent
			elseif id == M.Gesture.SWIPE_DOWN then
				return hasSwipeDown, swipeStrengthPercent
			elseif id == M.Gesture.SNATCH then
				return hasSnatch, swipeStrengthPercent
			end
		elseif id == M.Gesture.FLICK or id == M.Gesture.FLICK_UP then
			hasFlick, hasFlickUp, flickStrengthPercent = M.getFlickGestures(deltaTime, hand)
			if id == M.Gesture.FLICK then
				return hasFlick, flickStrengthPercent
			end
			return hasFlickUp, flickStrengthPercent
		elseif id == M.Gesture.SWING then
			local began, ended, strength, active = M.getSwingGestures(deltaTime, hand, currentPos, pawnPos, pawnRot)
			return began or ended, strength, began, ended, active
		end
	end
	return false
end

function M.detectGestureWithState(id, state, hand, continuous)
	if id == M.Gesture.HOLSTER then
		return detectHolster(state, hand, continuous)
	elseif id == M.Gesture.RELOAD then
		return detectReload(state, hand, continuous)
	elseif id == M.Gesture.CHESTGRAB then
		local gripChest = detectBody(state, hand, continuous)
		return gripChest
	elseif id == M.Gesture.EAT then
		local gripMouth, gripEyes, gripHead, gripEar, triggerMouth, triggerEyes, triggerHead, triggerEar = detectFace(state, hand, continuous)
		return gripMouth
	elseif id == M.Gesture.GLASSESGRAB then
		local gripMouth, gripEyes, gripHead, gripEar, triggerMouth, triggerEyes, triggerHead, triggerEar = detectFace(state, hand, continuous)
		return gripEyes
	elseif id == M.Gesture.HATGRAB then
		local gripMouth, gripEyes, gripHead, gripEar, triggerMouth, triggerEyes, triggerHead, triggerEar = detectFace(state, hand, continuous)
		return gripHead
	elseif id == M.Gesture.EARGRAB then
		local gripMouth, gripEyes, gripHead, gripEar, triggerMouth, triggerEyes, triggerHead, triggerEar = detectFace(state, hand, continuous)
		return gripEar
	elseif id == M.Gesture.LIPSCRATCH then
		local gripMouth, gripEyes, gripHead, gripEar, triggerMouth, triggerEyes, triggerHead, triggerEar = detectFace(state, hand, continuous)
		return triggerMouth
	elseif id == M.Gesture.EYESCRATCH then
		local gripMouth, gripEyes, gripHead, gripEar, triggerMouth, triggerEyes, triggerHead, triggerEar = detectFace(state, hand, continuous)
		return triggerEyes
	elseif id == M.Gesture.HEADSCRATCH then
		local gripMouth, gripEyes, gripHead, gripEar, triggerMouth, triggerEyes, triggerHead, triggerEar = detectFace(state, hand, continuous)
		return triggerHead
	elseif id == M.Gesture.EARSCRATCH then
		local gripMouth, gripEyes, gripHead, gripEar, triggerMouth, triggerEyes, triggerHead, triggerEar = detectFace(state, hand, continuous)
		return triggerEar
	elseif id == M.Gesture.BLOCK then
		return detectBlock(hand)
	elseif id == M.Gesture.STOP then
		return detectStop(hand)
	elseif id == M.Gesture.STOP_TWO_HANDED then
		return detectStop(Handed.Left) and detectStop(Handed.Right)
	end
end

function M.detectComponentGrab(state, hand, component, maxDistance)
	if component ~= nil then
		if uevrUtils.isButtonPressed(state, hand == Handed.Left and XINPUT_GAMEPAD_LEFT_SHOULDER or XINPUT_GAMEPAD_RIGHT_SHOULDER) then
			local distance = controllers.getDistanceFromController(hand, component)
			if distance ~= nil and distance < (maxDistance or getParam({"componentGrab", "maxDistance"})) then
				return true, distance
			end
		end
	end
	return false, nil
end

function M.getHeadGestures(state, hand, continuous)
	return detectFace(state, hand, continuous)
end

function M.getBodyGestures(state, hand, continuous)
	return detectBody(state, hand, continuous)
end

function M.getSwipeGestures(deltaTime, hand, currentPos, currentRot, pawnPos, pawnRot)
	if hand == nil then hand = Handed.Right end
	if currentPos == nil then
		currentPos = controllers.getControllerLocation(hand)
	end
	if currentRot == nil then
		currentRot = controllers.getControllerRotation(hand)
	end
	if pawnPos == nil then
		pawnPos = controllers.getControllerLocation(2)
	end
	if pawnRot == nil then
		pawnRot = controllers.getControllerRotation(2)
	end
	if currentPos == nil or currentRot == nil or pawnPos == nil or pawnRot == nil then
		return false, false, false, false, false, false, 0
	else
		return updateSwipeDetector(swipeDetectors[hand], currentPos, currentRot, pawnPos, pawnRot, deltaTime)
	end
end

function M.getSwingGestures(deltaTime, hand, currentPos, pawnPos, pawnRot)
	if hand == nil then hand = Handed.Right end
	if currentPos == nil then
		currentPos = controllers.getControllerLocation(hand)
	end
	if pawnPos == nil then
		pawnPos = controllers.getControllerLocation(2)
	end
	if pawnRot == nil then
		pawnRot = controllers.getControllerRotation(2)
	end
	if currentPos == nil or pawnPos == nil or pawnRot == nil then
		return false, false, 0, false
	end
	return updateSwingDetector(swingDetectors[hand], currentPos, pawnPos, pawnRot, deltaTime)
end

-- Lost tracking reports identity pose at (0,0,0). get_pose also needs a quat out-arg.
local flickPosePos = nil
local flickPoseQuat = nil

local function isVrControllerIdentityPose(hand)
	local vr = uevr and uevr.params and uevr.params.vr
	if vr == nil or vr.get_pose == nil then
		return false
	end
	local index = uevrUtils.getControllerIndex(hand)
	if index == nil then
		return false
	end
	if flickPosePos == nil then
		flickPosePos = Vector3f.new(0, 0, 0)
		flickPoseQuat = Quaternionf.new(0, 0, 0, 0)
	end
	vr.get_pose(index, flickPosePos, flickPoseQuat)
	local x, y, z = flickPosePos.X, flickPosePos.Y, flickPosePos.Z
	return (x * x + y * y + z * z) < 1e-8, flickPoseQuat
end

local function rawPoseToForward(quat)
	if quat == nil then return nil end
	local x, y, z, w = quat.X, quat.Y, quat.Z, quat.W
	local normSquared = x * x + y * y + z * z + w * w
	if not (normSquared > 1e-8 and normSquared < math.huge) then
		return nil
	end
	-- Rotate tracking-space forward (0,0,-1) by the raw pose quaternion.
	-- Express it as (-Z,X,Y) so the shared detector's forward.Z is physical up.
	-- No pawn transform, recenter offset, or world controller component is involved.
	return {
		X = 1 - 2 * (x * x + y * y) / normSquared,
		Y = -2 * (x * z + w * y) / normSquared,
		Z = 2 * (w * x - y * z) / normSquared,
	}
end

local function getWorldFlickGestures(deltaTime, hand)
	local detector = flickDetectors[hand]
	local identityPose, quat = isVrControllerIdentityPose(hand)
	if identityPose then
		resetFlickMotion(detector)
		return false, false, 0
	end
	local controller = controllers.getController(hand, true)
	if controller == nil then
		return false, false, 0
	end
	local rot = uevrUtils.getComponentRotation(controller)
	if rot == nil then
		return false, false, 0
	end
	local rawForward
	if gestureTestId == M.Gesture.FLICK or gestureTestId == M.Gesture.FLICK_UP then
		rawForward = rawPoseToForward(quat)
	end
	return updateFlickDetector(detector, rotationToForwardVector(rot), deltaTime, hand, rawForward)
end

local function isValidAimOffset(offset)
	if type(offset) ~= "table" then return false end
	local x, y, z, w = offset.X, offset.Y, offset.Z, offset.W
	if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" or type(w) ~= "number" then
		return false
	end
	local norm = x*x + y*y + z*z + w*w
	return norm > 0.98 and norm < 1.02
end

local function getRawFlickGestures(deltaTime, hand)
	local detector = rawFlickDetectors[hand]
	local identityPose, quat = isVrControllerIdentityPose(hand)
	if identityPose or quat == nil then
		resetRawFlickMotion(detector, true)
		-- A controller can change while untracked; fetch its offset again once it returns.
		detector.aimOffset, detector.aimRetry = nil, 0
		return false, false, 0
	end
	if detector.aimOffset == nil and type(deltaTime) == "number" then
		detector.aimRetry = (detector.aimRetry or 0) - deltaTime
		if detector.aimRetry <= 0 then
			detector.aimRetry = RAW_FLICK_AIM_RETRY
			local offset = plugin.getControllerAimOffset(hand == Handed.Left and "left" or "right")
			if isValidAimOffset(offset) then
				detector.aimOffset = offset
			end
		end
	end
	return updateRawFlickDetector(detector, flickPosePos, quat, deltaTime, hand)
end

function M.getFlickGestures(deltaTime, hand)
	if hand == nil then hand = Handed.Right end
	if useRawControllers then
		return getRawFlickGestures(deltaTime, hand)
	end
	return getWorldFlickGestures(deltaTime, hand)
end

function M.autoDetectGesture(id, val, hand)
	if val == nil then val = true end
	if hand == nil then hand = Handed.Right end
	if autoDetect[id] == nil then
		autoDetect[id] = {}
	end
	autoDetect[id][hand] = val
end

-- Dev config "Test" mode: when set, that gesture is treated as autodetect for both hands.
local swipeTestGestureIds = {
	[M.Gesture.SWIPE_LEFT] = true,
	[M.Gesture.SWIPE_RIGHT] = true,
	[M.Gesture.SWIPE_UP] = true,
	[M.Gesture.SWIPE_DOWN] = true,
	[M.Gesture.SNATCH] = true,
}
local flickTestGestureIds = {
	[M.Gesture.FLICK] = true,
	[M.Gesture.FLICK_UP] = true,
}
local faceTestGestureIds = {
	[M.Gesture.EARGRAB] = true,
	[M.Gesture.EAT] = true,
	[M.Gesture.GLASSESGRAB] = true,
	[M.Gesture.HATGRAB] = true,
	[M.Gesture.EARSCRATCH] = true,
	[M.Gesture.HEADSCRATCH] = true,
	[M.Gesture.LIPSCRATCH] = true,
	[M.Gesture.EYESCRATCH] = true,
}

uevrUtils.registerUEVRCallback("on_gesture_test", function(gestureId)
	if gestureId == nil or gestureId == false then
		gestureTestId = nil
	else
		gestureTestId = gestureId
	end
end)

local function hasAutodetect(id, hand)
	if gestureTestId ~= nil then
		if gestureTestId == id then
			return true
		end
		-- Testing any swipe/snatch id enables the whole swipe detector family.
		if swipeTestGestureIds[gestureTestId] and swipeTestGestureIds[id] then
			return true
		end
		-- Testing any flick id enables the whole flick detector family.
		if flickTestGestureIds[gestureTestId] and flickTestGestureIds[id] then
			return true
		end
		-- Testing any face id enables the whole face detector family.
		if faceTestGestureIds[gestureTestId] and faceTestGestureIds[id] then
			return true
		end
	end
	if autoDetect[id] ~= nil then
		return autoDetect[id][hand] == true
	end
	return false
end

local function hasAnyFaceAutodetect(hand)
	for id, _ in pairs(faceTestGestureIds) do
		if hasAutodetect(id, hand) then
			return true
		end
	end
	return false
end

local function updateChestAutodetect(state, hand)
	local active = detectBody(state, hand, true) == true
	if active ~= chestCallbackActive[hand] then
		chestCallbackActive[hand] = active
		uevrUtils.executeUEVRCallbacks("on_gesture_chestgrab", active, hand)
	end
end

local function updateFaceAutodetect(state, hand)
	local gripMouth, gripEyes, gripHead, gripEar, triggerMouth, triggerEyes, triggerHead, triggerEar = detectFace(state, hand, true)
	local results = {
		[M.Gesture.EAT] = gripMouth == true,
		[M.Gesture.GLASSESGRAB] = gripEyes == true,
		[M.Gesture.HATGRAB] = gripHead == true,
		[M.Gesture.EARGRAB] = gripEar == true,
		[M.Gesture.LIPSCRATCH] = triggerMouth == true,
		[M.Gesture.EYESCRATCH] = triggerEyes == true,
		[M.Gesture.HEADSCRATCH] = triggerHead == true,
		[M.Gesture.EARSCRATCH] = triggerEar == true,
	}
	local prev = faceCallbackActive[hand]
	for id, active in pairs(results) do
		if active ~= (prev[id] == true) then
			prev[id] = active
			uevrUtils.executeUEVRCallbacks(faceGestureCallbackNames[id], active, hand)
		end
	end
end

uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)
	if hasAutodetect(M.Gesture.CHESTGRAB, Handed.Right) then
		updateChestAutodetect(state, Handed.Right)
	end
	if hasAutodetect(M.Gesture.CHESTGRAB, Handed.Left) then
		updateChestAutodetect(state, Handed.Left)
	end
	if hasAnyFaceAutodetect(Handed.Right) then
		updateFaceAutodetect(state, Handed.Right)
	end
	if hasAnyFaceAutodetect(Handed.Left) then
		updateFaceAutodetect(state, Handed.Left)
	end
end)

local function hasPushTwoHandedAutodetect()
	return hasAutodetect(M.Gesture.PUSH_TWO_HANDED, Handed.Right)
		or hasAutodetect(M.Gesture.PUSH_TWO_HANDED, Handed.Left)
end

local function tryMatchTwoHandedPush()
	local window = getParam({"push", "twoHandedSyncWindow"}) or 0.35
	local leftP = pendingTwoHandPush[Handed.Left]
	local rightP = pendingTwoHandPush[Handed.Right]
	if leftP == nil or rightP == nil then
		return false
	end
	if math.abs(leftP.time - rightP.time) > window then
		return false
	end
	local strength = leftP.strength
	if rightP.strength < strength then
		strength = rightP.strength
	end
	uevrUtils.executeUEVRCallbacks("on_gesture_push_two_handed", strength)
	pendingTwoHandPush[Handed.Left] = nil
	pendingTwoHandPush[Handed.Right] = nil
	return true
end

local function expirePendingTwoHandPush()
	local window = getParam({"push", "twoHandedSyncWindow"}) or 0.35
	for _, hand in ipairs({Handed.Left, Handed.Right}) do
		local p = pendingTwoHandPush[hand]
		if p ~= nil and pushTwoHandedClock - p.time > window then
			pendingTwoHandPush[hand] = nil
			if hasAutodetect(M.Gesture.PUSH, hand) then
				local otherHand = hand == Handed.Left and Handed.Right or Handed.Left
				local otherP = pendingTwoHandPush[otherHand]
				if otherP == nil or pushTwoHandedClock - otherP.time > window then
					uevrUtils.executeUEVRCallbacks("on_gesture_push", p.strength, hand)
				end
			end
		end
	end
end

local function handlePushResults(delta, leftPush, leftStrength, rightPush, rightStrength)
	local twoHandedActive = hasPushTwoHandedAutodetect()
	if twoHandedActive
		or pendingTwoHandPush[Handed.Left] ~= nil
		or pendingTwoHandPush[Handed.Right] ~= nil then
		pushTwoHandedClock = pushTwoHandedClock + delta
	end

	if twoHandedActive then
		if leftPush then
			pendingTwoHandPush[Handed.Left] = { strength = leftStrength, time = pushTwoHandedClock }
		end
		if rightPush then
			pendingTwoHandPush[Handed.Right] = { strength = rightStrength, time = pushTwoHandedClock }
		end
		if not tryMatchTwoHandedPush() then
			expirePendingTwoHandPush()
		end
		return
	end

	if leftPush and hasAutodetect(M.Gesture.PUSH, Handed.Left) then
		uevrUtils.executeUEVRCallbacks("on_gesture_push", leftStrength, Handed.Left)
	end
	if rightPush and hasAutodetect(M.Gesture.PUSH, Handed.Right) then
		uevrUtils.executeUEVRCallbacks("on_gesture_push", rightStrength, Handed.Right)
	end
end

local function needsHeadFrame()
	return hasAutodetect(M.Gesture.STOP, Handed.Right)
		or hasAutodetect(M.Gesture.STOP, Handed.Left)
		or hasAutodetect(M.Gesture.STOP_TWO_HANDED, Handed.Right)
		or hasAutodetect(M.Gesture.STOP_TWO_HANDED, Handed.Left)
		or hasAutodetect(M.Gesture.PUSH, Handed.Right)
		or hasAutodetect(M.Gesture.PUSH, Handed.Left)
		or hasAutodetect(M.Gesture.PUSH_TWO_HANDED, Handed.Right)
		or hasAutodetect(M.Gesture.PUSH_TWO_HANDED, Handed.Left)
end

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
	local headFrame = needsHeadFrame() and buildHeadFrame() or nil
	if hasAutodetect(M.Gesture.PUNCH, Handed.Right) then
		local isPunch, strength = M.detectGesture(M.Gesture.PUNCH, delta, Handed.Right)
		if isPunch then
			uevrUtils.executeUEVRCallbacks("on_gesture_punch", strength, Handed.Right)
		end
	end
	if hasAutodetect(M.Gesture.PUNCH, Handed.Left) then
		local isPunch, strength = M.detectGesture(M.Gesture.PUNCH, delta, Handed.Left)
		if isPunch then
			uevrUtils.executeUEVRCallbacks("on_gesture_punch", strength, Handed.Left)
		end
	end
	if hasAutodetect(M.Gesture.SWIPE_LEFT, Handed.Right) or hasAutodetect(M.Gesture.SWIPE_RIGHT, Handed.Right) or hasAutodetect(M.Gesture.SWIPE_UP, Handed.Right) or hasAutodetect(M.Gesture.SWIPE_DOWN, Handed.Right) or hasAutodetect(M.Gesture.SNATCH, Handed.Right) then
		local left, right, up, down, punch, snatch, strength = M.getSwipeGestures(delta, Handed.Right)

		if left then uevrUtils.executeUEVRCallbacks("on_gesture_swipe_left", strength, Handed.Right) end
		if right then uevrUtils.executeUEVRCallbacks("on_gesture_swipe_right", strength, Handed.Right) end
		if up then uevrUtils.executeUEVRCallbacks("on_gesture_swipe_up", strength, Handed.Right) end
		if down then uevrUtils.executeUEVRCallbacks("on_gesture_swipe_down", strength, Handed.Right) end
		if snatch then uevrUtils.executeUEVRCallbacks("on_gesture_snatch", strength, Handed.Right) end
	end
	if hasAutodetect(M.Gesture.SWIPE_LEFT, Handed.Left) or hasAutodetect(M.Gesture.SWIPE_RIGHT, Handed.Left) or hasAutodetect(M.Gesture.SWIPE_UP, Handed.Left) or hasAutodetect(M.Gesture.SWIPE_DOWN, Handed.Left) or hasAutodetect(M.Gesture.SNATCH, Handed.Left) then
		local left, right, up, down, punch, snatch, strength = M.getSwipeGestures(delta, Handed.Left)

		if left then uevrUtils.executeUEVRCallbacks("on_gesture_swipe_left", strength, Handed.Left) end
		if right then uevrUtils.executeUEVRCallbacks("on_gesture_swipe_right", strength, Handed.Left) end
		if up then uevrUtils.executeUEVRCallbacks("on_gesture_swipe_up", strength, Handed.Left) end
		if down then uevrUtils.executeUEVRCallbacks("on_gesture_swipe_down", strength, Handed.Left) end
		if snatch then uevrUtils.executeUEVRCallbacks("on_gesture_snatch", strength, Handed.Left) end
	end
	if hasAutodetect(M.Gesture.SWING, Handed.Right) then
		local began, ended, strength, active, endedStrength = M.getSwingGestures(delta, Handed.Right)
		if ended then uevrUtils.executeUEVRCallbacks("on_gesture_swing_end", endedStrength or strength, Handed.Right) end
		if began then uevrUtils.executeUEVRCallbacks("on_gesture_swing_begin", strength, Handed.Right) end
	end
	if hasAutodetect(M.Gesture.SWING, Handed.Left) then
		local began, ended, strength, active, endedStrength = M.getSwingGestures(delta, Handed.Left)
		if ended then uevrUtils.executeUEVRCallbacks("on_gesture_swing_end", endedStrength or strength, Handed.Left) end
		if began then uevrUtils.executeUEVRCallbacks("on_gesture_swing_begin", strength, Handed.Left) end
	end
	if hasAutodetect(M.Gesture.FLICK, Handed.Right) or hasAutodetect(M.Gesture.FLICK_UP, Handed.Right) then
		local flick, flickUp, strength = M.getFlickGestures(delta, Handed.Right)
		if flick then uevrUtils.executeUEVRCallbacks("on_gesture_flick", strength, Handed.Right) end
		if flickUp then uevrUtils.executeUEVRCallbacks("on_gesture_flick_up", strength, Handed.Right) end
	end
	if hasAutodetect(M.Gesture.FLICK, Handed.Left) or hasAutodetect(M.Gesture.FLICK_UP, Handed.Left) then
		local flick, flickUp, strength = M.getFlickGestures(delta, Handed.Left)
		if flick then uevrUtils.executeUEVRCallbacks("on_gesture_flick", strength, Handed.Left) end
		if flickUp then uevrUtils.executeUEVRCallbacks("on_gesture_flick_up", strength, Handed.Left) end
	end
	if hasAutodetect(M.Gesture.BLOCK, Handed.Right) then
		local active = detectBlock(Handed.Right)
		if active ~= blockCallbackActive[Handed.Right] then
			blockCallbackActive[Handed.Right] = active
			uevrUtils.executeUEVRCallbacks("on_gesture_block", active, Handed.Right)
		end
	end
	if hasAutodetect(M.Gesture.BLOCK, Handed.Left) then
		local active = detectBlock(Handed.Left)
		if active ~= blockCallbackActive[Handed.Left] then
			blockCallbackActive[Handed.Left] = active
			uevrUtils.executeUEVRCallbacks("on_gesture_block", active, Handed.Left)
		end
	end
	if headFrame ~= nil then
		if hasAutodetect(M.Gesture.STOP, Handed.Right) then
			local active = detectStop(Handed.Right, headFrame)
			if active ~= stopCallbackActive[Handed.Right] then
				stopCallbackActive[Handed.Right] = active
				uevrUtils.executeUEVRCallbacks("on_gesture_stop", active, Handed.Right)
			end
		end
		if hasAutodetect(M.Gesture.STOP, Handed.Left) then
			local active = detectStop(Handed.Left, headFrame)
			if active ~= stopCallbackActive[Handed.Left] then
				stopCallbackActive[Handed.Left] = active
				uevrUtils.executeUEVRCallbacks("on_gesture_stop", active, Handed.Left)
			end
		end
		if hasAutodetect(M.Gesture.STOP_TWO_HANDED, Handed.Right) or hasAutodetect(M.Gesture.STOP_TWO_HANDED, Handed.Left) then
			local active = detectStop(Handed.Left, headFrame) and detectStop(Handed.Right, headFrame)
			if active ~= stopTwoHandedCallbackActive then
				stopTwoHandedCallbackActive = active
				uevrUtils.executeUEVRCallbacks("on_gesture_stop_two_handed", active)
			end
		end
		local pawnPos = headFrame.head
		local leftPush, leftStrength, rightPush, rightStrength = false, 0, false, 0
		if hasAutodetect(M.Gesture.PUSH, Handed.Left) or hasAutodetect(M.Gesture.PUSH_TWO_HANDED, Handed.Left) then
			local pos = controllers.getControllerLocation(Handed.Left)
			if pos ~= nil then
				leftPush, leftStrength = updatePushDetector(pushDetectors[Handed.Left], pos, pawnPos, headFrame, delta, detectStop(Handed.Left, headFrame))
			end
		end
		if hasAutodetect(M.Gesture.PUSH, Handed.Right) or hasAutodetect(M.Gesture.PUSH_TWO_HANDED, Handed.Right) then
			local pos = controllers.getControllerLocation(Handed.Right)
			if pos ~= nil then
				rightPush, rightStrength = updatePushDetector(pushDetectors[Handed.Right], pos, pawnPos, headFrame, delta, detectStop(Handed.Right, headFrame))
			end
		end
		handlePushResults(delta, leftPush, leftStrength, rightPush, rightStrength)
	end
end)

local function registerGestureDetection(id, rightHand, leftHand)
	if rightHand == nil and leftHand == nil then
		M.autoDetectGesture(id, true, Handed.Right)
	else
		if rightHand == true then
			M.autoDetectGesture(id, true, Handed.Right)
		end
		if leftHand == true then
			M.autoDetectGesture(id, true, Handed.Left)
		end
	end
end
function M.registerSwipeLeftCallback(callback, rightHand, leftHand)
	registerGestureDetection(M.Gesture.SWIPE_LEFT, rightHand, leftHand)
	uevrUtils.registerUEVRCallback("on_gesture_swipe_left", callback)
end
function M.registerSwipeRightCallback(callback, rightHand, leftHand)
	registerGestureDetection(M.Gesture.SWIPE_RIGHT, rightHand, leftHand)
	uevrUtils.registerUEVRCallback("on_gesture_swipe_right", callback)
end
function M.registerSwipeUpCallback(callback, rightHand, leftHand)
	registerGestureDetection(M.Gesture.SWIPE_UP, rightHand, leftHand)
	uevrUtils.registerUEVRCallback("on_gesture_swipe_up", callback)
end
function M.registerSwipeDownCallback(callback, rightHand, leftHand)
	registerGestureDetection(M.Gesture.SWIPE_DOWN, rightHand, leftHand)
	uevrUtils.registerUEVRCallback("on_gesture_swipe_down", callback)
end
function M.registerSwingBeginCallback(callback, rightHand, leftHand)
	registerGestureDetection(M.Gesture.SWING, rightHand, leftHand)
	uevrUtils.registerUEVRCallback("on_gesture_swing_begin", callback)
end
function M.registerSwingEndCallback(callback, rightHand, leftHand)
	registerGestureDetection(M.Gesture.SWING, rightHand, leftHand)
	uevrUtils.registerUEVRCallback("on_gesture_swing_end", callback)
end
function M.registerFlickCallback(callback, rightHand, leftHand)
	registerGestureDetection(M.Gesture.FLICK, rightHand, leftHand)
	uevrUtils.registerUEVRCallback("on_gesture_flick", callback)
end
function M.registerFlickUpCallback(callback, rightHand, leftHand)
	registerGestureDetection(M.Gesture.FLICK_UP, rightHand, leftHand)
	uevrUtils.registerUEVRCallback("on_gesture_flick_up", callback)
end
function M.registerBlockCallback(callback, rightHand, leftHand)
	registerGestureDetection(M.Gesture.BLOCK, rightHand, leftHand)
	uevrUtils.registerUEVRCallback("on_gesture_block", callback)
end
function M.registerStopCallback(callback, rightHand, leftHand)
	registerGestureDetection(M.Gesture.STOP, rightHand, leftHand)
	uevrUtils.registerUEVRCallback("on_gesture_stop", callback)
end
function M.registerStopTwoHandedCallback(callback, rightHand, leftHand)
	registerGestureDetection(M.Gesture.STOP_TWO_HANDED, rightHand, leftHand)
	uevrUtils.registerUEVRCallback("on_gesture_stop_two_handed", callback)
end
function M.registerPushCallback(callback, rightHand, leftHand)
	registerGestureDetection(M.Gesture.PUSH, rightHand, leftHand)
	uevrUtils.registerUEVRCallback("on_gesture_push", callback)
end
function M.registerPushTwoHandedCallback(callback, rightHand, leftHand)
	registerGestureDetection(M.Gesture.PUSH_TWO_HANDED, rightHand, leftHand)
	uevrUtils.registerUEVRCallback("on_gesture_push_two_handed", callback)
end

function M.getConfigurationWidgets(options)
	if gestureConfig == nil then
		gestureConfig = require("libs/config/gesture_config")
	end
	createConfigMonitor()
	gestureConfig.init(paramManager)
	return gestureConfig.getConfigurationWidgets(options)
end

function M.showConfiguration(saveFileName, options)
	if gestureConfig == nil then
		gestureConfig = require("libs/config/gesture_config")
	end
	createConfigMonitor()
	gestureConfig.init(paramManager)
	gestureConfig.showConfiguration(saveFileName, options)
end

function M.init(isDeveloperMode, logLevel)
	paramManager:load(true)
	applyDetectorParameters()

	if logLevel ~= nil then
		M.setLogLevel(logLevel)
	end
	if isDeveloperMode == nil and uevrUtils.getDeveloperMode() ~= nil then
		isDeveloperMode = uevrUtils.getDeveloperMode()
	end

	if isDeveloperMode then
		gestureConfigDev = require("libs/config/gesture_config_dev")
		gestureConfigDev.init(paramManager)
		createConfigMonitor()
	end
end

return M
