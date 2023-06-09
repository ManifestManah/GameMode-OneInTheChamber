// List of Includes
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <multicolors>

// The code formatting rules we wish to follow
#pragma semicolon 1;
#pragma newdecls required;


// The retrievable information about the plugin itself 
public Plugin myinfo =
{
	name		= "[CS:GO] One In The Chamber",
	author		= "Manifest @Road To Glory",
	description	= "Changes the gameplay so that players have just one bullet to finish off their enemies.",
	version		= "V. 1.0.0 [Beta]",
	url			= ""
};



/////////////////
// - Convars - //
/////////////////

ConVar cvar_RespawnTime;
ConVar cvar_SpawnProtectionTime;
ConVar cvar_SpawnProtectionColoring;
ConVar cvar_MaximumKills;
ConVar cvar_MaximumRounds;
ConVar cvar_KnifeSpeedIncrease;
ConVar cvar_BunnyHopping;
ConVar cvar_AutoBunnyHopping;
ConVar cvar_FallDamage;
ConVar cvar_MaximumVelocity;
ConVar cvar_LeftClickKnifing;
ConVar cvar_OneHitKnifeAttacks;
ConVar cvar_RandomPistols;
ConVar cvar_NoSpreadAndRecoil;
ConVar cvar_HeadshotScoreBonus;
ConVar cvar_FreeForAll;
ConVar cvar_FreeForAllModels;
ConVar cvar_ObjectiveBomb;
ConVar cvar_ObjectiveHostage;



//////////////////////////
// - Global Variables - //
//////////////////////////

// Global Booleans
bool gameHasEnded = false;
bool weaponGivingFailSafe = false;
bool isSpawnProtected[MAXPLAYERS + 1] = {false,...};
bool isPlayerRecentlyConnected[MAXPLAYERS + 1] = {false,...};


// Global Integers
int playerSpawnCounter[MAXPLAYERS + 1] = {0, ...};
int playerCurrentMVPs[MAXPLAYERS + 1] = {0, ...};
int playerCurrentKills[MAXPLAYERS + 1] = {0, ...};
int knifeMovementSpeedCounter[MAXPLAYERS + 1] = {0, ...};
int playerWeaponSwapCounter[MAXPLAYERS + 1] = {0, ...};


// Global Floats
float knifeMovementSpeedBase = 1.0;
float KnifeMovementSpeedIncrement = 0.0;


// Global Characters
char pistolClassName[64];



//////////////////////////
// - Forwards & Hooks - //
//////////////////////////


// This happens when the plugin is loaded
public void OnPluginStart()
{
	// Loads the translaltion file which we intend to use
	LoadTranslations("manifest_OneInTheChamber.phrases");

	// Creates the names and assigns values to the ConVars the modification will be using 
	CreateModSpecificConvars();

	// Hooks the events that we intend to use in our plugin
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	HookEvent("round_start", Event_RoundStart, EventHookMode_Post);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_Post);
	HookEvent("weapon_fire", Event_WeaponFire, EventHookMode_Pre);

	// Calls upon our CommandListenerJoinTeam function whenever a player changes team
	AddCommandListener(CommandListenerJoinTeam, "jointeam");

	// Removes any unowned weapon and item entities from the map every second
	CreateTimer(1.0, Timer_CleanFloor, _, TIMER_REPEAT);

	// Fixes an issue with the hint area not displaying html colors
	AllowHtmlHintMessages();

	// Fixes an issue with the Hud Hint displaying a dollar sign symbol
	FixDollarSign();

	// Calculates the values used for the bonus knife movement speed
	CalculateSpeedValues();

	// Adds an additional tagsto the server's sv_tags line after 3 seconds has passed
	CreateTimer(3.0, Timer_AddSvTags, _, TIMER_FLAG_NO_MAPCHANGE);

	// Allows the modification to be loaded while the server is running, without causing gameplay issues
	LateLoadSupport();

	// Sends the specified multi-language message to all clients
	SendChatMessageToAll("Chat - Mod Loaded");
}


// This happens when the plugin is unloaded
public void OnPluginEnd()
{
	// Sends the specified multi-language message to all clients
	SendChatMessageToAll("Chat - Mod Unloaded");

	// Loops through all of the clients
	for (int client = 1; client <= MaxClients; client++)
	{
		// If the client does not meet our validation criteria then execute this section
		if(!IsValidClient(client))
		{
			continue;
		}

		// Adds a hook to the client which will let us track when the player is eligible to pick up a weapon
		SDKHook(client, SDKHook_WeaponCanUse, Hook_WeaponCanUse);

		// Adds a hook to the client which will let us track when the player takes damage
		SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
	}
}


// This happens when a new map is loaded
public void OnMapStart()
{
	// Changes the state of whether the game has ended already to false
	gameHasEnded = false;

	// Sets whether or not auto bunny jumping should be toggle on or off
	SetAutoBunnyHopping();

	// Sets the maximum amount of rounds that should be played
	SetMaxRounds();

	// Sets the amount of fall damage players should take
	SetFallDamage();

	// Sets the maximum amount of velocity that should be possible for a player to acquire
	SetMaxVelocity();

	// Removes all of the buy zones from the map
	RemoveEntityBuyZones();

	// If the value of cvar_ObjectiveBomb is set to false then execute this section
	if(!GetConVarBool(cvar_ObjectiveBomb))
	{
		// Removes all of the bomb sites from the map
		RemoveEntityBombSites();
	}

	// If the value of cvar_ObjectiveHostage is set to false then execute this section
	if(!GetConVarBool(cvar_ObjectiveHostage))
	{
		// Removes Hostage Rescue Points from the map
		RemoveEntityHostageRescuePoint();
	}

	// Executes the appropriate configuration files depending on the convar settings
	ExecuteServerConfigurationFiles();

	// Allows the modification to be loaded while the server is running, without causing gameplay issues
	LateLoadSupport();
}


// This happens once all post authorizations have been performed and the client is fully in-game
public void OnClientPostAdminCheck(int client)
{
	// If the client does not meet our validation criteria then execute this section
	if(!IsValidClient(client))
	{
		return;
	}

	// Sets the client's recently connected status true
	isPlayerRecentlyConnected[client] = true;

	// Resets the value of the playerCurrentKills variable back to 0
	playerCurrentKills[client] = 0;

	// Resets the value of the playerCurrentMVPs variable back to 0
	playerCurrentMVPs[client] = 0;

	// Adds a hook to the client which will let us track when the player is eligible to pick up a weapon
	SDKHook(client, SDKHook_WeaponCanUse, Hook_WeaponCanUse);

	// Adds a hook to the client which will let us track when the player takes damage
	SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);

	// Adds a hook to the client which will let us track when the player switches weapon
	SDKHook(client, SDKHook_WeaponSwitchPost, Hook_OnWeaponSwitchPost);
}


// This happens when a player disconnects
public void OnClientDisconnect(int client)
{
	// If the client does not meet our validation criteria then execute this section
	if(!IsValidClient(client))
	{
		return;
	}

	// Removes the hook that we had added to the client to track when he was eligible to pick up weapons
	SDKUnhook(client, SDKHook_WeaponCanUse, Hook_WeaponCanUse);

	// Removes the hook that we had added to the client to track when the player took damage
	SDKUnhook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);

	// Removes the hook that we had added to the client to track when he they change weapon
	SDKUnhook(client, SDKHook_WeaponSwitchPost, Hook_OnWeaponSwitchPost);
}


// This happens when a player can pick up a weapon
public Action Hook_WeaponCanUse(int client, int weapon)
{
	// If the client does not meet our validation criteria then execute this section
	if(!IsValidClient(client))
	{
		return Plugin_Continue;
	}

	// If the weapon that was picked up our entity criteria of validation then execute this section
	if(!IsValidEntity(weapon))
	{
		return Plugin_Continue;
	}

	// Creates a variable called ClassName which we will store the weapon entity's name within
	char className[64];

	// Obtains the classname of the weapon entity and store it within our ClassName variable
	GetEntityClassname(weapon, className, sizeof(className));

	// If the pistolClassName variable is weapon_cz75a then execute this section
	if(StrEqual(pistolClassName, "weapon_cz75a", false))
	{
		// If the weapon's entity name is that of the specified pistols's then execute this section
		if(StrEqual(className, "weapon_p250", false))
		{
			return Plugin_Continue;
		}
	}

	// If the pistolClassName variable is weapon_usp_silencer then execute this section
	else if(StrEqual(pistolClassName, "weapon_usp_silencer", false))
	{
		// If the weapon's entity name is that of the specified pistols's then execute this section
		if(StrEqual(className, "weapon_hkp2000", false))
		{
			return Plugin_Continue;
		}
	}

	// If the pistolClassName variable is weapon_revolver then execute this section
	else if(StrEqual(pistolClassName, "weapon_revolver", false))
	{
		// If the weapon's entity name is that of the specified pistols's then execute this section
		if(StrEqual(className, "weapon_deagle", false))
		{
			return Plugin_Continue;
		}
	}

	// If the weapon's entity name is that of a pistols's or knife then execute this section
	if(StrEqual(className, pistolClassName, false) | StrEqual(className, "weapon_knife", false))
	{
		return Plugin_Continue;
	}

	// Kills the weapon entity, removing it from the game
	AcceptEntityInput(weapon, "Kill");

	return Plugin_Handled;
}


