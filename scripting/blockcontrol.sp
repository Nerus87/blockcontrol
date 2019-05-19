#include <collisionhook>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_NAME				"Block Control"
#define PLUGIN_VERSION			"v1.2"
#define PLUGIN_DESCRIPTION		"Control player colissions with teammates, nades and hostages"

enum COLISIONS_GROPUS
{
	COLLISION_GROUP_NONE = 0,
	COLLISION_GROUP_DEBRIS,				// Collides with nothing but world and static stuff
	COLLISION_GROUP_DEBRIS_TRIGGER,		// Same as debris, but hits triggers
	COLLISION_GROUP_INTERACTIVE_DEBRIS, // Collides with everything except other interactive debris or debris
	COLLISION_GROUP_INTERACTIVE,		// Collides with everything except interactive debris or debris
	COLLISION_GROUP_PLAYER,
	COLLISION_GROUP_BREAKABLE_GLASS,
	COLLISION_GROUP_VEHICLE,
	COLLISION_GROUP_PLAYER_MOVEMENT,	// For HL2, same as Collision_Group_Player  
	COLLISION_GROUP_NPC,				// Generic NPC group
	COLLISION_GROUP_IN_VEHICLE,			// for any entity inside a vehicle
	COLLISION_GROUP_WEAPON,				// for any weapons that need collision detection
	COLLISION_GROUP_VEHICLE_CLIP,		// vehicle clip brush to restrict vehicle movement
	COLLISION_GROUP_PROJECTILE,			// Projectiles!
	COLLISION_GROUP_DOOR_BLOCKER,		// Blocks entities not permitted to get near moving doors
	COLLISION_GROUP_PASSABLE_DOOR,		// Doors that the player shouldn't collide with
	COLLISION_GROUP_DISSOLVING,			// Things that are dissolving are in this group
	COLLISION_GROUP_PUSHAWAY,			// Nonsolid on client and server, pushaway in player code
	COLLISION_GROUP_NPC_ACTOR,			// Used so NPCs in scripts ignore the player.
}

const int MAX_STRING_LENGHT = 256;
const int MAX_PREDEFINED_PLAYERS = 32 + 1; // 1 is a SourceTV

bool IS_KNIFE_FIGHT = false;

int OFFSET_COLLISION_GROUP = -1;

static char TRANSLATION_DESCRIPTION[MAX_STRING_LENGHT];
static char TRANSLATION_ENABLE[MAX_STRING_LENGHT];
static char TRANSLATION_HOSTAGES[MAX_STRING_LENGHT];
static char TRANSLATION_DEBUG[MAX_STRING_LENGHT];

ConVar sm_blockcontrol = null;
ConVar sm_blockcontrol_debug = null;
ConVar sm_blockcontrol_noblock_hostages = null;

public Plugin myinfo = {
	name = PLUGIN_NAME,
	author = "Nerus",
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?p=2422426"
};

public void SetTranslation()
{
	LoadTranslations("blockcontrol.phrases");

	Format(TRANSLATION_DESCRIPTION, MAX_STRING_LENGHT, "%T", "sm_blockcontrol_description", LANG_SERVER);

	Format(TRANSLATION_ENABLE, MAX_STRING_LENGHT, "%T", "sm_blockcontrol", LANG_SERVER);

	Format(TRANSLATION_DEBUG, MAX_STRING_LENGHT, "%T", "sm_blockcontrol_debug", LANG_SERVER);

	Format(TRANSLATION_HOSTAGES, MAX_STRING_LENGHT, "%T", "sm_blockcontrol_noblock_hostages", LANG_SERVER);
}

public void SetValues()
{
	SetOffsetCollisionGroup();
}

public void SetConVars()
{
	CreateConVar("sm_blockcontrol_version", PLUGIN_VERSION, TRANSLATION_DESCRIPTION);

	sm_blockcontrol = CreateConVar("sm_blockcontrol", "1", TRANSLATION_ENABLE);

	sm_blockcontrol_debug = CreateConVar("sm_blockcontrol_debug", "0", TRANSLATION_DEBUG);

	sm_blockcontrol_noblock_hostages = CreateConVar("sm_blockcontrol_noblock_hostages", "1", TRANSLATION_HOSTAGES);

	AutoExecConfig(true, "blockcontrol");
}

