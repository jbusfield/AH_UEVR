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
--local dev = require('libs/uevr_dev')
--dev.init()

uevrUtils.setLogLevel(LogLevel.Debug)
reticule.setLogLevel(LogLevel.Debug)
-- input.setLogLevel(LogLevel.Debug)
attachments.setLogLevel(LogLevel.Debug)
-- animation.setLogLevel(LogLevel.Debug)
ui.setLogLevel(LogLevel.Debug)
remap.setLogLevel(LogLevel.Debug)
--hands.setLogLevel(LogLevel.Debug)

uevrUtils.setDeveloperMode(true)
--hands.enableConfigurationTool()
ui.init()
montage.init()
interaction.init()
attachments.init()
reticule.init()
pawnModule.init()
remap.init()
input.init()

local wasArmsAnimating = false
local isInAnimationCutscene = false
local isInCar = false
local isClimbing = false
local materialUtils = nil
local leftHandDirectionOffset = 40
local GameplayStatics = nil
local activateCassetteMenu = false
local isGrabbingCassette = false


--local playerUtils = nil

local versionTxt = "v1.0.0"
local title = "Atomic Heart First Person Mod " .. versionTxt
local configDefinition = {
	{
		panelLabel = "Atomic Heart Config",
		saveFile = "atomic_heart_config",
		layout = spliceableInlineArray
		{
			{ widgetType = "text", id = "title", label = title },
			-- { widgetType = "indent", width = 20 }, { widgetType = "text", label = "Input" }, { widgetType = "begin_rect", },
			-- 	expandArray(input.getConfigurationWidgets, {{id="eyeOffset",isHidden=false},}),
			-- { widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			-- { widgetType = "new_line" },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Reticule" }, { widgetType = "begin_rect", },
				expandArray(reticule.getConfigurationWidgets,{{id="uevr_reticule_update_distance", initialValue=200},}),
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "UI" }, { widgetType = "begin_rect", },
				expandArray(ui.getConfigurationWidgets),
				{
					widgetType = "drag_float",
					id = "leftHandDirectionOffset",
					label = "Left Hand Target Angle",
					speed = 1,
					range = {-90, 90},
					initialValue = leftHandDirectionOffset
				},
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
		}
	}
}
configui.create(configDefinition)
configui.onCreateOrUpdate("leftHandDirectionOffset", function(value)
	leftHandDirectionOffset = value
end)

local function replaceText()
	local lb = nil
	local sprites = uevrUtils.find_all_instances("Class /Script/Paper2D.PaperSprite",true)
	print(sprites)
	for index, sprite in pairs(sprites) do
		print(sprite:get_full_name())
		if sprite:get_full_name() == "PaperSprite /Game/Development/UI/Textures/HUD/Frames/XBox/XBOX_LB_02_png.XBOX_LB_02_png" then
			lb = sprite
		end
	end
	print("Here", lb)
	if lb ~= nil then
		local allMeshes = uevrUtils.find_all_instances("WidgetBlueprintGeneratedClass /Game/Core/UI/Interaction/WBP_IteractionIndicatorWidget.WBP_IteractionIndicatorWidget_C", false)
		if allMeshes ~= nil then
			print("Updating widgets")
			for index, mesh in pairs(allMeshes) do
				mesh.ActionButton.ButtonImage.Brush.ResourceObject = lb
			end
		end
	end
end

--reticule.showConfiguration(nil, {{id="uevr_reticule_update_distance",initialValue = 800},})

-- local remapParameters = {}
-- remapParameters = {
--     right_shoulder = {{state = remap.InputState.PRESSED, unpress = true, actions = {left_trigger = {state = remap.ActionState.PRESS}}}, },
--     left_shoulder = {{state = remap.InputState.PRESSED, unpress = true, actions = {right_shoulder = {state = remap.ActionState.PRESS}}}, },
--     left_trigger = {{state = remap.InputState.TOGGLED_ON, unpress = true, threshold = 100, actions = {left_shoulder = {state = remap.ActionState.PRESS}}}, {state = remap.InputState.TOGGLED_OFF, threshold = 100, actions = {left_shoulder = {state = remap.ActionState.PRESS}}}},
-- --    right_trigger = {{state = remap.InputState.PRESSED, unpress = true, threshold = 100}}
-- }
-- remap.setRemapParameters(remapParameters)

-- reticule.setReticuleType(reticule.ReticuleType.CUSTOM)
-- reticule.registerOnCustomCreateCallback(function()
-- 	local AHStatics = uevrUtils.find_default_instance("Class /Script/AtomicHeart.AHGameplayStatics")
-- 	if AHStatics ~= nil then
-- 		local hud = AHStatics:GetPlayerHUD(uevrUtils.getWorld(), 0)
-- 		if hud ~= nil then
-- 			return reticule.ReticuleType.WIDGET, hud.CrosshairWidget,  { removeFromViewport = true, twoSided = true }
-- 		end
-- 	end
-- 	return nil
-- end)

