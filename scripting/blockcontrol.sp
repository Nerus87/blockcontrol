#include <sourcemod>
#include <collisionhook>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_NAME				"Block Control"
#define PLUGIN_VERSION			"v1.1"
#define PLUGIN_DESCRIPTION		"Control noblock for players, teams, nades, hostages"

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

bool PLUGIN_ENABLED = true;
bool CROUCH_BLOCK_ENABLED = true;
bool NOBLOCK_HOSTAGE_ENABLED = true;
bool NOBLOCK_NADE_ENABLED = true;
bool PLUGIN_ADVERTS_ENABLED = true;

bool TIMER_CREATED[MAX_PREDEFINED_PLAYERS];
bool PLAYER_IN_DUCK[MAX_PREDEFINED_PLAYERS];
bool IS_PLAYER_SOLID[MAX_PREDEFINED_PLAYERS];
bool PLUGIN_WELCOME_MESSAGE[MAX_PREDEFINED_PLAYERS];

int OFFSET_COLLISION_GROUP = -1;

int NOBLOCK_TYPE = 2;

char TRANSLATION_DESCRIPTION[MAX_STRING_LENGHT];
char TRANSLATION_PLUGIN_ENABLED[MAX_STRING_LENGHT];
char TRANSLATION_CROUCH[MAX_STRING_LENGHT];
char TRANSLATION_BLOCK_TIME[MAX_STRING_LENGHT];
char TRANSLATION_HOSTAGES[MAX_STRING_LENGHT];
char TRANSLATION_TYPES[MAX_STRING_LENGHT];
char TRANSLATION_NADES[MAX_STRING_LENGHT];
char TRANSLATION_ADVERTS[MAX_STRING_LENGHT];

float BLOCK_TIME = 3.0;

Handle sm_blockcontrol_enable = INVALID_HANDLE;
Handle sm_blockcontrol_noblock_crouch = INVALID_HANDLE;
Handle sm_blockcontrol_crouch_block_time = INVALID_HANDLE;
Handle sm_blockcontrol_noblock_hostages = INVALID_HANDLE;
Handle sm_blockcontrol_noblock_type = INVALID_HANDLE;
Handle sm_blockcontrol_noblock_nades = INVALID_HANDLE;
Handle sm_blockcontrol_adverts = INVALID_HANDLE;

Handle sv_turbophysics = INVALID_HANDLE;

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

	Format(TRANSLATION_PLUGIN_ENABLED, MAX_STRING_LENGHT, "%T", "sm_blockcontrol_enable", LANG_SERVER);

	Format(TRANSLATION_TYPES, MAX_STRING_LENGHT, "%T", "sm_blockcontrol_noblock_type", LANG_SERVER);

	Format(TRANSLATION_CROUCH, MAX_STRING_LENGHT, "%T", "sm_blockcontrol_noblock_crouch", LANG_SERVER);

	Format(TRANSLATION_BLOCK_TIME, MAX_STRING_LENGHT, "%T", "sm_blockcontrol_crouch_block_time", LANG_SERVER);
	
	Format(TRANSLATION_HOSTAGES, MAX_STRING_LENGHT, "%T", "sm_blockcontrol_noblock_hostages", LANG_SERVER);

	Format(TRANSLATION_NADES, MAX_STRING_LENGHT, "%T", "sm_blockcontrol_noblock_nades", LANG_SERVER);

	Format(TRANSLATION_ADVERTS, MAX_STRING_LENGHT, "%T", "sm_blockcontrol_adverts", LANG_SERVER);
}

public void SetValues()
{
	SetOffsetCollisionGroup();

	SetTurboPhysics();
}