public void SetOffsetCollisionGroup()
{
	OFFSET_COLLISION_GROUP = FindSendPropInfo("CBaseEntity", "m_CollisionGroup");

	if (OFFSET_COLLISION_GROUP == -1)
	{
		char error[MAX_STRING_LENGHT];
		Format(error, MAX_STRING_LENGHT, "[%s] ERROR: %T", PLUGIN_NAME, "collision_group_error", LANG_SERVER);

		SetFailState(error);		
	}
}

////////////////////
/// Plugin events

public void OnPluginStart()
{
	SetTranslation();

	SetValues();	

	SetConVars();
}

///////////////////////////
/// Other plugins events

public void OnPreKnifeFight(int client, int secod)
{
	IS_KNIFE_FIGHT = true;
}

public void OnStartKnifeFight()
{
	IS_KNIFE_FIGHT = false;
}

public void OnPostKnifeFight(int client, int secod)
{
	IS_KNIFE_FIGHT = false;
}

//////////////////
/// Game events

public void OnEntityCreated(int entity, const char[] classname)	
{
	if(sm_blockcontrol.BoolValue && sm_blockcontrol_noblock_hostages.BoolValue && IsHostage(entity))
		CreateTimer(0.1, NonSolidHostages, entity);
}

public Action CH_PassFilter(int ent1, int ent2, bool &result)
{
	if(!sm_blockcontrol.BoolValue || !IsValidEntity(ent1) || !IsValidEntity(ent2))
		return Plugin_Continue;

	/// Noblock - check teammates
	if(IsAlivePlayer(ent1, false) && IsAlivePlayer(ent2, false))
	{
		if(IS_KNIFE_FIGHT)
		{
			DisableCollisionsWithPlayer(ent1);
			DisableCollisionsWithPlayer(ent2);

			if(sm_blockcontrol_debug.BoolValue)
				PrintToServer("Collision between %N and %N disabled on Knife Fight", ent1, ent2);

			return Plugin_Continue;
		}

		if(IsSamePlayer(ent1, ent2) || !IsTeamMate(ent1, ent2) || IsPlayerAboveAnotherOne(ent1, ent2) || IsPlayerAboveAnotherOne(ent2, ent1))
		{
			EnableCollisionsWithPlayer(ent1);
			EnableCollisionsWithPlayer(ent2);

			if(sm_blockcontrol_debug.BoolValue)
				PrintToServer("Collision between %N and %N enabled", ent1, ent2);
		}
		else
		{
			DisableCollisionsWithPlayer(ent1);
			DisableCollisionsWithPlayer(ent2);

			if(sm_blockcontrol_debug.BoolValue)
				PrintToServer("Collision between %N and %N disabled", ent1, ent2);
		}

		return Plugin_Continue;
	}

	/// Noblock - check nade and player 
	if(IsNade(ent1) && IsAlivePlayer(ent2, false))
	{
		int nade_owner = GetThrowedNadeOwner(ent1);
		if(!IsValidPlayer(nade_owner, false) || IsSamePlayer(nade_owner, ent2))
		{
			result = true;

			return Plugin_Continue;
		}

		if(IsTeamMate(nade_owner, ent2) && IsPlayersInSamePlace(nade_owner, ent2))
		{
			result = false;
				
			return Plugin_Handled;
		}
	}

	/// Noblock - check player and nade
	if(IsNade(ent2) && IsAlivePlayer(ent1, false))
	{
		int nade_owner = GetThrowedNadeOwner(ent2);
		if(!IsValidPlayer(nade_owner, false) || IsSamePlayer(nade_owner, ent1))
		{
			result = true;

			return Plugin_Continue;
		}

		if(IsTeamMate(nade_owner, ent1) && IsPlayersInSamePlace(nade_owner, ent1))
		{
			result = false;

			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

/////////////
/// Timers

public Action NonSolidHostages(Handle timer, any data)
{
	if(sm_blockcontrol_noblock_hostages.IntValue && IsValidEntity(data))
		SetEntData(data, OFFSET_COLLISION_GROUP, COLLISION_GROUP_DEBRIS_TRIGGER, 4, true);

	return Plugin_Continue;
}

////////////////////////
/// Usefull functions

stock void EnableCollisionsWithPlayer(int player)
{
	if(IsValidPlayer(player, false))
		SetEntData(player, OFFSET_COLLISION_GROUP, COLLISION_GROUP_PLAYER, 4, true);
}

stock void DisableCollisionsWithPlayer(int player)
{
	if(IsValidPlayer(player, false))
		SetEntData(player, OFFSET_COLLISION_GROUP, COLLISION_GROUP_INTERACTIVE_DEBRIS, 4, true);
}

stock bool IsPlayersInSamePlace(int player, int other)
{
	float player_pos[3]; 
	GetClientAbsOrigin(player, player_pos);

	float other_pos[3]; 
	GetClientAbsOrigin(other, other_pos);

	player_pos[2] = 0.0;
	other_pos[2] = 0.0;

	float distance = GetVectorDistance(player_pos, other_pos, false);

	if(sm_blockcontrol_debug.BoolValue)
		PrintToServer("Distance between %N and %N is: %f", player, other, distance);

	return distance < 33.0;
}

public bool IsPlayerAboveAnotherOne(int player, int other)
{
	float player_pos[3];
	GetClientAbsOrigin(player, player_pos);

	float other_pos[3];
	GetClientAbsOrigin(other, other_pos);

	float y_diff = FloatAbs(player_pos[2] - other_pos[2]);

	if(sm_blockcontrol_debug.BoolValue)
		PrintToServer("Player %N is on player %N with diff: [%f, %f]", player, other, player_pos[2], other_pos[2]);

	if(IsPlayerCrouched(player) || IsPlayerCrouched(other))
		return (y_diff > 45.031250);
	else
		return (y_diff >= 62.086700);
}

stock bool IsSameTeam(int client, int player)
{
	int player_team = GetClientTeam(client);

	int teammate_team = GetClientTeam(player);

	if(player_team == teammate_team)
		return true;
		
	return false;
}

stock bool IsClient(int client)
{
	return (client > 0 && client < MaxClients + 1);
}

stock bool IsValidClient(int client)
{
	return (IsClient(client) && IsClientConnected(client) && IsClientInGame(client));
}

stock bool IsValidPlayer(int client, bool only_human)
{
	if(only_human)
		return (IsValidClient(client) && !IsClientSourceTV(client) && !IsFakeClient(client));
	
	return (IsValidClient(client) && !IsClientSourceTV(client));
}

stock bool IsAlivePlayer(int client, bool only_human)
{
	return (IsValidPlayer(client, only_human) && IsPlayerAlive(client));
}

stock bool IsDeadPlayer(int client, bool only_human = false)
{
	return (IsValidPlayer(client, only_human) && !IsPlayerAlive(client));
}

stock bool IsBot(int client)
{
	return (IsValidPlayer(client, false) && IsFakeClient(client));
}

stock bool IsSamePlayer(int client, int other)
{
	return (client == other);
}

stock bool IsTeamMate(int client, int second)
{
	return (IsValidPlayer(second, false) && GetClientTeam(client) == GetClientTeam(second));
}

stock bool IsPlayerCrouched(int player)
{
	return GetEntProp(player, Prop_Send, "m_bDucked", 1) > 0;
}

stock bool IsNade(int entity)
{
	if(!IsValidEntity(entity))
		return false;
	
	char classname[32];
	GetEntityClassname(entity, classname, 32);

	return (StrEqual(classname, "smokegrenade_projectile") || StrEqual(classname, "flashbang_projectile") || StrEqual(classname, "hegrenade_projectile"));
}

stock bool IsHostage(int entity)
{
	if(!IsValidEntity(entity))
		return false;

	char classname[32];
	GetEntityClassname(entity, classname, 32);

	return (StrEqual(classname, "hostage_entity"));
}

stock int GetThrowedNadeOwner(int entity)
{
	if(!IsValidEntity(entity))
		return 0;

	return GetEntPropEnt(entity, Prop_Send, "m_hThrower");
}
