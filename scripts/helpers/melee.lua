local uevrUtils = require('libs/uevr_utils')
local plugin = require('libs/core/plugin')

local M = {}

local status = {}


local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[melee] " .. text, logLevel)
	end
end

-- local loggedMeleeAttackAssets = {}
-- local meleeAttackAssetsByWeapon = {}

-- local function getMeleeAttackAssets(weapon)
-- 	local address = weapon:get_address()
-- 	if meleeAttackAssetsByWeapon[address] ~= nil then
-- 		return meleeAttackAssetsByWeapon[address]
-- 	end
-- 	local ok, assets = pcall(plugin.getProperty, weapon, "AttackAssets")
-- 	if ok and type(assets) == "table" then
-- 		meleeAttackAssetsByWeapon[address] = assets
-- 		return assets
-- 	end
-- 	return nil
-- end

-- function M.logMeleeAttackAssetsOnce()
-- 	local pawn = uevrUtils.get_local_pawn()
-- 	local weapon = pawn and pawn.GetCurrentWeapon and pawn:GetCurrentWeapon()
-- 	if weapon == nil then return end
-- 	local address = weapon:get_address()
-- 	if loggedMeleeAttackAssets[address] then return end
-- 	loggedMeleeAttackAssets[address] = true

-- 	local assets = getMeleeAttackAssets(weapon)
-- 	if assets == nil then
-- 		uevrUtils.print("[MeleeData] AttackAssets lookup failed", LogLevel.Warning)
-- 		return
-- 	end

-- 	for actionType, attackData in pairs(assets) do
-- 		local attackName = attackData and attackData.get_full_name and attackData:get_full_name() or tostring(attackData)
-- 		local hitSettings
-- 		if attackData ~= nil then
-- 			local hitOk, result = pcall(plugin.getProperty, attackData, "HitSettings")
-- 			if hitOk then hitSettings = result end
-- 		end
-- 		local hitName = hitSettings and hitSettings.get_full_name and hitSettings:get_full_name() or tostring(hitSettings)
-- 		local damageMin, damageMax = "?", "?"
-- 		if hitSettings ~= nil then
-- 			local minOk, minValue = pcall(plugin.getProperty, hitSettings, "DamageMin")
-- 			local maxOk, maxValue = pcall(plugin.getProperty, hitSettings, "DamageMax")
-- 			if minOk then damageMin = tostring(minValue) end
-- 			if maxOk then damageMax = tostring(maxValue) end
-- 		end
-- 		uevrUtils.print(string.format("[MeleeData] action=%s asset=%s hitSettings=%s damage=%s..%s", tostring(actionType), attackName, hitName, damageMin, damageMax))
-- 	end
-- end

local meleeWindow = nil
local hitNotifiesByWeapon = {}
local pendingInitializationAddress = nil
local abilityCache = nil
local stopAnimatedAttack

local function isLive(object)
	if object == nil then return false end
	local ok, exists = pcall(UEVR_UObjectHook.exists, object)
	return ok and exists == true
end

local function findMeleeHitNotify(montage)
	if not isLive(montage) then return nil end

    --scan through a montage's notifies for the correct notify
	local ok, events = pcall(plugin.getProperty, montage, "Notifies")
	if ok and type(events) == "table" then
		for _, event in pairs(events) do
			if type(event) == "table" then
				local notify = event.NotifyStateClass or event.Notify
				if isLive(notify) and notify:get_full_name():match("^AnimNotify_MeleeHit ") then
					M.print("Found notify " .. notify:get_full_name())
                    return notify
				end
			end
		end
	end
	return nil
end

-- This should be able to find the notify without waiting for the montage to play
-- in case we ever figure out how to initialize the game state for full melee behavior
-- without needing to play an initial animation. Until then, we'll use the montage scan.
local function findNotifyFromWeaponAssets(weapon)
    local ok, attacks = pcall(plugin.getProperty, weapon, "AttackAssets")
    if not ok or type(attacks) ~= "table" then return nil end

    for _, attack in pairs(attacks) do
        if isLive(attack) then
            local animations = attack.Animations
            if isLive(animations) then
                local readOk, sequences =
                    pcall(plugin.getProperty, animations, "Sequences")

                if readOk and type(sequences) == "table" then
                    for _, sequence in pairs(sequences) do
                        for _, phase in pairs(sequence.Phases or {}) do
                            local montage = phase.Montage
                            if isLive(montage) then
                                local notify = findMeleeHitNotify(montage)
                                if notify then return notify end
                            end
                        end
                    end
                end
            end
        end
    end

    return nil
end

