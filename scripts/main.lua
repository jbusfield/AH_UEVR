local uevrUtils = require('libs/uevr_utils')
local controllers = require('libs/controllers')
local configui = require("libs/configui")
local reticule = require("libs/reticule")
local hands = require('libs/hands')
local attachments = require('libs/attachments')
local input = require('libs/input')
local pawnModule = require('libs/pawn')
local animation = require('libs/animation')
local montage = require('libs/montage')
local interaction = require('libs/interaction')
local ui = require('libs/ui')
local remap = require('libs/remap')
local gestures = require('libs/gestures')
local gunstock = require('libs/gunstock')

--uevrUtils.setLogLevel(LogLevel.Debug)
-- reticule.setLogLevel(LogLevel.Debug)
-- -- input.setLogLevel(LogLevel.Debug)
-- attachments.setLogLevel(LogLevel.Debug)
-- -- animation.setLogLevel(LogLevel.Debug)
-- ui.setLogLevel(LogLevel.Debug)
-- remap.setLogLevel(LogLevel.Debug)
-- --hands.setLogLevel(LogLevel.Debug)
--interaction.setLogLevel(LogLevel.Debug)


uevrUtils.setDeveloperMode(true)
-- hands.enableConfigurationTool()

ui.init()
montage.init()
interaction.init()
attachments.init()
attachments.setGripUpdateTimeout(400)
reticule.init()
pawnModule.init()
remap.init()
input.init()
gunstock.showConfiguration()

local wasArmsAnimating = false
local isInAnimationCutscene = false
local isInCar = false
local isClimbing = false
local materialUtils = nil
local leftHandDirectionOffset = 40
local activateCassetteMenu = false
local isGrabbingCassette = false
local jumpTurnDeadzone = 32000

--temp debug param
--local socketList = {"None"}

local versionTxt = "v1.0.3"
local title = "Atomic Heart First Person Mod " .. versionTxt
local configDefinition = {
	{
		panelLabel = "Atomic Heart Config",
		saveFile = "atomic_heart_config",
		layout = spliceableInlineArray
		{
			{ widgetType = "text", id = "title", label = title },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Reticule" }, { widgetType = "begin_rect", },
				expandArray(reticule.getConfigurationWidgets,{{id="uevr_reticule_update_distance", initialValue=200},}),
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "UI" }, { widgetType = "begin_rect", },
				expandArray(ui.getConfigurationWidgets),
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Input" }, { widgetType = "begin_rect", },
				expandArray(input.getConfigurationWidgets),
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Control" }, { widgetType = "begin_rect", },
				{
					widgetType = "drag_float",
					id = "leftHandDirectionOffset",
					label = "Left Hand Target Angle",
					speed = 1,
					range = {-90, 90},
					initialValue = leftHandDirectionOffset
				},
				{
					widgetType = "drag_int",
					id = "jumpTurnDeadzone",
					label = "Jump/Turn Deadzone",
					speed = 1,
					range = {0, 100},
					initialValue = 0
				},
				-- {
				-- 	widgetType = "combo",
				-- 	id = "handle_socket_right",
				-- 	label = "Handle Socket Right",
				-- 	selections = socketList,
				-- 	initialValue = 1
				-- },
				-- {
				-- 	widgetType = "combo",
				-- 	id = "handle_socket_left",
				-- 	label = "Handle Socket Left Hand",
				-- 	selections = socketList,
				-- 	initialValue = 1
				-- },
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
		}
	}
}

local status = {}
local function setInCar(value)
	isInCar = value
	pawnModule.hideArmsBones(not isInCar)
	hands.hideHands(isInCar)
end
local function setIsClimbing(value) --0 not climbing, 1 climbing, 2 hanging by left hand
	isClimbing = value
	if value == 0 then
		pawnModule.hideArmsBones(true)
		hands.hideHands(false)
		input.setDisabled(false)
	elseif value == 1 then
		pawnModule.hideArmsBones(false)
		hands.hideHands(true)
		input.setDisabled(true)
	elseif value == 2 then
		pawnModule.hideArmsBones(true)
		hands.hideHand(Handed.Left, true)
		hands.hideHand(Handed.Right, false)
		input.setDisabled(true)
	end