// This happens when the player takes damage
public Action Hook_OnTakeDamage(int client, int &attacker, int &inflictor, float &damage, int &damagetype) 
{
	// If the client does not meet our validation criteria then execute this section
	if(!IsValidClient(client))
	{
		return Plugin_Continue;
	}

	// If the attacker does not meet our validation criteria then execute this section
	if(!IsValidClient(attacker))
	{
		return Plugin_Continue;
	}

	// If the inflictor is not a valid entity then execute this section
	if(!IsValidEntity(inflictor))
	{
		return Plugin_Continue;
	}

	// If the value of cvar_FreeForAll is set to false then execute this section
	if(!GetConVarBool(cvar_FreeForAll))
	{
		// If the victim and attacker is on the same team
		if(GetClientTeam(client) == GetClientTeam(attacker))
		{
			return Plugin_Continue;
		}
	}

	// Obtains the name of the player's weapon and store it within our variable entity
	int entity = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");

	// If the entity does not meet the criteria of validation then execute this section
	if(!IsValidEntity(entity))
	{
		return Plugin_Continue;
	}

	// Creates a variable which we will use to store data within
	char className[64];

	// Obtains the entity's class name and store it within our className variable
	GetEntityClassname(entity, className, sizeof(className));

	// If the weapon's entity name is that of a pistols then execute this section
	if(StrEqual(className, pistolClassName, false))
	{
		// Changes the amount of damage to zero
		damage = 500.0;

		// Calls upon the Timer_RespawnPlayer function after (3.0 default) seconds
		CreateTimer(0.0, Timer_GiveAmmo, attacker, TIMER_FLAG_NO_MAPCHANGE);

		return Plugin_Changed;
	}

	// If the pistolClassName variable is weapon_cz75a then execute this section
	if(StrEqual(pistolClassName, "weapon_cz75a", false))
	{
		// If the weapon's entity name is that of the specified pistols's then execute this section
		if(StrEqual(className, "weapon_p250", false))
		{
			// Changes the amount of damage to zero
			damage = 500.0;

			// Calls upon the Timer_RespawnPlayer function after (3.0 default) seconds
			CreateTimer(0.0, Timer_GiveAmmo, attacker, TIMER_FLAG_NO_MAPCHANGE);

			return Plugin_Changed;
		}
	}

	// If the pistolClassName variable is weapon_usp_silencer then execute this section
	else if(StrEqual(pistolClassName, "weapon_usp_silencer", false))
	{
		// If the weapon's entity name is that of the specified pistols's then execute this section
		if(StrEqual(className, "weapon_hkp2000", false))
		{
			// Changes the amount of damage to zero
			damage = 500.0;

			// Calls upon the Timer_RespawnPlayer function after (3.0 default) seconds
			CreateTimer(0.0, Timer_GiveAmmo, attacker, TIMER_FLAG_NO_MAPCHANGE);

			return Plugin_Changed;
		}
	}

	// If the pistolClassName variable is weapon_revolver then execute this section
	else if(StrEqual(pistolClassName, "weapon_revolver", false))
	{
		// If the weapon's entity name is that of the specified pistols's then execute this section
		if(StrEqual(className, "weapon_deagle", false))
		{
			// Changes the amount of damage to zero
			damage = 500.0;

			// Calls upon the Timer_RespawnPlayer function after (3.0 default) seconds
			CreateTimer(0.0, Timer_GiveAmmo, attacker, TIMER_FLAG_NO_MAPCHANGE);

			return Plugin_Changed;
		}
	}

	// If the cvar_OneHitKnifeAttacks convar returns false then execute this section
	if(!GetConVarBool(cvar_OneHitKnifeAttacks))
	{
		return Plugin_Continue;
	}

	// If the weapon's entity name is that of a pistols then execute this section
	if(StrEqual(className, "weapon_knife", false))
	{
		// Changes the amount of damage to zero
		damage = 500.0;

		return Plugin_Changed;
	}

	return Plugin_Continue;
}


// This happens when a player switches
public Action Hook_OnWeaponSwitchPost(int client, int weapon)
{
	// If the value of cvar_KnifeSpeedIncrease is 0 or below then execute this section
	if(GetConVarInt(cvar_KnifeSpeedIncrease) <= 0)
	{
		return Plugin_Continue;
	}

	// If the client does not meet our validation criteria then execute this section
	if(!IsValidClient(client))
	{
		return Plugin_Continue;
	}

	// If the weapon that was picked up our entity criteria of validation then execute this section
	if(!IsValidEntity(weapon))
	{
		// Resets the player's speed and speed related variables
		ResetPlayerSpeed(client);

		return Plugin_Continue;
	}

	// If the weapon entity's classname is not a knife then execute this section
	if(!IsWeaponKnife(weapon))
	{
		// Resets the player's speed and speed related variables
		ResetPlayerSpeed(client);

		return Plugin_Continue;
	}

	// Changes the movement speed of the player to a higher value
	SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", knifeMovementSpeedBase);

	// Resets the player's stack counter back to 0
	knifeMovementSpeedCounter[client] = 0;

	// Adds + 1 to the value of our playerWeaponSwapCounter[client] variable
	playerWeaponSwapCounter[client]++;
	
	// Creates a datapack called pack which we will store our data within 
	DataPack pack = new DataPack();

	// Stores the client's index within our datapack
	pack.WriteCell(client);

	// Stores the playerWeaponSwapCounter variable within our datapack
	pack.WriteCell(playerWeaponSwapCounter[client]);

	// After (3.5 default) seconds remove the spawn protection from the player
	CreateTimer(0.1, Timer_MovementSpeedIncrease, pack, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Continue;
}


// This happens 0.1 seconds after a player switches weapon to a knife
public Action Timer_MovementSpeedIncrease(Handle timer, DataPack dataPackage)
{

	dataPackage.Reset();

	// Obtains client index stored within our data pack and store it within the client variable
	int client = dataPackage.ReadCell();

	// Obtains the value of playerWeaponSwapCounter[client] stored within our data pack and store it within the localSwapCount variable
	int localSwapCount = dataPackage.ReadCell();
	
	// Deletes our data package after having acquired the information we needed
	delete dataPackage;
	
	// If the client does not meet our validation criteria then execute this section
	if(!IsValidClient(client))
	{
		return Plugin_Stop;
	}

	// If the value of localSwapCount and playerWeaponSwapCounter[client] variable differs then execute this section
	if(localSwapCount != playerWeaponSwapCounter[client])
	{
		// Resets the player's speed and speed related variables
		ResetPlayerSpeed(client);

		return Plugin_Stop;
	}

	// If the client is not alive then execute this section
	if(!IsPlayerAlive(client))
	{
		// Resets the player's speed and speed related variables
		ResetPlayerSpeed(client);

		return Plugin_Stop;
	}

	// Obtains the name of the player's weapon and store it within our variable entity
	int entity = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");

	// If the entity does not meet the criteria of validation then execute this section
	if(!IsValidEntity(entity))
	{
		// Resets the player's speed and speed related variables
		ResetPlayerSpeed(client);

		return Plugin_Stop;
	}

	// If the weapon entity's classname is not a knife then execute this section
	if(!IsWeaponKnife(entity))
	{
		// Resets the player's speed and speed related variables
		ResetPlayerSpeed(client);

		return Plugin_Stop;
	}

	// If the player is already at full speed then execute this section
	if(knifeMovementSpeedCounter[client] == 8)
	{
		return Plugin_Stop;
	}

	// Adds +1 to the player's movement speed counter variable
	knifeMovementSpeedCounter[client]++;

	// Calculates the total amount of movement speed and store it within the totalKnifeMovementSpeed variable
	float totalKnifeMovementSpeed = knifeMovementSpeedBase + (KnifeMovementSpeedIncrement * knifeMovementSpeedCounter[client]);

	// Changes the movement speed of the player to the value of our totalKnifeMovementSpeed variable
	SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", totalKnifeMovementSpeed);

	// Creates a datapack called pack which we will store our data within 
	DataPack pack = new DataPack();

	// Stores the client's index within our datapack
	pack.WriteCell(client);

	// Stores the playerWeaponSwapCounter variable within our datapack
	pack.WriteCell(localSwapCount);

	// After (3.5 default) seconds remove the spawn protection from the player
	CreateTimer(0.1, Timer_MovementSpeedIncrease, pack, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Stop;
}


// This happens when a player joins or changes team 
public Action CommandListenerJoinTeam(int client, const char[] command, int numArgs)
{
	// If the client does not meet our validation criteria then execute this section
	if(!IsValidClient(client))
	{
		return Plugin_Continue;
	}

	// Calls upon the Timer_RespawnPlayer function after (3.0 default) seconds
	CreateTimer(GetConVarFloat(cvar_RespawnTime), Timer_RespawnPlayer, client, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Continue;
}


// This happens when a player presses a key
public Action OnPlayerRunCmd(int client, int &buttons) 
{
	// If the cvar_LeftClickKnifing convar returns true then execute this section
	if(GetConVarBool(cvar_LeftClickKnifing))
	{
		return Plugin_Continue;
	}

	// If the client does not meet our validation criteria then execute this section
	if(!IsValidClient(client))
	{
		return Plugin_Continue;
	}

	// If the client is not alive then execute this section
	if(!IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}

	// Obtains the name of the player's weapon and store it within our variable entity
	int entity = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");

	// If the entity does not meet the criteria of validation then execute this section
	if(!IsValidEntity(entity))
	{
		return Plugin_Continue;
	}

	// Creates a variable which we will use to store data within
	char className[64];

	// Obtains the entity's class name and store it within our className variable
	GetEntityClassname(entity, className, sizeof(className));

	// If the weapon's entity name is that of a knife then execute this section
	if(!StrEqual(className, "weapon_knife", false))
	{
		return Plugin_Continue;
	}

	// Prevents the knife entity from being fired by adding a delay to when the next primary attack can be performed
	SetEntPropFloat(entity, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() + 1.0);

	// If the button that is being pressed is the left click then execute this section
	if(buttons & IN_ATTACK2)
	{
		// If the player is not spawn protected then execute this section
		if(!isSpawnProtected[client])
		{
			return Plugin_Continue;
		}

		// Removes the spawn protection from the client
		RemoveSpawnProtection(client, 2);
	}

	// If the button that is being pressed is the left click then execute this section
	if(buttons & IN_ATTACK)
	{
		// If the client is a bot then execute this section
		if(IsFakeClient(client))
		{
			return Plugin_Continue;
		}

		// Creates a variable which we will use to store our data within
		char hudMessage[1024];

		// Formats the message that we wish to send to the player and store it within our hudMessage variable
		Format(hudMessage, 1024, "\n<font color='#fbb227'>Restriction:</font>");
		Format(hudMessage, 1024, "%s\n<font color='#fbb227'>Left click knife attacks are disabled</font>", hudMessage);

		// Displays the contents of our hudMessage variable for the client to see in the hint text area of their screen 
		PrintHintText(client, hudMessage);
	}

	return Plugin_Continue;
}



////////////////
// - Events - //
////////////////


// This happens when a player spawns
public void Event_PlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
	// Obtains the client's userid and converts it to an index and store it within our client variable
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	// If the client does not meet our validation criteria then execute this section
	if(!IsValidClient(client))
	{
		return;
	}

	// Removes the hook that we had added to the client to track when he was eligible to pick up weapons
	SDKUnhook(client, SDKHook_WeaponCanUse, Hook_WeaponCanUse);

	// Removes the hook that we had added to the client to track when the player took damage
	SDKUnhook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);

	// Adds a hook to the client which will let us track when the player is eligible to pick up a weapon
	SDKHook(client, SDKHook_WeaponCanUse, Hook_WeaponCanUse);

	// Adds a hook to the client which will let us track when the player takes damage
	SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);

	// Creates and sends a menu with introduction information to the client
	IntroductionMenu(client);

	// Renders the player immune to any incoming damage
	GivePlayerSpawnProtection(client);

	// Assign a model to the player if Free for all is enabled 
	SetPlayerModels(client);

	// Sets the player's MVP count to that of the playerCurrentMVPs[client] variable
	SetPlayerMVPs(client);

	// Resets the player's speed and speed related variables
	ResetPlayerSpeed(client);

	// Removes all the weapons from the client
	RemoveAllWeapons(client);

	// Gives the client a knife
	GiveKnife(client);

	// Gives the player a pistol after 0.1 seconds
	CreateTimer(0.1, Timer_GivePistol, client, TIMER_FLAG_NO_MAPCHANGE);

	// Changes the ammo of the player's pistol after 0.2 seconds
	CreateTimer(0.2, Timer_GiveAmmo, client, TIMER_FLAG_NO_MAPCHANGE);

	// If the game still hasn't ended then execute this section
	if(!gameHasEnded)
	{
		return;
	}
	
	// Renders the player unable to move or perform any movement related actions
	SetEntityFlags(client, GetEntityFlags(client) | FL_FROZEN);
}