-- uevrUtils.registerUEVRCallback("on_interaction_hit", function (hitResult)
-- 	print(hitResult.Actor:get_full_name())	
-- end)
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

			if string.find(uevrUtils.getShortName(currentWeapon), "BP_Krepysh") then
				--Big boy injures you when attached to mesh
				return currentWeapon.RootComponent
			elseif string.find(uevrUtils.getShortName(currentWeapon), "BP_Kuzmich") then
				--secondary floating magazine needs to be hidden
				currentWeapon.SK_Kuzmich_Magazine:call("SetRenderCustomDepth", false)
				currentWeapon.SK_Kuzmich_Magazine:call("SetRenderInMainPass", false)

				--DLC shotgun hits the pawn when connected to the hand mesh so connect to the raw controller (I didnt feel like redoing all other attachments to match)
				--Unfortunately when doing this, the secondary shock weapon fires from origin points that are not located on the gun itself although generally points in the right direction. Havent figured out why
				return currentWeapon.RootComponent
			else
				return currentWeapon.RootComponent, hand, nil, nil, nil, nil, true
				--return currentWeapon.RootComponent, controllers.getController(Handed.Right)
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
	--GameplayStatics = uevrUtils.find_default_instance("Class /Script/AtomicHeart.AHGameplayStatics")

	--playerUtils = uevrUtils.find_first_of("Class /Script/AtomicHeart.PlayerUtils", true)
	replaceText()

	-- attempt to move interaction to head based
	-- if pawn ~= nil then
	-- 	local interactionComponent = uevrUtils.getChildComponent(pawn.FPCamera, "PlayerInteractionZone")
	-- 	if interactionComponent ~= nil then
	-- 	interactionComponent:DetachFromParent(false,false)
	-- 	uevrUtils.attachComponentToController(2, interactionComponent, "")
	-- 	end
	-- end
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

-- interaction.registerOnHitCallback(function(hitResult)
-- 	print(hitResult.Component:get_full_name(), hitResult.Actor:get_full_name())
-- 	--print("Face Index " .. hitResult.FaceIndex .. " Time " .. hitResult.Time .. " Distance " .. hitResult.Distance .. " Location " .. hitResult.Location.X .. ", " .. hitResult.Location.Y .. ", " .. hitResult.Location.Z .. " Item " .. tostring(hitResult.Item) .. " ElementIndex " .. hitResult.ElementIndex .. " bBlockingHit " .. tostring(hitResult.bBlockingHit) .. " Actor " .. hitResult.Actor:get_full_name() .. " BoneName " .. hitResult.BoneName .. " PenetrationDepth " .. hitResult.PenetrationDepth .. " bStartPenetrating " .. tostring(hitResult.bStartPenetrating) .. " Component " .. hitResult.Component:get_full_name())
-- 	-- if hitResult.BoneName ~= "None" then
-- 	-- 	--print("Hit bone:", hitResult.BoneName, "Hit Component:", hitResult.Component:get_full_name())
-- 	-- end
-- end)

--BlueprintGeneratedClass hooks generally need to be registered whenever the level changes
uevrUtils.registerLevelChangeCallback(function()
	hook_function("BlueprintGeneratedClass /Game/Core/Player/BP_PlayerCharacter.BP_PlayerCharacter_C", "K2_OnDrivingVehicle", false, nil,
		function(fn, obj, locals, result)
			--print("K2_OnDrivingVehicle called", locals, result, locals.IsDriving)
			setInCar(locals.IsDriving)
		end
	, true)

	-- hook_function("BlueprintGeneratedClass /Game/DLC/Core/Weapons/Range/Plasmagun/BP_Plasmagun_Attack.BP_Plasmagun_Attack_C", "K2_OnSecondaryActionPressed", false, nil,
	-- 	function(fn, obj, locals, result)
	-- 		print("K2_OnSecondaryActionPressed called")--, locals, result)
	-- 		obj.BeamCenter:SetVisibility(true, false)
	-- 		obj.Beam_Left:SetVisibility(true, false)
	-- 		obj.Beam_Right:SetVisibility(true, false)
	-- 		obj.ChargingProjectileFX:SetVisibility(true, false)
	-- 	end
	-- , true)

	-- hook_function("BlueprintGeneratedClass /Game/DLC/Core/Weapons/Range/Plasmagun/BP_Plasmagun_Attack.BP_Plasmagun_Attack_C", "K2_OnSecondaryActionReleased", false, nil,
	-- 	function(fn, obj, locals, result)
	-- 		print("K2_OnSecondaryActionReleased called")--, locals, result)
	-- 		obj.BeamCenter:SetVisibility(false, false)
	-- 		obj.Beam_Left:SetVisibility(false, false)
	-- 		obj.Beam_Right:SetVisibility(false, false)
	-- 		obj.ChargingProjectileFX:SetVisibility(false, false)
	-- 	end
	-- , true)
--plasmaGun.BaseWeaponAttack. BeamCenter, BeamLeft, BeamRight, ChargingProjectileFX SetVisibility(false,false)


end)


