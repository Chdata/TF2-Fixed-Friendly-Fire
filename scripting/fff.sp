/*
    Fixed Friendly Fire
    By: Chdata & Kit O' Rifty

    TODO:
    Fix Flying Guillotine cleavers.
    Investigate bodies falling through the ground when you die after toggling the plugin on/off.
*/

#pragma semicolon 1
#include <sourcemod>
#include <sdkhooks>
#include <tf2_stocks>
#include <dhooks>
#include <morecolors>

#define PLUGIN_VERSION "0x03"

#if !defined _smlib_included
enum // Collision_Group_t in const.h - m_CollisionGroup
{
    COLLISION_GROUP_NONE  = 0,
    COLLISION_GROUP_DEBRIS,             // Collides with nothing but world and static stuff
    COLLISION_GROUP_DEBRIS_TRIGGER,     // Same as debris, but hits triggers
    COLLISION_GROUP_INTERACTIVE_DEBRIS, // Collides with everything except other interactive debris or debris
    COLLISION_GROUP_INTERACTIVE,        // Collides with everything except interactive debris or debris         // Can be hit by bullets, explosions, players, projectiles, melee
    COLLISION_GROUP_PLAYER,                                                                                     // Can be hit by bullets, explosions, players, projectiles, melee
    COLLISION_GROUP_BREAKABLE_GLASS,
    COLLISION_GROUP_VEHICLE,
    COLLISION_GROUP_PLAYER_MOVEMENT,    // For HL2, same as Collision_Group_Player, for
                                        // TF2, this filters out other players and CBaseObjects
    COLLISION_GROUP_NPC,                // Generic NPC group
    COLLISION_GROUP_IN_VEHICLE,         // for any entity inside a vehicle                                      // Can be hit by explosions. Melee unknown.
    COLLISION_GROUP_WEAPON,             // for any weapons that need collision detection
    COLLISION_GROUP_VEHICLE_CLIP,       // vehicle clip brush to restrict vehicle movement
    COLLISION_GROUP_PROJECTILE,         // Projectiles!
    COLLISION_GROUP_DOOR_BLOCKER,       // Blocks entities not permitted to get near moving doors
    COLLISION_GROUP_PASSABLE_DOOR,      // ** sarysa TF2 note: Must be scripted, not passable on physics prop (Doors that the player shouldn't collide with)
    COLLISION_GROUP_DISSOLVING,         // Things that are dissolving are in this group
    COLLISION_GROUP_PUSHAWAY,           // ** sarysa TF2 note: I could swear the collision detection is better for this than NONE. (Nonsolid on client and server, pushaway in player code) // Can be hit by bullets, explosions, projectiles, melee

    COLLISION_GROUP_NPC_ACTOR,          // Used so NPCs in scripts ignore the player.
    COLLISION_GROUP_NPC_SCRIPTED = 19,  // USed for NPCs in scripts that should not collide with each other.

    LAST_SHARED_COLLISION_GROUP
};
#endif

static const String:g_sPvPProjectileClasses[][] = 
{
    //"tf_projectile_pipe_remote",
    //"tf_projectile_cleaver",
    "tf_projectile_rocket", 
    "tf_projectile_sentryrocket", 
    "tf_projectile_arrow", 
    "tf_projectile_stun_ball",
    "tf_projectile_ball_ornament",
    "tf_projectile_energy_ball",
    "tf_projectile_energy_ring",
    "tf_projectile_flare",
    "tf_projectile_healing_bolt",
    "tf_projectile_jar",
    "tf_projectile_jar_milk",
    "tf_projectile_pipe",
    "tf_projectile_syringe"
};

static bool:g_bFriendlyFire = false;
static Handle:mp_friendlyfire;

static Handle:g_fnWantsLagCompensationOnEntity;

public Plugin:myinfo = {
    name = "Fixed Friendly Fire",
    author = "Kit O'Rifty & Chdata",
    description = "Hexy.",
    version = PLUGIN_VERSION,
    url = "http://steamcommunity.com/groups/tf2data",
};

