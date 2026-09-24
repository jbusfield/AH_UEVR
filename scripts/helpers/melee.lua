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

function M.beginInitialization(weapon)
	if isLive(weapon) then pendingInitializationAddress = weapon:get_address() end
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
	if isLive(window.weapon) then
		local ok, err = pcall(function() window.weapon:ResetMeleeCollisions() end)
		if not ok then M.print("weapon sweep reset failed: " .. tostring(err), LogLevel.Warning) end
	end
	if isLive(window.ability) and isLive(window.notify) then
		local ok, err = pcall(function()
			window.ability:OnAnimNotifyActivateMeleeCollisions(window.hitInfo, false, true)
		end)
		if not ok then M.print("native end failed: " .. tostring(err), LogLevel.Warning) end
	end
	M.print("weapon sweep + native window ended")
end

function M.closeMeleeWindow()
	closeMeleeWindow()
end

function M.reset()
	closeMeleeWindow()
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
local function setMeleeAnimRate(rate)
	local mesh = uevrUtils.getValid(pawn, {"Mesh"})
	if mesh ~= nil then
		mesh.GlobalAnimRateScale = rate
	end
end

function M.animateMelee(id)
	local weapon = pawn and pawn.GetCurrentWeapon and pawn:GetCurrentWeapon()
	if weapon == nil then return end

	if status.currentWeapon ~= weapon then
		status.currentWeapon = weapon
		status.isWeaponInitialized = false
	end

	if status.isWeaponInitialized == true then
		local windowOk, windowError = M.openMeleeWindow(weapon)
		if windowOk == false then
			M.print(tostring(windowError), LogLevel.Error)
		end
	else
        -- on the first swing use the game animation swing to get the intialization data
        -- needed for autonomous melee swings for every subsequent melee attack
		local previousMontage = pawn and pawn.GetCurrentMontage and pawn:GetCurrentMontage()
		M.beginInitialization(weapon)
		setMeleeAnimRate(meleePlayRate)
		uevr.api:get_player_controller(0):EquippedItemPrimaryInputPressed(1.0) -- Trigger melee attack
		local currentMontage = pawn and pawn.GetCurrentMontage and pawn:GetCurrentMontage()
		if currentMontage ~= nil and (previousMontage == nil or currentMontage:get_address() ~= previousMontage:get_address()) then
			M.observeMontage(currentMontage)
		end
		delay(500, function()
			setMeleeAnimRate(1.0)
			uevr.api:get_player_controller(0):EquippedItemPrimaryInputReleased(0.0)
			status.isWeaponInitialized = true
		end)
	end
end

return M