end

attachments.registerOnGripUpdateCallback(function()
	if not isInAnimationCutscene and uevrUtils.getValid(pawn) ~= nil and pawn.GetCurrentWeapon ~= nil then
		local currentWeapon = pawn:GetCurrentWeapon()
		local hand = hands.getHandComponent(Handed.Right)
		if currentWeapon ~= nil and hand ~= nil and currentWeapon.RootComponent ~= nil then
			--No idea why but the weapon debug arrows are being shown when firing so hide them
			if currentWeapon.Barrel and currentWeapon.Barrel.DebugArrowSize ~= nil then
				currentWeapon.Barrel.DebugArrowSize = 0
			end

			--Fix FOV distortion on weapons
			pawn:EnablePaniniProjection(false)
			--Fix Panini on Cassettes
			if materialUtils ~= nil then
				local cassetteMesh = uevrUtils.getValid(currentWeapon,{"AHWeaponCassetteSlot","LastSpawnedCassette","Mesh"})
				if cassetteMesh ~= nil then
					materialUtils:EnablePaniniForMesh(cassetteMesh,  false)
				end
			end

			-- if string.find(uevrUtils.getShortName(currentWeapon), "BP_Krepysh") then
			-- 	return currentWeapon.RootComponent
			if string.find(uevrUtils.getShortName(currentWeapon), "BP_Kuzmich") then
				--secondary floating magazine needs to be hidden
				currentWeapon.SK_Kuzmich_Magazine:call("SetRenderCustomDepth", false)
				currentWeapon.SK_Kuzmich_Magazine:call("SetRenderInMainPass", false)
				currentWeapon.Barrel.RelativeLocation.X = 50 --move barrel forward to avoid firing into the capsule component
				return currentWeapon.RootComponent, controllers.getController(Handed.Right), nil, nil, nil, nil, true
			else
				--return currentWeapon.RootComponent, hand, nil, nil, nil, nil, true
				return currentWeapon.RootComponent, controllers.getController(Handed.Right), nil, nil, nil, nil, true
			end
		end
	end
end)

attachments.registerAttachmentChangeCallback(function()
	local currentWeapon = pawn:GetCurrentWeapon()
	--fixes plasma gun beam FX not hiding properly on activation
	if currentWeapon.BaseWeaponAttack ~= nil and currentWeapon.BaseWeaponAttack.BeamCenter ~= nil then
		currentWeapon.BaseWeaponAttack.BeamCenter:SetVisibility(false, false)
		currentWeapon.BaseWeaponAttack.Beam_Left:SetVisibility(false, false)
		currentWeapon.BaseWeaponAttack.Beam_Right:SetVisibility(false, false)
		currentWeapon.BaseWeaponAttack.ChargingProjectileFX:SetVisibility(false, false)
	end

	-- Reduces processing when no melee weapon is equipped
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_RIGHT, attachments.isActiveAttachmentMelee(Handed.Right))
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_LEFT, attachments.isActiveAttachmentMelee(Handed.Right))

	-- if currentWeapon ~= nil and currentWeapon.Handle ~= nil then
	-- 	uevrUtils.getSocketNames(currentWeapon.Handle, function(names)
	-- 		if names == nil then
	-- 			print("No socket names received")
	-- 			return
	-- 		end
	-- 		socketList = names
	-- 		configui.setSelections("handle_socket_right", socketList)
	-- 		configui.setSelections("handle_socket_left", socketList)
	-- 		-- for i, name in ipairs(names) do
	-- 		-- 	print("Socket " .. i .. ": " .. tostring(name))
	-- 		-- end
	-- 	end)
	-- end

	-- if currentWeapon ~= nil and currentWeapon.Handle ~= nil then
	-- 	local names = currentWeapon.Handle:GetAllSocketNames()
	-- 	if names == nil then
	-- 		print("No sockets found on weapon handle", currentWeapon.Handle.Sockets)
	-- 	else
	-- 		for _, name in pairs(names) do
	-- 			uevrUtils.print("Socket: " .. tostring(name))
	-- 		end
	-- 	end
	-- end

