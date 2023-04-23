// List of Includes
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>

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
ConVar cvar_ObjectiveBomb;
ConVar cvar_ObjectiveHostage;



//////////////////////////
// - Global Variables - //
//////////////////////////



//////////////////////////
// - Forwards & Hooks - //
//////////////////////////


// This happens when the plugin is loaded
public void OnPluginStart()
{
	// Creates the names and assigns values to the ConVars the modification will be using 
	CreateModSpecificConvars();

	// Hooks the events that we intend to use in our plugin
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	HookEvent("round_start", Event_RoundStart, EventHookMode_Post);

	// Calls upon our CommandListenerJoinTeam function whenever a player changes team
	AddCommandListener(CommandListenerJoinTeam, "jointeam");

	// Removes any unowned weapon and item entities from the map every second
	CreateTimer(1.0, Timer_CleanFloor, _, TIMER_REPEAT);

	// Allows the modification to be loaded while the server is running, without causing gameplay issues
	LateLoadSupport();
}


// This happens when a new map is loaded
public void OnMapStart()
{
	// Removes all of the buy zones from the map
	RemoveEntityBuyZones();

	// If the cvar_ObjectiveBomb is set to 0 then execute this section
	if(!cvar_ObjectiveBomb)
	{
		// Removes all of the bomb sites from the map
		RemoveEntityBombSites();
	}

	// If the cvar_ObjectiveHostage is set to 0 then execute this section
	if(!cvar_ObjectiveHostage)
	{
		// Removes Hostage Rescue Points from the map
		RemoveEntityHostageRescuePoint();
	}
}


// This happens once all post authorizations have been performed and the client is fully in-game
public void OnClientPostAdminCheck(int client)
{
	// If the client does not meet our validation criteria then execute this section
	if(!IsValidClient(client))
	{
		return;
	}

	// Adds a hook to the client which will let us track when the player is eligible to pick up a weapon
	SDKHook(client, SDKHook_WeaponCanUse, Hook_WeaponCanUse);
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

	// If the weapon's entity name is that of a decoy grenade's then execute this section
	if(StrEqual(className, "weapon_deagle", false) | StrEqual(className, "weapon_knife", false))
	{
		return Plugin_Continue;
	}

	PrintToChatAll("Debug - %s is restricted", className);

	// Kills the weapon entity, removing it from the game
	AcceptEntityInput(weapon, "Kill");

	return Plugin_Handled;
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

	// Removes all the weapons from the client
	RemoveAllWeapons(client);
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
	// If the cvar_ObjectiveHostage is set to 0 then execute this section
	if(!cvar_ObjectiveHostage)
	{
		// Removes all of the hostages from the map
		RemoveEntityHostage();
	}
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
	cvar_ObjectiveBomb = 				CreateConVar("OITC_ObjectiveBomb", 					"0",	 	"Should the bomb and defusal game mode objectives be active? - [Default = 0]");
	cvar_ObjectiveHostage = 			CreateConVar("OITC_ObjectiveHostage", 				"0",	 	"Should the hostage and rescue game mode objectives be active? - [Default = 0]");

	// Automatically generates a config file that contains our variables
	AutoExecConfig(true, "oneinthechamber_convars", "sourcemod/OneInTheChamber");
}


// This happens when the plugin is loaded
public void LateLoadSupport()
{
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

		PrintToChatAll("Debug - A Buyzone has been removed from the map :%i", entity);
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

		PrintToChatAll("Debug - A Bomb Target has been removed from the map :%i", entity);
	}
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

		PrintToChatAll("Debug - A Hostage has been removed from the map :%i", entity);
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

		PrintToChatAll("Debug - A Hostage Spawn has been removed from the map :%i", entity);
	}
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