// This happens when a player dies
public Action Event_PlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	// Obtains the client's userid and converts it to an index and store it within our client variable
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	// If the client does not meet our validation criteria then execute this section
	if(!IsValidClient(client))
	{
		return Plugin_Continue;
	}

	// Calls upon the Timer_RespawnPlayer function after (3.0 default) seconds
	CreateTimer(GetConVarFloat(cvar_RespawnTime), Timer_RespawnPlayer, client, TIMER_FLAG_NO_MAPCHANGE);

	// Obtains the attacker's userid and converts it to an index and store it within our attacker variable
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	// If the attacker does not meet our validation criteria then execute this section
	if(!IsValidClient(attacker))
	{
		return Plugin_Continue;
	}

	// If the attacker is the same as the victim (suicide) then execute this section or if the attacker is the world like for fall damage etc.
	if((attacker == client) | (attacker == 0))
	{
		return Plugin_Continue;
	}

	// If the game still hasn't ended then execute this section
	if(!gameHasEnded)
	{
		// If headshot bonus points are set to more than 1 then execute this section
		if(GetConVarInt(cvar_HeadshotScoreBonus) > 1)
		{
			// If the attack was a headshot then execute this section
			if(GetEventBool(event, "headshot"))
			{
				// Adds + 1 point to the value of the attacker's current kill score
				playerCurrentKills[attacker] += GetConVarInt(cvar_HeadshotScoreBonus);

				// Adds additional kills to the player's score
				SetEntProp(attacker, Prop_Data, "m_iFrags", playerCurrentKills[attacker]);

				// Sends a multi-language message to the client
				CPrintToChat(attacker, "%t", "Chat - Headshot Bonus", GetConVarInt(cvar_HeadshotScoreBonus) - 1);
			}

			// If the attack was not a headshot then execute this section
			else
			{
				// Adds + 1 point to the value of the attacker's current kill score
				playerCurrentKills[attacker]++;
			}
		}

		// If headshot bonus points are set to 1 or less then execute this section
		else
		{
			// Adds + 1 point to the value of the attacker's current kill score
			playerCurrentKills[attacker]++;
		}

		// If the attacker has acquired a maximum kill score required for the game to end then execute this section
		if(playerCurrentKills[attacker] >= GetConVarInt(cvar_MaximumKills))
		{
			// Ends the current round
			EndCurrentRound(attacker);
		}

		else
		{
			// Creates a variable which we will use to store our data within
			char hudMessage[1024];

			// Formats the message that we wish to send to the player and store it within our hudMessage variable
			Format(hudMessage, 1024, "\n<font color='#fbb227'>Score Tracker:</font>");
			Format(hudMessage, 1024, "%s\n<font color='#fbb227'>You have</font><font color='#5fd6f9'> %i</font><font color='#fbb227'> out of</font><font color='#5fd6f9'> %i</font><font color='#fbb227'> kill points!</font>", hudMessage, playerCurrentKills[attacker], GetConVarInt(cvar_MaximumKills));

			// Displays the contents of our hudMessage variable for the client to see in the hint text area of their screen 
			PrintHintText(attacker, hudMessage);
		}
	}

	// Creates a variable which we will use to store data within
	char attackerWeapon[64];

	// Obtains the name of the attacker's weapon and store it within the variable attackerWeapon
	GetEventString(event, "weapon", attackerWeapon, sizeof(attackerWeapon));

	// If the attackerWeapon contains the word "knife" then execute this section
	if(StrContains(attackerWeapon, "knife") == -1)
	{
		return Plugin_Continue;
	}

	// Changes the attacker's the ammunition and bullets in their clip
	ChangePlayerAmmo(attacker);

	return Plugin_Continue;
}


// This happens every time a player changes team (NOTE: This is required in order to make late-joining bots respawn)
public Action Event_PlayerTeam(Handle event, const char[] name, bool dontBroadcast)
{
	// Obtains the client's userid and converts it to an index and store it within our client variable
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	// If the client does not meet our validation criteria then execute this section
	if(!IsValidClient(client))
	{
		return Plugin_Continue;
	}

	// If the client is not a bot then execute this section
	if(!IsFakeClient(client))
	{
		return Plugin_Continue;
	}

	// If the client is alive then execute this section
	if(IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}

	// Obtains the team which the player changed to
	int team = GetEventInt(event, "team");

	// If the team is the observer or spectator team execute this section
	if(team <= 1)
	{
		return Plugin_Continue;
	}

	// Calls upon the Timer_RespawnPlayer function after (3.0 default) seconds
	CreateTimer(GetConVarFloat(cvar_RespawnTime), Timer_RespawnPlayer, client, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Continue;
}


// This happens when a new round starts
public void Event_RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	// If the value of cvar_RandomPistols is set to true then execute this section
	if(GetConVarBool(cvar_RandomPistols))
	{
		// Chooses a random weapon from a list of weapons that will be the one used during this round
		ChooseRandomWeapon();
	}

	// If the value of cvar_ObjectiveHostage is set to false then execute this section
	if(!GetConVarBool(cvar_ObjectiveHostage))
	{
		// Removes all of the hostages from the map
		RemoveEntityHostage();
	}
	
	// Loops through all of the clients
	for (int client = 1; client <= MaxClients; client++)
	{
		// If the client does not meet our validation criteria then execute this section
		if(!IsValidClient(client))
		{
			continue;
		}

		//Resets the player's scoreboard stats
		ResetPlayerScores(client);
	}
}