public OnPluginStart()
{
    mp_friendlyfire = FindConVar("mp_friendlyfire");
    HookConVarChange(mp_friendlyfire, CvarChange);

    RegAdminCmd("sm_fff", cmdFriendlyFireToggle, ADMFLAG_CHEATS, "sm_friendlyfire <on/off> - Toggles mp_friendlyfire status.");
    RegAdminCmd("sm_friendlyfire", cmdFriendlyFireToggle, ADMFLAG_CHEATS, "sm_friendlyfire <on/off> - Toggles mp_friendlyfire status.");

    Gamedata_OnPluginStart();
}

void Gamedata_OnPluginStart()
{
    Handle hConfig = LoadGameConfigFile("data.friendlyfire");
    if (hConfig == INVALID_HANDLE)
    {
        SetFailState("Could not find friendlyfire gamedata file: [data.friendlyfire.txt]!");
    }
    
    int iOffset = GameConfGetOffset(hConfig, "CTFPlayer::WantsLagCompensationOnEntity"); 
    g_fnWantsLagCompensationOnEntity = DHookCreate(iOffset, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity, Hook_ClientWantsLagCompensationOnEntity); 
    if (g_fnWantsLagCompensationOnEntity == INVALID_HANDLE)
    {
        SetFailState("Failed to create hook CTFPlayer::WantsLagCompensationOnEntity offset from [data.friendlyfire.txt] gamedata!");
    }
    
    DHookAddParam(g_fnWantsLagCompensationOnEntity, HookParamType_CBaseEntity);
    DHookAddParam(g_fnWantsLagCompensationOnEntity, HookParamType_ObjectPtr);
    DHookAddParam(g_fnWantsLagCompensationOnEntity, HookParamType_Unknown);
}

public OnClientPutInServer(iClient)
{
    if (g_bFriendlyFire)
    {
        SDKHook(iClient, SDKHook_PreThinkPost, Client_OnPreThinkPost);

        if (IsFakeClient(iClient))
        {
            return;
        }
        DHookEntity(g_fnWantsLagCompensationOnEntity, true, iClient);
    }
}

public OnMapStart()
{
    for (new lClient = 1; lClient <= MaxClients; lClient++)
    {
        if (IsClientInGame(lClient))
        {
            if (GetConVarBool(mp_friendlyfire))
            {
                SDKHook(lClient, SDKHook_PreThinkPost, Client_OnPreThinkPost);
            }
        }
    }
}

public OnConfigsExecuted()
{
    g_bFriendlyFire = GetConVarBool(mp_friendlyfire);
}

public CvarChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
    new Handle:svtags = FindConVar("sv_tags");
    new sflags = GetConVarFlags(svtags);
    sflags &= ~FCVAR_NOTIFY;
    SetConVarFlags(svtags, sflags);

    new flags = GetConVarFlags(convar);
    flags &= ~FCVAR_NOTIFY;
    SetConVarFlags(convar, flags);

    g_bFriendlyFire = GetConVarBool(convar);

    SetConVarBool(FindConVar("tf_avoidteammates"), !g_bFriendlyFire, true);

    for (new lClient = 1; lClient <= MaxClients; lClient++)
    {
        if (IsClientInGame(lClient))
        {
            if (g_bFriendlyFire)
            {
                SDKHook(lClient, SDKHook_PreThinkPost, Client_OnPreThinkPost);
            }
            else
            {
                SDKUnhook(lClient, SDKHook_PreThinkPost, Client_OnPreThinkPost);
            }
            
        }
    }

    //CPrintToChatAll("{green}[{lightgreen}FF{green}]{default} Friendly Fire has been %sabled.", g_bFriendlyFire ? "en" : "dis");
}

/*
    Runs every frame for clients

*/
public Client_OnPreThinkPost(iClient)
{
    if (IsPlayerAlive(iClient) && IsPlayerStuck(iClient))       // If a player is stuck in a player, push them apart
    {
        PushClientsApart(iClient, TR_GetEntityIndex());         // Temporarily remove collision while we push apart
    }
    else
    {
        SetEntProp(iClient, Prop_Send, "m_CollisionGroup", COLLISION_GROUP_PLAYER);
    }
}

public MRESReturn Hook_ClientWantsLagCompensationOnEntity(int iClient, Handle hReturn, Handle hParams)
{
    if (!g_bFriendlyFire)
    {
        return MRES_Ignored;
    }

    DHookSetReturn(hReturn, true);
    return MRES_Supercede;
}

