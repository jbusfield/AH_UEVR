# VR melee window research for Atomic Heart

This document records how `scripts/helpers/melee.lua` arrived at its current approach and what an AI should investigate when adapting it to another Unreal Engine game. It describes observed behavior, not a universal Unreal melee API.

## Goal and current result

In VR, the player moves a weapon with a controller. Atomic Heart normally moves that weapon with an attack animation and enables melee contact during a short part of the animation. The original VR mod started the game's attack at 8× speed when a swipe was detected. That could open the game's hit window too early or too late relative to the physical swing.

The current handler uses one normal attack on the **first swing with each equipped weapon**. This initializes game state and exposes that weapon's loaded `AnimNotify_MeleeHit`. Once the notify is captured, the handler calls the game's own melee-window functions at swing start and closes the window at swing end. If initialization or a native-window call fails, it uses the old animated attack on later swings and logs each fallback. The first swing remains animation based; this is a deliberate limitation of the current implementation, not a solved animation-free initialization path.

The user reported the Shved working with this approach. The code has since been generalized to equipped melee weapons, but this document does not claim that every weapon and contact type has been validated in play.

## Current implementation

The active path is in `scripts/helpers/melee.lua`; `scripts/main.lua` supplies swing and montage events.

1. `main.lua` enables swing detection while a right-hand attachment is marked as melee. Swing begin calls `melee.animateMelee()`. Swing end calls `melee.closeMeleeWindow()`. The game's montage callback calls `melee.observeMontage()`.
2. On the first swing for a weapon, `animateMelee()` calls `EquippedItemPrimaryInputPressed`, temporarily sets the player mesh animation rate to 8×, then releases the input after 500 ms. It marks the weapon ready only if a live `AnimNotify_MeleeHit` was captured. If no notify was captured, it marks initialization failed.
3. While that attack plays, `observeMontage()` examines the montage's `Notifies` array through `libs/core/plugin.lua`. Lua's ordinary UEVR property access did not reliably enumerate this Unreal `TArray`. The handler finds a loaded `AnimNotify_MeleeHit` and caches it under the weapon's object address.
4. On subsequent swing begins, `openMeleeWindow()` checks that the cached weapon and notify still exist and that the weapon is equipped. It finds the player's `GA_MeleeAttack_C`, reads the notify's `HitInfo`, calls `OnAnimNotifyActivateMeleeCollisions(hitInfo, true, true)`, and calls the weapon's `ApplyDefaultMeleeCollisions()`.
5. On swing end, `closeMeleeWindow()` calls `ResetMeleeCollisions()` and `OnAnimNotifyActivateMeleeCollisions(hitInfo, false, true)`. `reset()` closes any open window and clears caches when scripts or levels reset.
6. If initialization fails or a native window call errors, later swings use the original 8× animated attack. Each such swing prints a `[MeleeFallback]` warning. One call in `animateMelee()` controls this fallback and can be commented out.

The intent is to let Atomic Heart's melee code process whatever the weapon contacts: a live enemy, corpse, wall, or other valid object. The handler does not select targets or assign damage to individual actor types.

Several names in this path are **Atomic Heart specific**: `MeleeAbility`, `GA_MeleeAttack_C`, `CachedCharacterOwner`, `AnimNotify_MeleeHit`, `HitInfo`, `OnAnimNotifyActivateMeleeCollisions`, `ApplyDefaultMeleeCollisions`, `ResetMeleeCollisions`, `GetCurrentWeapon`, and `EquippedItemPrimaryInputPressed/Released`. `UEVR_UObjectHook`, `uevrUtils`, and `plugin.lua` are UEVR/mod infrastructure, not standard Unreal Engine APIs. The current module also relies on the host script's global `pawn` and `delay`.

## What the investigation showed

| Attempt or observation | Result and lesson |
| --- | --- |
| Start the normal attack at 8× speed on every swipe | Hits could occur, but the animation controlled the window timing. A physical swing could cross a target while the window was closed. |
| Read montage `Notifies` directly from Lua | The lookup appeared empty. Unreal `TArray`, `TMap`, and `TSet` are not reliably exposed as ordinary Lua tables. The existing `plugin.lua` bridge could marshal the `Notifies` array and reveal the loaded `AnimNotify_MeleeHit`. |
| Invoke the melee notify's begin/tick/end callbacks directly | Calls returned false in the observed runs and produced no damage. Locating a notify alone did not recreate its gameplay context. |
| Call `ApplyDefaultMeleeCollisions()` and later `ResetMeleeCollisions()` | The calls dispatched, but the target took no damage. Enabling weapon collision alone was insufficient. A void Unreal function returning `nil` from Lua was not proof of either success or failure. |
| Execute attack notifier actions with observed indexes 2 and 3, alongside collision calls | The calls ran, but the target still took no damage. Those actions were not the whole melee hit path. |
| Perform custom sphere traces and try to feed hits into game logic | Traces missed even at close range in several runs. More importantly, manually picking targets would bypass the game's different responses for corpses, enemies, walls, and other objects. This was rejected as the design for the mod. |
| Open the game's native collision notify while the melee ability was inactive | The native calls could run without producing the full attack result. Logs showed `active=false`; a collision callback firing was not enough to establish that damage processing occurred. |
| Initialize private cached weapon pointers through a new native DLL | This could make contact reactions appear after a fresh level load, but repeated corpse hits did not sever limbs as normal melee did. It was not a complete result and the user rejected this line of inquiry. The old source/DLL may remain under `native/` and `plugins/`, but the current `melee.lua` does not call that bridge. Do not treat it as part of the working method. |
| Use one normal attack per equipped weapon, then manually open and close the native window | The user reported this working for Shved. It keeps the game's own contact processing for later physical swings. The first attack is still required by the current code. |