// This happens when a round ends
public void Event_RoundEnd(Handle event, const char[] name, bool dontBroadcast)
{
	// If the mp_round_restart_delay convar is higher than 0.0 then execute this section
	if(GetConVarFloat(FindConVar("mp_round_restart_delay")) > 0.0)
	{
		// Calls upon the Timer_RespawnPlayer function after (3.0 default) seconds
		CreateTimer(GetConVarFloat(FindConVar("mp_round_restart_delay")) - 0.10, Timer_ResetGameState, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		// Resets the game state back to not having ended
		ResetGameState();
	}

	GameRules_SetProp("m_totalRoundsPlayed", GameRules_GetProp("m_totalRoundsPlayed") + 1);

	// If the mp_maxrounds variable is the same as the current amount of rounds played
	if(GetConVarInt(FindConVar("mp_maxrounds")) != GameRules_GetProp("m_totalRoundsPlayed"))
	{
		return;
	}

	// Calls upon the Timer_StartEndingTheGame function to initiate the ending of the game
	CreateTimer(2.50, Timer_StartEndingTheGame, _, TIMER_FLAG_NO_MAPCHANGE);
}


// This happens when a player fires their weapon
public Action Event_WeaponFire(Handle event, const char[] name, bool dontBroadcast)
{
	// Obtains the client's userid and converts it to an index and store it within our client variable
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	// If the client does not meet our validation criteria then execute this section
	if(!IsValidClient(client))
	{
		return Plugin_Continue;
	}

	// If the player is not spawn protected then execute this section
	if(!isSpawnProtected[client])
	{
		return Plugin_Continue;
	}

	// Removes the spawn protection from the client
	RemoveSpawnProtection(client, 2);

	return Plugin_Continue;
}



///////////////////////////
// - Regular Functions - //
///////////////////////////


// This happens when the plugin is loaded
public void CreateModSpecificConvars()
{
	///////////////////////////////
	// - Configuration Convars - //
	///////////////////////////////

	cvar_RespawnTime = 					CreateConVar("OITC_RespawnTime", 					"3.00",	 	"How many seconds should it take before a player is respawned? - [Default = 3.00]");
	cvar_SpawnProtectionTime = 			CreateConVar("OITC_SpawnProtectionTime", 			"5.00",	 	"How many seconds should a player be protected for after spawning? (0.0 means disabled) - [Default = 5.00]");
	cvar_SpawnProtectionColoring =		CreateConVar("OITC_SpawnProtectionColoring", 		"1",	 	"Should players be colored green while spawn protected? - [Default = 1]");
	cvar_MaximumKills =					CreateConVar("OITC_MaximumKills", 					"50",	 	"How many kills should one player get in order to win the current round? - [Default = 50]");
	cvar_MaximumRounds =				CreateConVar("OITC_MaximumRounds", 					"3",	 	"How many rounds should be played before the map changes? - [Default = 3]");
	cvar_KnifeSpeedIncrease =			CreateConVar("OITC_KnifeSpeedIncrease", 			"40",	 	"How much increased speed, in percentages, should the player receive while using their knife? (0.0 means disabled) - [Default = 50]");
	cvar_BunnyHopping =					CreateConVar("OITC_BunnyHopping", 					"1",	 	"Should the server have bunny jumping settings enabled? - [Default = 1]");
	cvar_AutoBunnyHopping =				CreateConVar("OITC_AutoBunnyHopping", 				"0",	 	"Should players be able to automatically jump by holding down their jump key? - [Default = 0]");
	cvar_FallDamage =					CreateConVar("OITC_FallDamage", 					"1",	 	"Should players be able to take damage from falling? - [Default = 1]");
	cvar_MaximumVelocity =				CreateConVar("OITC_MaximumVelocity", 				"400",	 	"What is the maximum velocity a player should be able to achieve? - [Default = 400]");
	cvar_LeftClickKnifing =				CreateConVar("OITC_LeftClickKnifing", 				"0",	 	"Should players be able to use the left knife attack? - [Default = 0]");
	cvar_RandomPistols =				CreateConVar("OITC_RandomPistols", 					"0",	 	"Should the players be given a random pistol every new round? - [Default = 0]");
	cvar_OneHitKnifeAttacks =			CreateConVar("OITC_OneHitKnifeAttacks", 			"1",	 	"Should attacking an enemy with the knife always result in a guranteed kill? - [Default = 1]");
	cvar_NoSpreadAndRecoil =			CreateConVar("OITC_NoSpreadAndRecoil", 				"0",	 	"Should weapons have recoil and spread removed from them? - [Default = 0]");
	cvar_HeadshotScoreBonus =			CreateConVar("OITC_HeadshotScoreBonus", 			"1",	 	"How many points should the player receive for making a headshot? - [Default = 1]");
	cvar_FreeForAll = 					CreateConVar("OITC_FreeForAll", 					"1",	 	"Should the game mode be set to free-for-all mode? - [Default = 1]");
	cvar_FreeForAllModels = 			CreateConVar("OITC_FreeForAllModels", 				"1",	 	"Should all players have the same player model when the free-for-all mode is active? - [Default = 1]");
	cvar_ObjectiveBomb = 				CreateConVar("OITC_ObjectiveBomb", 					"0",	 	"Should the bomb and defusal game mode objectives be active? - [Default = 0]");
	cvar_ObjectiveHostage = 			CreateConVar("OITC_ObjectiveHostage", 				"0",	 	"Should the hostage and rescue game mode objectives be active? - [Default = 0]");

	// Automatically generates a config file that contains our variables
	AutoExecConfig(true, "oneinthechamber_convars", "sourcemod/one_in_the_chamber");
}


// This happens when a new map is loaded
public void ExecuteServerConfigurationFiles()
{
	// If the value of cvar_FreeForAll is set to true then execute this section
	if(GetConVarBool(cvar_FreeForAll))
	{
		// Executes the configuration file containing the modification specific configurations
		ServerCommand("exec sourcemod/one_in_the_chamber/freeforall_settings.cfg");
	}
	
	// If the cvar_FreeForAll is set to false then execute this section
	else
	{
		// Executes the configuration file containing the modification specific configurations
		ServerCommand("exec sourcemod/one_in_the_chamber/teamdeathmatch_settings.cfg");
	}

	// If the value of cvar_NoSpreadAndRecoil is set to true then execute this section
	if(GetConVarBool(cvar_NoSpreadAndRecoil))
	{
		// Executes the configuration file containing the modification specific configurations
		ServerCommand("exec sourcemod/one_in_the_chamber/nospreadandrecoil_settings.cfg");
	}
	
	// If the cvar_NoSpreadAndRecoil is set to false then execute this section
	else
	{
		// Executes the configuration file containing the modification specific configurations
		ServerCommand("exec sourcemod/one_in_the_chamber/spreadandrecoil_settings.cfg");
	}

	// If the value of cvar_SpawnProtectionColoring is set to true then execute this section
	if(GetConVarBool(cvar_BunnyHopping))
	{
		// Executes the configuration file containing the modification specific configurations
		ServerCommand("exec sourcemod/one_in_the_chamber/bunnyjump_settings.cfg");
	}

	// If the cvar_BunnyHopping is set to false then execute this section
	else
	{
		// Executes the configuration file containing the modification specific configurations
		ServerCommand("exec sourcemod/one_in_the_chamber/normaljump_settings.cfg");
	}

	// Executes the configuration file containing the modification specific configurations
	ServerCommand("exec sourcemod/one_in_the_chamber/oneinthechamber_settings.cfg");
}


// This happens when the plugin is loaded
public void LateLoadSupport()
{
	// Ends the round informing players about a new round soon starting
	EndCurrentRoundByReloading();

	// Changes this round's weapon to the specified one
	pistolClassName = "weapon_deagle";

	// If the value of cvar_RandomPistols is set to true then execute this section
	if(GetConVarBool(cvar_RandomPistols))
	{
		// Chooses a random weapon from a list of weapons that will be the one used during this round
		ChooseRandomWeapon();
	}

	// Precaches the contents that requires precaching
	PrecacheContents();

	// Loops through all of the clients
	for (int client = 1; client <= MaxClients; client++)
	{
		// If the client does not meet our validation criteria then execute this section
		if(!IsValidClient(client))
		{
			continue;
		}

		//Resets the player's scoreboard stats
		ResetPlayerScores(client);

		// Resets the value of the playerCurrentMVPs variable back to 0
		playerCurrentMVPs[client] = 0;

		// Resets the client's mvp awards back to zero
		CS_SetMVPCount(client, 0);

		// Adds a hook to the client which will let us track when the player switches weapon
		SDKHook(client, SDKHook_WeaponSwitchPost, Hook_OnWeaponSwitchPost);
	}
}


// This happens when the game mode is being loaded 
public void EndCurrentRoundByReloading()
{
	// If there are 0 or fewer clients in the game then execute this section
	if(GetClientCount() <= 0)
	{
		return;
	}

	// Changes the game state to having ended
	gameHasEnded = true;

	// Forcefully ends the round and considers it a round draw
	CS_TerminateRound(GetConVarFloat(FindConVar("mp_round_restart_delay")), CSRoundEnd_Draw);

	// Creates a variable which we will use to store our data within
	char hudMessage[1024];

	// Modifies the contents stored within the hudMessage variable
	Format(hudMessage, 1024, "\n<font color='#fbb227'>Loading:</font>");
	Format(hudMessage, 1024, "%s\n<font color='#fbb227'>A new round is</font><font color='#5fd6f9'> commencing soon</font><font color='#5fd6f9'>!</font>", hudMessage);

	// Loops through all of the clients
	for (int client = 1; client <= MaxClients; client++)
	{
		// If the client does not meet our validation criteria then execute this section
		if(!IsValidClient(client))
		{
			continue;
		}

		// Renders the player unable to move or perform any movement related actions
		SetEntityFlags(client, GetEntityFlags(client) | FL_FROZEN);

		// If the client is a bot then execute this section
		if(IsFakeClient(client))
		{
			continue;
		}

		// Displays the contents of our hudMessage variable for the client to see in the hint text area of their screen 
		PrintHintText(client, hudMessage);
	}
}


// This happens when the plugin is loaded, unloaded and when a new round starts
public void SendChatMessageToAll(const char[] chatMessage)
{
	// Loops through all of the clients
	for (int client = 1; client <= MaxClients; client++)
	{
		// If the client does not meet our validation criteria then execute this section
		if(!IsValidClient(client))
		{
			continue;
		}

		// If the client is a bot then execute this section
		if(IsFakeClient(client))
		{
			continue;
		}

		// Sends a multi-language message to the client
		CPrintToChat(client, "%t", chatMessage);
	}
}


// This happens when the plugin is loaded
public void ResetPlayerScores(int client)
{
	// Resets the value of the playerCurrentKills variable back to 0
	playerCurrentKills[client] = 0;

	// Resets the client's kills back to zero
	SetEntProp(client, Prop_Data, "m_iFrags", 0);

	// Resets the client's assists back to zero
	CS_SetClientAssists(client, 0);

	// Resets the client's deaths back to zero
	SetEntProp(client, Prop_Data, "m_iDeaths", 0);

	// Resets the client's contribution score back to zero
	CS_SetClientContributionScore(client, 0);
}


// This happens when the plugin is loaded
public void CalculateSpeedValues()
{
	// If the value of cvar_KnifeSpeedIncrease is 0 or below then execute this section
	if(GetConVarInt(cvar_KnifeSpeedIncrease) <= 0)
	{
		return;
	}

	// Calculates the base amount of speed that the player should receive
	knifeMovementSpeedBase = ((GetConVarFloat(cvar_KnifeSpeedIncrease) / 100) / 5) + 1.0;

	// Calculates the amount that the speed should gradually increment by and store it within our KnifeMovementSpeedIncrement variable
	KnifeMovementSpeedIncrement = ((GetConVarFloat(cvar_KnifeSpeedIncrease) / 100) / 10);
}


// This happens when a new map is loaded
public void SetAutoBunnyHopping()
{
	// Creates a variable to store our data within
	char autoBunnyHoppingString[128];

	// Converts the cvar_AutoBunnyHopping integer value to a string named autoBunnyHopping
	IntToString(GetConVarInt(cvar_AutoBunnyHopping), autoBunnyHoppingString, sizeof(autoBunnyHoppingString));
	
	// Changes the value of mp_maxrounds to that of our cvar_AutoBunnyHopping convar
	SetConVar("sv_autobunnyhopping", autoBunnyHoppingString);
}


// This happens when a new map is loaded
public void SetFallDamage()
{
	// Creates a variable to store our data within
	char valueString[128];

	// Converts the cvar_FallDamage integer value to a string named autoBunnyHopping
	IntToString(GetConVarInt(cvar_FallDamage), valueString, sizeof(valueString));
	
	// Changes the value of mp_maxrounds to that of our cvar_FallDamage convar
	SetConVar("sv_falldamage_scale", valueString);
}


// This happens when a new map is loaded
public void SetMaxRounds()
{
	// Creates a variable to store our data within
	char maxRoundsString[128];

	// Converts the cvar_MaximumRounds integer value to a string named maxRoundsString
	IntToString(GetConVarInt(cvar_MaximumRounds), maxRoundsString, sizeof(maxRoundsString));
	
	// Changes the value of mp_maxrounds to that of our cvar_MaximumRounds convar
	SetConVar("mp_maxrounds", maxRoundsString);
}


// This happens when a new map is loaded
public void SetMaxVelocity()
{
	// Creates a variable to store our data within
	char maxVelocityString[128];

	// Converts the cvar_MaximumVelocity integer value to a string named maxVelocityString
	IntToString(GetConVarInt(cvar_MaximumVelocity), maxVelocityString, sizeof(maxVelocityString));
	
	// Changes the value of mp_maxrounds to that of our cvar_MaximumVelocity convar
	SetConVar("sv_maxvelocity ", maxVelocityString);
}


// This happens when we wish to change a server variable convar
public void SetConVar(const char[] ConvarName, const char[] ConvarValue)
{
	// Finds an existing convar with the specified name and store it within the ServerVariable name 
	ConVar ServerVariable = FindConVar(ConvarName);

	// If the convar exists then execute this section
	if(ServerVariable != null)
	{
		// Changes the value of the convar to the value specified in the ConvarValue variable
		ServerVariable.SetString(ConvarValue, true);
	}
}


// This happens when a new round starts 
public void RemoveEntityBuyZones()
{
	// Creates a variable named entity with a value of -1
	int entity = -1;
	
	// Loops through all of the entities and tries to find any matching the specified criteria
	while ((entity = FindEntityByClassname(entity, "func_buyzone")) != -1)
	{
		// If the entity does not meet the criteria of validation then execute this section
		if(!IsValidEntity(entity))
		{
			continue;
		}

		// Kills the entity, removing it from the game
		AcceptEntityInput(entity, "Kill");
	}
}



// This happens when a new round starts 
public void RemoveEntityBombSites()
{
	// Creates a variable named entity with a value of -1
	int entity = -1;
	
	// Loops through all of the entities and tries to find any matching the specified criteria
	while ((entity = FindEntityByClassname(entity, "func_bomb_target")) != -1)
	{
		// If the entity does not meet the criteria of validation then execute this section
		if(!IsValidEntity(entity))
		{
			continue;
		}

		// Kills the entity, removing it from the game
		AcceptEntityInput(entity, "Kill");
	}
}


// This happens when a new map is loaded
public void RemoveEntityHostageRescuePoint()
{
	// Creates a variable named entity with a value of -1
	int entity = -1;

	// Loops through all of the entities and tries to find any matching the specified criteria
	while ((entity = FindEntityByClassname(entity, "func_hostage_rescue")) != -1)
	{
		// If the entity does not meet the criteria of validation then execute this section
		if(!IsValidEntity(entity))
		{
			continue;
		}

		// Kills the entity, removing it from the game
		AcceptEntityInput(entity, "Kill");
	}
}


// This happens when a new round starts
public void ChooseRandomWeapon()
{
	// Sets the weaponGivingFailSafe variable to false
	weaponGivingFailSafe = false;

	// Picks a random number between 1 and 10 and store it within our randomWeapon variable
	int randomWeapon = GetRandomInt(1, 10);

	// Creates a switch statement to manage outcomes depnding on the value of our variable
	switch(randomWeapon)
	{
		// If the randomWeapon variable is 1 then execute this section
		case 1:
		{
			// Changes this round's weapon to the specified one
			pistolClassName = "weapon_glock";
		}

		case 2:
		{
			// Changes this round's weapon to the specified one
			pistolClassName = "weapon_fiveseven";
		}

		case 3:
		{
			// Changes this round's weapon to the specified one
			pistolClassName = "weapon_tec9";
		}

		case 4:
		{
			// Changes this round's weapon to the specified one
			pistolClassName = "weapon_revolver";

			// Sets the weaponGivingFailSafe variable to false
			weaponGivingFailSafe = true;
		}

		case 5:
		{
			// Changes this round's weapon to the specified one
			pistolClassName = "weapon_deagle";
		}

		case 6:
		{
			// Changes this round's weapon to the specified one
			pistolClassName = "weapon_elite";
		}

		case 7:
		{
			// Changes this round's weapon to the specified one
			pistolClassName = "weapon_p250";
		}

		case 8:
		{
			// Changes this round's weapon to the specified one
			pistolClassName = "weapon_cz75a";

			// Sets the weaponGivingFailSafe variable to false
			weaponGivingFailSafe = true;
		}

		case 9:
		{
			// Changes this round's weapon to the specified one
			pistolClassName = "weapon_hkp2000";

			// Sets the weaponGivingFailSafe variable to false
			weaponGivingFailSafe = true;
		}

		case 10:
		{
			// Changes this round's weapon to the specified one
			pistolClassName = "weapon_usp_silencer";

			// Sets the weaponGivingFailSafe variable to false
			weaponGivingFailSafe = true;
		}
	}

	// Loops through all of the clients
	for (int client = 1; client <= MaxClients; client++)
	{
		// If the client does not meet our validation criteria then execute this section
		if(!IsValidClient(client))
		{
			continue;
		}

		// If the client is a bot then execute this section
		if(IsFakeClient(client))
		{
			continue;
		}

		// Sends a multi-language message to the client
		CPrintToChat(client, "%t", "Chat - Current Round Random Weapon", pistolClassName);
	}
}


// This happens when a round ends and is just about to transition to a new round
public void ResetGameState()
{
	// Resets the game state to not having ended
	gameHasEnded = false;
}


// This happens when all of the mp_maxrounds has been played to the end
public void PrepareLevelChange()
{
	if(GetConVarFloat(FindConVar("mp_endmatch_votenextleveltime")) >= 1.0)
	{
		// Calls upon the Timer_ChangeLevel function just prior to the expiration of mp_endmatch_votenextleveltime
		CreateTimer(GetConVarFloat(FindConVar("mp_endmatch_votenextleveltime")) - 0.25, Timer_ChangeLevel, _, TIMER_FLAG_NO_MAPCHANGE);

		return;
	}

	// Changes the map to a new map
	ChangeLevel();
}


// Changes the map to a new map
public void ChangeLevel()
{
	// Creates a variable to store our data within
	char nameOfMap[64];
	
	// Obtain the name of the next map and store it within our nameOfMap variable
	GetNextMap(nameOfMap, sizeof(nameOfMap));
	
	// Change the level to the one that is supposed to be the next map	
	ForceChangeLevel(nameOfMap, "One In The Chamber changed map after all the rounds has been played.");
}


// This happens 3.0 seconds after the modification is loaded
public void AddGameModeTags(const char[] newTag)
{
	// Creates a variable to store our data within
	char lineOfTags[128];

	// Obtains the contents of the sv_tags convar and store it within our variable
	GetConVarString(FindConVar("sv_tags"), lineOfTags, sizeof(lineOfTags));

	// If the sv_tags line already contains the contents of our newTag variable then execute this section
	if(StrContains(lineOfTags, newTag, false) != -1)
	{
		return;
	}

	// Formats the lineOfTags to add contents of newTag to the front of the sv_tags line
	Format(lineOfTags, sizeof(lineOfTags), "%s,%s", newTag, lineOfTags);

	// Changes the sv_tags line to now also include the contents contained within our newTag variable
	SetConVarString(FindConVar("sv_tags"), lineOfTags, true, false);
}


// This happens when a player spawns
public void IntroductionMenu(int client)
{
	// If the client's recently connected status is false then execute this section
	if(!isPlayerRecentlyConnected[client])
	{
		return;
	}

	// Sets the client's recently connected status false
	isPlayerRecentlyConnected[client] = false;

	// Creates a menu and connects it to a menu handler
	Menu introductionMenu = new Menu(introductionMenu_Handler);

	// Creates a variable which we will use to store our data within
	char menuMessage[1024];

	// Formats the message that we wish to send to the player and store it within our hudMessage variable
	Format(menuMessage, 1024, "One In The Chamber - How to play");
	Format(menuMessage, 1024, "%s\n-----------------------------------------", menuMessage);

	Format(menuMessage, 1024, "%s\nYour gun can only contain 1 bullet", menuMessage);
	Format(menuMessage, 1024, "%s\ngetting a kill refills the gun's clip.", menuMessage);

	// If the value of cvar_KnifeSpeedIncrease is above 0 then execute this section
	if(GetConVarInt(cvar_KnifeSpeedIncrease) > 0)
	{
		// If the value of cvar_OneHitKnifeAttacks is set to true then execute this section
		if(GetConVarBool(cvar_OneHitKnifeAttacks))
		{
			Format(menuMessage, 1024, "%s\nKnife attacks kill in one hit.", menuMessage);
			Format(menuMessage, 1024, "%s\nWielding a knife increases speed.", menuMessage);
		}

		// If the value of cvar_OneHitKnifeAttacks is set to true then execute this section
		else
		{
			Format(menuMessage, 1024, "%s\nWielding a knife increases speed.", menuMessage);
		}
	}

	// If the value of cvar_KnifeSpeedIncrease is 0 or below then execute this section
	else
	{
		// If the value of cvar_OneHitKnifeAttacks is set to true then execute this section
		if(GetConVarBool(cvar_OneHitKnifeAttacks))
		{
			Format(menuMessage, 1024, "%s\n  \nKnife attacks kill in one hit.", menuMessage);
		}
	}

	Format(menuMessage, 1024, "%s\n  \nWin the round by earning a total of", menuMessage);

	// If headshot bonus points are set to more than 1 then execute this section
	if(GetConVarInt(cvar_HeadshotScoreBonus) > 1)
	{
		Format(menuMessage, 1024, "%s\n%i points. A kill awards 1 point,", menuMessage, GetConVarInt(cvar_MaximumKills));
		Format(menuMessage, 1024, "%s\nand headshots award %i points.", menuMessage, GetConVarInt(cvar_HeadshotScoreBonus));
	}

	// If headshot bonus points are set to 0 or less then execute this section
	else
	{
		Format(menuMessage, 1024, "%s\n%i points. A kill awards 1 point.", menuMessage, GetConVarInt(cvar_MaximumKills));
	}

	// If the value of cvar_RandomPistols is set to true then execute this section
	if(GetConVarBool(cvar_RandomPistols))
	{
		Format(menuMessage, 1024, "%s\n  \nYou get a new pistol each round,", menuMessage, GetConVarInt(cvar_MaximumRounds));

		Format(menuMessage, 1024, "%s\nafter %i rounds the map changes.", menuMessage, GetConVarInt(cvar_MaximumRounds));

	}

	// If the value of cvar_RandomPistols is set to false then execute this section
	else
	{
		Format(menuMessage, 1024, "%s\n  \nAfter %i rounds the map changes.", menuMessage, GetConVarInt(cvar_MaximumRounds));
	}

	// If the value of cvar_FreeForAll is set to true then execute this section
	if(GetConVarBool(cvar_FreeForAll))
	{
		Format(menuMessage, 1024, "%s\nThe game is set to free for all.", menuMessage);
	}

	// Adds a title to our menu
	introductionMenu.SetTitle(menuMessage, "Introduction");

	// Adds an item to our menu
	introductionMenu.AddItem("Introduction", "I am ready to have fun!", ITEMDRAW_DEFAULT);

	// Disables the menu's exit option 
	introductionMenu.ExitButton = false;

	// Sends the menu with all of its contents to the client
	introductionMenu.Display(client, MENU_TIME_FOREVER);
}


// This happens when a player interacts with the introuction menu
public int introductionMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	return;
}


