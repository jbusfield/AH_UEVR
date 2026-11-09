--[[
Usage
    Drop the libs folder containing this file into your project folder
    Add code like this in your script:
        local grip = require("libs/grip")

    Decides which system owns each press of a hand's grip button, so several systems (menus, gestures, ladders, grabbing,
    chords such as LB+RB) can share the grips without knowing about each other. It holds no game or mod knowledge: systems
    register claims under their own names with their own priorities, and the mod decides the order. Nothing runs until the
    first claim is registered, so projects that never use grip.lua pay nothing.

    Concepts
        Press
            One press of a hand's grip button, from the frame it goes down until the frame it comes up. grip.lua reads the
            button in a pre-input callback at priority grip.PRE_INPUT_PRIORITY (90). A press created or hidden by a callback
            that runs earlier (higher priority) is seen as it is at that point; presses synthesized by callbacks that run later
            (e.g. a spell pressing LB+RB for the game) are not grip presses.

        Claim
            A function a system registers to say "this press is mine". It returns a priority number, or nil for no claim.
            Claims should be cheap and free of side effects: they only decide, the system acts once it owns the press.
            - Start claim (default): asked once, on the frame the press starts. If it wins, it owns the press until the press
              ends or it yields, whatever happens during the press.
            - Continuous claim: asked on every frame of the press. It owns the press only on frames where it returns a priority
              higher than the start owner's and every other claim's, so it can take a press that is already underway, and the
              press returns to the start owner when it stops claiming.
            - Chord claim: covers both grips at once. Asked on every frame both grips are down, with both presses. When it wins,
              it owns both presses on those frames.
            - Shared claim: an observer. It never owns a press and never changes who does, but systems can ask whether it is
              claiming (hasClaim), and it can still hide the press from the game while it claims.

        Owner
            The name of the winning claim for a hand's press on the current frame, or nil when nothing claims it.
            Highest priority wins. Ties: the start owner keeps the press, otherwise the claim registered first wins.

        Hiding
            Each claim says what its press is hidden from while it owns it (or, for a shared claim, while it claims):
            - grip.Hide.Game (default): the grip button is cleared in a post-input callback after all others (priority
              grip.POST_INPUT_PRIORITY, -150), so the game never sees it but every system's input callbacks still do
              (e.g. hand grip animation still closes the hand).
            - grip.Hide.Systems: also cleared right after the owner is decided, so pre-input callbacks that run after grip.lua
              see the button released too (as a ladder that must keep gestures and menus from reacting does).
            - grip.Hide.None: the game sees the press (e.g. a chord the game itself should handle).

        Hiders
            For hiding that does not follow ownership (a system that hides some presses it does not own, or decides frame by
            frame), a system registers a hider instead: a function asked on every frame a hand's press exists, whoever owns it.
            When it returns true the press is hidden from the game, and, with fromPriority, also from every pre-input callback
            with a lower priority (grip.lua clears the button in a pre-input callback of its own at fromPriority). Register at a
            fromPriority just below the system's own input callback when the hider reads state that callback updates.

        Yield
            An owner can give up a press part way through with grip.yield. The press then goes to the next start claim in line, as if
            the yielding claim had never claimed it (every start claim made when the press started is kept in priority order), unless
            a continuous or chord claim beats it; with none left it goes to nobody (the game sees it, unless something else hides it).
            A start claim that yields on the press's first frame (e.g. a ladder whose grab fails) leaves the press exactly as the other
            claims decided it.

    Rules
        - Priorities are plain numbers chosen by the mod; grip.lua defines no feature-specific values. Conventional levels:
              grip.LOW = 10, grip.NORMAL = 50, grip.HIGH = 100
        - Claims are asked in registration order.
        - Only user index 0 is handled.

    Available functions:

    grip.registerClaim(name, claimFunc, options)
        name: string - the owner name reported for presses this claim wins (unique per claim)
        claimFunc:
            start or continuous claim: function(hand, state, press) -> number|nil
            chord claim:               function(state, leftPress, rightPress) -> number|nil
            hand: Handed.Left or Handed.Right
            state: the XInput state of the current frame
            press: see Press info below
        options (all optional):
            continuous: boolean (default false)
            chord: boolean (default false) - implies continuous
            shared: boolean (default false)
            hide: grip.Hide value (default grip.Hide.Game)

    grip.getOwner(hand) -> string|nil
        The owner of the hand's press on the current frame.
    grip.isOwner(hand, name) -> boolean
    grip.hasClaim(hand, name) -> boolean
        True while a shared claim named name is claiming the hand's press.
    grip.yield(hand, name)
        If name owns the hand's press, it gives it up for the rest of the press.
    grip.isPressed(hand) -> boolean
        The grip as grip.lua read it this frame (before any hiding).
    grip.getPress(hand) -> press|nil
        Press info while the hand's grip is down.
    grip.setGripButton(hand, button)
        The XInput button that counts as the hand's grip. Defaults: LEFT_SHOULDER / RIGHT_SHOULDER.
    grip.registerOwnerChangeCallback(func)
        func(hand, newOwner, oldOwner) - called when a hand's owner changes, including to nil when the press ends.
    grip.registerHider(name, hideFunc, options)
        hideFunc: function(hand, press, state) -> boolean - true hides the hand's press this frame
            state: the XInput state as the other input callbacks have left it at that point (grip.lua decides every hand before
                hiding any, so a hider checking both grips sees them as they were before grip.lua's own hiding)
        options (optional):
            fromPriority: number - also hide from pre-input callbacks below this priority

    Press info (read-only table)
        hand: Handed
        startTime: os.clock() when the press started
        age: seconds since the press started (updated every frame)
        startOwner: the name of the start claim that won, or nil
        owner: the current owner, or nil

    Examples (how Hogwarts Legacy uses it)
        The mod keeps its precedence order in one module, helpers/grip_priority.lua, shared by the systems below:

            local M = {
                LADDER = 1000,       -- a grip that starts with a ladder rung in reach
                ITEM_HELD = 200,     -- Physical Item Grab: a press while an item is already flying or held
                PALETTE_WHEEL = 100, -- a left grip that starts with the palette wheel open
                HEAD_GESTURE = 90,   -- a left grip that starts at the ear (menu)
                ITEM_GRAB = 50,      -- Physical Item Grab: grab, or hold X on, what the game's interaction prompt is on
            }
            return M

            local GRIP_PRIORITY = require("helpers/grip_priority")

        Ladder (ladder.lua; a start claim hidden from systems, so gestures, the palette and the grab never react to a climbing grip.
        It takes hold when it wins, and yields if the grab fails so the press goes to whatever else claimed it):

            grip.registerClaim("ladder", function(hand, state, press)
                if enabled and status.ladder ~= nil and isInReach(hand) then return GRIP_PRIORITY.LADDER end
                return nil
            end, {hide = grip.Hide.Systems})

            grip.registerOwnerChangeCallback(function(hand, newOwner, oldOwner)
                if newOwner == "ladder" then
                    if climber:grab(hand) then
                        claimedGrips[hand] = true
                        uevrUtils.triggerHapticVibration(hand, 0, 0.04, 1000, 0.4)
                    else
                        grip.yield(hand, "ladder")
                    end
                elseif oldOwner == "ladder" and claimedGrips[hand] then
                    claimedGrips[hand] = nil
                    climber:release(hand)
                end
            end)

            -- On level change the ladder lets go of any press it still owns:
            for _, hand in ipairs({Handed.Left, Handed.Right}) do grip.yield(hand, "ladder") end

        Palette (palette.lua; a start claim for the open wheel, and a hider for its own hiding rules. Its input callback runs at 6 and
        decides consumeGrip, so the hider runs at 5.9: callbacks above 6 (gestures, grip.lua) still see the grip, those below
        (accessories, holster, hand animation, grab) do not):

            grip.registerClaim("palette", function(hand, state, press)
                if hand == Handed.Left and enabled and M.isWheelOpen() then return GRIP_PRIORITY.PALETTE_WHEEL end
                return nil
            end, {hide = grip.Hide.None}) -- the hider below does the palette's hiding

            grip.registerHider("palette", function(hand, press)
                return enabled and consumeGrip[hand] == true and accessPawn == pawn and gadgetAvailable and ui.isRemapDisabled() == false
            end, {fromPriority = 5.9})

            -- The gadget copy stands aside for a grip another system owns (e.g. an item grab), on the press's first frame:
            local owner = grip.getOwner(Handed.Left)
            leftAccessory = allowed and (accessories.isGripHandEngaged(Handed.Left) or (owner ~= nil and owner ~= "palette"))

        Head gestures (main.lua; a start claim keeps the palette copy and the item grab away from a grip that starts at the ear, and a
        hider hides a grip that fires an ear or mouth gesture at any point in the press from the game only, so the palette can still
        drink at the mouth):

            grip.registerClaim("head_gesture", function(hand, state, press)
                if hand ~= Handed.Left then return nil end
                local _, _, _, gripEar = gestures.getHeadGestures(state, Handed.Left, true)
                if gripEar then return GRIP_PRIORITY.HEAD_GESTURE end
                return nil
            end, {hide = grip.Hide.None})

            grip.registerHider("head_gesture", function(hand, press)
                return hand == Handed.Left and status.headGestureGripLeft == true
            end)

        Physical Item Grab (libs/grabbable registers the claim itself; interactions.lua passes the mod's priorities):

            local itemGrab = grabbable.new({
                name = "item_grab",
                claimPriority = GRIP_PRIORITY.ITEM_GRAB,
                heldPriority = GRIP_PRIORITY.ITEM_HELD,
                ...
            })

            -- Inside grabbable: a start claim, hidden from the game for the whole press, acted on only when owned.
            grip.registerClaim(self.name, function(claimHand, state, press)
                if claimHand ~= self.hand then return nil end
                if self.flight ~= nil or self.held ~= nil then return self.heldPriority end
                if getClaimTarget(self, state) ~= nil then return self.claimPriority end
                return nil
            end)
            if grip.isOwner(self.hand, self.name) and self.claimTarget ~= nil then ... grab, or hold the interact button ... end

        Holster (holster.lua; a hider that checks both grips in the state it is given, so LB+RB is hidden while the wand is put away
        only when both still reach the game after the other systems' own hiding):

            grip.registerHider("holster", function(hand, press, state)
                return wandStowed and uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_LEFT_SHOULDER)
                    and uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_RIGHT_SHOULDER)
            end)

        Chord claims (not used by Hogwarts Legacy, whose LB+RB Ancient Magic handling stays inside the palette): a claim on both grips,
        e.g. giving LB+RB to the game when the right grip joins the left within a short window:

            grip.registerClaim("two_hand_action", function(state, left, right)
                if math.abs(right.startTime - left.startTime) <= 0.15 then return grip.HIGH end
                return nil
            end, {chord = true, hide = grip.Hide.None})
]]