function M.beginInitialization(weapon)
	if not isLive(weapon) then return false end
	local address = weapon:get_address()

    -- local notify = findNotifyFromWeaponAssets(weapon)
    -- hitNotifiesByWeapon[address] = notify
    -- pendingInitializationAddress = notify == nil and address or nil

	hitNotifiesByWeapon[address] = nil
	pendingInitializationAddress = address
	return true
end

function M.observeMontage(montage)
	if pendingInitializationAddress == nil or montage == nil then return end
	local weapon = pawn and pawn.GetCurrentWeapon and pawn:GetCurrentWeapon()
	if not isLive(weapon) or weapon:get_address() ~= pendingInitializationAddress then return end
	local notify = findMeleeHitNotify(montage)
	if notify == nil then return end
	hitNotifiesByWeapon[pendingInitializationAddress] = notify
	pendingInitializationAddress = nil
	M.print("loaded hit notify for " .. weapon:get_full_name())
end

local function getMeleeAbility(pawn)
	if abilityCache ~= nil and abilityCache.pawnAddress == pawn:get_address() and isLive(abilityCache.ability) then
		return abilityCache.ability
	end
	for _, candidate in ipairs(uevrUtils.find_all_of("Class /Script/AtomicHeart.MeleeAbility", false)) do
		local owner = candidate.CachedCharacterOwner
		if isLive(owner) and owner:get_address() == pawn:get_address() and string.find(candidate:get_full_name(), "GA_MeleeAttack_C", 1, true) then
			abilityCache = {pawnAddress = pawn:get_address(), ability = candidate}
			return candidate
		end
	end
	return nil
end

local function closeMeleeWindow()
	local window = meleeWindow
	if window == nil then return end
	meleeWindow = nil
	local failure = nil
	if isLive(window.weapon) then
		local ok, err = pcall(function() window.weapon:ResetMeleeCollisions() end)
		if not ok then failure = "weapon sweep reset failed: " .. tostring(err) end
	end
	if isLive(window.ability) and isLive(window.notify) then
		local ok, err = pcall(function()
			window.ability:OnAnimNotifyActivateMeleeCollisions(window.hitInfo, false, true)
		end)
		if not ok then failure = "native end failed: " .. tostring(err) end
	elseif isLive(window.weapon) then
		failure = "native end unavailable: melee ability or notify expired"
	end
	if failure ~= nil then
		if isLive(window.weapon) and status.weaponAddress == window.weapon:get_address() then
			status.initState = "failed"
			status.failureReason = failure
		end
		M.print(failure, LogLevel.Error)
	else
		M.print("weapon sweep + native window ended")
	end
end

function M.closeMeleeWindow()
	closeMeleeWindow()
end

function M.reset()
	closeMeleeWindow()
	if stopAnimatedAttack ~= nil then stopAnimatedAttack() end
	hitNotifiesByWeapon = {}
	pendingInitializationAddress = nil
	abilityCache = nil
    status = {}
end

function M.openMeleeWindow(weapon)
	if not isLive(weapon) then return false, "current melee weapon unavailable" end
	if not isLive(pawn) then return false, "player pawn unavailable" end
	local equipped = pawn.GetCurrentWeapon and pawn:GetCurrentWeapon()
	if not isLive(equipped) or equipped:get_address() ~= weapon:get_address() then
		return false, "melee weapon is no longer equipped"
	end
	local weaponAddress = weapon:get_address()
	if meleeWindow ~= nil and (not isLive(meleeWindow.weapon) or meleeWindow.weapon:get_address() ~= weaponAddress) then
		closeMeleeWindow()
	end
	if meleeWindow == nil then
		local notify = hitNotifiesByWeapon[weaponAddress]
		if not isLive(notify) then
			hitNotifiesByWeapon[weaponAddress] = nil
			return false, "no loaded MeleeHit notify for current weapon"
		end
		local ability = getMeleeAbility(pawn)
		if ability == nil then return false, "player melee ability unavailable" end
		local hitInfo = notify.HitInfo
		if hitInfo == nil then return false, "notify HitInfo unavailable" end
		local ok, err = pcall(function()
			ability:OnAnimNotifyActivateMeleeCollisions(hitInfo, true, true)
			weapon:ApplyDefaultMeleeCollisions()
		end)
		if not ok then
			pcall(function() weapon:ResetMeleeCollisions() end)
			pcall(function() ability:OnAnimNotifyActivateMeleeCollisions(hitInfo, false, true) end)
			return false, "native begin failed: " .. tostring(err)
		end
		meleeWindow = {ability = ability, notify = notify, hitInfo = hitInfo, weapon = weapon}
		M.print(string.format("native begin + weapon sweep active=%s limb=%s", tostring(ability.bIsActive), tostring(hitInfo.LimbType)))
	end
	return true
end