// This happens when a player spawns
public void GivePlayerSpawnProtection(int client)
{
	// If the value of cvar_SpawnProtectionTime is 0.0 or below then execute this section
	if(GetConVarFloat(cvar_SpawnProtectionTime) <= 0.0)
	{
		return;
	}

	// If the player is alive then proceed
	if(!IsPlayerAlive(client))
	{
		return;
	}

	// If the value of cvar_SpawnProtectionColoring is set to true then execute this section
	if(GetConVarBool(cvar_SpawnProtectionColoring))
	{
		// Changes the rendering mode of the client
		SetEntityRenderMode(client, RENDER_TRANSCOLOR);

		// Changes the client's color to purple
		SetEntityRenderColor(client, 35, 236, 0, 255);
	}

	// Renders the client invulnerable
	SetEntProp(client, Prop_Data, "m_takedamage", 0, 1);

	// Changes the client's isSpawnProtected status to be true
	isSpawnProtected[client] = true;

	// Adds + 1 to the client's playerSpawnCounter variable
	playerSpawnCounter[client]++;

	// Creates a datapack called pack which we will store our data within 
	DataPack pack = new DataPack();

	// Stores the client's index within our datapack
	pack.WriteCell(client);

	// Stores the playerSpawnCounter variable within our datapack
	pack.WriteCell(playerSpawnCounter[client]);

	// Calls upon the Timer_RemoveSpawnProtection function after (5.0 default) seconds
	CreateTimer(GetConVarFloat(cvar_SpawnProtectionTime), Timer_RemoveSpawnProtection, pack, TIMER_FLAG_NO_MAPCHANGE);
}