end)

local function isPlayerPlaying()
	if isInAnimationCutscene or (uevrUtils.getValid(pawn) ~= nil and pawn.bIsScripted) then
		return false
	end
	return true
end

--return true if input should be disabled, second param is priority
input.registerIsDisabledCallback(function()
	return not isPlayerPlaying() or isInCar, 0
end)
--return true if hands should be hidden, second param is priority
hands.registerIsHiddenCallback(function()
	return not isPlayerPlaying(), 0
end)
hands.onCreatedCallback(function(hand, component)
	--Fix FOV distortion on hands
	if materialUtils ~= nil then
		materialUtils:EnablePaniniForMesh(component,  false)
	end
end)

--return true if hands should be animating from an external source, second param is priority
hands.registerIsAnimatingFromMeshCallback(function(hand)
	return hand == Handed.Left and wasArmsAnimating or nil
end)
--return true if arm bones should be hidden
pawnModule.registerIsArmBonesHiddenCallback(function()
	return isPlayerPlaying(), 0
end)
--return true if motion sickness causing scene is playing
ui.registerIsInMotionSicknessCausingSceneCallback(function()
	return isInAnimationCutscene, 0
end)

--callback from uevrUtils that fires whenever the game is paused
function on_game_paused(isPaused)
	uevrUtils.print("Paused " .. tostring(isPaused))
end

--callback from uevrUtils that fires whenever the UEVR UI state changes
function on_uevr_ui_change(uiDrawn)
	uevrUtils.print("UEVR UI drawn " .. tostring(uiDrawn))
end

--callback from uevrUtils that fires whenever the level changes
function on_level_change(level, levelName)
	uevrUtils.print("Level changed to " .. levelName)
	isInCar = false

	--Get the Atomic Heart Specific MaterialUtils in order to fix panini projection
	materialUtils = uevrUtils.find_default_instance("Class /Script/AtomicHeart.MaterialUtils")
	if materialUtils == nil then
		uevrUtils.print("MaterialUtils not found")
	end

end

--callback from uevrUtils that fires whenever a cutscene change is detected
function on_cutscene_change(isActive)
	if isActive then
		uevrUtils.print("In Cinematic")
	else
		uevrUtils.print("Out of Cinematic")
	end
end

function on_client_restart(newPawn)
	uevrUtils.print("Pawn changed to " .. newPawn:get_full_name())
end

function on_character_hidden(isHidden)
	uevrUtils.print("Character hidden changed to " .. tostring(isHidden))
	--uevr.params.vr.set_mod_value("VR_CameraForwardOffset", isHidden and "25.000000" or "0.000000") -- Realign camera when Nora active
	--vr.set_mod_value("VR_CameraRightOffset", isHidden and "-25.000000" or "0.000000")

end

--BlueprintGeneratedClass hooks generally need to be registered whenever the level changes
uevrUtils.registerLevelChangeCallback(function()
	hook_function("BlueprintGeneratedClass /Game/Core/Player/BP_PlayerCharacter.BP_PlayerCharacter_C", "K2_OnDrivingVehicle", false, nil,
		function(fn, obj, locals, result)
			--print("K2_OnDrivingVehicle called", locals, result, locals.IsDriving)
			setInCar(locals.IsDriving)
		end
	, true)
end)

local function setDefaultTargeting(handed)
	if handed == Handed.Left then
		input.setAimMethod(input.AimMethod.LEFT_CONTROLLER)
		input.setAimRotationOffset({Pitch=0, Yaw=leftHandDirectionOffset, Roll=0})
		input.setAimCameraOverride(true)
		reticule.setTargetMethod(reticule.ReticuleTargetMethod.LEFT_CONTROLLER)
		reticule.setTargetRotationOffset({Pitch=0, Yaw=leftHandDirectionOffset, Roll=0})
	else
		input.setAimMethod(input.AimMethod.RIGHT_WEAPON)
		input.setAimRotationOffset({Pitch=0, Yaw=0, Roll=0})
		input.setAimCameraOverride(false)
		reticule.setTargetMethod(reticule.ReticuleTargetMethod.CAMERA)
		reticule.setTargetRotationOffset()
	end
	status["currentTargetingHand"] = handed
