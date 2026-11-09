--[[
Usage
    Drop the libs folder containing this file into your project folder
    Add code like this in your script:
        local grabbable = require("libs/grabbable")

    Lets a VR hand grab world items. A grip flies the item into the hand, it is carried while the grip is held, and releasing
    throws it with the hand's velocity (or drops it), or collects it when released during a collect gesture. The game-specific
    parts (what can be grabbed, what the game currently offers to interact with, how it collects) are supplied as callbacks.

    How holding works
        The item's mesh is its root component when that has a static mesh, otherwise its Mesh property; items with neither are not
        grabbed. Item meshes may refuse attachment, so the real item is never attached. When a grab starts, a hidden copy of the item's
        static mesh (with its materials) is created and exposed through getHeldMesh(). grabbable attaches it like any other hand
        attachment through libs/attachments' grip update, with a callback of its own below the game's (priority -10): the hand
        holding a copy gets it, on the mesh and socket the game's grip callback gives for that hand, unless the game's callback
        puts something in that hand itself (a game can also return the copy from its own callback, with its own options). Its
        transform is configured per item in the attachments UI. The real item
        flies to the copy's live transform (location, rotation and scale) and is then hidden while the copy is shown. Releasing
        puts the real item back at the copy's transform, where it falls under gravity and eases back to its own size. The fall is
        kinematic (swept steps with the gravity option) unless grabbable.useRealPhysics(true) is set; then the released item simulates
        physics, starting with the throw velocity.

    Grip arbitration
        Uses libs/grip. Each grabbable registers a start claim under its name: claimPriority when a starting press would grab or
        interact, and heldPriority when an item is already flying or held (so toggle mode presses keep going to it). It only acts on
        presses it owns, and grip.lua hides owned presses from the game for the whole press. Other systems take precedence over it
        by claiming above claimPriority (e.g. an open menu), or by returning false from canClaim.

    Available functions:

    grabbable.new(options) -> Grabbable
        options:
            name: string (default "grabbable") - owner name used in grip claims
            claimPriority: number (default grip.NORMAL) - grip claim for a press that would grab or interact
            heldPriority: number (default 200) - grip claim for a press while an item is flying or held
            hand: Handed (default Handed.Left)
            gripButton: XINPUT button (default the hand's shoulder button)
            isGrabbable: function(actor) -> boolean (required)
            canClaim: function(state) -> boolean (optional)
                Return false to leave a starting grip to something else (e.g. head gestures).
            getInteractTarget: function(state) -> actor|nil (optional)
                The game's current interaction target (e.g. what its prompt is on). A grip on a grabbable target grabs it;
                any other target gets interactButton held for as long as the grip.
            interactButton: XINPUT button (optional)
            isCollectGesture: function(state) -> boolean (optional)
                Checked every frame while carrying; releasing the grip during the gesture collects the item.
            collectButton: XINPUT button (optional)
                Pressed for collectFrames on a collect release. The game is expected to collect (destroy) the item within
                collectTimeout seconds, otherwise it is dropped.
            collectCallback: function(actor) (optional)
                Called once on a collect release with the real item, instead of pressing collectButton (it wins when both are
                set), for games that collect by calling something. The game is expected to collect (destroy) the item within
                collectTimeout seconds, otherwise it is dropped.
            collectFrames: number (default 6)
            collectTimeout: seconds (default 0.5)
            collectHaptic: table (optional) - vibrates the hand when a collect succeeds (the game removed the item within
                collectTimeout): {duration = seconds, frequency = Hz, amplitude = 0-1}, each defaulting to
                uevrUtils.triggerHapticVibration's (0.05, 1000, 1). Absent: no vibration.
            arriveHaptic: table|false (default {duration = 0.03, amplitude = 0.3}) - vibrates the hand when a grabbed item
                reaches it: {duration = seconds, frequency = Hz, amplitude = 0-1}, missing fields defaulting to
                uevrUtils.triggerHapticVibration's (0.05, 1000, 1). false: no vibration.
            toggleGrip: boolean (default false)
                Dev: the grip toggles (press to grab, the item stays after release, press again to collect or drop), for
                adjusting attachment transforms hands-free. No throwing in this mode.
            touch: table (optional) - a grip that starts with the hand touching a grabbable item grabs it (before the interaction
                target, which stays the fallback). One overlap around the hand on the press frame; the nearest grabbable item wins.
                enabled: boolean (default false)
                distance: cm (default 15)
                objectTypes: {EObjectTypeQuery} (default all) - all, so items are found whatever collision channel they use
                flightTime: seconds (default 0.1) - the item is already at the hand, so its flight is short
            pointing: table (optional) - choose items by pointing the palm at them instead of by interaction target
                enabled: boolean
                highlight: function(actor, on) (optional)
                shouldScan: function() -> boolean (optional) - gate for the overlap scan, which goes through the plugin bridge
                objectTypes: {EObjectTypeQuery} (default {1, 3}: WorldDynamic, PhysicsBody)
                maxDistance: cm (default 400)
                selectAngle: degrees (default 15) - cone around the palm axis that selects an item
                keepAngle: degrees (default 20) - wider cone that keeps the current item selected
                switchMargin: cosine (default 0.02) - another item must be this much closer to the palm axis to take over
                palmSign: 1|-1 (default 1) - the palm faces along the controller's right vector times palmSign
                scanInterval: ms (default 250)
            flightTime: seconds (default 0.4)
            flightDistance: cm (optional) - flights take their full time from this far away or more and proportionally less from
                closer (measured once, when the grab starts), so a grab right next to the hand is almost immediate
            minFlightTime: seconds (default 0.03) - the shortest flight with flightDistance
            catchFlightTime: seconds|false (default 0) - flight time for a catch, an item moving faster than catchSpeed when the
                grab starts: by default straight into the hand, so a late catch doesn't fly back up to it. false: the normal flight
            catchSpeed: cm/s (default 100)
            arcHeight: cm (default 15)
            sampleHistory: seconds of hand positions kept while carrying (default 0.2)
            throwWindow: seconds of hand movement measured for a throw (default 0.06)
            throwScale: (default 1.3) - VR throws feel weak at the hand's raw speed
            throwMinSpeed: cm/s (default 100) - slower releases just drop
            throwMaxSpeed: cm/s (default 1500)
            gravity: cm/s^2 (default 980)
            maxFallDistance: cm (default 1000)
            floorNormalZ: (default 0.7) - a hit surface whose normal points at least this far up counts as ground
            dropRescaleTime: seconds (default 0.5) - time a released item takes to ease back to its own size
            dropRescaleEase: number (default 1) - ease-in power for that: 1 is linear, 2 or 3 change little at first and most
                near the end
            dropRescaleDelay: seconds (default 0) - how long a released item keeps its release size before easing back
            keepDropScale: boolean (default false) - released items keep the size they had at release instead of easing back
                to their own; that size counts as their own from then on
            setPhysics: function(actor, mesh, velocity) (optional, real physics only)
                Called instead of simulating the item's mesh when a released item starts real physics, after the item is back
                at the copy's transform with its visibility and collision restored. velocity is the throw velocity {x, y, z} in
                cm/s, or nil for a drop. The caller starts (and later ends) the physics itself.
            physics: table (optional, real physics only; setPhysics takes precedence) - grabbable runs the released item's physics
                on a chosen body and puts it back once it comes to rest (see "Managed physics" in the code):
                getBody: function(actor, mesh) -> component (default the item mesh) - e.g. a simple collision shape when the mesh
                    has no simple collision
                linearDamping, angularDamping: numbers (optional) - while simulating
                lockRotation: {roll = boolean, pitch = boolean, yaw = boolean} (optional) - e.g. to stop a capsule rolling like a pin
                settleMinTime: seconds (default 0.5) - how long it simulates before being asleep counts as having come to rest
            stopPhysics: function(actor, mesh) (optional, with setPhysics) - ends the game's own physics on an item that is grabbed
                while still moving (e.g. thrown up and caught), before its flight to the hand starts. Without it, a simulating item
                mesh is simply stopped.
            dropWhenHandTaken: boolean (default false) - drops a held item when the game's grip callback puts something else in
                its hand (e.g. a weapon is drawn). Leave it off where the game's callback shows something else there for a while
                and the item should wait (e.g. a menu that takes the hand). With hands, a table sets it per hand, e.g.
                {[Handed.Right] = true}.
            hands: {Handed, ...} (optional) - one grabbable serving several hands (e.g. {Handed.Left, Handed.Right}) instead of
                options.hand. Each hand gets its own grab (its own grip claim, flight, hold, throw and collect); a hand doesn't
                grab the item another hand holds or is pulling in, and doesn't claim while the game's grip callback has something
                in it (e.g. a weapon). The callbacks get the hand as an extra last argument: isGrabbable(actor, hand),
                canClaim(state, hand), getInteractTarget(state, hand), isCollectGesture(state, hand), collectCallback(actor, hand),
                setPhysics(actor, mesh, velocity, hand).
            names: {[Handed] = string} (optional, with hands) - each hand's grip claim name. Default name .. "_left"/"_right"
            handoffDistance: cm (default 12, with hands; 0 or false disables) - a grip that starts with an empty, free hand this
                close to the item the other hand holds moves it to that hand (no flight; the hold, throw and collect go with it)
            handoffPriority: number (default heldPriority, with hands) - grip claim for such a press

    grabbable.useRealPhysics(value)
        true: released items simulate physics (engine gravity, bouncing, tumbling) instead of the kinematic fall. Default false.
        The gravity, maxFallDistance and floorNormalZ options only apply to the kinematic fall.

    Grabbable:setEnabled(value)
        Disabling drops anything held where it is and removes any highlight.
    Grabbable:isEnabled() -> boolean
    Grabbable:getHeldMesh() -> component|nil
        The copy to attach to the hand, from the start of a grab (hidden during the flight).
    Grabbable:getHeldActor() -> actor|nil
        The real item from the start of a grab until it is released, or nil.
    Grabbable:setToggleGrip(value)

    With options.hands, new returns an object with the same methods, each taking an optional hand (nil: any or all hands):
        setEnabled(value), isEnabled(), getHeldMesh(hand), getHeldActor(hand), isHolding(hand), setToggleGrip(value), reset()
        canGrab(actor, hand) -> boolean - whether hand would grab actor now (enabled, empty, not busy, grabbable, not the other
            hand's), apart from canClaim, which needs the input state. For things like a prompt icon.
    Grabbable:isHolding() -> boolean
        True while an item is in the hand, and for the rest of a grip press that grabbed, collected or dropped one.
    Grabbable:reset()
        Also runs on level change and script reset.
]]

local uevrUtils = require("libs/uevr_utils")
local controllers = require("libs/controllers")
local attachments = require("libs/attachments")
local plugin = require("libs/core/plugin")
local physics = require("libs/physics")
local grip = require("libs/grip")

local M = {}

local realPhysics = false

-- Held copies are attached through libs/attachments' grip update, below the game's own callback (priority 0): a hand holding a copy
-- gets it unless the game's callback puts something there itself, and the hand's mesh and socket come from the game's callback.
local GRIP_UPDATE_PRIORITY = -10
-- How a held copy is attached: it has no origin to return to, so it is only detached (in place) on release.
local HELD_ATTACH_OPTIONS = {
	detachFromOriginOnGrip = false,
	detachFromParentOnRelease = true,
	maintainWorldPositionOnDetachFromParent = true,
	reattachToOriginOnRelease = false,
	allowChildVisibilityHandling = false,
	allowChildHiddenInGameHandling = false,
	allowRenderInMainPassHandling = false,
	useCurrentAttachedSocketName = false,
}
local instances = {}

-- The copy held (or flying) in hand, from any grabbable.
local function getHandCopy(hand)
	for _, instance in ipairs(instances) do
		if instance.hand == hand then
			local copy = uevrUtils.getValid(instance.copy)
			if copy ~= nil then return copy end
		end
	end
	return nil
end

local function registerGripUpdate()
	attachments.registerOnGripUpdateCallback(function()
		local right, left = getHandCopy(Handed.Right), getHandCopy(Handed.Left)
		return right, nil, nil, left, nil, nil, right ~= nil and HELD_ATTACH_OPTIONS or nil, left ~= nil and HELD_ATTACH_OPTIONS or nil
	end, GRIP_UPDATE_PRIORITY)
end

-- true: released items are handed to the physics engine (SetSimulatePhysics) instead of the built-in kinematic fall.
function M.useRealPhysics(value)
	realPhysics = value == true
end

------------------- Managed physics (options.physics) -------------------
-- Released items simulate on a chosen body: the item mesh, or e.g. a simple collision shape when the mesh has no simple collision
-- (a simulating mesh without one falls through the world). The body blocks the world but not the player or the camera. A body that
-- isn't the actor's root is detached by simulating, so the actor follows it every tick, keeping the body's offset from it (measured
-- without scale, as held items can be mirrored). Once the body has come to rest (asleep after settleMinTime) it is put back as it
-- was: re-attached in place with its own collision profile, gravity, damping and rotation locks. An item grabbed while its body
-- still simulates (e.g. caught in the air) is settled first, where it is. Everything still simulating settles on level change,
-- script reset, and when a grabbable using this is disabled. The body's collision is restored by profile name, so a body with a
-- custom (unnamed) collision setup isn't restored exactly.
local SNAP_TO_TARGET = 2 -- EAttachmentRule
local SIX_DOF = 1 -- EDOFMode
local managed = {} -- actor address -> what following and settling need
local managedTickRegistered = false

local function unscaledTransform(location, rotation)
	return kismet_math_library:MakeTransform(location, rotation, uevrUtils.vector(1, 1, 1))
end

-- Moves the actor (location and rotation; grabbable owns its scale) to where the body's offset from it puts it.
local function followBody(entry, actor, body)
	local bodyWorld = unscaledTransform(body:K2_GetComponentLocation(), body:K2_GetComponentRotation())
	local location = kismet_math_library:TransformLocation(bodyWorld, kismet_math_library:InverseTransformLocation(entry.offset, uevrUtils.vector(0, 0, 0)))
	local rotation = kismet_math_library:TransformRotation(bodyWorld, kismet_math_library:InverseTransformRotation(entry.offset, uevrUtils.rotator(0, 0, 0)))
	actor:K2_SetActorLocationAndRotation(location, rotation, false, reusable_hit_result, true)
end

local function settleBody(entry)
	local actor, body = uevrUtils.getValid(entry.actor), uevrUtils.getValid(entry.body)
	if actor == nil or body == nil then return end
	body:SetSimulatePhysics(false)
	if not entry.isRoot then
		followBody(entry, actor, body)
		local parent = uevrUtils.getValid(entry.parent)
		if parent ~= nil then
			body:K2_AttachToComponent(parent, entry.socket, SNAP_TO_TARGET, SNAP_TO_TARGET, SNAP_TO_TARGET, false)
			body:K2_SetRelativeLocationAndRotation(entry.relLocation, entry.relRotation, false, reusable_hit_result, true)
		end
	end
	body:SetEnableGravity(entry.gravity)
	body:SetLinearDamping(entry.linearDamping)
	body:SetAngularDamping(entry.angularDamping)
	local instance = body.BodyInstance
	instance.bLockXRotation, instance.bLockYRotation, instance.bLockZRotation = entry.lockX, entry.lockY, entry.lockZ
	body:SetConstraintMode(entry.dofMode)
	body:SetCollisionProfileName(entry.profile, true)
end

local function settleAllManaged()
	for key, entry in pairs(managed) do
		settleBody(entry)
		managed[key] = nil
	end
end

-- Settles the actor's body where it is if it is still simulating; true if it was.
local function settleManaged(actor)
	local key = actor:get_address()
	local entry = managed[key]
	if entry == nil then return false end
	settleBody(entry)
	managed[key] = nil
	return true
end

local function registerManagedTick()
	if managedTickRegistered then return end
	managedTickRegistered = true
	uevrUtils.registerPostEngineTickCallback(function(_, delta)
		for key, entry in pairs(managed) do
			entry.elapsed = entry.elapsed + delta
			local body, actor = uevrUtils.getValid(entry.body), uevrUtils.getValid(entry.actor)
			if body == nil or actor == nil then
				managed[key] = nil
			elseif entry.elapsed >= entry.settleMinTime and not body:IsAnyRigidBodyAwake() then
				settleBody(entry)
				managed[key] = nil
			elseif not entry.isRoot then
				followBody(entry, actor, body)
			end
		end
	end)
	uevrUtils.registerLevelChangeCallback(settleAllManaged)
	uevr.params.sdk.callbacks.on_script_reset(settleAllManaged)
end

-- The item is at the hand's copy transform with its visibility and collision restored; velocity is the throw velocity or nil.
local function startManagedPhysics(config, actor, mesh, velocity)
	local body = config.getBody ~= nil and uevrUtils.getValid(config.getBody(actor, mesh)) or mesh
	if body == nil then return end
	local root = uevrUtils.getValid(actor, {"RootComponent"})
	local isRoot = root ~= nil and root:get_address() == body:get_address()
	local parent = uevrUtils.getValid(body, {"AttachParent"})
	if not isRoot and parent == nil then return end
	local location, rotation = body.RelativeLocation, body.RelativeRotation
	local instance = body.BodyInstance
	managed[actor:get_address()] = {actor = actor, body = body, isRoot = isRoot, parent = parent, socket = body.AttachSocketName,
		relLocation = uevrUtils.vector(location.X, location.Y, location.Z), relRotation = uevrUtils.rotator(rotation.Pitch, rotation.Yaw, rotation.Roll),
		offset = kismet_math_library:MakeRelativeTransform(unscaledTransform(body:K2_GetComponentLocation(), body:K2_GetComponentRotation()),
			unscaledTransform(actor:K2_GetActorLocation(), actor:K2_GetActorRotation())),
		profile = body:GetCollisionProfileName(), gravity = body:IsGravityEnabled(), linearDamping = body:GetLinearDamping(),
		angularDamping = body:GetAngularDamping(), dofMode = instance.DOFMode, lockX = instance.bLockXRotation,
		lockY = instance.bLockYRotation, lockZ = instance.bLockZRotation, elapsed = 0, settleMinTime = config.settleMinTime}
	-- The body's own profile may ignore the world (e.g. an interaction-only collider), so every channel blocks first;
	-- makeComponentPhysicsGrippable then makes it a simulating PhysicsBody with gravity that ignores the player.
	body:SetCollisionResponseToAllChannels(ECollisionResponse.Block)
	physics.makeComponentPhysicsGrippable(body)
	body:SetCollisionResponseToChannel(ECollisionChannel.ECC_Camera, ECollisionResponse.Ignore)
	if config.linearDamping ~= nil then body:SetLinearDamping(config.linearDamping) end
	if config.angularDamping ~= nil then body:SetAngularDamping(config.angularDamping) end
	local lock = config.lockRotation
	if lock ~= nil then
		instance.bLockXRotation, instance.bLockYRotation, instance.bLockZRotation = lock.roll == true, lock.pitch == true, lock.yaw == true
		body:SetConstraintMode(SIX_DOF)
	end
	physics.applyThrowVelocity(body, velocity and uevrUtils.vector(velocity.x, velocity.y, velocity.z))
	registerManagedTick()
end
------------------- End managed physics -------------------

local Grabbable = {}
Grabbable.__index = Grabbable

local function default(value, fallback)
	if value == nil then return fallback end
	return value
end

-- A collected item stays valid while the game destroys it, so being destroyed counts as gone.
local function getLiveActor(actor)
	actor = uevrUtils.getValid(actor)
	if actor == nil or actor.bActorIsBeingDestroyed then return nil end
	return actor
end

local function canGrab(self, actor)
	return actor ~= nil and not actor.bActorIsBeingDestroyed and self.isGrabbable(actor) == true
end

-- The item's static mesh component: the root when it has a static mesh (e.g. Hogwarts Legacy), otherwise the actor's Mesh property
-- (e.g. FateKeeper, whose items have a bare SceneComponent root). A Mesh without a StaticMesh (e.g. a skeletal mesh) is not used.
-- Further fallbacks can be added here as games need them. Resolved once per grab.
-- Unreal records whether a mesh is mirrored (an odd number of negative scale axes) when it builds the mesh's render data, so a mesh
-- whose mirroring changes while it is visible (e.g. a held copy moved to the other hand, or an item mirrored on release or at the
-- start of a flight) can draw inside out, looking see-through. Hiding and showing it again in the same frame rebuilds that data.
local function refreshMirroring(component)
	component = uevrUtils.getValid(component)
	if component == nil or not component:IsVisible() then return end
	component:SetVisibility(false, true)
	component:SetVisibility(true, true)
end

local function getItemMesh(actor)
	local root = uevrUtils.getValid(actor, {"RootComponent"})
	if root ~= nil and root.StaticMesh ~= nil then return root end
	local mesh = uevrUtils.getValid(actor, {"Mesh"})
	if mesh ~= nil and mesh.StaticMesh ~= nil then return mesh end
	return nil
end

------------------- Palm pointing -------------------
-- Self-contained: pointing the palm at a grabbable item highlights it, and a grip grabs it. Candidates come from an overlap
-- scan around the hand. Everything outside this block reaches it only through getSelected, clearPointing, scanPointing and
-- updatePointing.
local actorClass = nil

local function selectItem(self, actor)
	local pointing = self.pointing
	if actor == pointing.selected then return end
	if pointing.highlight ~= nil then
		if uevrUtils.getValid(pointing.selected) ~= nil then pointing.highlight(pointing.selected, false) end
		if actor ~= nil then pointing.highlight(actor, true) end
	end
	pointing.selected = actor
end

-- The highlighted item a grip should grab, or nil.
local function getSelected(self)
	return self.pointing.enabled and self.pointing.selected or nil
end

-- Removes the highlight and forgets the candidates (a grab started, or the grabbable stopped).
local function clearPointing(self)
	selectItem(self, nil)
	self.pointing.candidates = {}
end

-- Finds grabbable items around the hand. Runs on the scan interval, and only while nothing is flying or held.
local function scanPointing(self)
	local pointing = self.pointing
	if not pointing.enabled or not self.enabled or self.flight ~= nil or self.held ~= nil or uevrUtils.getValid(pawn) == nil
		or (pointing.shouldScan ~= nil and not pointing.shouldScan()) then
		pointing.candidates = {}
		return
	end
	local hand = controllers.getControllerLocation(self.hand)
	if hand == nil then
		pointing.candidates = {}
		return
	end
	actorClass = actorClass or uevrUtils.get_class("Class /Script/Engine.Actor")
	-- SphereOverlapActors takes and returns TArrays, which native Lua does not marshal, so it goes through the plugin bridge.
	local result = plugin.executeFunction(kismet_system_library, "SphereOverlapActors", uevrUtils.get_world(), hand, pointing.maxDistance, pointing.objectTypes, actorClass, {pawn}, {})
	local found = {}
	for _, actor in ipairs(result and result.OutActors or {}) do
		if canGrab(self, actor) then found[#found + 1] = actor end
	end
	pointing.candidates = found
end
scanPointing = uevrUtils.profiler:wrap("Grabbable: pointing scan", scanPointing)

-- Highlights the candidate closest to the palm axis. Runs every tick while nothing is flying or held.
local function updatePointing(self)
	local pointing = self.pointing
	if not pointing.enabled then return end
	if #pointing.candidates == 0 then
		selectItem(self, nil)
		return
	end
	local hand = controllers.getControllerLocation(self.hand)
	local palm = controllers.getControllerRightVector(self.hand)
	if hand == nil or palm == nil then return end
	local best, bestCos, currentCos = nil, pointing.selectCos, nil
	for _, actor in ipairs(pointing.candidates) do
		if uevrUtils.getValid(actor) ~= nil then
			local loc = actor:K2_GetActorLocation()
			local dx, dy, dz = loc.X - hand.X, loc.Y - hand.Y, loc.Z - hand.Z
			local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
			if distance > 1 and distance <= pointing.maxDistance then
				local cos = (dx * palm.X + dy * palm.Y + dz * palm.Z) * pointing.palmSign / distance
				if actor == pointing.selected then currentCos = cos end
				if cos >= bestCos then best, bestCos = actor, cos end
			end
		end
	end
	-- Keep the current item inside the wider cone unless another is clearly closer to the palm axis, so items side by side don't flicker.
	if currentCos ~= nil and currentCos >= pointing.keepCos and (best == nil or bestCos < currentCos + pointing.switchMargin) then
		best = pointing.selected
	end
	selectItem(self, best)
end
------------------- End palm pointing -------------------

-- Ends a flight or a hold: removes the copy from the hand and gives the real item back its visibility, collision and size.
-- An item in the hand is first put at the copy's transform. With dropToGround it then falls from where it is, moving with the
-- optional throw velocity and easing back to its own size. With useRealPhysics the engine moves it instead, starting with the throw
-- velocity.
local matchScaleSigns -- defined with the flight code below; also used for the release transform

local function clearHeld(self, updateGrip, dropToGround, velocity)
	local copy = uevrUtils.getValid(self.copy)
	if copy == nil then return end
	local actor = getLiveActor(self.heldActor)
	if actor ~= nil then
		local scale = self.heldScale
		local inHand = self.held ~= nil and copy ~= nil
		local simulate = dropToGround and realPhysics
		local releaseScale = nil
		if inHand then
			local location, rotation = copy:K2_GetComponentLocation(), copy:K2_GetComponentRotation()
			local releaseRotation = uevrUtils.rotator(rotation.Pitch, rotation.Yaw, rotation.Roll)
			-- Easing back to its own size from a scale with other signs (e.g. a mirrored hand) would pass through 0 and shrink the item
			-- to nothing on the way, so the release transform is rewritten with the item's own signs (the same transform), and a mirror
			-- that remains is applied at once.
			if dropToGround and scale ~= nil and not self.keepDropScale then
				local mirrorAxis
				releaseRotation, releaseScale, mirrorAxis = matchScaleSigns(scale, releaseRotation, copy:K2_GetComponentScale())
				if mirrorAxis ~= nil then releaseScale[mirrorAxis] = -releaseScale[mirrorAxis] end
			end
			actor:K2_SetActorLocationAndRotation(uevrUtils.vector(location.X, location.Y, location.Z), releaseRotation, false, reusable_hit_result, true)
		end
		if dropToGround and scale ~= nil then
			local from = releaseScale or (inHand and copy:K2_GetComponentScale() or actor:GetActorScale3D())
			local fromScale = uevrUtils.vector(from.X, from.Y, from.Z)
			actor:SetActorScale3D(fromScale)
			local location = actor:K2_GetActorLocation()
			-- With real physics the engine moves the item, so its entry only eases the size back (it starts out landed).
			self.falling[#self.falling + 1] = {actor = actor, x = location.X, y = location.Y, z = location.Z, minZ = location.Z - self.maxFallDistance,
				vx = velocity and velocity.x or 0, vy = velocity and velocity.y or 0, vz = velocity and velocity.z or 0,
				fromScale = fromScale, toScale = self.keepDropScale and fromScale or scale, elapsed = 0, landed = simulate or nil}
			scale = nil -- the fall eases it back
		end
		if scale ~= nil then actor:SetActorScale3D(scale) end
		actor:SetActorHiddenInGame(false)
		refreshMirroring(self.heldMesh)
		local mesh = uevrUtils.getValid(self.heldMesh)
		if mesh ~= nil and self.heldCollision ~= nil then mesh:SetCollisionEnabled(self.heldCollision) end
		if mesh ~= nil and simulate then
			if self.setPhysics ~= nil then
				self.setPhysics(actor, mesh, velocity)
			elseif self.physics ~= nil then
				startManagedPhysics(self.physics, actor, mesh, velocity)
			else
				mesh:SetSimulatePhysics(true)
				if dropToGround and velocity ~= nil then
					mesh:SetPhysicsLinearVelocity(uevrUtils.vector(velocity.x, velocity.y, velocity.z), false, uevrUtils.fname_from_string(""))
				end
			end
		end
	end
	self.flight, self.held, self.copy, self.heldActor, self.heldMesh, self.heldCollision, self.heldScale = nil, nil, nil, nil, nil, nil, nil
	self.collectDeadline, self.handSamples = nil, {}
	-- Let the grip update detach the copy before it is destroyed.
	if copy ~= nil and updateGrip then attachments.forceGripUpdate() end
	if copy ~= nil then uevrUtils.destroyComponent(copy, true) end
end

-- The copy is made and attached to the hand, hidden, when the grab starts, so the real item can fly to the copy's transform
-- (including its attachment config scale) and be swapped for it on arrival.
local function startFlight(self, actor, flightTime)
	local mesh = getItemMesh(actor)
	if mesh == nil then return end
	-- An item caught while still falling stops falling, and its own size is the one it was easing back to. Any hand may have
	-- dropped or thrown it, so every grabbable's falling items are checked.
	local ownScale = nil
	for _, instance in ipairs(instances) do
		for i = #instance.falling, 1, -1 do
			if instance.falling[i].actor == actor then
				ownScale = instance.falling[i].toScale
				table.remove(instance.falling, i)
			end
		end
	end
	-- An item caught while it is still moving under physics (e.g. thrown up and caught) stops simulating first: settled where it
	-- is (managed physics), the game's own stopPhysics when it supplied setPhysics, otherwise the item's mesh, which grabbable
	-- itself set simulating.
	-- A catch (the item is moving fast when the grab starts) can use its own flight time. Measured before its physics stops, on the
	-- body that simulates (managed physics) or the item mesh.
	local caught = false
	if self.catchFlightTime ~= nil then
		local entry = managed[actor:get_address()]
		local body = entry ~= nil and uevrUtils.getValid(entry.body) or mesh
		local v = body:GetComponentVelocity()
		caught = v.X * v.X + v.Y * v.Y + v.Z * v.Z > self.catchSpeed * self.catchSpeed
	end
	if not settleManaged(actor) then
		if self.stopPhysics ~= nil then
			self.stopPhysics(actor, mesh)
		elseif mesh:IsAnySimulatingPhysics() then
			mesh:SetSimulatePhysics(false)
		end
	end
	local copy = uevrUtils.createStaticMeshComponent(mesh.StaticMesh, {visible = false, collisionEnabled = false})
	if copy == nil then return end
	for i = 0, mesh:GetNumMaterials() - 1 do copy:SetMaterial(i, mesh:GetMaterial(i)) end
	copy:SetVisibility(false, true)
	local location, rotation, scale = actor:K2_GetActorLocation(), actor:K2_GetActorRotation(), actor:GetActorScale3D()
	self.copy, self.heldActor, self.heldMesh, self.heldCollision = copy, actor, mesh, mesh:GetCollisionEnabled()
	self.handSamples, self.collectDeadline = {}, nil
	self.heldScale = ownScale or uevrUtils.vector(scale.X, scale.Y, scale.Z)
	mesh:SetCollisionEnabled(ECollisionEnabled.NoCollision)
	self.flight = {actor = actor, elapsed = 0, duration = flightTime or self.flightTime, location = uevrUtils.vector(location.X, location.Y, location.Z),
		rotation = uevrUtils.rotator(rotation.Pitch, rotation.Yaw, rotation.Roll), scale = uevrUtils.vector(scale.X, scale.Y, scale.Z)}
	attachments.forceGripUpdate()
	if copy.AttachParent == nil then
		clearHeld(self, true)
		return
	end
	-- flightDistance: the flight takes its full time from that far away or more, and proportionally less when the item starts
	-- closer to the hand (measured once, from the item to the copy in the hand), down to minFlightTime.
	if self.flightDistance ~= nil and self.flightDistance > 0 then
		local at = copy:K2_GetComponentLocation()
		local dx, dy, dz = at.X - location.X, at.Y - location.Y, at.Z - location.Z
		local fraction = math.min(math.sqrt(dx * dx + dy * dy + dz * dz) / self.flightDistance, 1)
		self.flight.duration = math.max(self.flight.duration * fraction, self.minFlightTime)
	end
	if caught and self.flight ~= nil then self.flight.duration = math.max(self.catchFlightTime, 0.001) end
end

-- A target scale with negative axes (e.g. a left hand mirrored with scale -1) can't be eased to from the item's scale per axis
-- without passing through 0, which shrinks the item to nothing on the way. Negating two scale axes and turning 180 degrees about
-- the third gives the same transform, so the target is rewritten to match the item's signs. An odd number of differing signs is
-- a mirror, which can't be eased at all; it is left on X (not Z, which would turn the item upside down) and returned for the
-- flight to mirror the item once.
function matchScaleSigns(fromScale, toRotation, toScale)
	local scale = {X = toScale.X, Y = toScale.Y, Z = toScale.Z}
	local flip, count = {}, 0
	for _, axis in ipairs({"X", "Y", "Z"}) do
		flip[axis] = (scale[axis] < 0) ~= (fromScale[axis] < 0)
		if flip[axis] then count = count + 1 end
	end
	local mirrorAxis = nil
	if count % 2 == 1 then
		mirrorAxis = "X"
		flip.X = not flip.X
	end
	local turn = nil
	if flip.Y and flip.Z then turn = "X" elseif flip.X and flip.Z then turn = "Y" elseif flip.X and flip.Y then turn = "Z" end
	if turn ~= nil then
		for _, axis in ipairs({"X", "Y", "Z"}) do
			if flip[axis] then scale[axis] = -scale[axis] end
		end
		local axis = uevrUtils.vector(turn == "X" and 1 or 0, turn == "Y" and 1 or 0, turn == "Z" and 1 or 0)
		toRotation = kismet_math_library:ComposeRotators(kismet_math_library:RotatorFromAxisAndAngle(axis, 180), toRotation)
	end
	return toRotation, scale, mirrorAxis
end

-- Moves the real item from where it was toward the hidden copy's current transform, then swaps them.
local function updateFlight(self, delta)
	local flight = self.flight
	local copy = uevrUtils.getValid(self.copy)
	if getLiveActor(flight.actor) == nil or copy == nil then
		clearHeld(self, true)
		return
	end
	flight.elapsed = flight.elapsed + delta
	local t = math.min(flight.elapsed / flight.duration, 1)
	local eased = t * t * (3 - 2 * t)
	local toLocation = copy:K2_GetComponentLocation()
	local toRotation, toScale, mirrorAxis = matchScaleSigns(flight.scale, copy:K2_GetComponentRotation(), copy:K2_GetComponentScale())
	-- A mirror can't be eased; the item is mirrored once, on the flight's first frame.
	if mirrorAxis ~= nil then flight.scale[mirrorAxis] = -flight.scale[mirrorAxis] end
	local s, sc = flight.location, flight.scale
	local location = uevrUtils.vector(s.X + (toLocation.X - s.X) * eased, s.Y + (toLocation.Y - s.Y) * eased, s.Z + (toLocation.Z - s.Z) * eased + math.sin(math.pi * t) * self.arcHeight)
	flight.actor:K2_SetActorLocationAndRotation(location, kismet_math_library:RLerp(flight.rotation, toRotation, eased, true), false, reusable_hit_result, true)
	flight.actor:SetActorScale3D(uevrUtils.vector(sc.X + (toScale.X - sc.X) * eased, sc.Y + (toScale.Y - sc.Y) * eased, sc.Z + (toScale.Z - sc.Z) * eased))
	if mirrorAxis ~= nil then refreshMirroring(self.heldMesh) end
	if t >= 1 then
		flight.actor:SetActorHiddenInGame(true)
		copy:SetVisibility(true, true)
		self.flight, self.held = nil, copy
		local haptic = self.arriveHaptic
		if haptic then uevrUtils.triggerHapticVibration(self.hand, 0, haptic.duration, haptic.frequency, haptic.amplitude) end
	end
end

-- Released items move under gravity and ease back to their own size. Each step is swept with the item's own collision, so it
-- stops on whatever it would rest on (a Visibility trace misses some terrain and lets items fall through it).
local function updateFalling(self, delta)
	for i = #self.falling, 1, -1 do
		local fall = self.falling[i]
		local actor = getLiveActor(fall.actor)
		local done = actor == nil
		if actor ~= nil then
			if not fall.landed then
				fall.vz = fall.vz - self.gravity * delta
				local x, y, z = fall.x + fall.vx * delta, fall.y + fall.vy * delta, math.max(fall.z + fall.vz * delta, fall.minZ)
				actor:K2_SetActorLocation(uevrUtils.vector(x, y, z), true, reusable_hit_result, false)
				if reusable_hit_result.bBlockingHit then
					local location = actor:K2_GetActorLocation()
					x, y, z = location.X, location.Y, location.Z
					local normalZ = reusable_hit_result.ImpactNormal.Z
					-- A floor (or starting inside something) ends the fall; a wall stops the sideways motion and a ceiling the upward motion.
					if reusable_hit_result.bStartPenetrating or normalZ > self.floorNormalZ then
						fall.landed = true
					else
						fall.vx, fall.vy = 0, 0
						if normalZ < 0 and fall.vz > 0 then fall.vz = 0 end
					end
				end
				fall.x, fall.y, fall.z = x, y, z
				if z <= fall.minZ then fall.landed = true end
			end
			fall.elapsed = fall.elapsed + delta
			local t = math.min(math.max(fall.elapsed - self.dropRescaleDelay, 0) / self.dropRescaleTime, 1) ^ self.dropRescaleEase
			local a, b = fall.fromScale, fall.toScale
			actor:SetActorScale3D(uevrUtils.vector(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t))
			done = fall.landed and t >= 1
		end
		if done then table.remove(self.falling, i) end
	end
end

-- Puts items that are still falling on their ground at once, with one sweep down to where they would stop, at their own size.
local function landFalling(self)
	for _, fall in ipairs(self.falling) do
		local actor = getLiveActor(fall.actor)
		if actor ~= nil then
			if not fall.landed then actor:K2_SetActorLocation(uevrUtils.vector(fall.x, fall.y, fall.minZ), true, reusable_hit_result, false) end
			actor:SetActorScale3D(fall.toScale)
		end
	end
	self.falling = {}
end

-- Recent hand positions while an item is carried, for the throw velocity at release.
local function sampleHand(self)
	local hand = controllers.getControllerLocation(self.hand)
	if hand == nil then return end
	local samples = self.handSamples
	samples[#samples + 1] = {t = self.clock, x = hand.X, y = hand.Y, z = hand.Z}
	while self.clock - samples[1].t > self.sampleHistory do table.remove(samples, 1) end
end

-- Throw velocity from the hand's movement over about throwWindow; nil for a gentle release, which just drops.
local function getThrowVelocity(self)
	local samples = self.handSamples
	local last, first = samples[#samples], nil
	if last == nil then return nil end
	for i = #samples - 1, 1, -1 do
		first = samples[i]
		if last.t - first.t >= self.throwWindow then break end
	end
	local dt = first ~= nil and last.t - first.t or 0
	if dt <= 0 then return nil end
	local scale = self.throwScale
	local vx, vy, vz = (last.x - first.x) / dt * scale, (last.y - first.y) / dt * scale, (last.z - first.z) / dt * scale
	local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
	if speed < self.throwMinSpeed then return nil end
	local k = math.min(1, self.throwMaxSpeed / speed)
	return {x = vx * k, y = vy * k, z = vz * k}
end

-- Collects the carried item during the collect gesture, otherwise throws it with the given velocity (or drops it when nil).
local function releaseItem(self, atCollect, velocity)
	if self.held ~= nil and atCollect and (self.collectCallback ~= nil or self.collectButton ~= nil) then
		if self.collectCallback ~= nil then self.collectCallback(self.heldActor) else self.collectFrames = self.collectFramesTotal end
		self.collectDeadline = self.clock + self.collectTimeout
	else
		clearHeld(self, true, true, velocity)
	end
end

-- The item a starting grip would grab or interact with, or nil. Remembered for the input callback that acts on the claim.
-- Every object type query (ObjectTypeQuery1..32), so a touch finds items whatever collision channel their collision uses.
local ALL_OBJECT_TYPES = {}
for i = 0, 31 do ALL_OBJECT_TYPES[#ALL_OBJECT_TYPES + 1] = i end

-- The grabbable item nearest the hand within touch reach, or nil. One overlap, on the frame a grip press starts.
local function findTouchTarget(self)
	local touch = self.touch
	if not touch.enabled or uevrUtils.getValid(pawn) == nil then return nil end
	local hand = controllers.getControllerLocation(self.hand)
	if hand == nil then return nil end
	actorClass = actorClass or uevrUtils.get_class("Class /Script/Engine.Actor")
	-- SphereOverlapActors takes and returns TArrays, which native Lua does not marshal, so it goes through the plugin bridge.
	local result = plugin.executeFunction(kismet_system_library, "SphereOverlapActors", uevrUtils.get_world(), hand, touch.distance, touch.objectTypes, actorClass, {pawn}, {})
	local best, bestDistance = nil, nil
	for _, actor in ipairs(result and result.OutActors or {}) do
		if canGrab(self, actor) then
			-- The item's mesh, which a game's physics can carry away from the actor's own location.
			local mesh = getItemMesh(actor)
			local at = mesh ~= nil and mesh:K2_GetComponentLocation() or actor:K2_GetActorLocation()
			local dx, dy, dz = at.X - hand.X, at.Y - hand.Y, at.Z - hand.Z
			local distance = dx * dx + dy * dy + dz * dz
			if bestDistance == nil or distance < bestDistance then best, bestDistance = actor, distance end
		end
	end
	return best
end

local function getClaimTarget(self, state)
	self.claimTarget, self.claimIsTouch = nil, nil
	if not self.enabled or (self.canClaim ~= nil and not self.canClaim(state)) then return nil end
	-- An item within reach of the hand comes first; the game's interaction target (or the pointed-at item) is the fallback.
	local touched = findTouchTarget(self)
	if touched ~= nil then
		self.claimTarget, self.claimIsTouch = touched, true
		return touched
	end
	local target = getSelected(self)
	if target == nil and self.getInteractTarget ~= nil then
		target = self.getInteractTarget(state)
		-- Without an interact button, only a grabbable target is worth claiming the grip for.
		if target ~= nil and self.interactButton == nil and (self.pointing.enabled or not canGrab(self, target)) then target = nil end
	end
	self.claimTarget = target
	return target
end

-- Hold to carry: a grip grabs the item, and it is carried while the grip is held. Releasing during the collect gesture collects it;
-- releasing anywhere else throws it with the hand's velocity, or drops it if the hand is nearly still. A grip on an interaction
-- target that is not grabbed holds interactButton for as long as the grip.
local function onInput(self, state)
	local pressed = uevrUtils.isButtonPressed(state, self.gripButton)
	local carrying = self.flight ~= nil or (self.held ~= nil and self.collectDeadline == nil)
	if pressed and not self.gripWasPressed then
		if self.toggleGrip and carrying then
			-- Dev toggle mode: the next press collects (during the collect gesture) or drops.
			releaseItem(self, self.isCollectGesture ~= nil and self.isCollectGesture(state), nil)
			self.gripLatched = true
		elseif not carrying and self.held == nil and grip.isOwner(self.hand, self.name) and self.getHandoff ~= nil and self.getHandoff(state) ~= nil then
			-- Hand to hand (two-hand grabbables): the other hand's item moves to this one, and this press now holds it.
			self.onHandoff(self.getHandoff(state))
			self.gripLatched = true
		elseif not carrying and self.held == nil and grip.isOwner(self.hand, self.name) and self.claimTarget ~= nil then
			local target, selected = self.claimTarget, getSelected(self)
			if self.claimIsTouch then
				-- Within reach: the item is already at the hand, so the flight is short.
				clearPointing(self)
				startFlight(self, target, self.touch.flightTime)
			elseif selected ~= nil then
				clearPointing(self)
				startFlight(self, selected)
			elseif not self.pointing.enabled and canGrab(self, target) then
				startFlight(self, target)
			else
				self.interacting = true
			end
			self.gripLatched = true
		end
	elseif pressed and carrying then
		-- The grip is already up at release, so remember each frame whether the collect gesture is being made.
		self.atCollect = self.isCollectGesture ~= nil and self.isCollectGesture(state) == true
	elseif not pressed and self.gripWasPressed and carrying and not self.toggleGrip then
		releaseItem(self, self.atCollect, getThrowVelocity(self))
	end
	if not pressed then self.gripLatched, self.atCollect, self.interacting = nil, nil, nil end
	self.gripWasPressed = pressed
	if self.interacting and self.interactButton ~= nil then uevrUtils.pressButton(state, self.interactButton) end
	if self.collectFrames ~= nil then
		uevrUtils.pressButton(state, self.collectButton)
		self.collectFrames = self.collectFrames > 1 and self.collectFrames - 1 or nil
	end
end

local function onTick(self, delta)
	self.clock = self.clock + delta
	if #self.falling > 0 then updateFalling(self, delta) end
	if self.flight ~= nil then
		sampleHand(self)
		updateFlight(self, delta)
	elseif self.held ~= nil then
		sampleHand(self)
		-- The real item can be destroyed while its copy is held (e.g. collected); drop the copy too.
		if uevrUtils.getValid(self.held) == nil or getLiveActor(self.heldActor) == nil then
			-- Gone after a collect release: the game took it.
			local haptic = self.collectHaptic
			if haptic ~= nil and self.collectDeadline ~= nil and getLiveActor(self.heldActor) == nil then
				uevrUtils.triggerHapticVibration(self.hand, 0, haptic.duration, haptic.frequency, haptic.amplitude)
			end
			clearHeld(self, true)
		elseif self.collectDeadline ~= nil and self.clock >= self.collectDeadline then
			-- The collect press went to something else; drop the item instead.
			clearHeld(self, true, true)
		elseif self.dropWhenHandTaken then
			-- The game's grip callback put something else in the hand (e.g. a weapon drawn). What the hand grips is checked
			-- rather than the copy's parent, which is briefly gone while the hands are rebuilt.
			local current = attachments.getCurrentGrippedAttachment(self.hand)
			if current ~= nil and current:get_address() ~= self.held:get_address() then clearHeld(self, true, true) end
		end
	else
		updatePointing(self)
	end
end

-- Profiling (uevrUtils.profiler; does nothing until profiling is toggled on): the per-frame and per-grab work.
onTick = uevrUtils.profiler:wrap("Grabbable: tick", onTick)
onInput = uevrUtils.profiler:wrap("Grabbable: input", onInput)
getClaimTarget = uevrUtils.profiler:wrap("Grabbable: claim target", getClaimTarget)
findTouchTarget = uevrUtils.profiler:wrap("Grabbable: touch overlap", findTouchTarget)
startFlight = uevrUtils.profiler:wrap("Grabbable: grab start", startFlight)
updateFlight = uevrUtils.profiler:wrap("Grabbable: flight update", updateFlight)
updateFalling = uevrUtils.profiler:wrap("Grabbable: falling update", updateFalling)
clearHeld = uevrUtils.profiler:wrap("Grabbable: release", clearHeld)

local MultiGrabbable = {}
MultiGrabbable.__index = MultiGrabbable

local function isOtherHandsItem(multi, hand, actor)
	for otherHand, other in pairs(multi.byHand) do
		local held = otherHand ~= hand and other:getHeldActor() or nil
		if held ~= nil and held:get_address() == actor:get_address() then return true end
	end
	return false
end

-- Moves a held item's hold from one hand's grabbable to the other's: the same copy and real item, now released, thrown and
-- collected by the receiving hand. Nothing is destroyed, unhidden or flown; the next grip update attaches the copy to the new hand
-- (grabbable's grip callback returns it for that hand, and nothing for the giving one, which is detached first).
local function transferHold(from, to)
	to.copy, to.held, to.heldActor, to.heldMesh, to.heldCollision, to.heldScale = from.copy, from.held, from.heldActor, from.heldMesh, from.heldCollision, from.heldScale
	to.flight, to.collectDeadline, to.atCollect, to.handSamples = nil, nil, nil, {}
	from.flight, from.held, from.copy, from.heldActor, from.heldMesh, from.heldCollision, from.heldScale = nil, nil, nil, nil, nil, nil, nil
	from.collectDeadline, from.atCollect, from.handSamples = nil, nil, {}
	attachments.forceGripUpdate()
	refreshMirroring(to.copy)
	local haptic = to.arriveHaptic
	if haptic then uevrUtils.triggerHapticVibration(to.hand, 0, haptic.duration, haptic.frequency, haptic.amplitude) end
end

-- One grabbable per hand (the single-hand code, unchanged), with the game's callbacks given the hand, the other hand's item
-- excluded, and a hand the game's grip callback has something in left alone.
local function newMultiHand(options)
	local multi = setmetatable({byHand = {}, list = {}, isGrabbable = options.isGrabbable}, MultiGrabbable)
	local handoffDistance = options.handoffDistance == false and 0 or default(options.handoffDistance, 15)
	local names = options.names or {}
	local baseName = options.name or "grabbable"
	for _, hand in ipairs(options.hands) do
		local handOptions = {}
		for key, value in pairs(options) do handOptions[key] = value end
		handOptions.hands, handOptions.names = nil, nil
		handOptions.hand = hand
		handOptions.name = names[hand] or (baseName .. (hand == Handed.Left and "_left" or "_right"))
		if type(options.dropWhenHandTaken) == "table" then handOptions.dropWhenHandTaken = options.dropWhenHandTaken[hand] == true end
		handOptions.isGrabbable = function(actor)
			return options.isGrabbable ~= nil and options.isGrabbable(actor, hand) == true and not isOtherHandsItem(multi, hand, actor)
		end
		handOptions.canClaim = function(state)
			if attachments.getCurrentGrippedAttachment(hand) ~= nil then return false end
			return options.canClaim == nil or options.canClaim(state, hand) ~= false
		end
		-- Hand to hand: a grip that starts with this (empty, free) hand near the item the other hand holds takes it.
		handOptions.getHandoff = function(state)
			local receiver = multi.byHand[hand]
			if handoffDistance <= 0 or receiver == nil or not receiver.enabled or receiver.flight ~= nil or receiver.held ~= nil then return nil end
			if not handOptions.canClaim(state) then return nil end
			local location = controllers.getControllerLocation(hand)
			if location == nil then return nil end
			for otherHand, other in pairs(multi.byHand) do
				local copy = otherHand ~= hand and other.held ~= nil and other.collectDeadline == nil and uevrUtils.getValid(other.copy) or nil
				if copy ~= nil then
					local at = copy:K2_GetComponentLocation()
					local dx, dy, dz = at.X - location.X, at.Y - location.Y, at.Z - location.Z
					if dx * dx + dy * dy + dz * dz <= handoffDistance * handoffDistance then return other end
				end
			end
			return nil
		end
		handOptions.onHandoff = function(source)
			transferHold(source, multi.byHand[hand])
		end
		if options.getInteractTarget ~= nil then handOptions.getInteractTarget = function(state) return options.getInteractTarget(state, hand) end end
		if options.isCollectGesture ~= nil then handOptions.isCollectGesture = function(state) return options.isCollectGesture(state, hand) end end
		if options.collectCallback ~= nil then handOptions.collectCallback = function(actor) return options.collectCallback(actor, hand) end end
		if options.setPhysics ~= nil then handOptions.setPhysics = function(actor, mesh, velocity) return options.setPhysics(actor, mesh, velocity, hand) end end
		local instance = M.new(handOptions)
		multi.byHand[hand] = instance
		multi.list[#multi.list + 1] = instance
	end
	return multi
end

function MultiGrabbable:setEnabled(value)
	for _, instance in ipairs(self.list) do instance:setEnabled(value) end
end

function MultiGrabbable:isEnabled()
	return self.list[1] ~= nil and self.list[1]:isEnabled()
end

function MultiGrabbable:setToggleGrip(value)
	for _, instance in ipairs(self.list) do instance:setToggleGrip(value) end
end

function MultiGrabbable:reset()
	for _, instance in ipairs(self.list) do instance:reset() end
end

-- A hand's value, or with hand nil the first hand that has one.
local function firstOf(multi, hand, method)
	if hand ~= nil then
		local instance = multi.byHand[hand]
		return instance ~= nil and instance[method](instance) or nil
	end
	for _, instance in ipairs(multi.list) do
		local value = instance[method](instance)
		if value then return value end
	end
	return nil
end

function MultiGrabbable:getHeldMesh(hand)
	return firstOf(self, hand, "getHeldMesh")
end

function MultiGrabbable:getHeldActor(hand)
	return firstOf(self, hand, "getHeldActor")
end

function MultiGrabbable:isHolding(hand)
	return firstOf(self, hand, "isHolding") == true
end

function MultiGrabbable:canGrab(actor, hand)
	local instance = self.byHand[hand]
	if instance == nil or actor == nil or not instance:isEnabled() or instance:isHolding() then return false end
	if attachments.getCurrentGrippedAttachment(hand) ~= nil then return false end
	return self.isGrabbable ~= nil and self.isGrabbable(actor, hand) == true and not isOtherHandsItem(self, hand, actor)
end

function M.new(options)
	options = options or {}
	if options.hands ~= nil then return newMultiHand(options) end
	local hand = default(options.hand, Handed.Left)
	local pointingOptions = options.pointing or {}
	local touchOptions = options.touch or {}
	local self = setmetatable({
		name = default(options.name, "grabbable"),
		claimPriority = default(options.claimPriority, grip.NORMAL),
		heldPriority = default(options.heldPriority, 200),
		hand = hand,
		gripButton = default(options.gripButton, hand == Handed.Right and XINPUT_GAMEPAD_RIGHT_SHOULDER or XINPUT_GAMEPAD_LEFT_SHOULDER),
		isGrabbable = options.isGrabbable or function() return false end,
		canClaim = options.canClaim,
		getInteractTarget = options.getInteractTarget,
		interactButton = options.interactButton,
		isCollectGesture = options.isCollectGesture,
		collectButton = options.collectButton,
		collectCallback = options.collectCallback,
		collectFramesTotal = default(options.collectFrames, 6),
		collectTimeout = default(options.collectTimeout, 0.5),
		collectHaptic = options.collectHaptic,
		arriveHaptic = default(options.arriveHaptic, {duration = 0.03, amplitude = 0.3}),
		toggleGrip = options.toggleGrip == true,
		flightTime = default(options.flightTime, 0.4),
		flightDistance = options.flightDistance,
		minFlightTime = default(options.minFlightTime, 0.03),
		catchFlightTime = options.catchFlightTime ~= false and default(options.catchFlightTime, 0) or nil,
		catchSpeed = default(options.catchSpeed, 100),
		arcHeight = default(options.arcHeight, 15),
		sampleHistory = default(options.sampleHistory, 0.2),
		throwWindow = default(options.throwWindow, 0.06),
		throwScale = default(options.throwScale, 1.3),
		throwMinSpeed = default(options.throwMinSpeed, 100),
		throwMaxSpeed = default(options.throwMaxSpeed, 1500),
		gravity = default(options.gravity, 980),
		maxFallDistance = default(options.maxFallDistance, 1000),
		floorNormalZ = default(options.floorNormalZ, 0.7),
		dropRescaleTime = default(options.dropRescaleTime, 0.5),
		dropRescaleEase = default(options.dropRescaleEase, 1),
		dropRescaleDelay = default(options.dropRescaleDelay, 0),
		keepDropScale = options.keepDropScale == true,
		setPhysics = options.setPhysics,
		physics = options.physics ~= nil and {getBody = options.physics.getBody, linearDamping = options.physics.linearDamping,
			angularDamping = options.physics.angularDamping, lockRotation = options.physics.lockRotation,
			settleMinTime = default(options.physics.settleMinTime, 0.5)} or nil,
		dropWhenHandTaken = options.dropWhenHandTaken == true,
		stopPhysics = options.stopPhysics,
		-- Set by the two-hand wrapper: getHandoff(state) -> the other hand's grabbable to take from, onHandoff(source).
		getHandoff = options.getHandoff,
		onHandoff = options.onHandoff,
		handoffPriority = default(options.handoffPriority, default(options.heldPriority, 200)),
		touch = {
			enabled = touchOptions.enabled == true,
			distance = default(touchOptions.distance, 15),
			objectTypes = default(touchOptions.objectTypes, ALL_OBJECT_TYPES),
			flightTime = default(touchOptions.flightTime, 0.1),
		},
		pointing = {
			enabled = pointingOptions.enabled == true,
			highlight = pointingOptions.highlight,
			shouldScan = pointingOptions.shouldScan,
			objectTypes = default(pointingOptions.objectTypes, {1, 3}),
			maxDistance = default(pointingOptions.maxDistance, 400),
			selectCos = math.cos(math.rad(default(pointingOptions.selectAngle, 15))),
			keepCos = math.cos(math.rad(default(pointingOptions.keepAngle, 20))),
			switchMargin = default(pointingOptions.switchMargin, 0.02),
			palmSign = default(pointingOptions.palmSign, 1),
			candidates = {},
		},
		enabled = false,
		falling = {},
		handSamples = {},
		clock = 0,
	}, Grabbable)
	instances[#instances + 1] = self
	if #instances == 1 then registerGripUpdate() end

	-- Start claim (libs/grip): grip.lua hides an owned press from the game for the whole press.
	grip.registerClaim(self.name, function(claimHand, state, press)
		if claimHand ~= self.hand then return nil end
		if self.flight ~= nil or self.held ~= nil then return self.heldPriority end
		if self.enabled and self.getHandoff ~= nil and self.getHandoff(state) ~= nil then return self.handoffPriority end
		if getClaimTarget(self, state) ~= nil then return self.claimPriority end
		return nil
	end)
	-- Only controller 0 carries the player's input (as in grip.lua); games that also poll empty slots would otherwise read every
	-- held grip as released on those calls.
	uevrUtils.registerOnPreInputGetStateCallback(function(retval, userIndex, state)
		if userIndex ~= 0 then return end
		onInput(self, state)
	end)
	uevrUtils.registerPostEngineTickCallback(function(engine, delta) onTick(self, delta) end)
	if self.pointing.enabled then
		uevrUtils.setInterval(default(pointingOptions.scanInterval, 250), function() scanPointing(self) end)
	end
	-- Rebuilding the hands hides everything attached to them; show the copy again when it is reattached.
	attachments.registerAttachmentChangeCallback(function(id, gripHand, attachment)
		if attachment ~= nil and attachment == self.held then attachment:SetVisibility(true, true) end
	end)
	uevrUtils.registerLevelChangeCallback(function() self:reset() end)
	uevr.params.sdk.callbacks.on_script_reset(function() self:reset() end)
	return self
end

function Grabbable:setEnabled(value)
	self.enabled = value == true
	if self.enabled then return end
	clearPointing(self)
	clearHeld(self, true)
	landFalling(self)
	if self.physics ~= nil then settleAllManaged() end
end

function Grabbable:isEnabled()
	return self.enabled
end

function Grabbable:getHeldMesh()
	return uevrUtils.getValid(self.copy)
end

function Grabbable:getHeldActor()
	return getLiveActor(self.heldActor)
end

function Grabbable:setToggleGrip(value)
	self.toggleGrip = value == true
end

function Grabbable:isHolding()
	return self.held ~= nil or self.gripLatched == true
end

function Grabbable:reset()
	clearPointing(self)
	clearHeld(self, false)
	landFalling(self)
	self.collectFrames, self.gripLatched, self.atCollect, self.interacting, self.claimTarget = nil, nil, nil, nil, nil
end

return M