local meleePlayRate = 8.0
local animatedController = nil
local animatedPawn = nil
local animatedAttackToken = 0

local function setMeleeAnimRate(rate, attackPawn)
	local mesh = uevrUtils.getValid(attackPawn, {"Mesh"})
	if mesh ~= nil then
		mesh.GlobalAnimRateScale = rate
	end
end

stopAnimatedAttack = function()
	animatedAttackToken = animatedAttackToken + 1
	if animatedController ~= nil then
		pcall(function() animatedController:EquippedItemPrimaryInputReleased(0.0) end)
	end
	if animatedPawn ~= nil then pcall(setMeleeAnimRate, 1.0, animatedPawn) end
	animatedController = nil
	animatedPawn = nil
end

local function playAnimatedAttack(onComplete)
	stopAnimatedAttack()
	local attackPawn = pawn
	local ok, controllerOrError = pcall(function() return uevr.api:get_player_controller(0) end)
	if not ok or controllerOrError == nil then
		return false, "player controller unavailable: " .. tostring(controllerOrError)
	end
	local controller = controllerOrError
	animatedController = controller
	animatedPawn = attackPawn
	local pressed, pressError = pcall(function()
		setMeleeAnimRate(meleePlayRate, attackPawn)
		controller:EquippedItemPrimaryInputPressed(1.0)
	end)
	if not pressed then
		stopAnimatedAttack()
		return false, "animated attack input failed: " .. tostring(pressError)
	end
	local token = animatedAttackToken
	local scheduled, scheduleError = pcall(delay, 500, function()
		if token ~= animatedAttackToken then return end
		stopAnimatedAttack()
		if onComplete ~= nil then onComplete() end
	end)
	if not scheduled then
		stopAnimatedAttack()
		return false, "animated attack release could not be scheduled: " .. tostring(scheduleError)
	end
	return true
end

local function playAnimatedMeleeFallback(reason)
	-- This message is deliberately emitted for every fallback swing, regardless of the module log level.
	uevrUtils.print("[MeleeFallback] Animated attack used on this swing: " .. tostring(reason), LogLevel.Warning)
	local ok, err = playAnimatedAttack()
	if not ok then M.print("animated fallback failed: " .. tostring(err), LogLevel.Error) end
end

function M.animateMelee(id)
	local weapon = pawn and pawn.GetCurrentWeapon and pawn:GetCurrentWeapon()
	if not isLive(weapon) then return end
	local weaponAddress = weapon:get_address()

	if status.weaponAddress ~= weaponAddress then
		closeMeleeWindow()
		status = {weaponAddress = weaponAddress, initState = "new"}
	end

	if status.initState == "ready" then
		local called, windowOk, windowError = pcall(M.openMeleeWindow, weapon)
		if called and windowOk then return end
		if not called then closeMeleeWindow() end
		status.initState = "failed"
		status.failureReason = tostring(called and windowError or windowOk)
		M.print("native melee window failed: " .. status.failureReason, LogLevel.Error)
	end

	if status.initState == "failed" then
		-- Comment out this one call to disable the old animation based fallback.
		playAnimatedMeleeFallback(status.failureReason)
		return
	end

	if status.initState == "initializing" then return end

	-- The first swing uses a normal attack to load the weapon's MeleeHit notify.
	local previousMontage = pawn.GetCurrentMontage and pawn:GetCurrentMontage()
	if not M.beginInitialization(weapon) then
		status.initState = "failed"
		status.failureReason = "weapon unavailable during initialization"
		M.print(status.failureReason, LogLevel.Error)
		return
	end
	status.initState = "initializing"
	M.print("animated initialization swing for equipped weapon")
	local initializationStatus = status
	local started, startError = playAnimatedAttack(function()
		if status ~= initializationStatus or status.initState ~= "initializing" then return end
		local notify = hitNotifiesByWeapon[weaponAddress]
		if isLive(notify) then
			status.initState = "ready"
			status.failureReason = nil
			M.print("MeleeHit notify captured; native melee window ready")
		else
			pendingInitializationAddress = nil
			status.initState = "failed"
			status.failureReason = "initial attack did not load a MeleeHit notify"
			M.print(status.failureReason, LogLevel.Error)
		end
	end)
	if not started then
		pendingInitializationAddress = nil
		status.initState = "failed"
		status.failureReason = tostring(startError)
		M.print("melee initialization failed: " .. status.failureReason, LogLevel.Error)
		return
	end
	local currentMontage = pawn.GetCurrentMontage and pawn:GetCurrentMontage()
	if currentMontage ~= nil and (previousMontage == nil or currentMontage:get_address() ~= previousMontage:get_address()) then
		M.observeMontage(currentMontage)
	end
end

return M