end
--won't callback unless an updateDeferral hasnt been called in the last 1000ms
uevrUtils.createDeferral("melee_attack", 1000, function()
	setDefaultTargeting(Handed.Right)
	--reticule.setHidden(false)

	uevr.api:get_player_controller(0):EquippedItemPrimaryInputReleased(0.0)
	uevrUtils.print("Melee attack ended")
end)

local weaponMontages = {
	BP_Shved_C_SK_Shved_Base = {"AM_Shved_PlayerHands_Right_Attack", "AM_Shved_Hands_Release_Left_Attack"}, --reversed anims look better for some reason
	BP_Lisa_C_SK_Lisa_HandleBase = {"AM_PlayerCharacterHands_Lisa_Attack_Left", "AM_PlayerCharacterHands_Lisa_Attack_Right"},
	BP_Pashtet_C_SK_Pashtet = {"AM_PlayerCharacterHands_Pashtet_Right_Attack", "AM_PlayerCharacterHands_Pashtet_Attack_Left"},
	BP_Zvezdochka_C_SK_ZvezdochkaBase = {"AM_PlayerCharacterHands_Zvezdochka_Attack_Left", "AM_PlayerCharacterHands_Zvezdochka_Attack_Right"},
	BP_Snejok_C_SK_Snejok_Base = {"AM_Snejok_PlayerHands_Right_Attack", "AM_Snejok_Hands_Release_Left_Attack"},
	BP_EmptyHands_C_Mesh = {"AM_PlayerCharacterHands_Arms_Attack01_Release_Montage", "AM_PlayerCharacterHands_Arms_Attack01_Release_Montage"},
	BP_Klusha_C_SK_Klusha_Handle01 = {"AM_PlayerCharacterHands_Klusha_Combo_A1", "AM_PlayerCharacterHands_Klusha_Combo_A2"},
	BP_Shved_Limbo_C_SK_Shved_Limbo_Base = {"AM_Shved_PlayerHands_Right_Attack", "AM_Shved_Hands_Release_Left_Attack"},
	BP_Gromoverzhec_C_SK_Gromoverzec_Base02 = {"AM_PlayerCharacterHands_Gromoverzec_SimpleAttack_01", "AM_PlayerCharacterHands_Gromoverzec_SimpleAttack_02"},
}
local function animateMelee(direction) -- 0-left, 1-right
	--print("Animating melee in direction:", direction)
	if attachments.isActiveAttachmentMelee(Handed.Right) == true then
		--print("Melee attack started")
		input.setAimMethod(input.AimMethod.RIGHT_WEAPON)
		local offset = attachments.getActiveAttachmentMeleeRotationOffset(Handed.Right)
		input.setAimRotationOffset(offset) --adjust reticule during melee to match the melee weapon head
		--input.setAimRotationOffset(uevrUtils.rotator(40,-65,0)) --adjust reticule during melee to match the melee weapon head
		--reticule.setTargetRotationOffset(offset)

		-- reticule.setTargetMethod(reticule.ReticuleTargetMethod.CAMERA)
		-- reticule.setTargetRotationOffset(uevrUtils.rotator(40,25,0))

		--reticule.setHidden(true)
		uevr.api:get_player_controller(0):EquippedItemPrimaryInputPressed(1.0) -- Trigger melee attack

		local id = attachments.getActiveAttachmentID(Handed.Right)
		if id ~= nil and weaponMontages[id] ~= nil and weaponMontages[id][direction + 1] ~= nil then
			local animName = weaponMontages[id][direction + 1]
			uevrUtils.print("Animating melee with animation: " .. animName)
			montage.playMontage(animName, 5.0) -- set speed to 5.0 to make it more responsive
		else
			uevrUtils.print("No melee animation found for attachment ID: " .. id)
		end
		uevrUtils.updateDeferral("melee_attack")
	end
end

gestures.registerSwipeRightCallback(function()
	--print("Swipe Right detected")
	animateMelee(1)
end)

