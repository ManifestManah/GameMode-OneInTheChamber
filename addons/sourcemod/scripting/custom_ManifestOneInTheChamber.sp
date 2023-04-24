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

ConVar cvar_AutoRespawn;
ConVar cvar_RespawnTime;
ConVar cvar_MaximumKills;
ConVar cvar_MaximumKRounds;
ConVar cvar_KnifeSpeed;
ConVar cvar_KnifeSpeedIncrease;
ConVar cvar_LeftClickKnifing;
ConVar cvar_OneHitKnifeAttacks;
ConVar cvar_ObjectiveBomb;
ConVar cvar_ObjectiveHostage;



//////////////////////////
// - Global Variables - //
//////////////////////////

// Global Booleans
bool gameHasEnded = false;

// Global Integers
int playerCurrentKills[MAXPLAYERS + 1] = {0, ...};
int knifeMovementSpeedCounter[MAXPLAYERS + 1] = {0, ...};
int playerWeaponSwapCounter[MAXPLAYERS + 1] = {0, ...};

// Global Floats
float knifeMovementSpeedBase = 1.0;
float KnifeMovementSpeedIncrement = 0.0;



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
}


// This happens when a new map is loaded
public void OnMapStart()
{
	// Changes the state of whether the game has ended already to false
	gameHasEnded = false;

	// Sets the maximum amount of rounds that should be played
	SetMaxRounds();

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

	// If the weapon's entity name is that of a pistols's or knife then execute this section
	if(StrEqual(className, "weapon_deagle", false) | StrEqual(className, "weapon_knife", false))
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

	// If the victim and attacker is on the same team
	if(GetClientTeam(client) == GetClientTeam(attacker))
	{
		return Plugin_Continue;
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
	if(StrEqual(className, "weapon_deagle", false))
	{
		// Changes the amount of damage to zero
		damage = 500.0;

		// Calls upon the Timer_RespawnPlayer function after (3.0 default) seconds
		CreateTimer(0.0, Timer_GiveAmmo, attacker, TIMER_FLAG_NO_MAPCHANGE);

		return Plugin_Changed;
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
	// If the cvar_KnifeSpeed convar returns false then execute this section
	if(!GetConVarBool(cvar_KnifeSpeed))
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
	// If the cvar_AutoRespawn is set to 0 then execute this section
	if(!cvar_AutoRespawn)
	{
		return Plugin_Continue;
	}

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
	if(buttons & IN_ATTACK)
	{
		// If the client is a bot then execute this section
		if(IsFakeClient(client))
		{
			return Plugin_Continue;
		}

		// Creates a variable which we will use to store our data within
		char hudMessage[1024];

		// Formats the message that we wish to send to the player and store it within our message_string variable
		Format(hudMessage, 1024, "\n<font color='#e30000'>Restriction:</font>");
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

	// Resets the player's speed and speed related variables
	ResetPlayerSpeed(client);

	// Removes all the weapons from the client
	RemoveAllWeapons(client);

	// Gives the client a knife
	GiveKnife(client);

	// Gives the client a pistol
	GivePistol(client);

	// Calls upon the Timer_RespawnPlayer function after (3.0 default) seconds
	CreateTimer(0.1, Timer_GiveAmmo, client, TIMER_FLAG_NO_MAPCHANGE);
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

	// If the cvar_AutoRespawn is set to 1 then execute this section
	if(cvar_AutoRespawn)
	{
		// Calls upon the Timer_RespawnPlayer function after (3.0 default) seconds
		CreateTimer(GetConVarFloat(cvar_RespawnTime), Timer_RespawnPlayer, client, TIMER_FLAG_NO_MAPCHANGE);
	}

	// Obtains the attacker's userid and converts it to an index and store it within our attacker variable
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	// If the attacker does not meet our validation criteria then execute this section
	if(!IsValidClient(attacker))
	{
		return Plugin_Continue;
	}

	// If the game still hasn't ended then execute this section
	if(!gameHasEnded)
	{
		// Adds + 1 point to the value of the attacker's current kill score
		playerCurrentKills[attacker]++;

		// If the attacker has acquired a maximum kill score required for the game to end then execute this section
		if(playerCurrentKills[attacker] >= GetConVarInt(cvar_MaximumKills))
		{
			// Ends the current round
			EndCurrentRound(attacker);
		}

		else
		{
			PrintToChat(attacker,"You have %i out of %i kills", playerCurrentKills[attacker], GetConVarInt(cvar_MaximumKills));
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
	// If the cvar_AutoRespawn is set to 0 then execute this section
	if(!cvar_AutoRespawn)
	{
		return Plugin_Continue;
	}

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
// - Regular Functions - //4
///////////////////////////


// This happens when the plugin is loaded
public void CreateModSpecificConvars()
{
	///////////////////////////////
	// - Configuration Convars - //
	///////////////////////////////

	cvar_AutoRespawn =					CreateConVar("OITC_AutoRespawn", 					"1",	 	"Should players be respawned after they die? - [Default = 1]");
	cvar_RespawnTime = 					CreateConVar("OITC_RespawnTime", 					"3.00",	 	"How many seconds should it take before a player is respawned? - [Default = 3.00]");
	cvar_MaximumKills =					CreateConVar("OITC_MaximumKills", 					"50",	 	"How many kills should one player get in order to win the current round? - [Default = 50]");
	cvar_MaximumKRounds =				CreateConVar("OITC_MaximumRounds", 					"3",	 	"How many rounds should be played before the map changes? - [Default = 3]");
	cvar_KnifeSpeed =					CreateConVar("OITC_KnifeSpeed", 					"1",	 	"Should players' speed be increased while using their knife? - [Default = 0]");
	cvar_KnifeSpeedIncrease =			CreateConVar("OITC_KnifeSpeedIncrease", 			"40",	 	"How much increased speed, in percentages, should the player receive while using their knife? - [Default = 50]");
	cvar_LeftClickKnifing =				CreateConVar("OITC_LeftClickKnifing", 				"0",	 	"Should players be able to use the left knife attack? - [Default = 0]");
	cvar_OneHitKnifeAttacks =			CreateConVar("OITC_OneHitKnifeAttacks", 			"1",	 	"Should attacking an enemy with the knife always result in a guranteed kill? - [Default = 1]");
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

		//Resets the player's scoreboard stats
		ResetPlayerScores(client);

		// Adds a hook to the client which will let us track when the player is eligible to pick up a weapon
		SDKHook(client, SDKHook_WeaponCanUse, Hook_WeaponCanUse);

		// Adds a hook to the client which will let us track when the player takes damage
		SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);

		// Adds a hook to the client which will let us track when the player switches weapon
		SDKHook(client, SDKHook_WeaponSwitchPost, Hook_OnWeaponSwitchPost);
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

	// Resets the client's mvp awards back to zero
	CS_SetMVPCount(client, 0);

	// Resets the client's contribution score back to zero
	CS_SetClientContributionScore(client, 0);
}


// This happens when the plugin is loaded
public void CalculateSpeedValues()
{
	// Calculates the base amount of speed that the player should receive
	knifeMovementSpeedBase = ((GetConVarFloat(cvar_KnifeSpeedIncrease) / 100) / 5) + 1.0;

	// Calculates the amount that the speed should gradually increment by and store it within our KnifeMovementSpeedIncrement variable
	KnifeMovementSpeedIncrement = ((GetConVarFloat(cvar_KnifeSpeedIncrease) / 100) / 10);
}


// This happens when a new map is loaded
public void SetMaxRounds()
{
	// Creates a variable to store our data within
	char maxRoundsString[128];

	// Converts the maxRounds integer value to a string named maxRoundsString
	IntToString(GetConVarInt(cvar_MaximumKRounds), maxRoundsString, sizeof(maxRoundsString));
	
	// Changes the value of mp_maxrounds to that of our cvar_MaximumKRounds convar
	SetConVar("mp_maxrounds", maxRoundsString);
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
	// Gives the client the specified weapon
	GivePlayerItem(client, "weapon_deagle");
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

	// If the weapon's entity name is that of a pistols then execute this section
	if(!StrEqual(className, "weapon_deagle", false))
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

	// Creates a variable which we will use to store data within
	char attackerName[64];

	// Obtains the name of attacker and store it within the attackerName variable
	GetClientName(attacker, attackerName, sizeof(attackerName));

	// Creates a variable which we will use to store our data within
	char hudMessage[1024];

	// Modifies the contents stored within the hudMessage variable
	Format(hudMessage, 1024, "\n<font color='#5fd6f9'>%s</font><font color='#fbb227'> reached</font><font color='#5fd6f9'> %i</font><font color='#fbb227'> kills and won the round!</font>", attackerName, GetConVarInt(cvar_MaximumKills));

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