local function setDefaultTargeting(handed)
	if handed == Handed.Left then
		input.setAimMethod(input.AimMethod.LEFT_CONTROLLER)
		input.setAimRotationOffset({Pitch=0, Yaw=leftHandDirectionOffset, Roll=0})
		--if we were using reticule Camera Targetting method we wouldnt need this
		--but in this game Camera Targetting is not accurate
		reticule.setTargetRotationOffset({Pitch=0, Yaw=leftHandDirectionOffset, Roll=0})
		reticule.setTargetMethod(reticule.ReticuleTargetMethod.LEFT_CONTROLLER)
	else
		input.setAimMethod(input.AimMethod.RIGHT_CONTROLLER)
		input.setAimRotationOffset({Pitch=0, Yaw=0, Roll=0})
		reticule.setTargetRotationOffset()
		reticule.setTargetMethod(reticule.ReticuleTargetMethod.RIGHT_CONTROLLER)
	end
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
		input.setAimMethod(input.AimMethod.RIGHT_CONTROLLER)
		input.setAimRotationOffset(uevrUtils.rotator(40,25,0)) --adjust reticule during melee to match the melee weapon head
		reticule.setTargetMethod(reticule.ReticuleTargetMethod.CAMERA)
		reticule.setTargetRotationOffset()
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

-- local swingRightAnim = nil -- = find_required_object("AnimMontage /Game/Development/Characters/PlayerCharacterHands/Animations/Shved/AM_Shved_PlayerHands_Right_Attack.AM_Shved_PlayerHands_Right_Attack")
-- local swingLeftAnim = nil -- = find_required_object("AnimMontage /Game/Development/Characters/PlayerCharacterHands/Animations/Shved/AM_Shved_PlayerHands_Right_Attack.AM_Shved_PlayerHands_Right_Attack")
gestures.registerSwipeRightCallback(function()
	--print("Swipe Right detected")
	animateMelee(1)
end)

gestures.registerSwipeLeftCallback(function()
	--print("Swipe Left detected")
	animateMelee(0)
end)


-- uevr.sdk.callbacks.on_xinput_get_state(function(retval, user_index, state)
-- 	if SwingingFast == true then
-- 		if state.Gamepad.bLeftTrigger >= 200 then
-- 			state.Gamepad.bLeftTrigger = 0 -- Heavy melee swing
-- 		else
-- 			state.Gamepad.bRightTrigger = 200 -- Light melee swing
-- 		end
-- 	end
-- end)
-- AM_PlayerCharacterHands_Telekinesis
-- AM_PlayerCharacterHands_TelekinesisThrow
-- AM_Shved_PlayerHands_Right_Attack
-- AM_Shved_Hands_Right_Rise_Montage

-- local function onArmsAnimatingChanged(isArmsCurrentlyAnimating)
-- 	if isArmsCurrentlyAnimating then
-- 	else
-- 		hands.setInitialTransform(Handed.Left)
-- 	end
-- end

--callback from uevrUtils that fires whenever a montage playstate changes
-- local leftControllerOnMontages = {
-- 	AM_PlayerCharacterHands_PolymerLongThrow = true,
-- 	AM_PlayerCharacterHards_CastingActiveIdleShortLength = true,
-- 	AM_PlayerCharacterHands_ContinuousPickup_Start = true,
-- 	AM_PlayerCharacterHands_Telekinesis = true,
-- }
-- local leftControllerOffMontages = {
-- 	AM_PlayerCharacterHands_PolymerBombSkill_Unequip_PreparationCancelled = true,
-- 	AM_PlayerCharacterHands_FrozenSkill_Unequip_PreparationCancelled = true,
-- 	AM_PlayerCharacterHands_ContinuousPickup_EndShort = true,
-- --	AM_PlayerCharacterHands_TelekinesisThrow = true,

-- }
-- local rightControllerOnMontages = {
-- }

--local blockLeft = false

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

function on_montage_change(montage, montageName)
	handleVehicle(montageName)

	--fixes a bug in the game
	if montageName == "AM_PlayerCharacterHands_ClimbingMantle" then
		isInAnimationCutscene = false
		wasArmsAnimating = false
		return
	end

	local isArmsAnimating = string.sub(montageName, 1, 3) == "AM_"
	if isArmsAnimating ~= wasArmsAnimating then
		--uevrUtils.print("Arms animating changed to " .. tostring(isArmsAnimating) .. " " .. montageName)
		--onArmsAnimatingChanged(isArmsAnimating)
		--hands.setHandsAreAnimatingFromMesh(isArmsAnimating, false)
		wasArmsAnimating = isArmsAnimating
	end

	if montageName == "" or isArmsAnimating then
		isInAnimationCutscene = false
	else
		uevrUtils.print("Montage playing " .. montageName)
		isInAnimationCutscene = true
	end

   	-- if leftControllerOnMontages[montageName] == true then
	-- 	input.setAimMethod(input.AimMethod.LEFT_CONTROLLER)
	-- 	input.setAimRotationOffset({Pitch=0, Yaw=45, Roll=0})
	-- 	blockLeft = true
	-- 	delay(1000, function()
	-- 		blockLeft = false
	-- 	end)
   	-- -- elseif leftControllerOffMontages[montageName] == true then
	-- -- 	input.setAimMethod(input.AimMethod.RIGHT_CONTROLLER)
	-- -- 	input.setAimRotationOffset({Pitch=0, Yaw=0, Roll=0})
	-- end
	-- if rightControllerOnMontages[montageName] == true then
	-- 	input.setAimMethod(input.AimMethod.RIGHT_CONTROLLER)
	-- 	input.setAimRotationOffset({Pitch=0, Yaw=0, Roll=0})
	-- end
	--ui.setIsInMotionSicknessCausingScene(isInAnimationCutscene)