local uevrUtils = require("libs/uevr_utils")

local M = {}

M.LOW, M.NORMAL, M.HIGH = 10, 50, 100
M.Hide = {Game = "game", Systems = "systems", None = "none"}
M.PRE_INPUT_PRIORITY = 90
M.POST_INPUT_PRIORITY = -150

local OWNER_CHANGED = "grip_owner_changed"

local hands = {Handed.Left, Handed.Right}
local gripButtons = {[Handed.Left] = XINPUT_GAMEPAD_LEFT_SHOULDER, [Handed.Right] = XINPUT_GAMEPAD_RIGHT_SHOULDER}
local claims = {} -- in registration order: {name, func, continuous, chord, shared, hide}
local presses = {} -- per hand while its grip is down
local pressed = {} -- per hand, as read this frame
local hooksInstalled = false
local hiders = {} -- in registration order: {name, func, fromPriority}
local hiderHooks = {} -- fromPriority -> true once its pre-input callback is registered

local function isHiddenBy(hider, hand, state)
	local press = presses[hand]
	return press ~= nil and hider.func(hand, press, state) == true
end

-- The first start claim in line that has not yielded ({name, priority, hide}), or nil.
local function currentStart(press)
	for _, candidate in ipairs(press.startCandidates) do
		if not press.yielded[candidate.name] then return candidate end
	end
	return nil