public void SetConVars()
{
	CreateConVar("sm_blockcontrol_version", PLUGIN_VERSION, TRANSLATION_DESCRIPTION);

	sm_blockcontrol_enable = CreateConVar("sm_blockcontrol_enable", "1", TRANSLATION_PLUGIN_ENABLED);

	sm_blockcontrol_noblock_type = CreateConVar("sm_blockcontrol_noblock_type", "2", TRANSLATION_TYPES);

	sm_blockcontrol_noblock_crouch = CreateConVar("sm_blockcontrol_noblock_crouch", "1", TRANSLATION_CROUCH);

	sm_blockcontrol_crouch_block_time = CreateConVar("sm_blockcontrol_crouch_block_time", "3.0", TRANSLATION_BLOCK_TIME);

	sm_blockcontrol_noblock_hostages = CreateConVar("sm_blockcontrol_noblock_hostages", "1", TRANSLATION_HOSTAGES);

	sm_blockcontrol_noblock_nades = CreateConVar("sm_blockcontrol_noblock_nades", "1", TRANSLATION_NADES);

	sm_blockcontrol_adverts = CreateConVar("sm_blockcontrol_adverts", "1", TRANSLATION_ADVERTS);

	AutoExecConfig(true, "blockcontrol");
}

public void SetHooks()
{
	/// Plugin ConVars hooks
	HookConVarChange(sm_blockcontrol_enable, OnConVarEnableChange);

	HookConVarChange(sm_blockcontrol_noblock_type, OnConVarNoblockTypeChange);

	HookConVarChange(sm_blockcontrol_noblock_crouch, OnConVarNoblockCrouchChange);

	HookConVarChange(sm_blockcontrol_crouch_block_time, OnConVarBlockTimeChange);

	HookConVarChange(sm_blockcontrol_noblock_hostages, OnConVarHostagesChange);

	HookConVarChange(sm_blockcontrol_noblock_nades, OnConVarNoblockNadesChange);

	HookConVarChange(sm_blockcontrol_adverts, OnConVarAdvertsChange);

	/// Game ConVars hooks
	if(sv_turbophysics != INVALID_HANDLE)
		HookConVarChange(sv_turbophysics, OnConVarTurboPhysicsChange);

	/// Game Events hooks
	HookEvent("player_spawn", OnPlayerSpawn);
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

public void SetTurboPhysics()
{
	if(CommandExists("sv_turbophysics"))
	{
		sv_turbophysics = FindConVar("sv_turbophysics");
	
		if(sv_turbophysics != INVALID_HANDLE)
			SetConVarInt(sv_turbophysics, 1);
		else
		{
			char error[MAX_STRING_LENGHT];
			Format(error, MAX_STRING_LENGHT, "[%s] ERROR: %T", PLUGIN_NAME, "sv_turbophysics_error", LANG_SERVER);
	
			SetFailState(error);
		}
	}
}

public void OnPluginStart()
{
	SetTranslation();

	SetValues();	

	SetConVars();

	SetHooks();
}

/*
 *  ConVar Events
 */

public void OnConVarEnableChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(GetConVarInt(sm_blockcontrol_enable) > 0) 
		PLUGIN_ENABLED = true;
	else
		PLUGIN_ENABLED = false;
}

public void OnConVarNoblockTypeChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
	switch(GetConVarInt(sm_blockcontrol_noblock_type))
	{
		case 0:
			NOBLOCK_TYPE = 0;

		case 1:
			NOBLOCK_TYPE = 1;

		case 2:
			NOBLOCK_TYPE = 2;

		default:
			NOBLOCK_TYPE = 2;
	}
}

public void OnConVarNoblockCrouchChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(GetConVarInt(sm_blockcontrol_noblock_crouch) > 0) 
		CROUCH_BLOCK_ENABLED = true;
	else
		CROUCH_BLOCK_ENABLED = false;
}

public void OnConVarBlockTimeChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
	float block_time = GetConVarFloat(sm_blockcontrol_crouch_block_time);

	if(block_time > 0.1) 
		BLOCK_TIME = block_time;
	else
		BLOCK_TIME = 0.1;
}

public void OnConVarHostagesChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(GetConVarInt(sm_blockcontrol_noblock_hostages) > 0) 
		NOBLOCK_HOSTAGE_ENABLED = true;
	else
		NOBLOCK_HOSTAGE_ENABLED = false;
}

public void OnConVarNoblockNadesChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(GetConVarInt(sm_blockcontrol_noblock_nades) > 0) 
		NOBLOCK_NADE_ENABLED = true;
	else
		NOBLOCK_NADE_ENABLED = false;
}