stock bool:IsPlayerStuck(iEntity)
{
    decl Float:vecMin[3], Float:vecMax[3], Float:vecOrigin[3];
    
    GetEntPropVector(iEntity, Prop_Send, "m_vecMins", vecMin);
    GetEntPropVector(iEntity, Prop_Send, "m_vecMaxs", vecMax);
    GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", vecOrigin);
    
    TR_TraceHullFilter(vecOrigin, vecOrigin, vecMin, vecMax, MASK_SOLID, TraceRayPlayerOnly, iEntity);
    return (TR_DidHit());
}

public bool:TraceRayPlayerOnly(iEntity, iMask, any:iData)
{
    return (IsValidClient(iEntity) && IsValidClient(iData) && iEntity != iData);
}

stock PushClientsApart(iClient1, iClient2)
{
    SetEntProp(iClient1, Prop_Send, "m_CollisionGroup", COLLISION_GROUP_DEBRIS_TRIGGER);     // No collision with players and certain projectiles
    SetEntProp(iClient2, Prop_Send, "m_CollisionGroup", COLLISION_GROUP_DEBRIS_TRIGGER);

    decl Float:vVel[3];

    decl Float:vOrigin1[3];
    decl Float:vOrigin2[3];

    GetEntPropVector(iClient1, Prop_Send, "m_vecOrigin", vOrigin1);
    GetEntPropVector(iClient2, Prop_Send, "m_vecOrigin", vOrigin2);

    MakeVectorFromPoints(vOrigin1, vOrigin2, vVel);
    NormalizeVector(vVel, vVel);
    ScaleVector(vVel, -15.0);               // Set to 15.0 for a black hole effect

    vVel[1] += 0.1;                         // This is just a safeguard for sm_tele
    vVel[2] = 0.0;                          // Negate upwards push. += 280.0; for extra upwards push (can have sort of a fan/vent effect)

    SetEntPropVector(iClient1, Prop_Send, "m_vecBaseVelocity", vVel);
}

public Action:cmdFriendlyFireToggle(iClient, iArgc)
{
    if (iArgc < 1)
    {
        SetFriendlyFire(!g_bFriendlyFire);
    }
    else
    {
        decl String:arg[32];
        GetCmdArgString(arg, sizeof(arg));

        if (StrEqual(arg, "on") || arg[0] == '1')
        {
            SetFriendlyFire(true);
        }
        else if (StrEqual(arg, "off") || arg[0] == '0')
        {
            SetFriendlyFire(false);
        }
        else
        {
            SetFriendlyFire(!g_bFriendlyFire);
        }
    }

    return Plugin_Handled;
}

stock SetFriendlyFire(bool:bStatus)
{
    SetConVarBool(mp_friendlyfire, bStatus, true);
}

public OnEntityCreated(ent, const String:sClassname[])
{
    if (g_bFriendlyFire)
    {
        for (new i = 0; i < sizeof(g_sPvPProjectileClasses); i++)
        {
            if (StrEqual(sClassname, g_sPvPProjectileClasses[i], false))
            {
                SDKHook(ent, SDKHook_Spawn, Hook_PvPProjectileSpawn);
                SDKHook(ent, SDKHook_SpawnPost, Hook_PvPProjectileSpawnPost);
                break;
            }
        }
    }
}

public Action:Hook_PvPProjectileSpawn(ent)
{
    ChangeProjectileTeam(ent);

    return Plugin_Continue;
}

public Hook_PvPProjectileSpawnPost(ent)
{
    ChangeProjectileTeam(ent);
}

stock ChangeProjectileTeam(ent)
{
    if (g_bFriendlyFire)
    {
        decl String:sClass[64];
        GetEntityClassname(ent, sClass, sizeof(sClass));
        
        new iOwnerEntity = GetEntPropEnt(ent, Prop_Data, "m_hOwnerEntity");
        
        if (iOwnerEntity == -1)
        {
            iOwnerEntity = GetEntPropEnt(ent, Prop_Data, "m_hThrower");
        }

        if (IsValidClient(iOwnerEntity))
        {
            SetEntProp(ent, Prop_Data, "m_iInitialTeamNum", 0);
            SetEntProp(ent, Prop_Send, "m_iTeamNum", 0);
        }
    }
}

stock bool:IsValidClient(iClient)
{
    return bool:(0 < iClient && iClient <= MaxClients && IsClientInGame(iClient));
}