end

--PlayerController.HUDWidgetInstance
-- Theres a DisableGamepadCursor and LockCursorToCenter function
-- Also ToggleInventory() shows the inventory window
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
	if uevrUtils.getValid(pawn) ~= nil then
		local currentWeapon = pawn:GetCurrentWeapon()
		if currentWeapon ~= nil and currentWeapon:HasCassetteSlot() then
			isGrabbingCassette = gestures.detectComponentGrab(state, Handed.Left, uevrUtils.getValid(currentWeapon,{"AHWeaponCassetteSlot"}), 15)
			if isGrabbingCassette then
				uevrUtils.unpressButton(state, XINPUT_GAMEPAD_RIGHT_SHOULDER)
				uevrUtils.pressButton(state, XINPUT_GAMEPAD_X)
			end
		end
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
			if activateCassetteMenu == true then -- and GameplayStatics ~= nil then
				local radialMenu = uevrUtils.getValid(uevr.api:get_player_controller(0),{"HUDWidgetInstance","RadialMenuInstance"})
				if radialMenu ~= nil then radialMenu:OnApplyWindow() end
				-- uevr.api:get_player_controller(0).HUDWidgetInstance.RadialMenuInstance
				-- local hud = GameplayStatics:GetPlayerHUD(uevrUtils.get_world(), 0)
				-- if hud ~= nil then
				-- 	hud.RadialMenuInstance:OnApplyWindow()
				-- end
			end
			activateCassetteMenu = false
		end)
	elseif not active then
		activateCassetteMenu = false
	end
end)

-- -- local wasGrabbingCassette = false
-- -- local doTrigger = false
-- uevrUtils.registerOnInputGetStateCallback(function(retval, user_index, state)
-- 	if activateCassetteMenu then
-- 		--pull the left stick down momentarily so that it selects the cassette radial item
-- 		state.Gamepad.sThumbLY = -32000

-- 		-- --this is spamming. should only do this once after state.Gamepad.sThumbLY = -32000 has run for a bit
-- 		-- --deferral should work
-- 		-- delay(100, function()
-- 		-- 	doTrigger = false
-- 		-- 	delay(100, function()
-- 		-- 		local hud = GamePlayStatics:GetPlayerHUD(uevrUtils.get_world(), 0)
-- 		-- 		hud.RadialMenuInstance:OnApplyWindow()
-- 		-- 	end)
-- 		-- end)
-- 	end


-- 	-- local isGrabbingCassette = false
-- 	-- if uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_RIGHT_SHOULDER) then --using the rmeapped button
-- 	-- 	--check if the hand is close to a cassetteMesh
-- 	-- 	local currentWeapon = pawn and pawn:GetCurrentWeapon() or nil
-- 	-- 	if currentWeapon ~= nil then
-- 	-- 		--local distance = controllers.getDistanceFromController(Handed.Left, uevrUtils.getValid(currentWeapon,{"AHWeaponCassetteSlot","LastSpawnedCassette","Mesh"}))
-- 	-- 		local distance = controllers.getDistanceFromController(Handed.Left, uevrUtils.getValid(currentWeapon,{"AHWeaponCassetteSlot"}))
-- 	-- 		--print(distance)
-- 	-- 		if distance ~= nil and distance < 15 then
-- 	-- 			--print("Grabbing cassette")
-- 	-- 			uevrUtils.unpressButton(state, XINPUT_GAMEPAD_RIGHT_SHOULDER)
-- 	-- 			uevrUtils.pressButton(state, XINPUT_GAMEPAD_X)
-- 	-- 			isGrabbingCassette = true
-- 	-- 		end
-- 	-- 	end
-- 	-- end
-- 	-- if not wasGrabbingCassette and isGrabbingCassette then
-- 	-- 	delay(500, function()
-- 	-- 		print("Called CallCassetteChangingMenu")
-- 	-- 		doTrigger = true
-- 	-- 		--uevr.api:get_player_controller(0):CallCassetteChangingMenu()
-- 	-- 	end)
-- 	-- 	isGrabbingCassette = true
-- 	-- end
-- 	-- wasGrabbingCassette = isGrabbingCassette

-- end) --increased priority to get values before remap occurs


-- --infinite health
uevrUtils.setInterval(500, function()
	local health = uevrUtils.getValid(uevr.api:get_player_controller(0), {"Character", "AttributeSet", "Health"})
	if health ~= nil then
		health.BaseValue = 9999999
		health.CurrentValue = 9999999
	end

end)