// We call upon this function in multiple cases for turning off the player's spawn protection
public void RemoveSpawnProtection(int client, int disableReason)
{
	// If the player is not spawn protected then execute this section
	if(!isSpawnProtected[client])
	{
		return;
	}

	// If the value of cvar_SpawnProtectionColoring is set to true then execute this section
	if(GetConVarBool(cvar_SpawnProtectionColoring))
	{
		// Changes the player's color to the default color
		SetEntityRenderColor(client, 255, 255, 255, 255);
	}

	// Renders the player vulnerable
	SetEntProp(client, Prop_Data, "m_takedamage", 2, 1);

	// Changes the client's isSpawnProtected status to be true
	isSpawnProtected[client] = false;

	// If the client is not a bot then execute this section
	if(IsFakeClient(client))
	{
		return;
	}

	// Creates a variable which we will use to store our data within
	char hudMessage[1024];

	// Formats the message that we wish to send to the player and store it within our hudMessage variable
	Format(hudMessage, 1024, "\n<font color='#fbb227'>Spawn Protection:</font>");

	// If the disableReason is 1 then execute this section
	if(disableReason == 1)
	{
		Format(hudMessage, 1024, "%s\n<font color='#fbb227'>Your protection time has</font><font color='#5fd6f9'> expired</font><font color='#fbb227'>!</font>", hudMessage);
	}

	// If the disableReason is 1 then execute this section
	else if(disableReason == 2)
	{
		Format(hudMessage, 1024, "%s\n<font color='#fbb227'>Your protection was</font><font color='#5fd6f9'> turned off</font><font color='#fbb227'> early for attacking!</font>", hudMessage);
	}

	// Displays the contents of our hudMessage variable for the client to see in the hint text area of their screen 
	PrintHintText(client, hudMessage);
}


// This happens when a player spawns
public void SetPlayerModels(int client)
{
	// If the value of cvar_FreeForAll is set to false then execute this section
	if(!GetConVarBool(cvar_FreeForAll))
	{
		return;
	}
	
	// If the value of cvar_FreeForAllModels is set to false then execute this section
	if(!GetConVarBool(cvar_FreeForAllModels))
	{
		return;
	}
	
	// if the model is not precached already then execute this section
	if(!IsModelPrecached("models/player/custom_player/legacy/tm_jumpsuit_variantb.mdl"))
	{	
		// Precaches the specified model
		PrecacheModel("models/player/custom_player/legacy/tm_jumpsuit_variantb.mdl", true);
	}
	
	// if the model is not precached already then execute this section
	if(!IsModelPrecached("models/weapons/v_models/arms/jumpsuit/v_sleeve_jumpsuit.mdl"))
	{	
		// Precaches the specified model
		PrecacheModel("models/weapons/v_models/arms/jumpsuit/v_sleeve_jumpsuit.mdl", true);
	}

	// Changes the client's model to the specified model
	SetEntityModel(client, "models/player/custom_player/legacy/tm_jumpsuit_variantb.mdl");

	// Changes the client's arm model to the specified model
	SetEntPropString(client, Prop_Send, "m_szArmsModel", "models/weapons/v_models/arms/jumpsuit/v_sleeve_jumpsuit.mdl");
}