gestures.registerSwipeLeftCallback(function()
	--print("Swipe Left detected")
	animateMelee(0)
end)

local function handleVehicle(montageName)
	-- --getting in and out of car
	if montageName == "AM_PlayerHandsGetInMoskvichFL" or montageName == "AM_PlayerHandsGetInMoskvichFR" then
		--catching it early with animation rather than the hook function so we can disable input 
		--during the animation and get a better player orientation in the car
		--print("Getting in car")
		setInCar(true)
	end
 	if montageName == "AM_PlayerHandsGetOutMoskvichFL" or montageName == "AM_PlayerHandsGetOutMoskvichFR" or montageName == "AM_PlayerCharacterHands_Moskvich_JumpOutSlow" or  montageName == "AM_PlayerCharacterHands_Moskvich_JumpOutFast" then
		setTimeout(3000, function()
			--print("Getting out of car")
			setInCar(false)
		end) --delay to make animation look better
	end
end

function on_montage_change(montageObject, montageName)
	handleVehicle(montageName)

	-- if montageName == "AM_PlayerCharacterHands_AK_ReloadTactical_Montage" then
	-- 	montage.setPlaybackRate(montageObject, "", 0.1)
	-- end
	-- if montageName == "AM_PlayerCharacterHands_PM_CassetteReInstall_Montage" or montageName == "AM_PlayerCharacterHands_PM_CasseteRemove_Montage" then
	-- 	montage.pause(montageObject)
	-- 	delay(2500, function()
	-- 		montage.stop(montageObject, "", 0.0)
	-- 	end)
	-- end

	--fixes a bug in the game
	if montageName == "AM_PlayerCharacterHands_ClimbingMantle" then
		isInAnimationCutscene = false
		wasArmsAnimating = false
		return
	end

	--all montages that start with AM_ will make the left hand animate (unless overriden in the Montages UI)
	local isArmsAnimating = string.sub(montageName, 1, 3) == "AM_" or string.sub(montageName, 1, 3) == "AS_" or string.sub(montageName, 1, 2) == "A_"
	if isArmsAnimating ~= wasArmsAnimating then
		wasArmsAnimating = isArmsAnimating
	end

	if montageName == "" or isArmsAnimating then
		isInAnimationCutscene = false
	else
		uevrUtils.print("Montage playing " .. montageName)
		isInAnimationCutscene = true
	end

	-- if montageName == "AM_PlayerCharacterHands_Plasmagun_ReloadFast" or montageName == "AM_PlayerCharacterHands_Plasmagun_Reload" then
	-- 	-- local rightHand = hands.getHandComponent(Handed.Right)
	-- 	-- if rightHand ~= nil then
	-- 	-- 	local currentWeapon = pawn:GetCurrentWeapon()
	-- 	-- 	if currentWeapon ~= nil and currentWeapon.Handle ~= nil then
	-- 	-- 		print(currentWeapon:get_full_name())
	-- 	-- 		local socketName = socketList[configui.getValue("handle_socket_right")]
	-- 	-- 		print("Attaching handle to socket: " .. tostring(socketName))
	-- 	-- 		rightHand:K2_AttachTo(currentWeapon.Handle, uevrUtils.fname_from_string(socketName), EAttachmentRule.KeepWorld, false)
	-- 	-- 		--uevrUtils.set_component_relative_transform(rightHand)
	-- 	-- 	end
	-- 	-- end
	-- 	local leftHand = hands.getHandComponent(Handed.Left)
	-- 	if leftHand ~= nil then
	-- 		local currentWeapon = pawn:GetCurrentWeapon()
	-- 		if currentWeapon ~= nil and currentWeapon.Handle ~= nil then
	-- 			print(currentWeapon:get_full_name())
	-- 			local socketName = socketList[configui.getValue("handle_socket_left")]
	-- 			print("Attaching handle to socket: " .. tostring(socketName))
	-- 			leftHand:K2_AttachTo(currentWeapon.Mesh, uevrUtils.fname_from_string(socketName), EAttachmentRule.SnapToTarget, false)
	-- 			--uevrUtils.set_component_relative_transform(leftHand)
	-- 		end
	-- 	end
	-- end