local wasClimmbing = nil
function on_post_engine_tick(engine, delta)
	if uevrUtils.getValid(pawn) ~= nil then
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

	-- if wasArmsAnimating then
	-- 	local armsAnimationMesh = pawnModule.getArmsAnimationMesh()
	-- 	if armsAnimationMesh ~= nil then
	-- 		hands.updateAnimationFromMesh(Handed.Left, armsAnimationMesh)
	-- 	end
	-- end

	-- {
	-- 	widgetType = "input_text",
	-- 	id = "testWidget",
	-- 	label = "Test",
	-- 	initialValue = "",
	-- },
	-- if uevrUtils.getValid(playerUtils) ~= nil then
	-- 	--Navigation Menu Widget
	-- 	local mode = playerUtils:GetCurrentInputMode(uevr.api:get_player_controller(0))
	-- 	--print(mode)
	-- 	--print(uevr.api:get_player_controller(0).Character:GetCurrentInteractiveComponent())
	-- 	--configui.setValue("testWidget",uevr.api:get_player_controller(0).CurrentMouseCursor)
	-- 	ui.disableHeadLockedUI(mode ~= 3)
	-- end

	--when using nora
-- 	if uevrUtils.getValid(pawn) ~= nil and pawn.Controller ~= nil then
-- 		-- if not isInAnimationCutscene then
-- 		-- 	local isPlaying = not pawn.Controller.Character.bHidden
-- 		-- 	if isPlaying ~= wasPlaying then
-- 		-- 		updatePlayState(isPlaying)
-- 		-- 		wasPlaying = isPlaying
-- 		-- 	end
-- 		-- end
-- --		controlling = pawn.Controller.Character.bHidden



-- 		-- if pawn.Controller.Character.bHidden == true and controlling ~= pawn.Controller.Character.bHidden then
-- 		-- 	print("Lost Control")
-- 		-- 	--AddToViewport(0)
-- 		-- 	local craftMachines = uevrUtils.getAllActorsOfClass("Class /Script/AtomicHeart.AHCraftMachine")
-- 		-- 	for index, craftMachine in pairs(craftMachines) do
-- 		-- 		if craftMachine ~= nil then
-- 		-- 			print(craftMachine.SkillsTerminalWidget:get_full_name())
-- 		-- 			-- skillTreeWidget = craftMachine.SkillsTerminalWidget
-- 		-- 			-- craftMachine.SkillsTerminalWidget:AddToViewport(0)
-- 		-- 			-- local location = craftMachine:GetCraftLocation()
-- 		-- 			-- local headLocation = controllers.getControllerLocation(2)
-- 		-- 			-- print(location.X, location.Y, location.Z)
-- 		-- 			-- print(headLocation.X, headLocation.Y, headLocation.Z)
-- 		-- 		end
-- 		-- 	end
-- 		-- 	--check this to see if the skill tree has control and if so, move the head location real close
-- 		-- 	--Class /Script/AtomicHeart.AHCraftMachine
-- 		-- 	--BP_Base_CraftMachine_C /Game/Maps/Worlds/Atomic_World_01/Indoor/Vavilov/Vavilov_Dungeon/Vavilov_Entrance/Vavilov_Entrance_Stairs_2.Vavilov_Entrance_Stairs_2.PersistentLevel.BP_Base_CraftMachine_2
-- 		-- 	--AHStatics:GetPlayerHUD(uevrUtils.getWorld(), 0).CrosshairWidget:RemoveFromViewport()
-- 		-- elseif pawn.Controller.Character.bHidden == false and controlling ~= pawn.Controller.Character.bHidden then
-- 		-- 	local craftMachines = uevrUtils.getAllActorsOfClass("Class /Script/AtomicHeart.AHCraftMachine")
-- 		-- 	for index, craftMachine in pairs(craftMachines) do
-- 		-- 		if craftMachine ~= nil and craftMachine.SkillsTerminalWidget ~= nil then
-- 		-- 			print(craftMachine.SkillsTerminalWidget:get_full_name())
-- 		-- 			craftMachine.SkillsTerminalWidget:RemoveFromViewport()
-- 		-- 		end
-- 		-- 	end
-- 		-- 	if skillTreeWidget ~= nil then
-- 		-- 		skillTreeWidget:RemoveFromViewport()
-- 		-- 		skillTreeWidget = nil
-- 		-- 	end
-- 		-- end
-- 	end

	--print("Is disabled", input.isDisabled())
	-- local armsAnimationMesh = pawnModule.getArmsAnimationMesh()
	-- if armsAnimationMesh ~= nil then
		-- local isAnimating = armsAnimationMesh.AnimScriptInstance:IsAnyMontagePlaying()
		-- if isAnimating then				
			-- local montage = pawn:GetCurrentMontage() 
			-- print(uevrUtils.getShortName(montage))
			-- --AnimMontage_5752
			-- local montageName = uevrUtils.getShortName(montage)
			-- if montageName == "" then
				-- --do nothing
			-- elseif montageName == "AM_PlayerCharacterHards_CastingActiveIdleShortLength" or montageName == "AM_PlayerCharacterHands_FrozenSkill_Unequip_PreparationCancelled" then
				-- hands.updateAnimationFromMesh(Handed.Left, armsAnimationMesh)
			-- else
				-- input.setDisabled(isAnimating)
			-- end
		-- else
			-- input.setDisabled(false)
		-- end
	-- end