// This happens when a player wins the round and when the player spawns
public void SetPlayerMVPs(int client)
{
	// Sets the player's MVP count to that of the playerCurrentMVPs[client] variable
	CS_SetMVPCount(client, playerCurrentMVPs[client]);	
}


// This happens when the player stops holding a knife
public void ResetPlayerSpeed(int client)
{
	// Resets the player's stack counter back to 0
	knifeMovementSpeedCounter[client] = 0;

	// Changes the movement speed of the player back to the default movement speed
	SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.0);
}


// This happens when a player spawns
public void RemoveAllWeapons(int client)
{
	for(int loop3 = 0; loop3 < 4; loop3++)
	{
		for(int WeaponNumber = 0; WeaponNumber < 24; WeaponNumber++)
		{
			int WeaponSlotNumber = GetPlayerWeaponSlot(client, WeaponNumber);

			if(WeaponSlotNumber == -1)
			{
				continue;
			}

			if(!IsValidEdict(WeaponSlotNumber) || !IsValidEntity(WeaponSlotNumber))
			{
				continue;
			}

			RemovePlayerItem(client, WeaponSlotNumber);

			AcceptEntityInput(WeaponSlotNumber, "Kill");
		}
	}
}


// This happens when a player spawns
public void GiveKnife(int client)
{
	// Gives the client the specified weapon
	GivePlayerItem(client, "weapon_knife");
}


// This happens when a player spawns
public void GivePistol(int client)
{
	// If the weaponGivingFailSafe variable is set to true then execute this section
	if(weaponGivingFailSafe)
	{
		// Gives the client the specified weapon
		GivePlayerWeaponEntity(client);

		return;
	}

	// Gives the client the specified weapon
	GivePlayerItem(client, pistolClassName);
}


// This happens when a player spawns
public void GivePlayerWeaponEntity(int client)
{
	// Creates a healthshot and store it's index within our entity variable
	int entity = CreateEntityByName(pistolClassName);

	// If the entity does not meet our criteria validation then execute this section
	if(!IsValidEntity(entity))
	{
		return;
	}

	// Creates a variable to store our data within
	float playerLocation[3];

	// Obtains the client's location and store it within the playerLocation variable
	GetEntPropVector(client, Prop_Data, "m_vecOrigin", playerLocation);

	// Spawns the entity
	DispatchSpawn(entity);

	// Teleports the entity to the player's location
	TeleportEntity(entity, playerLocation, NULL_VECTOR, NULL_VECTOR);
}


// This happens 0.1 second after a player spawns
public void ChangePlayerAmmo(int client)
{
	int entity = GetPlayerWeaponSlot(client, 1);

	// If the entity does not meet the criteria of validation then execute this section
	if(!IsValidEntity(entity))
	{
		return;
	}

	// Creates a variable which we will use to store data within
	char className[64];

	// Obtains the entity's class name and store it within our className variable
	GetEntityClassname(entity, className, sizeof(className));

	// If the pistolClassName variable is weapon_cz75a then execute this section
	if(StrEqual(pistolClassName, "weapon_cz75a", false))
	{
		// If the weapon's entity name is that of the specified pistols's then execute this section
		if(StrEqual(className, "weapon_p250", false))
		{
			// Changes the amount of ammo in the player's pistol clip
			SetEntProp(entity, Prop_Send, "m_iClip1", 1);

			// Changes the amount of spare ammot the player have for their pistol 
			SetEntProp(entity, Prop_Send, "m_iPrimaryReserveAmmoCount", 0);

			return;
		}
	}

	// If the pistolClassName variable is weapon_usp_silencer then execute this section
	else if(StrEqual(pistolClassName, "weapon_usp_silencer", false))
	{
		// If the weapon's entity name is that of the specified pistols's then execute this section
		if(StrEqual(className, "weapon_hkp2000", false))
		{
			// Changes the amount of ammo in the player's pistol clip
			SetEntProp(entity, Prop_Send, "m_iClip1", 1);

			// Changes the amount of spare ammot the player have for their pistol 
			SetEntProp(entity, Prop_Send, "m_iPrimaryReserveAmmoCount", 0);

			return;
		}
	}

	// If the pistolClassName variable is weapon_revolver then execute this section
	else if(StrEqual(pistolClassName, "weapon_revolver", false))
	{
		// If the weapon's entity name is that of the specified pistols's then execute this section
		if(StrEqual(className, "weapon_deagle", false))
		{
			// Changes the amount of ammo in the player's pistol clip
			SetEntProp(entity, Prop_Send, "m_iClip1", 1);

			// Changes the amount of spare ammot the player have for their pistol 
			SetEntProp(entity, Prop_Send, "m_iPrimaryReserveAmmoCount", 0);

			return;
		}
	}

	// If the weapon's entity name is that of a pistols then execute this section
	if(!StrEqual(className, pistolClassName, false))
	{
		return;
	}

	// Changes the amount of ammo in the player's pistol clip
	SetEntProp(entity, Prop_Send, "m_iClip1", 1);

	// Changes the amount of spare ammot the player have for their pistol 
	SetEntProp(entity, Prop_Send, "m_iPrimaryReserveAmmoCount", 0);
}


// This happens when a player dies and a player reaches the maximum amount of kills required in order to win the round 
public void EndCurrentRound(int attacker)
{
	// Changes the game state to having ended
	gameHasEnded = true;

	// Adds + 1 point to the value of the attacker's current kill score
	playerCurrentMVPs[attacker]++;
	
	// Sets the player's MVP count to that of the playerCurrentMVPs[attacker] variable
	SetPlayerMVPs(attacker);

	// If the value of cvar_FreeForAll is set to true then execute this section
	if(GetConVarBool(cvar_FreeForAll))
	{
		// Forcefully ends the round and considers it a round draw
		CS_TerminateRound(GetConVarFloat(FindConVar("mp_round_restart_delay")), CSRoundEnd_Draw);
	}

	// If the cvar_FreeForAll is set to false then execute this section
	else
	{
		// If the client is on the terrorist team then execute this section
		if(GetClientTeam(attacker) == 2)
		{
			// Forcefully ends the round and considers it a win for the terrorist team
			CS_TerminateRound(GetConVarFloat(FindConVar("mp_round_restart_delay")), CSRoundEnd_TerroristWin);
		}

		// If the client is on the counter-terrorist team then execute this section
		else if(GetClientTeam(attacker) == 3)
		{
			// Forcefully ends the round and considers it a win for the counter-terrorist team
			CS_TerminateRound(GetConVarFloat(FindConVar("mp_round_restart_delay")), CSRoundEnd_CTWin);
		}
	}

	// Creates a variable which we will use to store data within
	char attackerName[64];

	// Obtains the name of attacker and store it within the attackerName variable
	GetClientName(attacker, attackerName, sizeof(attackerName));

	// Creates a variable which we will use to store our data within
	char hudMessage[1024];

	// Modifies the contents stored within the hudMessage variable
	Format(hudMessage, 1024, "\n<font color='#fbb227'>Winner Announcer:</font>");
	Format(hudMessage, 1024, "%s\n<font color='#5fd6f9'>%s</font><font color='#fbb227'> reached</font><font color='#5fd6f9'> %i</font><font color='#fbb227'> kills and won the round!</font>", hudMessage, attackerName, GetConVarInt(cvar_MaximumKills));

	// Loops through all of the clients
	for (int client = 1; client <= MaxClients; client++)
	{
		// If the client does not meet our validation criteria then execute this section
		if(!IsValidClient(client))
		{
			continue;
		}

		// Renders the player unable to move or perform any movement related actions
		SetEntityFlags(client, GetEntityFlags(client) | FL_FROZEN);

		// If the client is a bot then execute this section
		if(IsFakeClient(client))
		{
			continue;
		}

		// Displays the contents of our hudMessage variable for the client to see in the hint text area of their screen 
		PrintHintText(client, hudMessage);
	}
}


// This happens when a new round starts 
public void RemoveEntityHostage()
{
	// Creates a variable named entity with a value of -1
	int entity = -1;

	// Loops through all of the entities and tries to find any matching the specified criteria
	while ((entity = FindEntityByClassname(entity, "hostage_entity")) != -1)
	{
		// If the entity does not meet the criteria of validation then execute this section
		if(!IsValidEntity(entity))
		{
			continue;
		}

		// Kills the entity, removing it from the game
		AcceptEntityInput(entity, "Kill");
	}

	// Changes the value of the entity variable to -1
	entity = -1;

	// Loops through all of the entities and tries to find any matching the specified criteria
	while ((entity = FindEntityByClassname(entity, "info_hostage_spawn")) != -1)
	{
		// If the entity does not meet the criteria of validation then execute this section
		if(!IsValidEntity(entity))
		{
			continue;
		}

		// Kills the entity, removing it from the game
		AcceptEntityInput(entity, "Kill");
	}
}


// This happens when a new map starts and when the plugin is loaded
public void PrecacheContents()
{
	// Precaches the player and arms models
	PrecacheModel("models/player/custom_player/legacy/tm_jumpsuit_variantb.mdl", true);
	PrecacheModel("models/weapons/v_models/arms/jumpsuit/v_sleeve_jumpsuit.mdl", true);
}



///////////////////////////////
// - Timer Based Functions - //
///////////////////////////////