end

local function getActiveLockOfType(lockType)
	local locks = uevrUtils.find_all_instances("Class /Script/AtomicHeart.UniversalLock", false)
	if locks ~= nil then
		for key, lock in pairs(locks) do
			local parts = uevrUtils.getValid(lock, {"LockParts"})
			if parts ~= nil then
---@diagnostic disable-next-line: param-type-mismatch
				for _, part in pairs(parts) do
					if part ~= nil and part:is_a(uevrUtils.get_class(lockType)) then
						if lock.bInteracted then
							return lock
						end
					else
					end
				end
			end
		end
	end
	return nil
end

ui.registerWidgetChangeCallback("WBP_UniversalLockTooltipWidget_C", function(active)
	if active and getActiveLockOfType("Class /Script/AtomicHeart.CodeLock") ~= nil then
		interaction.setInteractionType(interaction.InteractionType.Mesh)
		interaction.setAllowMouseUpdate(true)
		interaction.setMeshTraceChannel(11)
		interaction.setMouseCursorVisibility(false)
	else
		interaction.setInteractionType(interaction.InteractionType.Widget)
		interaction.setAllowMouseUpdate(false)
	end
end)

uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)
	if state.Gamepad.bRightTrigger > 0 or uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_RIGHT_SHOULDER) then
		setDefaultTargeting(Handed.Right)
    elseif state.Gamepad.bLeftTrigger > 0 or uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_LEFT_SHOULDER) then
		setDefaultTargeting(Handed.Left)
    end

	isGrabbingCassette = false
	if uevrUtils.getValid(pawn) ~= nil and pawn.GetCurrentWeapon ~= nil then
		local currentWeapon = pawn:GetCurrentWeapon()
		if currentWeapon ~= nil and currentWeapon:HasCassetteSlot() then
			isGrabbingCassette = gestures.detectComponentGrab(state, Handed.Left, uevrUtils.getValid(currentWeapon,{"AHWeaponCassetteSlot"}), 15)
			if isGrabbingCassette then
				uevrUtils.unpressButton(state, XINPUT_GAMEPAD_RIGHT_SHOULDER)
				uevrUtils.pressButton(state, XINPUT_GAMEPAD_X)
			end
		end
	end

	-- prevent annoying accidental snap turn when jumping
	if state.Gamepad.sThumbRY >= jumpTurnDeadzone or state.Gamepad.sThumbRY <= -jumpTurnDeadzone then
		state.Gamepad.sThumbRX = 0
	end

	if activateCassetteMenu then
		--pull the left stick down momentarily so that it selects the cassette radial item
		state.Gamepad.sThumbLY = -32000
	end

end, 5) --increased priority to get values before remap occurs

ui.registerWidgetChangeCallback("WBP_RadialMenu_C", function(active)
	if active and isGrabbingCassette then
		activateCassetteMenu = true
		delay(100, function()
			if activateCassetteMenu == true then
				local radialMenu = uevrUtils.getValid(uevr.api:get_player_controller(0),{"HUDWidgetInstance","RadialMenuInstance"})
				if radialMenu ~= nil then radialMenu:OnApplyWindow() end
			end
			activateCassetteMenu = false
		end)
	elseif not active then
		activateCassetteMenu = false
	end
end)

-- -- --infinite health
-- uevrUtils.setInterval(500, function()
-- 	local health = uevrUtils.getValid(uevr.api:get_player_controller(0), {"Character", "AttributeSet", "Health"})
-- 	if health ~= nil then
-- 		health.BaseValue = 9999999
-- 		health.CurrentValue = 9999999
-- 	end

-- end)

local wasClimmbing = nil
function on_post_engine_tick(engine, delta)
	if uevrUtils.getValid(pawn) ~= nil and pawn.IsClimbing ~= nil then
		local currentClimbing = pawn:IsClimbing() and 1 or 0
		if currentClimbing == 1 then
			local currentWeapon = pawn:GetCurrentWeapon()
			if currentWeapon ~= nil then
				currentClimbing = 2
			end
		end

		if wasClimmbing ~= currentClimbing then
			setIsClimbing(currentClimbing)
			wasClimmbing = currentClimbing
		end
	end