end

-- The name and hiding of the claim that should own the press this frame. The start claim in line holds the press unless a continuous
-- or chord claim beats its priority; among those, the first registered wins a tie.
local function resolveOwner(press, state, chordName, chordPriority, chordHide)
	local owner, priority, hide = nil, nil, nil
	local start = currentStart(press)
	if start ~= nil then owner, priority, hide = start.name, start.priority, start.hide end
	for _, claim in ipairs(claims) do
		if claim.continuous and not claim.chord and not claim.shared and not press.yielded[claim.name] then
			local p = claim.func(press.hand, state, press)
			if p ~= nil and (priority == nil or p > priority) then owner, priority, hide = claim.name, p, claim.hide end
		end
	end
	if chordName ~= nil and not press.yielded[chordName] and (priority == nil or chordPriority > priority) then
		owner, priority, hide = chordName, chordPriority, chordHide
	end
	return owner, hide
end

local function setOwner(press, owner, hide)
	local old = press.owner
	press.owner, press.ownerHide = owner, hide
	if old ~= owner then uevrUtils.executeUEVRCallbacks(OWNER_CHANGED, press.hand, owner, old) end
end

local function startPress(hand, state, now)
	local press = {hand = hand, startTime = now, age = 0, yielded = {}, shared = {}, startCandidates = {}}
	for _, claim in ipairs(claims) do
		if not claim.continuous and not claim.chord then
			local p = claim.func(hand, state, press)
			if p ~= nil then
				if claim.shared then
					press.shared[claim.name] = claim.hide
				else
					-- Start claims are kept in line, highest priority first; on a tie the one registered first stays ahead.
					local line = press.startCandidates
					local at = #line + 1
					for i, candidate in ipairs(line) do
						if p > candidate.priority then
							at = i
							break
						end
					end
					table.insert(line, at, {name = claim.name, priority = p, hide = claim.hide})
				end
			end
		end
	end
	press.startOwner = press.startCandidates[1] ~= nil and press.startCandidates[1].name or nil
	presses[hand] = press
	return press