The corpse test was especially useful: visible movement or a hit reaction did **not** establish that the full melee outcome was correct. Normal melee could sever its limbs; the partial native-DLL approach did not. A useful test must check the game's outcome, not just whether something moved.

## Related Silent Hill 2 investigation

`C:\Users\john\Documents\Projects\SH2_UEVR\scripts\melee.lua` offered a different example. It finds a game-specific melee montage and notify, fills the game's attack request and animation context, and invokes the notify to run the game's traces and damage. It also changes montage/root-motion behavior. This demonstrated that a game's notify may require surrounding attack state to work. Its class names, memory offsets, notify invocation, and damage handling are specific to Silent Hill 2 and should not be copied into Atomic Heart or another title without independent evidence.

## Suggested investigation for another Unreal game

1. **Define the desired outcomes.** Test normal melee against several kinds of contact in that game, such as an enemy, a corpse or breakable prop, and a wall. Record damage, dismemberment, sound, decals, recoil, and any other relevant effects. This prevents a partial physics reaction from being mistaken for success.
2. **Find the game's real contact path.** Inspect decompiled headers and live UObjects for the equipped weapon, attack component or ability, montage notifies, collision components, traces, hit settings, and delegates. Prefer the game's existing melee begin/end or hit-processing functions over a generic physics collision toggle.
3. **Inspect loaded montage notifies correctly.** If a property is a `TArray`, `TMap`, or `TSet`, use a known-good marshalling bridge instead of assuming native Lua indexing works. Identify the notify that actually opens contact; a montage may also contain audio, effects, and direct-hit notifies with different purposes.
4. **Compare states before, during, and after a normal attack.** Observe what the game initializes: current weapon, active ability, attack asset, hit settings, cached references, and any collision or damage flags. Use read-only inspection first. A manual begin/end call is only promising if the game has enough state to process a contact.
5. **Try the smallest game-owned window.** Open the game's contact window at VR swing begin and close it at swing end. Keep the normal weapon and hit data so the game decides how to handle each contacted object. Validate the result across target types and after a level reload.
6. **Handle initialization explicitly.** If the game requires a legitimate first attack, document that requirement. A game may offer a clean reflected setup function; another may require an attack request or montage context. Do not mark initialization complete merely because a timer expired; the Atomic Heart handler now requires a live hit notify before using its native window.
7. **Keep game-specific operations behind an adapter.** A reusable UEVR controller can manage swing begin/end, object lifetime, caching, logging, and cleanup. A per-game adapter should provide weapon discovery, notify selection, attack initialization, and the native window begin/end calls. There is no single Unreal Engine melee-window function shared by all games.

For live work, `uevr_lua_exec` through the UEVR MCP can run small Lua probes without editing game files. Keep probes narrow and log the object, action, result, and relevant state without printing every frame. In this Atomic Heart investigation, hooked functions and one pattern-scan attempt caused crashes; those methods should be treated as high risk here. Repeated experiments should preserve a known working route and verify behavior after both script reset and level reload.

## Current limitations and transfer boundary

- The current code's first swing uses an animation. Subsequent swings open the collision window directly when initialization succeeds and native calls keep working.
- A cached notify proves that the first attack loaded the expected asset, but it does not prove that later native-window calls produced the full intended contact response. Gameplay still needs checking after a script reset and level reload.
- A failed native-window call switches that equipped weapon to animation based attacks until the melee module resets or the equipped weapon changes. Every fallback swing prints a warning.
- The cached notify is tied to one weapon object and the montage observed during its initial attack. Another game may have several attack directions or context-sensitive hit notifies that require different selection.
- `M.animateMelee(id)` currently does not use `id`; the host script decides whether a gripped attachment is a melee weapon.
- The method depends on Atomic Heart's ability and weapon functions. Other Unreal games may require a different native window, or may not have one that can be separated from animation at all.

## Reference files

- `scripts/helpers/melee.lua`: current handler.
- `scripts/main.lua`: gesture callbacks, montage observation, level/script cleanup.
- `scripts/libs/core/plugin.lua`: native bridge used to read Unreal container properties.
- `native/README.md` and `native/ah_melee_prime.cpp`: abandoned weapon-cache experiment; not used by the current handler.
- `C:\Users\john\Documents\Dumps\AH`: read-only Atomic Heart header dump used to identify game classes and fields.
- `C:\Users\john\Documents\Projects\SH2_UEVR\scripts\melee.lua`: read-only comparison showing a different game's notify-context approach.