public void OnConVarAdvertsChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(GetConVarInt(sm_blockcontrol_adverts) > 0) 
		PLUGIN_ADVERTS_ENABLED = true;
	else
		PLUGIN_ADVERTS_ENABLED = false;
}

public void OnConVarTurboPhysicsChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
	int value = StringToInt(newValue);

	if(value < 1) 
	{
		SetConVarInt(sv_turbophysics, 1);

		char warn[MAX_STRING_LENGHT];
		Format(warn, MAX_STRING_LENGHT, "[%s] WARN: %T", PLUGIN_NAME, "sv_turbophysics_warn", LANG_SERVER);

		PrintToServer(warn);
	}
}

/*
 *  Game Events
 */
public void OnClientConnected(int client)
{
	PLUGIN_WELCOME_MESSAGE[client] = false;
}

public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int userid = GetEventInt(event, "userid");
	int client = GetClientOfUserId(userid);
	
	if(IsClientRedy(client))
	{
		if(!PLUGIN_WELCOME_MESSAGE[client] && !IsFakeClient(client))
			if(PLUGIN_ADVERTS_ENABLED)
				CreateTimer(0.1, Welcome, client);

		TIMER_CREATED[client] = false;
		PLAYER_IN_DUCK[client] = false;
		IS_PLAYER_SOLID[client] = false;
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if(!PLUGIN_ENABLED || NOBLOCK_TYPE != 2 || !CROUCH_BLOCK_ENABLED || !IsClientValid(client))
		return Plugin_Continue;

	if(buttons == IN_DUCK)
		PLAYER_IN_DUCK[client] = true;
	else
		PLAYER_IN_DUCK[client] = false;

	if(!TIMER_CREATED[client] && PLAYER_IN_DUCK[client])
	{
		CreateTimer(BLOCK_TIME, NonsolidPlayer, client, TIMER_REPEAT);

		TIMER_CREATED[client] = true;
		IS_PLAYER_SOLID[client] = true;

		if(PLUGIN_ADVERTS_ENABLED && !IsFakeClient(client))
			PrintToChat(client, "\x04[Block Control]\x01 %T", "sm_blockcontrol_noblock_off", client, '\x04');
	}

	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(PLUGIN_ENABLED)
	{
		/// Set no block for all hostages
		if(NOBLOCK_HOSTAGE_ENABLED && IsHostage(entity))
			CreateTimer(0.1, NonsolidHostages, entity);

		if(NOBLOCK_TYPE == 1)
		{
			if(IsClientValid(entity))
				CreateTimer(0.1, NonsolidPlayer, entity);

			if(NOBLOCK_NADE_ENABLED && IsNade(entity))
				CreateTimer(0.1, NonsolidNades, entity);
		}
	}
}

public Action CH_PassFilter(int ent1, int ent2, bool &result)
{
	if(PLUGIN_ENABLED && NOBLOCK_TYPE == 2 && IsValidEntity(ent1) && IsValidEntity(ent2))
	{
		/// Noblock check teammates
		if(IsClientValid(ent1) && IsClientValid(ent2))
		{
			if(!IsSameTeam(ent1, ent2) || CROUCH_BLOCK_ENABLED && (IS_PLAYER_SOLID[ent1] || IS_PLAYER_SOLID[ent2]))
			{
				SetEntData(ent1, OFFSET_COLLISION_GROUP, COLLISION_GROUP_PLAYER, 4, true);
				SetEntData(ent2, OFFSET_COLLISION_GROUP, COLLISION_GROUP_PLAYER, 4, true);
			}
			else
			{
				SetEntData(ent1, OFFSET_COLLISION_GROUP, COLLISION_GROUP_INTERACTIVE_DEBRIS, 4, true);
				SetEntData(ent2, OFFSET_COLLISION_GROUP, COLLISION_GROUP_INTERACTIVE_DEBRIS, 4, true);
			}
		}

		if(NOBLOCK_NADE_ENABLED)
		{
			/// Noblock check nade and player 
			if(IsNade(ent1) && IsClientValid(ent2))
			{
				int nade_owner = GetOwnerOfEntity(ent1);
	
				if(!IsClientValid(nade_owner))
					return Plugin_Continue;

				if(!IsSameTeam(nade_owner, ent2))
					result = true;

				return Plugin_Handled;
			}
	
			/// Noblock check player and nade
			if(IsNade(ent2) && IsClientValid(ent1))
			{
				int nade_owner = GetOwnerOfEntity(ent2);
				
				if(!IsClientValid(nade_owner))
					return Plugin_Continue;

				if(!IsSameTeam(nade_owner, ent1))
					result = true;
	
				return Plugin_Handled;
			}
		}
	}

	return Plugin_Continue;
}

