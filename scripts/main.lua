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
local collision = require('libs/collision')
local ik = require('libs/ik')
ik.setInitialTransformOnAnimationCompleteEnabled(false)

-- uevrUtils.setLogLevel(LogLevel.Debug)
-- reticule.setLogLevel(LogLevel.Debug)
-- input.setLogLevel(LogLevel.Debug)
-- attachments.setLogLevel(LogLevel.Debug)
-- animation.setLogLevel(LogLevel.Debug)
-- ui.setLogLevel(LogLevel.Debug)
-- remap.setLogLevel(LogLevel.Debug)
-- hands.setLogLevel(LogLevel.Debug)
-- interaction.setLogLevel(LogLevel.Debug)
-- ik.setLogLevel(LogLevel.Debug)

-- uncomment the next line to see the full developer UI
uevrUtils.setDeveloperMode(true)
--hands.enableConfigurationTool()

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
collision.init()
ik.init()

--since weapons are attached to the hand sockets for this game
--only let the hands be affected by gunstock offsets
attachments.setGunstockOffsetsEnabled(false)
hands.setGunstockOffsetsEnabled(true)
ik.setGunstockOffsetsEnabled(true)

local wasArmsAnimating = false
local isInAnimationCutscene = false
local isInCar = false
local materialUtils = nil
local leftHandDirectionOffset = {X=0,Y=0,Z=0}
local activateCassetteMenu = false
local isGrabbingCassette = false
local jumpTurnDeadzone = 32000
--initial bone transforms for resetting Chrles animations
local uccInitialBoneTransforms = {}

hands.setAutoCreateHands(false)
ik.setAutoCreateArms(false)

