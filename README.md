# [Game Mode: One In The Chamber]
## About
"One In The Chamber" is a new game mode for Counter-Strike: Global Offensive laregely inspired by the game mode with the same name from the Call Of Duty series.
With "One In The Chamber" installed on the server players will spawn with nothing else than a pistol and a knife. The pistol can only contain one bullet, but the bullet always kill the enemy in the first shot.
If a player misses their shot, they have to rely on their knife in an attempt to secure a kill. Whenever a player manages to kill an enemy, the player will receive a bullet for their pistol. The first player to reach a certain amount of kills wins the round.


## Settings & Configuration Information
In the csgo/cfg/sourcemod/one_in_the_chamber/ directory you will find a file called "oneinthechamber_convars" which contains all of the convar settings the game mode provides. Below is a list of convar settings and what they do.

- OITC_HeadshotScoreBonus - Sets the amount of points players are awarded for headshotting an enemy.
- OITC_MaximumKills - Determines how many kills one player must acquire in order to win the round.
- OITC_MaximumRounds - Determines how many rounds should be played before the map changes.
- OITC_NoSpreadAndRecoil - Setting this to 1 will remove recoil and no spread from weapons, providing players with 100% accuracy.
- OITC_RandomPistols - When this is set to 1 players will receive a random pistol every round, elsewise the desert eagle is always used.
- OITC_OneHitKnifeAttacks - When set to 1 players' knife attacks will always kill the target in one hit.
- OITC_LeftClickKnifing - When set to 0 players will not be able to use their left click attack when using their knife.
- OITC_RespawnTime - This determines how long time it takes after a player dies before they are being respawned.
- OITC_SpawnProtectionTime - This determines for how long after a player spawns that they should be invulnerable.
- OITC_SpawnProtectionColoring - When set to 1 protected players will have a green color while they are invulnerable.
- OITC_FreeForAll - Setting this to 1 turns on the free-for-all mode, making everybody enemies.
- OITC_FreeForAllModels - Setting this to 1, while having free-for-all mode enabled, makes all players use the same type of player model.
- OITC_KnifeSpeedIncrease - This specifies how much faster than normally players should be running when they are using their knife.
- OITC_BunnyHopping - When this is set to 1 bunny jumping movement settings will be enabled, allowing players to move more freely.
- OITC_AutoBunnyHopping - When this is set to 1, players can hold down the jump key to automatically jump when touching the ground.
- OITC_MaximumVelocity - This determines how much velocity players can maximum acquire from bunny jumping and strafing.
- OITC_FallDamage - Setting this to 0 will make it so players will not be able to take damage from falling.
- OITC_ObjectiveBomb - Setting this to 0 will remove bombing objectives from the map.
- OITC_ObjectiveHostage - Setting this to 0 will remove hostages and rescue points from the map.

## Recommended Game Levels / Maps
This game mode is compatible with all of the maps in the current official map pool. The game mode can be played on any map, but when the free-for-all mode is enabled it is recommended to use maps that support the usage of random spawn locations. Fortunately, most maps already do this, this including all of the maps that have ever been part of the official map pool, and most maps in general, there may be a very few exceptions to this rule.


## Requirements
In order for the plugin to work, you must have the following installed:
- [SourceMod](https://www.sourcemod.net/downloads.php?branch=stable) 


## Installation
1) Download the contents and open the downloaded zip file.
2) Drag the files in to your server's csgo/ directory.
3) Edit the files in cfg/sourcemod/one_in_the_chamber/ to match your preferences
4) Compress and add the contents of the resource folder to your fast download server.
5) Restart your server.


## Known Bugs & Issues
- None.


## Future development plans
- [ ] Fix any bugs/issues that gets reported.


## Bug Reports, Problems & Help
This plugin has been tested and used on a server, there should be no bugs or issues aside from the known ones found here.
Should you run in to a bug that isn't listed here, then please report it in by creating an issue here on GitHub.