end

local function endPress(hand)
	local press = presses[hand]
	presses[hand] = nil
	if press ~= nil and press.owner ~= nil then uevrUtils.executeUEVRCallbacks(OWNER_CHANGED, hand, nil, press.owner) end
end

local function onPreInput(retval, userIndex, state)
	if userIndex ~= 0 or state == nil or state.Gamepad == nil then return end
	local now = os.clock()
	for _, hand in ipairs(hands) do
		pressed[hand] = uevrUtils.isButtonPressed(state, gripButtons[hand])
		if pressed[hand] then
			if presses[hand] == nil then startPress(hand, state, now) end
			presses[hand].age = now - presses[hand].startTime
		elseif presses[hand] ~= nil then
			endPress(hand)
		end
	end
	-- Chord claims are asked once per frame with both presses.
	local chordName, chordPriority, chordHide = nil, nil, nil
	local left, right = presses[Handed.Left], presses[Handed.Right]
	if left ~= nil and right ~= nil then
		for _, claim in ipairs(claims) do
			if claim.chord then
				local p = claim.func(state, left, right)
				if p ~= nil and (chordPriority == nil or p > chordPriority) then chordName, chordPriority, chordHide = claim.name, p, claim.hide end
			end
		end
	end
	for _, hand in ipairs(hands) do
		local press = presses[hand]
		if press ~= nil then
			-- Shared continuous claims are recorded every frame; shared start claims keep what they said at the start.
			for _, claim in ipairs(claims) do
				if claim.shared and claim.continuous then
					press.shared[claim.name] = claim.func(hand, state, press) ~= nil and claim.hide or nil
				end
			end
			setOwner(press, resolveOwner(press, state, chordName, chordPriority, chordHide))
			if press.owner ~= nil and press.ownerHide == M.Hide.Systems then uevrUtils.unpressButton(state, gripButtons[hand]) end
		end
	end