end

-- local currentReceiptsCategory = nil
-- uevrUtils.setInterval(1000, function()
-- 	if not hands.exists() then
-- 		local paramsFile = 'hands_parameters' -- found in the [game profile]/data directory
-- 		local configName = 'Main' -- the name you gave your config
-- 		local animationName = 'Shared' -- the name you gave your animation
-- 		hands.createFromConfig(paramsFile, configName, animationName)
-- 		--hands.enableOptimizedAnimations(true)
-- 	end

-- 	-- if not reticule.exists() then
-- 	-- 	createReticule()
-- 	-- end

-- 	-- local craftMachines = uevrUtils.getAllActorsOfClass("Class /Script/AtomicHeart.AHCraftMachine")
-- 	-- --print(#craftMachines)
-- 	-- for index, craftMachine in pairs(craftMachines) do
-- 	-- 	if craftMachine ~= nil and craftMachine.CraftWindow ~= nil then
-- 	-- 		-- if currentReceiptsCategory ~= craftMachine.CraftWindow.CurrentReceiptsCategory then
-- 	-- 		-- 	currentReceiptsCategory = craftMachine.CraftWindow.CurrentReceiptsCategory
-- 	-- 		-- 	ui.disableHeadLockedUI(true)
-- 	-- 		-- end
-- 	-- 		if craftMachine.CraftWindow.CurrentReceiptsCategory == 5 then
-- 	-- 			ui.disableHeadLockedUI(true)
-- 	-- 			--uevr.api:get_player_controller(0):SetMouseLocation(10, 10)
-- 	-- 			uevr.api:get_player_controller(0).bShowMouseCursor = true
-- 	-- 		end
-- 	-- 	end
-- 	-- end

-- -- enum class EInputMode : uint8
-- -- {
-- -- 	EInputModeUnknown                        = 0,
-- -- 	EInputModeGameAndUI                      = 1,
-- -- 	EInputModeUIOnly                         = 2,
-- -- 	EInputModeGameOnly                       = 3,
-- -- 	EInputMode_MAX                           = 4,
-- -- };

-- 	-- local obj = uevrUtils.find_first_of("Class /Script/AtomicHeart.PlayerUtils", true)
-- 	-- local playerController = uevr.api:get_player_controller(0)

-- 	-- print(obj:GetCurrentInputMode(playerController))
-- end)

register_key_bind("F1", function()
	--animation.logDescendantBoneTransforms(hands.getHandComponent(Handed.Left), "lowerarm_l", true, true, true)
	hands.setInitialTransform(Handed.Left)
	hands.setInitialTransform(Handed.Right)
end)

register_key_bind("F2", function()
	print("F2 pressed")
	pawn:K2_AddActorLocalOffset(uevrUtils.vector(50,50,50), false, reusable_hit_result, true)
end)

local allMeshes = nil
local currentIndex = 0

--WidgetBlueprintGeneratedClass /Game/Core/UI/Interaction/WBP_IteractionIndicatorWidget.WBP_IteractionIndicatorWidget_C
local pauseProcess = false
local function turnOffWidgetsSlowly()
	allMeshes = uevrUtils.find_all_instances("Class /Script/UMG.Widget", false)
	print("Found widgets:", #allMeshes)
	if allMeshes ~= nil then
		setInterval(100, function()
			if not pauseProcess then
				currentIndex = currentIndex + 1
				local mesh = allMeshes[currentIndex]
				print("Hiding widget:", mesh:get_full_name())
				mesh:SetVisibility(1)
			end
		end)
	end
end


local function tryWidget()
	--allMeshes = uevrUtils.find_all_instances("WidgetBlueprintGeneratedClass /Game/Core/UI/Interaction/WBP_IteractionIndicatorWidget.WBP_IteractionIndicatorWidget_C", false)
	--allMeshes = uevrUtils.find_all_instances("WidgetBlueprintGeneratedClass /Game/Core/UI/Widgets/LocationLootInfo/WBP_LocationLootItem.WBP_LocationLootItem_C", false)
	allMeshes = uevrUtils.find_all_instances("WidgetBlueprintGeneratedClass /Game/Core/UI/Interaction/WBP_IteractionsWidget.WBP_IteractionsWidget_C", false)

	if allMeshes ~= nil then
		print("Found widgets:", #allMeshes)
		for index, mesh in pairs(allMeshes) do
			print("Hiding widget:", mesh:get_full_name())
			mesh:SetVisibility(1)
			--mesh:SetHiddenInGame(true)
		end
	end

end



local function widgetText()
	allMeshes = uevrUtils.find_all_instances("WidgetBlueprintGeneratedClass /Game/Core/UI/Interaction/WBP_IteractionIndicatorWidget.WBP_IteractionIndicatorWidget_C", false)
	--allMeshes = uevrUtils.find_all_instances("WidgetBlueprintGeneratedClass /Game/Core/UI/Widgets/LocationLootInfo/WBP_LocationLootItem.WBP_LocationLootItem_C", false)
	--allMeshes = uevrUtils.find_all_instances("WidgetBlueprintGeneratedClass /Game/Core/UI/Interaction/WBP_IteractionsWidget.WBP_IteractionsWidget_C", false)

	--local lb = nil

	-- --PaperSprite /Game/Development/UI/Textures/HUD/Frames/XBox/XBOX_LB_02_png.XBOX_LB_02_png
	if allMeshes ~= nil then
		print("Found widgets:", #allMeshes)
		for index, mesh in pairs(allMeshes) do
			--print("Hiding widget:", mesh:get_full_name())
			--print(mesh.ActionButton.ActionText:GetText())
			--mesh.ActionButton.bHorizontalMirror = true
			--mesh.ActionButton.ButtonImage.Brush.ImageSize.X = 800
			-- mesh.Image.Brush.ImageSize.X = 400
			--mesh.ActionButton.ButtonImage.Brush.ResourceObject = nil
			--local textProp = mesh.TextBlock_88:GetText()
			--mesh.TextBlock_88:SetText(textProp)
			--mesh:SetHiddenInGame(true)
			--mesh.ActionButton.ButtonImage.Brush.ResourceObject = lb
			if mesh.ActionButton.ButtonImage.Brush.ResourceObject ~= nil then
				print(mesh:get_full_name(),mesh.ActionButton.ButtonImage.Brush.ResourceObject:get_full_name())
			end
		end
	end

end

-- function on_post_engine_tick(engine, delta)
-- 	if lb ~= nil then
-- 		allMeshes = uevrUtils.find_all_instances("WidgetBlueprintGeneratedClass /Game/Core/UI/Interaction/WBP_IteractionIndicatorWidget.WBP_IteractionIndicatorWidget_C", false)
-- 		if allMeshes ~= nil then
-- 			print("Updating widgets")
-- 			for index, mesh in pairs(allMeshes) do
-- 				mesh.ActionButton.ButtonImage.Brush.ResourceObject = lb
-- 			end
-- 		end
-- 	end
-- end

register_key_bind("F3", function()
	print("F3 pressed")
	local hud = uevrUtils.getValid(uevr.api:get_player_controller(0),{"HUDWidgetInstance"})
	if hud ~= nil then
		local vec = hud:GetDesiredSize()
		print("size",vec.X, vec.Y)
		vec = hud:GetAlignmentInViewport()
		print("Alignment",vec.X, vec.Y)
	end
	-- if hud ~= nil then
	-- 	hud:SetDesiredSizeInViewport(uevrUtils.vector2D(2000,2000))
	-- end
	--turnOffWidgetsSlowly()
	--tryWidget()
	--widgetText()
	-- local x = uevr.api:get_player_controller(0):GetAppliedContexts()
	-- print(x)
	-- uevr.api:get_player_controller(0):CallCassetteChangingMenu()
	-- --ScriptStruct /Script/EnhancedInput.InputActionValue
	-- local inputAction = uevrUtils.find_required_object("Package /Game/Core/Data/Input/Actions/IA_ScrollCassettes.IA_ScrollCassettes")
	-- if inputAction == nil then
    -- 	print("Failed to find IA_ScrollCassettes")
    -- end

	-- local tag = uevrUtils.get_reuseable_struct_object("ScriptStruct /Script/GameplayTags.GameplayTag")
	-- print("tag",tag)
	-- tag.TagName = uevrUtils.fname_from_string("IA.ScrollCassettes")
	-- local actionValue = uevr.api:get_player_controller(0):GetInputActionValue(tag)
    -- if actionValue ~= nil then
	-- 	print("Hello")
	-- 	--print("Value:", actionValue.Get())  -- Likely the float axis value
 	-- 	print("Value:", actionValue.Value)  -- Likely the float axis value
    --    	print("X:", actionValue.X)          -- If it's a vector (e.g., 2D axis)
    --     print("Y:", actionValue.Y)
    --     print("Magnitude:", actionValue.Magnitude)  -- If exposed
    --     print("Type:", actionValue.Type)    -- Input type enum
    --     --actionValue.Value = 1.0  -- Set the scroll value
	-- 	delay(2000, function()
    --     uevr.api:get_player_controller(0):ScrollCassettes(actionValue)
	-- 	print("Did something")
	-- 	end)
    -- else
    --     print("Failed to get FInputActionValue")
    -- end

	-- local inputAction = uevrUtils.get_reuseable_struct_object("ScriptStruct /Script/EnhancedInput.InputActionValue")
	-- print("inputAction",inputAction)
	-- if inputAction ~= nil then
	-- 	print("Value:", inputAction.Value)  -- Likely the float axis value
    --     print("X:", inputAction.X)          -- If it's a vector (e.g., 2D axis)
    --     print("Y:", inputAction.Y)
    --     print("Magnitude:", inputAction.Magnitude)  -- If exposed
    --     print("Type:", inputAction.Type)    -- Input type enum

	-- 	print("Properties of inputAction:")
	-- 	for k, v in pairs(inputAction) do
	-- 		print("  " .. tostring(k) .. " = " .. tostring(v))
	-- 	end

	-- 	inputAction.Value = 1.0
	-- 	uevr.api:get_player_controller(0):ScrollCassettes(inputAction)
	-- end

--uevr.api:get_player_controller(0) struct FInputActionValue GetInputActionValue(const struct FGameplayTag& ActionTag)
	--reticule.setActiveReticule("f334706c-5650-496f-b11f-63f17fc2ca55")
	-- allMeshes = uevrUtils.find_all_instances("Class /Script/UMG.Widget", false)
	-- if allMeshes ~= nil then
	-- 	for index, mesh in pairs(allMeshes) do
	-- 		print("Hiding widget:", mesh:get_full_name())
	-- 		mesh:SetVisibility(1)
	-- 		--mesh:SetHiddenInGame(true)
	-- 	end
	-- end
end)

register_key_bind("F4", function()
	print("F4 pressed")
	--pauseProcess = not pauseProcess
	-- if allMeshes ~= nil then
	-- 	currentIndex = currentIndex + 1
	-- 	local mesh = allMeshes[currentIndex]
	-- 	print("Hiding widget:", mesh:get_full_name())
	-- 	mesh:SetVisibility(1)
	-- end
	replaceText()

	--reticule.setActiveReticule("f334706c-5650-496f-b11f-63f17fc2ca55")
	-- allMeshes = uevrUtils.find_all_instances("Class /Script/UMG.Widget", false)
	-- if allMeshes ~= nil then
	-- 	for index, mesh in pairs(allMeshes) do
	-- 		print("Hiding widget:", mesh:get_full_name())
	-- 		mesh:SetVisibility(1)
	-- 		--mesh:SetHiddenInGame(true)
	-- 	end
	-- end
end)


register_key_bind("LeftMouseButton", function()
	print("Left mouse button pressed")
	local keyStruct = uevrUtils.get_reuseable_struct_object("ScriptStruct /Script/InputCore.Key")
	keyStruct.KeyName = uevrUtils.fname_from_string("F2")

	uevr.api:get_player_controller(0):ConsoleKey(keyStruct)
end)


-- register_key_bind("Gamepad_RightShoulder", function()
-- end)
-- register_key_bind("F2", function()
-- 	-- if skillTreeWidget ~= nil then
-- 	-- 	skillTreeWidget:RemoveFromViewport()
-- 	-- 	skillTreeWidget = nil
-- 	-- end
-- 	-- local interactionComponent = interaction.createWidgetInteractionComponent(true, false)
-- 	-- if interactionComponent ~= nil then
-- 	-- 	print("Created interaction component")
-- 	-- 	controllers.attachComponentToController(Handed.Right, interactionComponent)
-- 	-- end
-- 	--local laserComponent = interaction.createLaserComponent()
-- 	-- if laserComponent ~= nil then
-- 	-- 	print("Created laser component")
-- 	-- 	controllers.attachComponentToController(Handed.Right, laserComponent)
-- 	-- end
-- end)
-- register_key_bind("LeftMouseButton", function()
-- 	print("Left mouse button pressed")
-- end)

hook_function("Class /Script/AtomicHeart.QTESubsystem", "OnQTEPlay", true, nil,
	function(fn, obj, locals, result)
		print("OnQTEPlay called", locals)
		--obj:OnQTEActionResult(true)
		remap.setDisabled(true)
	end
, true)

hook_function("Class /Script/AtomicHeart.QTESubsystem", "OnQTEStop", true, nil,
	function(fn, obj, locals, result)
		print("OnQTEStop called", locals)
		remap.setDisabled(false)
	end
, true)

hook_function("Class /Script/AtomicHeart.QTESubsystem", "OnQTEPreStart", true, nil,
	function(fn, obj, locals, result)
		print("OnQTEPreStart called", locals)
	end
, true)

hook_function("Class /Script/AtomicHeart.QTESubsystem", "OnQTEActionResult", true, nil,
	function(fn, obj, locals, result)
		print("OnQTEActionResult called", locals, result)
	end
, true)

hook_function("Class /Script/AtomicHeart.QTESubsystem", "OnQTEActionResult", true, nil,
	function(fn, obj, locals, result)
		print("OnQTEActionResult called", locals, result)
	end
, true)


--Not sure why this one isnt called, maybe because the BlueprintGeneratedClass version of it is getting called instead?
-- hook_function("Class /Script/AtomicHeart.AHPlayerCharacter", "K2_OnDrivingVehicle", true, nil,
-- 	function(fn, obj, locals, result)
-- 		print("K2_OnDrivingVehicle called", locals, result, locals.IsDriving)
-- 	end
-- , true)