local versionTxt = "v1.0.8"
local title = "Atomic Heart First Person Mod " .. versionTxt
local configDefinition = {
	{
		panelLabel = "Atomic Heart Config",
		saveFile = "atomic_heart_config",
		layout = spliceableInlineArray
		{
			{ widgetType = "text", id = "title", label = title },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Control" }, { widgetType = "begin_rect", },
                {
                    widgetType = "combo",
                    id = "hands_type",
                    label = "Hands Type",
                    selections = {"Forearms", "IK Arms"},
                    initialValue = 1,
                },
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
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Reticule" }, { widgetType = "begin_rect", },
				expandArray(reticule.getConfigurationWidgets,{{id="uevr_reticule_update_distance", initialValue=200},}),
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
			--{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Control" }, { widgetType = "begin_rect", },
			{
				widgetType = "tree_node",
				id = "atomic_heart_advanced_settings",
				initialOpen = false,
				label = "Advanced Settings"
			},
						{
					widgetType = "drag_float3",
					id = "leftHandDirectionOffset",
					label = "Left Hand Target Angle",
					speed = 1,
					range = {-180, 180},
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
			{ widgetType = "tree_pop" },
			--{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
		}
	}
}

local status = {}

local HandsType = {
	Forearms = 1,
	IKArms = 2,
}
local function regenerateHands(value)
	--detach attachments first so they dont get "lost" when hands are destroyed
	attachments.detachGripAttachments(Handed.Right)
	attachments.detachGripAttachments(Handed.Left)

    hands.setAutoCreateHands(value == HandsType.Forearms)
    ik.setAutoCreateArms(value == HandsType.IKArms)

    hands.destroyHands()
    ik.destroyAll()
end

configui.onUpdate("hands_type", function(value)
    regenerateHands(value)
end)

ik.registerOnMeshCreatedCallback(function(meshComponentList, ikInstance)
    --print("IK Mesh created:", meshComponent ~= nil, ikInstance ~= nil and ikInstance.rigId or "")
    local meshComponent = meshComponentList and meshComponentList[1] or nil
	if meshComponent ~= nil then
        meshComponent.bCastDynamicShadow = false
        meshComponent.bRenderInDepthPass = false
        animation.setComponent("left_arms", meshComponent)
		animation.setComponent("right_arms", meshComponent)
        --status["ikMeshComponent"] = meshComponent
		if materialUtils ~= nil then
			materialUtils:EnablePaniniForMesh(meshComponent,  false)
		end
		if ikInstance ~= nil then
			ikInstance:setInitialCustomTransform(uccInitialBoneTransforms)
		end
    end
end)

local function setInCar(value)
	isInCar = value
	pawnModule.hideArmsBones(not isInCar)
	hands.hideHands(isInCar)
end
local function setIsClimbing(value) --0 not climbing, 1 climbing, 2 hanging by left hand
	if value == 0 then
		pawnModule.hideArmsBones(true)
		hands.hideHands(false)
		ik.hide(false)
		input.setDisabled(false)
	elseif value == 1 then
		pawnModule.hideArmsBones(false)
		hands.hideHands(true)
		ik.hide(true)
		--input.setDisabled(true)
	elseif value == 2 then
		pawnModule.hideArmsBones(true)
		hands.hideHand(Handed.Left, true)
		hands.hideHand(Handed.Right, false)
		ik.hide(false)
		--input.setDisabled(true)
	end
end

local function getHandComponents()
    local rightHandComponent = nil
   	local leftHandComponent = nil
	local handsType = configui.getValue("hands_type")
    if handsType == HandsType.None then
        rightHandComponent = controllers.getController(Handed.Right)
        leftHandComponent = controllers.getController(Handed.Left)
    elseif handsType == HandsType.Forearms then
        rightHandComponent = hands.getHandComponent(Handed.Right)
        leftHandComponent = hands.getHandComponent(Handed.Left)
    elseif handsType == HandsType.IKArms then
        rightHandComponent = ik.getCurrentMesh()
		leftHandComponent = ik.getCurrentMesh()
    end

    return rightHandComponent, leftHandComponent
end

local defaultAttachOptions = {
	detachFromOriginOnGrip = true,
	maintainWorldPositionOnDetachFromOrigin = false,
	detachFromParentOnRelease = true,
	maintainWorldPositionOnDetachFromParent = false,
	reattachToOriginOnRelease = false,
	restoreTransformToOriginOnReattach = false,
	useZeroTransformOnReattach = false,
	allowChildVisibilityHandling = false,
	allowChildHiddenInGameHandling = false,
	allowRenderInMainPassHandling = false,
}

attachments.registerOnGripUpdateCallback(function()
	if not isInAnimationCutscene and uevrUtils.getValid(pawn) ~= nil and pawn.GetCurrentWeapon ~= nil then
		local currentWeapon = pawn:GetCurrentWeapon()
		if currentWeapon ~= nil and currentWeapon.RootComponent ~= nil then --and hand ~= nil then
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
			local rightHandComponent, leftHandComponent = getHandComponents()
			local rightSocket = "hand_r" --"item_r_joint" --
			if string.find(uevrUtils.getShortName(currentWeapon), "BP_Kuzmich") then
				--secondary floating magazine needs to be hidden
				currentWeapon.SK_Kuzmich_Magazine:call("SetRenderCustomDepth", false)
				currentWeapon.SK_Kuzmich_Magazine:call("SetRenderInMainPass", false)
				currentWeapon.Barrel.RelativeLocation.X = 50 --move barrel forward to avoid firing into the capsule component
				return rightHandComponent and currentWeapon.RootComponent, rightHandComponent, rightSocket, nil, nil, nil, defaultAttachOptions
			else
				--return currentWeapon.RootComponent, hand, nil, nil, nil, nil, true
				return rightHandComponent and currentWeapon.RootComponent, rightHandComponent, rightSocket, nil, nil, nil, defaultAttachOptions
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

--ik.enableAnimationBoneListPrintout = true
--dont allow ik arms animations to modify these specific bone indexes
ik.registerGetCustomAnimationInitialTransformCallback(function()
	return {7,8,38}
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

-- Show LB when game tries to show RB
setInterval(1000, function()
	if uevrUtils.getValid(status.lbResource) == nil then
		status.lbResource = uevrUtils.find_required_object("PaperSprite /Game/Development/UI/Textures/HUD/Frames/XBox/XBOX_LB_02_png.XBOX_LB_02_png")
	end
	if status.lbResource == nil then
		print("LB not found")
		return
	end

	local allWidgets = uevrUtils.find_all_instances("WidgetBlueprintGeneratedClass /Game/Core/UI/Interaction/WBP_IteractionIndicatorWidget.WBP_IteractionIndicatorWidget_C", false)
	if allWidgets ~= nil then
		--print("Checking widgets")
		--it should be RB in the map screen
		for index, widget in pairs(allWidgets) do
			if widget.ActionButton.ButtonImage ~= nil and widget.ActionButton.ButtonImage.Brush.ResourceObject:get_full_name() == "PaperSprite /Game/Development/UI/Textures/HUD/Frames/XBox/XBOX_RB_02_png.XBOX_RB_02_png" then
				widget.ActionButton.ButtonImage:SetBrushResourceObject(status.lbResource)
			end
		end
	end
--PaperSprite /Game/Development/UI/Textures/HUD/Frames/XBox/XBOX_RB_02_png.XBOX_RB_02_png
end)

--callback from uevrUtils that fires whenever the level changes
function on_level_change(level, levelName)
	uevrUtils.print("Level changed to " .. levelName)
	isInCar = false

	--Get the Atomic Heart Specific MaterialUtils in order to fix panini projection
	materialUtils = uevrUtils.find_default_instance("Class /Script/AtomicHeart.MaterialUtils")
	if materialUtils == nil then
		uevrUtils.print("MaterialUtils not found")
	end

	regenerateHands(configui.getValue("hands_type"))
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
		input.setAimRotationOffset({Pitch=leftHandDirectionOffset.X, Yaw=leftHandDirectionOffset.Y, Roll=leftHandDirectionOffset.Z})
		input.setPlayerControllerRotationFollowsBody(false)
		reticule.setTargetMethod(reticule.ReticuleTargetMethod.LEFT_CONTROLLER)
		reticule.setTargetRotationOffset({Pitch=leftHandDirectionOffset.X, Yaw=leftHandDirectionOffset.Y, Roll=leftHandDirectionOffset.Z})
	else
		input.setAimMethod(input.AimMethod.RIGHT_WEAPON)
		input.setAimRotationOffset({Pitch=0, Yaw=0, Roll=0})
		input.setPlayerControllerRotationFollowsBody(true)
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
		uevr.api:get_player_controller(0):EquippedItemPrimaryInputPressed(1.0) -- Trigger melee attack

		local id = attachments.getActiveAttachmentID(Handed.Right)
		if id ~= nil and weaponMontages[id] ~= nil and weaponMontages[id][direction + 1] ~= nil then
			local animName = weaponMontages[id][direction + 1]
			if id == "BP_Klusha_C_SK_Klusha_Handle01" then
				status.updateAttachmentTransform = true
				if status.montageCheck == nil then
					status.montageExtension = ""
					status.montageCheck = true
					local className = montage.getMontageClassName(animName)
					if className ~= nil then
						if uevrUtils.get_class(className) == nil then
							status.montageExtension = "_DLC4"
						end
					end
				end
				animName = animName .. status.montageExtension
			end
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

--The Klusha in DLC4 does some kind of root reset when animation ends so this corrects it
local function resetAttachment()
	local attachmentData = attachments.getCurrentGrippedAttachmentData(uevrUtils.getHandedness())
	if attachmentData ~= nil and attachmentData.attachment ~= nil then --and attachmentData.attachment.RelativeLocation ~= nil and attachmentData.attachment.RelativeLocation.X == 0 and attachmentData.attachment.RelativeLocation.Y == 0 and attachmentData.attachment.RelativeLocation.Z == 0 then
		-- if uevrUtils.executeUEVRCallbacksWithBooleanResult("attachment_suppress_mesh_reattach", attachmentData.attachment, mesh) == true then
		-- 	return true
		-- end
		local loc, rot, scale = attachments.getAttachmentOffset(attachmentData.attachment)
		local attachmentID = attachments.getAttachmentIDFromAttachment(attachmentData.attachment)
		--print("Resetting attachment: ", rot.Pitch, rot.Yaw, rot.Roll)
		attachments.updateAttachmentTransform(loc, rot, scale, attachmentID)
	end
end

function on_montage_change(montageObject, montageName)
	handleVehicle(montageName)

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

	if montageName == "" then
		status.updateAttachmentTransform = false
	end
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
		status.isUsingCodeLock = true
	else
		interaction.setInteractionType(interaction.InteractionType.Widget)
		interaction.setAllowMouseUpdate(false)
		status.isUsingCodeLock = false
	end

	local widget = uevrUtils.find_first_instance("WidgetBlueprintGeneratedClass /Game/Core/UI/HUD/Widgets/UniversalLockTooltip/WBP_UniversalLockTooltipWidget.WBP_UniversalLockTooltipWidget_C", false)
	if widget ~= nil and widget.Background ~= nil then
		widget.Background:SetVisibility(1)
	end

end)


-----------------------------------
--hide the annoying slight opacity background of some dialogs
ui.registerWidgetChangeCallback("WBP_MainMenu_C", function(active)
	if active then
		local widget = uevrUtils.find_first_instance("WidgetBlueprintGeneratedClass /Game/Core/UI/Widgets/MainMenu/WBP_MainMenu.WBP_MainMenu_C", false)
		if widget ~= nil and widget.i_BG ~= nil and widget.i_BG.SetVisibility ~= nil then
			widget.i_BG:SetVisibility(1)
		end
	end
end)
ui.registerWidgetChangeCallback("WBP_Dialogue_C", function(active)
	if active then
		local widget = uevrUtils.find_first_instance("WidgetBlueprintGeneratedClass /Game/Core/UI/Dialogue/WBP_Dialogue.WBP_Dialogue_C", false)
		if widget ~= nil and widget.Image ~= nil then
			widget.Image:SetVisibility(1)
		end
	end
end)
----------------------------------

uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)
	-- When using laser, let left trigger work the same as pressing A
	if status.isUsingCodeLock or interaction.isHovering() then
		if state.Gamepad.bLeftTrigger > 0 then
			uevrUtils.pressButton(state, XINPUT_GAMEPAD_A)
		end
		state.Gamepad.bRightTrigger = 0
		state.Gamepad.bLeftTrigger = 0
		return
	end

	if ui.isRemapDisabled() ~= true then
		local isHolstering = gestures.detectGestureWithState(gestures.Gesture.HOLSTER, state, Handed.Right, false)
		if isHolstering then
			if pawn ~= nil then
				pawn:SetHolsteredMode(true)
			end
		end

		-- switch hands when using the hand's trigger or shoulder button
		-- Only suppress LT on a rising edge when switching hands. Zeroing an already-held LT
		-- creates a fake release that the left_trigger toggle remap treats as a real edge
		-- (hose toggles off, then a later real release toggles it back on).
		local leftTriggerHeld = state.Gamepad.bLeftTrigger > 0
		if state.Gamepad.bRightTrigger > 0 or uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_RIGHT_SHOULDER) then
			local currentHand = status["currentTargetingHand"]
			setDefaultTargeting(Handed.Right)
			if currentHand == Handed.Left and state.Gamepad.bRightTrigger > 0 then
				status.handChangedCount = 2 --delay trigger firing by two frames to allow the game to switch hands
			end
			if status.handChangedCount ~= nil and status.handChangedCount > 0 then
				status.handChangedCount = status.handChangedCount - 1
				state.Gamepad.bRightTrigger = 0
			end
		elseif leftTriggerHeld or uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_LEFT_SHOULDER) then
			local currentHand = status["currentTargetingHand"]
			setDefaultTargeting(Handed.Left)
			if currentHand == Handed.Right and leftTriggerHeld and not status.leftTriggerWasHeld then
				state.Gamepad.bLeftTrigger = 0
			end
		end
		status.leftTriggerWasHeld = leftTriggerHeld

		-- prevent annoying accidental snap turn when jumping
		if state.Gamepad.sThumbRY >= jumpTurnDeadzone or state.Gamepad.sThumbRY <= -jumpTurnDeadzone then
			state.Gamepad.sThumbRX = 0
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

		if activateCassetteMenu then
			--pull the left stick down momentarily so that it selects the cassette radial item
			state.Gamepad.sThumbLY = -32000
		end
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

		--when levitating a world item put the item directly in front of you instead of off to the side
		--pawn.GrabSocket.RelativeLocation.X = 0
		if pawn.GrabSocket ~= nil then
			pawn.GrabSocket.RelativeLocation.Y = 0
			pawn.GrabSocket.RelativeLocation.Z = 0
		end
	end

end

function on_pre_engine_tick(engine, delta)
	if pawn ~= nil then
		--Fixes issue with a DLC PM pistol animating incorectly
		pawn:EnablePaniniProjection(false)
	end
	if status.updateAttachmentTransform == true then
		resetAttachment()
	end
end

-- allow the player to physically move closer to NORA
function on_character_hidden(isCharacterHidden)
	uevrUtils.setUEVRParam("VR_RoomscaleMovement", tostring(not isCharacterHidden))
end

configui.onCreateOrUpdate("leftHandDirectionOffset", function(value)
	leftHandDirectionOffset = value
	setDefaultTargeting(status["currentTargetingHand"] or Handed.Right)
end)
configui.onCreateOrUpdate("jumpTurnDeadzone", function(value)
	print("Configured deadzone")
	jumpTurnDeadzone = 32000 - (value / 100 * 32000)
end)

configui.create(configDefinition)

register_key_bind("F2", function()
	print("F2 pressed")
	pawn:K2_AddActorLocalOffset(uevrUtils.vector(50,50,50), false, reusable_hit_result, true)
end)

register_key_bind("F3", function()
	print("F3 pressed")
	pawn:SetHolsteredMode(true)
end)

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
		delay(1000, function()
			uevrUtils.stopFadeCamera()
		end)
	end
, true)