end
-- local function checkWidgets()
-- 		local allWidgets = uevrUtils.find_all_instances("WidgetBlueprintGeneratedClass /Game/Core/UI/Interaction/WBP_IteractionIndicatorWidget.WBP_IteractionIndicatorWidget_C", false)
-- 		if allWidgets ~= nil then
-- 			print("Checking widgets")
-- 			for index, widget in pairs(allWidgets) do
-- 				--widget.ActionButton.ButtonImage.Brush.ResourceObject = lb
-- 			end
-- 		end
-- end

configui.onCreateOrUpdate("leftHandDirectionOffset", function(value)
	leftHandDirectionOffset = value
	setDefaultTargeting(status["currentTargetingHand"])
end)
configui.onCreateOrUpdate("jumpTurnDeadzone", function(value)
	print("Configured deadzone")
	jumpTurnDeadzone = 32000 - (value / 100 * 32000)
end)

configui.create(configDefinition)

-- configui.onCreateOrUpdate("handle_socket", function(value)
-- 	leftHandDirectionOffset = value
-- 	setDefaultTargeting(status["currentTargetingHand"])
-- end)


-- register_key_bind("F1", function()
-- 	uevrUtils.getSocketNames(pawn.Mesh, function(names)
-- 		if names == nil then
-- 			print("No socket names received")
-- 			return
-- 		end
-- 		for i, name in ipairs(names) do
-- 			print("Socket " .. i .. ": " .. tostring(name))
-- 		end
-- 	end)
-- 	-- hands.setInitialTransform(Handed.Left)
-- 	-- hands.setInitialTransform(Handed.Right)
-- 	--uevr.api:dispatch_custom_event("GetTArray:FName" .. ":" .. pawn.Mesh:get_full_name() .. ":" .. "GetAllSocketNames")
-- 	--uevr.api:dispatch_custom_event("GetTArray:FName" .. ":" .. pawn.Mesh:get_full_name() .. ":" .. "GetAllSocketNames", "")
-- end)

-- register_key_bind("F2", function()
-- 	print("F2 pressed")
-- 	pawn:K2_AddActorLocalOffset(uevrUtils.vector(50,50,50), false, reusable_hit_result, true)
-- end)

-- register_key_bind("F3", function()
-- 	print("F3 pressed")
-- 	checkWidgets()
-- end)

hook_function("Class /Script/AtomicHeart.QTESubsystem", "OnQTEPlay", true, nil,
	function(fn, obj, locals, result)
		print("OnQTEPlay called", locals)
		remap.setDisabled(true)
	end
, true)

hook_function("Class /Script/AtomicHeart.QTESubsystem", "OnQTEStop", true, nil,
	function(fn, obj, locals, result)
		print("OnQTEStop called", locals)
		remap.setDisabled(false)
	end
, true)

-- hook_function("Class /Script/AtomicHeart.QTESubsystem", "OnQTEPreStart", true, nil,
-- 	function(fn, obj, locals, result)
-- 		print("OnQTEPreStart called", locals)
-- 	end
-- , true)

-- hook_function("Class /Script/AtomicHeart.QTESubsystem", "OnQTEActionResult", true, nil,
-- 	function(fn, obj, locals, result)
-- 		print("OnQTEActionResult called", locals, result)
-- 	end
-- , true)

-- hook_function("Class /Script/AtomicHeart.QTESubsystem", "OnQTEActionResult", true, nil,
-- 	function(fn, obj, locals, result)
-- 		print("OnQTEActionResult called", locals, result)
-- 	end
-- , true)

--Not sure why this one isnt called, maybe because the BlueprintGeneratedClass version of it is getting called instead?
-- hook_function("Class /Script/AtomicHeart.AHPlayerCharacter", "K2_OnDrivingVehicle", true, nil,
-- 	function(fn, obj, locals, result)
-- 		print("K2_OnDrivingVehicle called", locals, result, locals.IsDriving)
-- 	end
-- , true)