end

-- Hides owned presses (and presses a hiding shared claim is claiming, or a hider hides) from the game, after every other input
-- callback. Every hand is decided before any is hidden, so hiders see the input as the other systems left it.
local function onPostInput(retval, userIndex, state)
	if userIndex ~= 0 or state == nil or state.Gamepad == nil then return end
	local hide = {}
	for _, hand in ipairs(hands) do
		local press = presses[hand]
		if press ~= nil then
			local hidden = press.owner ~= nil and press.ownerHide ~= M.Hide.None
			for _, sharedHide in pairs(press.shared) do
				if sharedHide ~= M.Hide.None then hidden = true end
			end
			for _, hider in ipairs(hiders) do
				if hidden then break end
				hidden = isHiddenBy(hider, hand, state)
			end
			hide[hand] = hidden
		end
	end
	for _, hand in ipairs(hands) do
		if hide[hand] then uevrUtils.unpressButton(state, gripButtons[hand]) end
	end
end

local function installHooks()
	if hooksInstalled then return end
	hooksInstalled = true
	uevrUtils.registerOnPreInputGetStateCallback(onPreInput, M.PRE_INPUT_PRIORITY)
	uevrUtils.registerOnPostInputGetStateCallback(onPostInput, M.POST_INPUT_PRIORITY)
end

-- Hides presses from the pre-input callbacks below fromPriority, for the hiders registered with it. Every hand is decided before any
-- is hidden.
local function installHiderHook(fromPriority)
	if hiderHooks[fromPriority] then return end
	hiderHooks[fromPriority] = true
	uevrUtils.registerOnPreInputGetStateCallback(function(retval, userIndex, state)
		if userIndex ~= 0 or state == nil or state.Gamepad == nil then return end
		local hide = {}
		for _, hand in ipairs(hands) do
			for _, hider in ipairs(hiders) do
				if hider.fromPriority == fromPriority and isHiddenBy(hider, hand, state) then
					hide[hand] = true
					break
				end
			end
		end
		for _, hand in ipairs(hands) do
			if hide[hand] then uevrUtils.unpressButton(state, gripButtons[hand]) end
		end
	end, fromPriority)
end

function M.registerHider(name, hideFunc, options)
	if type(name) ~= "string" or type(hideFunc) ~= "function" then return end
	options = options or {}
	hiders[#hiders + 1] = {name = name, func = hideFunc, fromPriority = options.fromPriority}
	installHooks()
	if options.fromPriority ~= nil then installHiderHook(options.fromPriority) end
end

function M.registerClaim(name, claimFunc, options)
	if type(name) ~= "string" or type(claimFunc) ~= "function" then return end
	options = options or {}
	local chord = options.chord == true
	claims[#claims + 1] = {
		name = name,
		func = claimFunc,
		chord = chord,
		continuous = chord or options.continuous == true,
		shared = not chord and options.shared == true,
		hide = options.hide or M.Hide.Game,
	}
	installHooks()
end

function M.getOwner(hand)
	local press = presses[hand]
	return press ~= nil and press.owner or nil
end

function M.isOwner(hand, name)
	return M.getOwner(hand) == name
end

function M.hasClaim(hand, name)
	local press = presses[hand]
	return press ~= nil and press.shared[name] ~= nil
end

function M.yield(hand, name)
	local press = presses[hand]
	if press == nil or press.owner ~= name then return end
	press.yielded[name] = true
	-- Until the next frame decides again (when continuous and chord claims are asked), the next start claim in line holds the press.
	local start = currentStart(press)
	setOwner(press, start ~= nil and start.name or nil, start ~= nil and start.hide or nil)
end

function M.isPressed(hand)
	return pressed[hand] == true
end

function M.getPress(hand)
	return presses[hand]
end

function M.setGripButton(hand, button)
	if gripButtons[hand] ~= nil and button ~= nil then gripButtons[hand] = button end
end

function M.registerOwnerChangeCallback(func)
	uevrUtils.registerUEVRCallback(OWNER_CHANGED, func)
end

return M