// This happens every 1.0 seconds and is used to remove items and weapons lying around in the map
public Action Timer_CleanFloor(Handle timer)
{
	// Loops through all entities that are currently in the game
	for (int entity = MaxClients + 1; entity <= GetMaxEntities(); entity++)
	{
		// If the entity does not meet our criteria of validation then execute this section
		if(!IsValidEntity(entity))
		{
			continue;
		}

		// Creates a variable which we will use to store data within
		char className[64];

		// Obtains the entity's class name and store it within our className variable
		GetEntityClassname(entity, className, sizeof(className));

		// If the className contains neither weapon_ nor item_ then execute this section
		if((StrContains(className, "weapon_") == -1 && StrContains(className, "item_") == -1))
		{
			continue;
		}

		// If the entity has an ownership relation then execute this section
		if(GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity") != -1)
		{
			continue;
		}

		// Removes the entity from the map 
		AcceptEntityInput(entity, "Kill");
	}

	return Plugin_Continue;
}


// This happens 3 seconds after the plugin is loaded
public Action Timer_AddSvTags(Handle timer) 
{
	// Adds the specified words to the server's sv_tags line
	AddGameModeTags("One In The Chamber");

	return Plugin_Continue;
}


// This function is called upon by our timer
public Action Timer_RemoveSpawnProtection(Handle timer, DataPack dataPackage)
{
	dataPackage.Reset();

	// Obtains client index stored within our data pack and store it within the client variable
	int client = dataPackage.ReadCell();

	// Obtains the value of playerWeaponSwapCounter[client] stored within our data pack and store it within the localSpawnCount variable
	int localSpawnCount = dataPackage.ReadCell();

	// Deletes our data package now that we have acquired the information we needed from it
	delete dataPackage;
	
	// If the client does not meet our validation criteria then execute this section
	if(!IsValidClient(client))
	{
		return Plugin_Stop;
	}
	
	// If the player is alive then proceed
	if(!IsPlayerAlive(client))
	{
		return Plugin_Stop;
	}

	// If the value of localSpawnCount is not the same as the value of the client's playerSpawnCounter then execute this section
	if(localSpawnCount != playerSpawnCounter[client])
	{
		return Plugin_Stop;
	}

	// Removes the spawn protection from the client
	RemoveSpawnProtection(client, 1);

	return Plugin_Stop;
}


// This function is called upon briefly after a player changes team or dies
public Action Timer_GivePistol(Handle timer, int client)
{
	// If the client does not meet our validation criteria then execute this section
	if(!IsValidClient(client))
	{
		return Plugin_Continue;
	}

	// If the client is on the spectator or observer team then execute this section
	if(GetClientTeam(client) <= 1)
	{
		return Plugin_Continue;
	}

	// If the client is not alive then execute this section
	if(!IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}

	// Gives the client a pistol
	GivePistol(client);

	return Plugin_Continue;
}



// This function is called upon briefly after a player changes team or dies
public Action Timer_GiveAmmo(Handle timer, int client)
{
	// If the client does not meet our validation criteria then execute this section
	if(!IsValidClient(client))
	{
		return Plugin_Continue;
	}

	// If the client is on the spectator or observer team then execute this section
	if(GetClientTeam(client) <= 1)
	{
		return Plugin_Continue;
	}

	// If the client is not alive then execute this section
	if(!IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}

	// Changes the player's the ammunition and bullets in the clip
	ChangePlayerAmmo(client);

	return Plugin_Continue;
}


// This function is called upon briefly after a player changes team or dies
public Action Timer_RespawnPlayer(Handle timer, int client)
{
	// If the client does not meet our validation criteria then execute this section
	if(!IsValidClient(client))
	{
		return Plugin_Continue;
	}

	// If the client is on the spectator or observer team then execute this section
	if(GetClientTeam(client) <= 1)
	{
		return Plugin_Continue;
	}

	// If the client is alive then execute this section
	if(IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}

	// Respawns the player
	CS_RespawnPlayer(client);

	return Plugin_Continue;
}


// This function is called upon briefly after a player changes team or dies
public Action Timer_ResetGameState(Handle timer)
{
	// Resets the game state back to not having ended
	ResetGameState();

	return Plugin_Continue;
}


// This function is called upon when the last round on a map has been played
public Action Timer_StartEndingTheGame(Handle timer)
{
	// Creates a variable called entityCounter which we will use to count the game_end entities
	int entityCounter = 0;

	// Creates a variable named entity with a value of -1
	int entity = -1;

	// Loops through all of the entities and tries to find any matching the specified criteria
	while ((entity = FindEntityByClassname(entity, "game_end")) != -1)
	{
		// If the entity does not meet the criteria of validation then execute this section
		if(!IsValidEntity(entity))
		{
			continue;
		}

		// Adds +1 to the value of our entityCounter variable
		entityCounter++;

		// Ends the current map
		AcceptEntityInput(entity, "EndGame");

		// Prepares to change the map to a new one
		PrepareLevelChange();
	}

	// If our entityCounter is not 0 then execute this section
	if(entityCounter != 0)
	{
		return Plugin_Continue;
	}

	// Creates a game_end entity and store it within our entityGameEnd variable
	int entityGameEnd = CreateEntityByName("game_end");

	// If the entity does not meet the criteria of validation then execute this section
	if(!IsValidEntity(entityGameEnd))
	{
		return Plugin_Continue;
	}

	// Ends the current map
	AcceptEntityInput(entityGameEnd, "EndGame");

	// Prepares to change the map to a new one
	PrepareLevelChange();

	return Plugin_Continue;
}


// This function is called upon shortly prior to the game changing to a new map
public Action Timer_ChangeLevel(Handle timer)
{
	// Changes the map to a new map
	ChangeLevel();

	return Plugin_Continue;
}



////////////////////////////////
// - Return Based Functions - //
////////////////////////////////


// Returns true if the client meets the validation criteria. elsewise returns false
public bool IsValidClient(int client)
{
	if (!(1 <= client <= MaxClients) || !IsClientConnected(client) || !IsClientInGame(client) || IsClientSourceTV(client) || IsClientReplay(client))
	{
		return false;
	}

	return true;
}


// Returns true if the entity is a knife elsewise it returns false
public bool IsWeaponKnife(int entity)
{
	// Creates a variable called ClassName which we will store the weapon entity's name within
	char className[64];

	// Obtains the classname of the weapon entity and store it within our ClassName variable
	GetEntityClassname(entity, className, sizeof(className));

	// If the weapon entity is not a knife then execute this section
	if(!StrEqual(className, "weapon_knife", false))
	{
		return false;
	}

	return true;
}



////////////////////////////////////
// - Functions By Other Authors - //
////////////////////////////////////


/*	Thanks to Phoenix (˙·٠●Феникс●٠·˙) and Franc1sco franug 
	for their Fix Hint Color Message plugin release. The code
	below is practically identical to their release, and was
	included in this plugin simply to make the life easier for
	the users of the game mode. The original plugin can be
	found as a stand alone at the link below:
	- https://github.com/Franc1sco/FixHintColorMessages 	*/

UserMsg g_TextMsg;
UserMsg g_HintText;
UserMsg g_KeyHintText;

public void AllowHtmlHintMessages()
{
	g_TextMsg = GetUserMessageId("TextMsg");
	g_KeyHintText = GetUserMessageId("KeyHintText");
	g_HintText = GetUserMessageId("HintText");
	
	HookUserMessage(g_KeyHintText, HintTextHook, true);
	HookUserMessage(g_HintText, HintTextHook, true);
}


public Action HintTextHook(UserMsg msg_id, Protobuf msg, const int[] players, int playersNum, bool reliable, bool init)
{
	char szBuf[2048];
	
	if(msg_id == g_KeyHintText)
	{
		msg.ReadString("hints", szBuf, sizeof szBuf, 0);
	}
	else
	{
		msg.ReadString("text", szBuf, sizeof szBuf);
	}
	
	if(StrContains(szBuf, "</") != -1)
	{
		DataPack hPack = new DataPack();
		
		hPack.WriteCell(playersNum);
		
		for(int i = 0; i < playersNum; i++)
		{
			hPack.WriteCell(players[i]);
		}
		
		hPack.WriteString(szBuf);
		
		hPack.Reset();
		
		RequestFrame(HintTextFix, hPack);
		
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}


public void HintTextFix(DataPack hPack)
{
	int iCountNew = 0, iCountOld = hPack.ReadCell();
	
	int iPlayers[MAXPLAYERS+1];
	
	for(int i = 0, iPlayer; i < iCountOld; i++)
	{
		iPlayer = hPack.ReadCell();
		
		if(IsClientInGame(iPlayer))
		{
			iPlayers[iCountNew++] = iPlayer;
		}
	}
	
	if(iCountNew != 0)
	{
		char szBuf[2048];
		
		hPack.ReadString(szBuf, sizeof szBuf);
		
		Protobuf hMessage = view_as<Protobuf>(StartMessageEx(g_TextMsg, iPlayers, iCountNew, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS));
		
		if(hMessage)
		{
			hMessage.SetInt("msg_dst", 4);
			hMessage.AddString("params", "#SFUI_ContractKillStart");
			
			Format(szBuf, sizeof szBuf, "</font>%s<script>", szBuf);
			hMessage.AddString("params", szBuf);
			
			hMessage.AddString("params", NULL_STRING);
			hMessage.AddString("params", NULL_STRING);
			hMessage.AddString("params", NULL_STRING);
			
			EndMessage();
		}
	}
	
	hPack.Close();
}


/*	Thanks to MaZa for sharing his fix which removes the
	dollar sign that would appear in the HUD messages.
	The two resource files below are identical to those that
	are found in his plugin, and the original plugin can be
	found as a stand alone at the link below:
	- https://github.com/xMaZax/fix_hint_dollar 	*/

public void FixDollarSign()
{
	AddFileToDownloadsTable("resource/closecaption_english.txt");
	AddFileToDownloadsTable("resource/closecaption_russian.txt");
}