/*
 *  Usefull functions
 */

public Action NonsolidHostages(Handle timer, any data)
{
	if(NOBLOCK_HOSTAGE_ENABLED && IsValidEntity(data))
		SetEntData(data, OFFSET_COLLISION_GROUP, COLLISION_GROUP_DEBRIS_TRIGGER, 4, true);

	return Plugin_Continue;
}

public Action NonsolidNades(Handle timer, any data)
{
	if(NOBLOCK_NADE_ENABLED && IsValidEntity(data))
		SetEntData(data, OFFSET_COLLISION_GROUP, COLLISION_GROUP_INTERACTIVE_DEBRIS, 4, true);

	return Plugin_Continue;
}

public Action NonsolidPlayer(Handle timer, any data)
{
	if(!PLUGIN_ENABLED || !IsClientValid(data))
		return Plugin_Stop;

	if(NOBLOCK_TYPE == 1)
	{
		SetEntData(data, OFFSET_COLLISION_GROUP, COLLISION_GROUP_DEBRIS_TRIGGER, 4, true);

		return Plugin_Stop;
	}

	if(NOBLOCK_TYPE == 2 && CROUCH_BLOCK_ENABLED && !PLAYER_IN_DUCK[data])
	{
		TIMER_CREATED[data] = false;
		IS_PLAYER_SOLID[data] = false;

		if(PLUGIN_ADVERTS_ENABLED && !IsFakeClient(data))
			PrintToChat(data, "\x04[Block Control]\x01 %T", "sm_blockcontrol_noblock_on", data, '\x04');

		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public Action Welcome(Handle timer, any data)
{
	if(!PLUGIN_ENABLED || !IsClientRedy(data))
		return Plugin_Stop;

	if(PLUGIN_ADVERTS_ENABLED)
		PrintToChat(data, "\x04[Block Control]\x01 %T", "sm_blockcontrol_welcome_message", data);

	PLUGIN_WELCOME_MESSAGE[data] = true;

	return Plugin_Continue;
}

/**
 * Check player and other player are in the same team
 *
 * @param client 	An client entity index.
 * @param player 	An other player entity index.
 * @return			Returns true if is a same team, false otherwise.
 */
stock bool IsSameTeam(int client, int player)
{
	int player_team = GetClientTeam(client);

	int teammate_team = GetClientTeam(player);

	if(player_team == teammate_team)
		return true;
		
	return false;
}

/**
 * Checks client is valid player.
 *
 * @param client 	An client entity index.
 * @return			Returns true if client is valid player, false otherwise.
 */
stock bool IsClientValid(int client)
{
	if(IsClientRedy(client) && IsPlayerAlive(client))
		return true;
		
	return false;
}

stock bool IsClientRedy(int client)
{
	if(IsClient(client) && IsClientInGame(client))
		return true;
		
	return false;
}

stock bool IsClient(int client)
{
	if(client > 0 && client < MaxClients)
		return true;
		
	return false;
}

stock bool IsNade(int entity)
{
	if(IsValidEntity(entity))
	{
		char classname[128];
		GetEntityClassname(entity, classname, 128);

		if(StrEqual(classname, "smokegrenade_projectile") || StrEqual(classname, "flashbang_projectile") || StrEqual(classname, "hegrenade_projectile"))
			return true;		
	}

	return false;
}

stock bool IsHostage(int entity)
{
	if(IsValidEntity(entity))
	{
		char classname[128];
		GetEntityClassname(entity, classname, 128);

		if(StrEqual(classname, "hostage_entity"))
			return true;		
	}

	return false;
}

stock int GetOwnerOfEntity(int entity)
{
	return GetEntPropEnt(entity, Prop_Send, "m_hThrower");
}