-- Initial left hand transforms used to reset Charles animations in IK module
uccInitialBoneTransforms = {
	["Use_10"] = {
		location = {-0.03125, -0.078125, -0.015625},
		rotation = {0, 0, 0},
	},
	["Use_11"] = {
		location = {-0.0625, -0.0625, 0.015625},
		rotation = {0, 0, 0},
	},
	["Use_12"] = {
		location = {-0.046875, -0.03125, 0.0234375},
		rotation = {0, 0, 0},
	},
	["Use_13"] = {
		location = {-0.015625, -0.078125, -0.0078125},
		rotation = {0, 0, 0},
	},
	["Use_14"] = {
		location = {0.03125, -0.078125, -0.0234375},
		rotation = {0, 0, 0},
	},
	["Use_15"] = {
		location = {0.015625, -0.09375, 0.0078125},
		rotation = {0, 0, 0},
	},
	["Use_16"] = {
		location = {0.03125, -0.09375, -0.015625},
		rotation = {0, 0, 0},
	},
	["Use_17"] = {
		location = {0.0, -0.21875, -0.0234375},
		rotation = {0, 0, 0},
	},
	["Use_18"] = {
		location = {0.046875, -0.40625, 0.0234375},
		rotation = {0, 0, 0},
	},
	["Use_19"] = {
		location = {0.0, -0.25, -0.0078125},
		rotation = {0, 0, 0},
	},
	["Use_2"] = {
		location = {-0.03125, 3.953125, 0.0234375},
		rotation = {0, 0, 0},
	},
	["Use_3"] = {
		location = {0.03125, -0.046875, 0.0},
		rotation = {0, 0, 0},
	},
	["Use_4"] = {
		location = {0.015625, -0.03125, 0.0234375},
		rotation = {0, 0, 0},
	},
	["Use_5"] = {
		location = {0.015625, -0.0625, 0.015625},
		rotation = {0, 0, 0},
	},
	["Use_6"] = {
		location = {-0.046875, -0.109375, -0.0078125},
		rotation = {0, 0, 0},
	},
	["Use_7"] = {
		location = {0.03125, -0.078125, -0.0234375},
		rotation = {0, 0, 0},
	},
	["Use_8"] = {
		location = {0.0625, -0.09375, -0.0234375},
		rotation = {0, 0, 0},
	},
	["Use_9"] = {
		location = {0.015625, -0.109375, -0.0390625},
		rotation = {0, 0, 0},
	},
	["star_1_joint"] = {
		location = {0.34375, -0.46875, -0.90625},
		rotation = {-9.6585769653320313, -89.991729736328125, -139.593505859375},
	},
	["star_2_joint"] = {
		location = {-0.75, -0.484375, -0.6328125},
		rotation = {-5.5460243225097656, -92.871475219726563, -67.689781188964844},
	},
	["star_3_joint"] = {
		location = {-0.8125, -0.546875, 0.4921875},
		rotation = {27.252023696899418, -94.110015869140639, 4.6310410499572754},
	},
	["star_4_joint"] = {
		location = {0.234375, -0.484375, 0.96875},
		rotation = {4.0176606178283691, -99.440490722656236, 75.364265441894531},
	},
	["star_5_joint"] = {
		location = {0.9375, -0.515625, 0.0546875},
		rotation = {14.376693725585938, -91.7796401977539, 147.20132446289065},
	},
	["tenBase_joint"] = {
		location = {4.84375, -0.5078125, -3.046875},
		rotation = {44.117504119873047, -34.216560363769531, -162.362060546875},
	},
	["ucc_10"] = {
		location = {0.078125, -0.09375, -0.03125},
		rotation = {0, 0, 0},
	},
	["ucc_11"] = {
		location = {-0.03125, -0.0625, -0.046875},
		rotation = {0, 0, 0},
	},
	["ucc_12"] = {
		location = {-0.015625, -0.0625, 0.03125},
		rotation = {0, 0, 0},
	},
	["ucc_13"] = {
		location = {0.0, -0.0625, 0.0},
		rotation = {0, 0, 0},
	},
	["ucc_14"] = {
		location = {-0.015625, -0.0625, 0.0078125},
		rotation = {0, 0, 0},
	},
	["ucc_15"] = {
		location = {-0.0625, -0.0625, -0.0078125},
		rotation = {0, 0, 0},
	},
	["ucc_16"] = {
		location = {-0.015625, -0.046875, -0.0078125},
		rotation = {0, 0, 0},
	},
	["ucc_17"] = {
		location = {-0.015625, -0.203125, 0.0078125},
		rotation = {0, 0, 0},
	},
	["ucc_18"] = {
		location = {0.015625, -0.296875, 0.0},
		rotation = {0, 0, 0},
	},
	["ucc_19"] = {
		location = {0.0, -0.265625, 0.015625},
		rotation = {0, 0, 0},
	},
	["ucc_2"] = {
		location = {0.25, 3.953125, 0.3046875},
		rotation = {0, 0, 0},
	},
	["ucc_3"] = {
		location = {0.015625, -0.0625, -0.03125},
		rotation = {0, 0, 0},
	},
	["ucc_4"] = {
		location = {-0.03125, -0.0625, 0.0},
		rotation = {0, 0, 0},
	},
	["ucc_5"] = {
		location = {0.0, -0.078125, 0.0},
		rotation = {0.0, 0.0, 0},
	},
	["ucc_6"] = {
		location = {-0.0625, -0.109375, -0.015625},
		rotation = {0, 0, 0},
	},
	["ucc_7"] = {
		location = {-0.015625, -0.0625, 0.046875},
		rotation = {0, 0, 0},
	},
	["ucc_8"] = {
		location = {0.0625, -0.125, 0.015625},
		rotation = {0, 0, 0},
	},
	["ucc_9"] = {
		location = {-0.046875, -0.046875, 0.0},
		rotation = {0, 0, 0},
	},
	["usb_10"] = {
		location = {0.078125, -0.09375, 0.0},
		rotation = {0, 0, 0},
	},
	["usb_11"] = {
		location = {-0.03125, -0.046875, -0.015625},
		rotation = {0, 0, 0},
	},
	["usb_12"] = {
		location = {0.015625, -0.046875, -0.0078125},
		rotation = {0, 0, 0},
	},
	["usb_13"] = {
		location = {-0.03125, -0.140625, -0.0390625},
		rotation = {0, 0, 0},
	},
	["usb_14"] = {
		location = {0.03125, -0.046875, 0.0078125},
		rotation = {0, 0, 0},
	},
	["usb_15"] = {
		location = {0.0, -0.125, 0.0},
		rotation = {0, 0, 0},
	},
	["usb_16"] = {
		location = {0.09375, -0.03125, 0.0234375},
		rotation = {0, 0, 0},
	},
	["usb_17"] = {
		location = {0.0625, -0.40625, -0.046875},
		rotation = {0, 0, 0},
	},
	["usb_18"] = {
		location = {0.015625, -0.171875, 0.0390625},
		rotation = {0, 0, 0},
	},
	["usb_19"] = {
		location = {0.0, -0.15625, -0.015625},
		rotation = {0, 0, 0},
	},
	["usb_2"] = {
		location = {-0.328125, 3.890625, -0.0859375},
		rotation = {0, 0, 0},
	},
	["usb_3"] = {
		location = {0.0, -0.078125, 0.03125},
		rotation = {0, 0, 0},
	},
	["usb_4"] = {
		location = {0.015625, -0.109375, -0.03125},
		rotation = {0, 0, 0},
	},
	["usb_5"] = {
		location = {-0.015625, -0.0625, 0.015625},
		rotation = {0, 0, 0},
	},
	["usb_6"] = {
		location = {0.0, -0.0625, 0.0},
		rotation = {0, 0, 0},
	},
	["usb_7"] = {
		location = {-0.03125, -0.109375, 0.0078125},
		rotation = {0, 0, 0},
	},
	["usb_8"] = {
		location = {0.0625, -0.15625, -0.03125},
		rotation = {0, 0, 0},
	},
	["usb_9"] = {
		location = {-0.03125, -0.0625, 0.0},
		rotation = {0, 0, 0},
	},
	["usd_10"] = {
		location = {0.0, -0.046875, 0.0},
		rotation = {0, 0, 0},
	},
	["usd_11"] = {
		location = {-0.0625, -0.0625, 0.0},
		rotation = {0, 0, 0},
	},
	["usd_12"] = {
		location = {0.0, -0.109375, -0.0078125},
		rotation = {0, 0, 0},
	},
	["usd_13"] = {
		location = {-0.03125, -0.0625, -0.0078125},
		rotation = {0, 0, 0},
	},
	["usd_14"] = {
		location = {0.0, -0.078125, 0.0390625},
		rotation = {0, 0, 0},
	},
	["usd_15"] = {
		location = {0.015625, -0.078125, -0.0390625},
		rotation = {0, 0, 0},
	},
	["usd_16"] = {
		location = {0.078125, -0.0625, -0.015625},
		rotation = {0, 0, 0},
	},
	["usd_17"] = {
		location = {0.015625, -0.671875, 0.0234375},
		rotation = {0, 0, 0},
	},
	["usd_18"] = {
		location = {-0.03125, -0.6875, -0.0234375},
		rotation = {0, 0, 0},
	},
	["usd_19"] = {
		location = {0.078125, 0.5, -0.03125},
		rotation = {0, 0, 0},
	},
	["usd_2"] = {
		location = {-0.21875, 3.9375, 0.3515625},
		rotation = {0, 0, 0},
	},
	["usd_3"] = {
		location = {-0.046875, -0.09375, -0.0234375},
		rotation = {0, 0, 0},
	},
	["usd_4"] = {
		location = {-0.03125, -0.078125, 0.0234375},
		rotation = {0, 0, 0},
	},
	["usd_5"] = {
		location = {0.015625, -0.046875, 0.0078125},
		rotation = {0, 0, 0},
	},
	["usd_6"] = {
		location = {0.015625, -0.0625, -0.0078125},
		rotation = {0, 0, 0},
	},
	["usd_7"] = {
		location = {0.015625, -0.125, -0.0234375},
		rotation = {0, 0, 0},
	},
	["usd_8"] = {
		location = {-0.015625, -0.125, -0.0078125},
		rotation = {0, 0, 0},
	},
	["usd_9"] = {
		location = {0.0, -0.046875, 0.0},
		rotation = {0, 0, 0},
	},
	["usf_10"] = {
		location = {0.03125, -0.046875, 0.0234375},
		rotation = {0, 0, 0},
	},
	["usf_11"] = {
		location = {-0.015625, 0.0, -0.0234375},
		rotation = {0, 0, 0},
	},
	["usf_12"] = {
		location = {0.0, -0.09375, -0.015625},
		rotation = {0, 0, 0},
	},
	["usf_13"] = {
		location = {0.0, -0.125, -0.03125},
		rotation = {0, 0, 0},
	},
	["usf_14"] = {
		location = {-0.015625, -0.03125, 0.015625},
		rotation = {0, 0, 0},
	},
	["usf_15"] = {
		location = {0.015625, -0.03125, 0.03125},
		rotation = {0, 0, 0},
	},
	["usf_16"] = {
		location = {-0.015625, -0.09375, -0.0546875},
		rotation = {0.0, 0, 0},
	},
	["usf_17"] = {
		location = {0.109375, -0.265625, 0.03125},
		rotation = {0, 0, 0},
	},
	["usf_18"] = {
		location = {-0.015625, -0.140625, -0.0078125},
		rotation = {0, 0, 0},
	},
	["usf_19"] = {
		location = {0.0, -0.359375, 0.015625},
		rotation = {0, 0, 0},
	},
	["usf_2"] = {
		location = {-0.078125, 3.84375, -0.3515625},
		rotation = {0, 0, 0},
	},
	["usf_3"] = {
		location = {0.0625, -0.0625, -0.015625},
		rotation = {0, 0, 0},
	},
	["usf_4"] = {
		location = {0.046875, -0.140625, -0.015625},
		rotation = {0, 0, 0},
	},
	["usf_5"] = {
		location = {-0.03125, -0.125, -0.015625},
		rotation = {0, 0, 0},
	},
	["usf_6"] = {
		location = {-0.03125, -0.03125, -0.0078125},
		rotation = {0, 0, 0},
	},
	["usf_7"] = {
		location = {-0.046875, -0.125, -0.0078125},
		rotation = {0, 0, 0},
	},
	["usf_8"] = {
		location = {0.0, -0.0625, -0.015625},
		rotation = {0, 0, 0},
	},
	["usf_9"] = {
		location = {0.046875, -0.078125, 0.0},
		rotation = {0, 0, 0},
	},
	["usg_10"] = {
		location = {-0.03125, -0.078125, 0.015625},
		rotation = {0, 0, 0},
	},
	["usg_11"] = {
		location = {-0.0625, 0.015625, 0.0234375},
		rotation = {0, 0, 0},
	},
	["usg_12"] = {
		location = {0.03125, -0.078125, -0.0234375},
		rotation = {0, 0, 0},
	},
	["usg_13"] = {
		location = {-0.015625, -0.0625, 0.015625},
		rotation = {0, 0, 0},
	},
	["usg_14"] = {
		location = {-0.03125, -0.0625, -0.0234375},
		rotation = {0, 0, 0},
	},
	["usg_15"] = {
		location = {-0.03125, 0.0, 0.03125},
		rotation = {0, 0, 0},
	},
	["usg_16"] = {
		location = {-0.046875, -0.0625, 0.0234375},
		rotation = {0, 0, 0},
	},
	["usg_17"] = {
		location = {-0.015625, -0.203125, 0.0},
		rotation = {0.0, 0, 0},
	},
	["usg_18"] = {
		location = {0.015625, -0.21875, 0.0},
		rotation = {0, 0, 0},
	},
	["usg_19"] = {
		location = {-0.015625, -0.21875, 0.0078125},
		rotation = {0, 0, 0},
	},
	["usg_2"] = {
		location = {0.34375, 3.859375, -0.1328125},
		rotation = {0, 0, 0},
	},
	["usg_3"] = {
		location = {-0.046875, -0.0625, 0.0078125},
		rotation = {0, 0, 0},
	},
	["usg_4"] = {
		location = {0.0, -0.109375, -0.0234375},
		rotation = {0, 0, 0},
	},
	["usg_5"] = {
		location = {0.0, -0.03125, -0.03125},
		rotation = {0, 0, 0},
	},
	["usg_6"] = {
		location = {-0.03125, -0.046875, 0.0078125},
		rotation = {0.0, 0, 0},
	},
	["usg_7"] = {
		location = {-0.015625, -0.09375, 0.03125},
		rotation = {0, 0, 0},
	},
	["usg_8"] = {
		location = {0.015625, -0.046875, -0.03125},
		rotation = {0, 0, 0},
	},
	["usg_9"] = {
		location = {0.015625, -0.09375, -0.046875},
		rotation = {0, 0, 0},
	},
}
