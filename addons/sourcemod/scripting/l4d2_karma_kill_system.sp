#pragma semicolon 1
#include <left4dhooks>
#include <sdkhooks>
#include <sdktools>
#include <sourcemod>

#pragma newdecls required

#undef REQUIRE_PLUGIN
#undef REQUIRE_EXTENSIONS
#tryinclude < updater>    // Comment out this line to remove updater support by force.
#define REQUIRE_PLUGIN
#define REQUIRE_EXTENSIONS

#define UPDATE_URL "https://github.com/eyal282/l4d2-karma-kill-system/blob/master/addons/sourcemod/updatefile.txt"

#define PLUGIN_VERSION "1.3"

#define TEST_DEBUG     0
#define TEST_DEBUG_LOG 0

float CHARGE_CHECKING_INTERVAL = 0.1;
float ANGLE_STRAIGHT_DOWN[3]   = { 90.0, 0.0, 0.0 };
char  SOUND_EFFECT[]           = "./level/loud/climber.wav";

Handle cvarisEnabled            = INVALID_HANDLE;
Handle cvarNoFallDamageOnCarry  = INVALID_HANDLE;
// Handle triggeringHeight				= INVALID_HANDLE;
Handle chargerTimer[MAXPLAYERS] = { INVALID_HANDLE, ... };
Handle karmaTime                = INVALID_HANDLE;
Handle cvarModeSwitch           = INVALID_HANDLE;
Handle cvarCooldown             = INVALID_HANDLE;
bool   isEnabled                = true;
// float lethalHeight					= 475.0;

Handle fw_OnKarmaEventPost = INVALID_HANDLE;

int LastCharger[MAXPLAYERS + 1];
int LastJockey[MAXPLAYERS + 1];
int LastSlapper[MAXPLAYERS + 1];
int LastPuncher[MAXPLAYERS + 1];
int LastImpacter[MAXPLAYERS + 1];
int LastSmoker[MAXPLAYERS + 1];

/* Blockers have two purposes:
1. For the duration they are there, the last responsible karma maker cannot change.
2. BlockAllChange must be active to register a karma that isn't height check based. This is because it is triggered upon the survivor being hurt.
*/
bool BlockRegisterCaptor[MAXPLAYERS + 1];
bool BlockAllChange[MAXPLAYERS + 1];
bool BlockSlapChange[MAXPLAYERS + 1];
bool BlockJockChange[MAXPLAYERS + 1];
bool BlockPunchChange[MAXPLAYERS + 1];
bool BlockImpactChange[MAXPLAYERS + 1];
bool BlockSmokeChange[MAXPLAYERS + 1];

bool bAllowKarmaHardRain = false;

Handle AllKarmaRegisterTimer[MAXPLAYERS] = { INVALID_HANDLE, ... };
Handle BlockRegisterTimer[MAXPLAYERS]    = { INVALID_HANDLE, ... };
Handle SlapRegisterTimer[MAXPLAYERS]     = { INVALID_HANDLE, ... };
Handle PunchRegisterTimer[MAXPLAYERS]    = { INVALID_HANDLE, ... };
Handle ImpactRegisterTimer[MAXPLAYERS]   = { INVALID_HANDLE, ... };
Handle SmokeRegisterTimer[MAXPLAYERS]    = { INVALID_HANDLE, ... };

Handle cooldownTimer = INVALID_HANDLE;

public Plugin myinfo =
{
	name        = "L4D2 Karma Kill System",
	author      = " AtomicStryker, heavy edit by Eyal282",
	description = " Very Very loudly announces the event of either a charger charging a survivor from a high height, or any SI sending a survivor to a death by height. ",
	version     = PLUGIN_VERSION,
	url         = "http://forums.alliedmods.net/showthread.php?p=1239108"


}

public void
	OnPluginStart()
{
	HookEvent("charger_carry_start", event_ChargerGrab);
	HookEvent("charger_carry_end", event_GrabEnded);
	HookEvent("jockey_ride_end", event_jockeyRideEndPre, EventHookMode_Pre);
	HookEvent("tongue_grab", event_tongueGrabOrRelease, EventHookMode_Post);
	HookEvent("tongue_release", event_tongueGrabOrRelease, EventHookMode_Post);
	HookEvent("charger_impact", event_ChargerImpact);
	HookEvent("player_hurt", CheckFallInHardRain, EventHookMode_Post);
	HookEvent("player_death", event_playerDeathPre, EventHookMode_Pre);
	HookEvent("round_start", RoundStart, EventHookMode_PostNoCopy);
	HookEvent("success_checkpoint_button_used", DisallowCheckHardRain, EventHookMode_PostNoCopy);

	CreateConVar("l4d2_karma_charge_version", PLUGIN_VERSION, " L4D2 Karma Charge Plugin Version ");
	// triggeringHeight = 	CreateConVar("l4d2_karma_charge_height",	"475.0", 		" What Height is considered karma ");
	karmaTime               = CreateConVar("l4d2_karma_charge_slowtime", "1.5", " How long does Time get slowed ");
	cvarisEnabled           = CreateConVar("l4d2_karma_charge_enabled", "1", " Turn Karma Charge on and off ");
	cvarNoFallDamageOnCarry = CreateConVar("l4d2_karma_charge_no_fall_damage_on_carry", "1", "Fixes this by disabling fall damage when carried: https://streamable.com/xuipb6");
	cvarModeSwitch          = CreateConVar("l4d2_karma_charge_slowmode", "0", " 0 - Entire Server gets slowed, 1 - Only Charger and Survivor do ");
	cvarCooldown            = CreateConVar("l4d2_karma_charge_cooldown", "0.0", "Non-decimal number that determines how long does it take for the next karma to freeze the entire map.");

	// public void KarmaKillSystem_OnKarmaEventPost(victim, attacker, const String:KarmaName[])
	fw_OnKarmaEventPost = CreateGlobalForward("KarmaKillSystem_OnKarmaEventPost", ET_Ignore, Param_Cell, Param_Cell, Param_String);

	HookConVarChange(cvarisEnabled, _cvarChange);
	// HookConVarChange(triggeringHeight, 	_cvarChange);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;

		Func_OnClientPutInServer(i);
	}
#if defined _updater_included
	if (LibraryExists("updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
#endif
}

public void OnAllPluginsLoaded()
{
	if (!CommandExists("sm_xyz"))
		RegConsoleCmd("sm_xyz", Command_XYZ);
}

public void OnClientPutInServer(int client)
{
	Func_OnClientPutInServer(client);
}

public void Func_OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, SDKEvent_OnTakeDamage);
}

// I don't know why, but player_hurt won't trigger on incap in the boathouse finale...
public Action SDKEvent_OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype)
{
	if (damagetype == DMG_DROWN || damagetype == DMG_FALL)
	{
		BlockAllChange[victim] = true;

		if (AllKarmaRegisterTimer[victim] != INVALID_HANDLE)
		{
			CloseHandle(AllKarmaRegisterTimer[victim]);
			AllKarmaRegisterTimer[victim] = INVALID_HANDLE;
		}

		AllKarmaRegisterTimer[victim] = CreateTimer(3.0, RegisterAllKarmaDelay, victim, TIMER_FLAG_NO_MAPCHANGE);

		RegisterCaptor(victim);

		if (GetConVarBool(cvarNoFallDamageOnCarry) && L4D_GetAttackerCarry(victim) != 0)
		{
			damage = 0.0;
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}

public void OnLibraryAdded(const char[] name)
{
#if defined _updater_included
	if (StrEqual(name, "updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
#endif
}

public void OnMapStart()
{
	PrefetchSound(SOUND_EFFECT);
	PrecacheSound(SOUND_EFFECT);

	for (int i = 1; i <= MaxClients; i++)
	{
		chargerTimer[i] = INVALID_HANDLE;

		AllKarmaRegisterTimer[i] = INVALID_HANDLE;
		BlockRegisterTimer[i]    = INVALID_HANDLE;
		SlapRegisterTimer[i]     = INVALID_HANDLE;
		PunchRegisterTimer[i]    = INVALID_HANDLE;
		ImpactRegisterTimer[i]   = INVALID_HANDLE;
		SmokeRegisterTimer[i]    = INVALID_HANDLE;
	}

	cooldownTimer = INVALID_HANDLE;
	/*
	char MapName[50];
	GetCurrentMap(MapName, sizeof(MapName) - 1);
	if(StrEqual(MapName, "c3m1_plankcountry", false))
	    lethalHeight = 444.0;

	else if(StrEqual(MapName, "c4m1_milltown_a", false) || StrEqual(MapName, "c4m5_milltown_escape", false))
	    lethalHeight = 400.0;

	else if(StrEqual(MapName, "c4m2_sugarmill_a", false))
	    lethalHeight = 450.0;

	else if(StrEqual(MapName, "c11m1_greenhouse", false))
	    lethalHeight = 360.0; // Not related to angles, just a coincidence.
	*/
}

public void _cvarChange(Handle convar, const char[] oldValue, const char[] newValue)
{
	isEnabled = GetConVarBool(cvarisEnabled);
	// lethalHeight = 	GetConVarFloat(triggeringHeight);
}

public void L4D2_OnPlayerFling_Post(int victim, int attacker, float vecDir[3])
{
	if (victim < 1 || victim > MaxClients || attacker < 1 || attacker > MaxClients)
		return;

	else if (GetClientTeam(victim) != 2 || GetClientTeam(attacker) != 3)
		return;

	L4D2ZombieClassType class = L4D2_GetPlayerZombieClass(attacker);

	if (class == L4D2ZombieClass_Boomer)    // Boomer
	{
		LastSlapper[victim]       = attacker;
		BlockSlapChange[victim]   = true;
		SlapRegisterTimer[victim] = CreateTimer(0.25, RegisterSlapDelay, victim, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void L4D_TankClaw_OnPlayerHit_Post(int tank, int claw, int victim)
{
	if (victim < 1 || victim > MaxClients || tank < 1 || tank > MaxClients)
		return;

	else if (GetClientTeam(victim) != 2 || GetClientTeam(tank) != 3)
		return;

	LastPuncher[victim]        = tank;
	BlockPunchChange[victim]   = true;
	PunchRegisterTimer[victim] = CreateTimer(0.25, RegisterPunchDelay, victim, TIMER_FLAG_NO_MAPCHANGE);
}

public Action CheckFallInHardRain(Handle event, const char[] name, bool dontBroadcast)
{
	if (!bAllowKarmaHardRain)
		return Plugin_Continue;

	char MapName[25];
	GetCurrentMap(MapName, sizeof(MapName));

	if (!StrEqual(MapName, "c4m2_sugarmill_a"))
		return Plugin_Continue;

	int victim = GetClientOfUserId(GetEventInt(event, "userid"));

	int type = GetEventInt(event, "type");

	if (type == DMG_FALL)
	{
		if (isEntityInsideFakeZone(victim, 100000.0, -100000.0, -9485.0, -100000.0, 85.0, 340.0))
		{
			LastCharger[victim] = 0;

			ForcePlayerSuicide(victim);

			if (LastJockey[victim] != 0)
			{
				AnnounceKarma(LastJockey[victim], victim, "Jockey");

				return Plugin_Continue;
			}

			else if (LastSlapper[victim] != 0)
			{
				AnnounceKarma(LastSlapper[victim], victim, "Slap");

				return Plugin_Continue;
			}

			else if (LastPuncher[victim] != 0)
			{
				AnnounceKarma(LastPuncher[victim], victim, "Punch");

				return Plugin_Continue;
			}

			else if (LastSmoker[victim] != 0)
			{
				AnnounceKarma(LastSmoker[victim], victim, "Smoke");

				return Plugin_Continue;
			}

			LastJockey[victim]   = 0;
			LastSlapper[victim]  = 0;
			LastCharger[victim]  = 0;
			LastImpacter[victim] = 0;
			LastSmoker[victim]   = 0;
		}
	}

	return Plugin_Continue;
}

public Action RegisterAllKarmaDelay(Handle timer, any victim)
{
	BlockAllChange[victim] = false;

	AllKarmaRegisterTimer[victim] = INVALID_HANDLE;

	return Plugin_Continue;
}

public Action RegisterSlapDelay(Handle timer, any victim)
{
	BlockSlapChange[victim] = false;

	SlapRegisterTimer[victim] = INVALID_HANDLE;

	return Plugin_Continue;
}

public Action RegisterPunchDelay(Handle timer, any victim)
{
	BlockPunchChange[victim] = false;

	PunchRegisterTimer[victim] = INVALID_HANDLE;

	return Plugin_Continue;
}

public Action RegisterCaptorDelay(Handle timer, any victim)
{
	BlockRegisterCaptor[victim] = false;

	BlockRegisterTimer[victim] = INVALID_HANDLE;

	return Plugin_Continue;
}

public Action event_playerDeathPre(Handle event, const char[] name, bool dontBroadcast)
{
	int victim      = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker    = GetClientOfUserId(GetEventInt(event, "attacker"));
	int attackerent = GetEventInt(event, "attackerentid");

	if (victim < 1 || victim > MaxClients)    // victim >= 1 && victim <= MaxClients -> Victim is a player
		return Plugin_Continue;

	else if (!IsClientInGame(victim))    // IsClientInGame(victim) -> Victim is inside the game.
		return Plugin_Continue;

	else if (GetClientTeam(victim) != 2)    // GetClientTeam(victim) == 2 -> Victim is a survivor
		return Plugin_Continue;

	else if (attacker > 0 && attacker <= MaxClients)    // ( attacker <= 0 && attacker > MaxClients ) || attacker == victim -> Attacker is not a player, attacker can be a player if the attacker is the victim.
		return Plugin_Continue;

	FixChargeTimeleftBug();

	char Classname[50];
	GetEdictClassname(attackerent, Classname, sizeof(Classname));

	if (StrEqual(Classname, "infected", false) || StrEqual(Classname, "witch", false))
		return Plugin_Continue;

	// New by Eyal282 because any fall or drown damage trigger this block.
	else if (!BlockAllChange[victim])
		return Plugin_Continue;

	else if (LastCharger[victim] != 0)
	{
		SetEntPropEnt(LastCharger[victim], Prop_Send, "m_carryVictim", -1);
		SetEntPropEnt(LastCharger[victim], Prop_Send, "m_pummelVictim", -1);

		CreateTimer(0.1, ResetAbility, LastCharger[victim], TIMER_FLAG_NO_MAPCHANGE);

		AnnounceKarma(LastCharger[victim], victim, "Charge");

		return Plugin_Continue;
	}
	else if (LastJockey[victim] != 0)
	{
		AnnounceKarma(LastJockey[victim], victim, "Jockey");

		return Plugin_Continue;
	}

	else if (LastSlapper[victim] != 0)
	{
		AnnounceKarma(LastSlapper[victim], victim, "Slap");

		return Plugin_Continue;
	}

	else if (LastPuncher[victim] != 0)
	{
		AnnounceKarma(LastPuncher[victim], victim, "Punch");

		return Plugin_Continue;
	}

	else if (LastImpacter[victim] != 0)
	{
		AnnounceKarma(LastImpacter[victim], victim, "Impact");

		return Plugin_Continue;
	}

	else if (LastSmoker[victim] != 0)
	{
		AnnounceKarma(LastSmoker[victim], victim, "Smoke");

		return Plugin_Continue;
	}
	return Plugin_Continue;
}

public void FixChargeTimeleftBug()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;

		else if (!IsPlayerAlive(i))
			continue;

		else if (L4D_GetClientTeam(i) != L4DTeam_Infected)
			continue;

		else if (L4D2_GetPlayerZombieClass(i) != L4D2ZombieClass_Charger)
			continue;

		int iCustomAbility = L4D_GetPlayerCustomAbility(i);

		// I have no clue why it's exactly 3600.0 when it bugs, but whatever.
		if (GetEntPropFloat(iCustomAbility, Prop_Send, "m_duration") == 3600.0)
		{
			SetEntPropFloat(iCustomAbility, Prop_Send, "m_timestamp", GetGameTime());
			SetEntPropFloat(iCustomAbility, Prop_Send, "m_duration", 0.0);
		}
	}
}

public Action ResetAbility(Handle hTimer, int client)
{
	int iEntity = GetEntPropEnt(client, Prop_Send, "m_customAbility");

	if (iEntity != -1)
	{
		SetEntPropFloat(iEntity, Prop_Send, "m_timestamp", GetGameTime());
		SetEntPropFloat(iEntity, Prop_Send, "m_duration", 0.0);
	}

	return Plugin_Continue;
}

public Action RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	bAllowKarmaHardRain = true;

	return Plugin_Continue;
}

public Action DisallowCheckHardRain(Handle event, const char[] name, bool dontBroadcast)
{
	bAllowKarmaHardRain = false;

	return Plugin_Continue;
}

public Action Command_XYZ(int client, int args)
{
	float Origin[3];
	GetEntPropVector(client, Prop_Data, "m_vecOrigin", Origin);

	PrintToChat(client, "%.4f, %.4f, %.4f", Origin[0], Origin[1], Origin[2]);

	return Plugin_Continue;
}

public void OnGameFrame()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (BlockAllChange[i])
			continue;

		else if (LastCharger[i] == 0 && LastJockey[i] == 0 && LastSlapper[i] == 0 && LastPuncher[i] == 0 && LastImpacter[i] == 0 && LastSmoker[i] == 0)
			continue;

		if (!IsClientInGame(i))
			continue;

		else if (!IsPlayerAlive(i))
			continue;

		else if (!(GetEntityFlags(i) & FL_ONGROUND))
			continue;

		else if (GetEntProp(i, Prop_Send, "m_isHangingFromLedge") || GetEntProp(i, Prop_Send, "m_isFallingFromLedge"))
			continue;

		else if (IsClientAffectedByFling(i))
			continue;

		else if (L4D_IsPlayerStaggering(i))
			continue;

		if (LastCharger[i] != 0 && !IsPinnedByCharger(i))
		{
			LastCharger[i] = 0;
		}

		else if (!BlockJockChange[i] && LastJockey[i] != 0)
			LastJockey[i] = 0;

		else if (LastSlapper[i] != 0 && SlapRegisterTimer[i] == INVALID_HANDLE && !BlockSlapChange[i])
			LastSlapper[i] = 0;

		else if (LastPuncher[i] != 0 && PunchRegisterTimer[i] == INVALID_HANDLE && !BlockPunchChange[i])
			LastPuncher[i] = 0;

		else if (LastImpacter[i] != 0 && ImpactRegisterTimer[i] == INVALID_HANDLE && !BlockImpactChange[i])
			LastImpacter[i] = 0;

		else if (LastSmoker[i] != 0 && SmokeRegisterTimer[i] == INVALID_HANDLE && !BlockSmokeChange[i])
			LastSmoker[i] = 0;
	}
}

public Action event_ChargerGrab(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!isEnabled
	    || !client
	    || !IsClientInGame(client))
	{
		return Plugin_Continue;
	}

	int victim = GetClientOfUserId(GetEventInt(event, "victim"));

	LastCharger[victim] = client;

	DebugPrintToAll("Charger Carry event caught, initializing timer");

	if (chargerTimer[client] != INVALID_HANDLE)
	{
		CloseHandle(chargerTimer[client]);
		chargerTimer[client] = INVALID_HANDLE;
	}

	chargerTimer[client] = CreateTimer(CHARGE_CHECKING_INTERVAL, _timer_Check, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	TriggerTimer(chargerTimer[client], true);

	return Plugin_Continue;
}

public Action event_GrabEnded(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int victim = GetClientOfUserId(GetEventInt(event, "victim"));

	if (chargerTimer[client] != INVALID_HANDLE)
	{
		CloseHandle(chargerTimer[client]);
		chargerTimer[client] = INVALID_HANDLE;
	}

	char MapName[50];
	GetCurrentMap(MapName, sizeof(MapName));

	if (StrEqual(MapName, "c10m4_mainstreet", false) && isEntityInsideFakeZone(client, -2720.0, -1665.0, -340.0, 1200.0, -75.0, 162.0) && GetEntProp(victim, Prop_Send, "m_isFallingFromLedge") == 0 && IsPlayerAlive(victim))
	{
		LastCharger[victim]  = 0;
		LastJockey[victim]   = 0;
		LastSlapper[victim]  = 0;
		LastPuncher[victim]  = 0;
		LastImpacter[victim] = 0;
		LastSmoker[victim]   = 0;

		SetEntProp(victim, Prop_Send, "m_isFallingFromLedge", 1);    // Makes his body impossible to defib.

		ForcePlayerSuicide(victim);

		AnnounceKarma(client, victim, "Charge");
	}

	else if (StrEqual(MapName, "c4m2_sugarmill_a", false) && isEntityInsideFakeZone(client, 100000.0, -100000.0, -9485.0, -100000.0, 85.0, 340.0) && bAllowKarmaHardRain)
	{
		LastCharger[victim]  = 0;
		LastJockey[victim]   = 0;
		LastSlapper[victim]  = 0;
		LastPuncher[victim]  = 0;
		LastImpacter[victim] = 0;
		LastSmoker[victim]   = 0;

		SetEntPropEnt(victim, Prop_Send, "m_carryAttacker", -1);
		SetEntPropEnt(victim, Prop_Send, "m_pummelAttacker", -1);
		for (int i = 1; i <= MaxClients; i++)    // Due to stealing from a charger bug ( irrelevant on vanilla servers )
		{
			if (!IsClientInGame(i))
				continue;

			else if (GetClientTeam(i) != 3)
				continue;

			else if (GetEntProp(i, Prop_Send, "m_zombieClass") != 6)
				continue;

			if (GetEntPropEnt(i, Prop_Send, "m_carryVictim") == victim)
				SetEntPropEnt(i, Prop_Send, "m_carryVictim", -1);

			if (GetEntPropEnt(i, Prop_Send, "m_pummelVictim") == victim)
				SetEntPropEnt(i, Prop_Send, "m_pummelVictim", -1);
		}
		float Origin[3];
		GetEntPropVector(client, Prop_Data, "m_vecOrigin", Origin);
		TeleportEntity(victim, Origin, NULL_VECTOR, NULL_VECTOR);

		int iEntity = GetEntPropEnt(client, Prop_Send, "m_customAbility");

		if (iEntity != -1 && IsValidEntity(iEntity))
		{
			SetEntPropFloat(iEntity, Prop_Send, "m_timestamp", GetGameTime());
			SetEntPropFloat(iEntity, Prop_Send, "m_duration", 0.0);
		}

		ForcePlayerSuicide(victim);
	}

	return Plugin_Continue;
}

public Action event_ChargerImpact(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int victim = GetClientOfUserId(GetEventInt(event, "victim"));

	if (GetEntPropEnt(victim, Prop_Send, "m_carryAttacker") == -1)
		LastImpacter[victim] = client;

	return Plugin_Continue;
}

public Action event_jockeyRideEndPre(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int victim = GetClientOfUserId(GetEventInt(event, "victim"));

	char MapName[50];

	GetCurrentMap(MapName, sizeof(MapName));

	if ((StrEqual(MapName, "c6m2_bedlam", false) && isEntityInsideFakeZone(victim, 2319.031250, 2448.96875, -1296.031250, -1345.0, -2.0, -128.0) && GetEntProp(victim, Prop_Send, "m_isFallingFromLedge") == 0 && IsPlayerAlive(victim)))
	{
		LastJockey[victim]  = 0;
		LastCharger[victim] = 0;
		LastSlapper[victim] = 0;
		LastPuncher[victim] = 0;
		LastSmoker[victim]  = 0;

		SetEntProp(victim, Prop_Send, "m_isFallingFromLedge", 1);    // Makes his body impossible to defib.

		ForcePlayerSuicide(victim);

		AnnounceKarma(client, victim, "Jockey");

		return Plugin_Continue;
	}

	BlockJockChange[victim] = true;

	LastJockey[victim] = client;

	CreateTimer(0.7, EndLastJockey, victim, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Continue;
}

public Action EndLastJockey(Handle timer, any victim)
{
	BlockJockChange[victim] = false;

	return Plugin_Continue;
}

public Action event_tongueGrabOrRelease(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int victim = GetClientOfUserId(GetEventInt(event, "victim"));

	if (client == 0 || victim == 0)
		return Plugin_Continue;

	Handle DP = CreateDataPack();

	WritePackCell(DP, client);
	WritePackCell(DP, victim);

	RequestFrame(Frame_TongueRelease, DP);

	return Plugin_Continue;
}

public void Frame_TongueRelease(Handle DP)
{
	ResetPack(DP);

	int client = ReadPackCell(DP);
	int victim = ReadPackCell(DP);

	CloseHandle(DP);

	if (!IsClientInGame(client) || !IsClientInGame(victim))
		return;

	if (!IsPlayerAlive(victim))
		return;

	BlockSmokeChange[victim] = true;
	LastSmoker[victim]       = client;

	CreateTimer(0.7, EndLastSmoker, victim, TIMER_FLAG_NO_MAPCHANGE);

	return;
}

public Action EndLastSmoker(Handle timer, any victim)
{
	BlockSmokeChange[victim] = false;

	return Plugin_Continue;
}

public Action _timer_Check(Handle timer, any client)
{
	if (!client || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		chargerTimer[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}

	if (GetEntityFlags(client) & FL_ONGROUND) return Plugin_Continue;

	float fOrigin[3], fEndOrigin[3];
	GetEntPropVector(client, Prop_Data, "m_vecOrigin", fOrigin);

	ArrayList aEntities = new ArrayList(1);

	TR_TraceRayFilter(fOrigin, ANGLE_STRAIGHT_DOWN, MASK_SHOT, RayType_Infinite, TraceFilter_DontHitPlayers);

	TR_GetEndPosition(fEndOrigin);

	TR_EnumerateEntities(fOrigin, fEndOrigin, PARTITION_SOLID_EDICTS | PARTITION_TRIGGER_EDICTS | PARTITION_STATIC_PROPS, RayType_EndPoint, TraceEnum_TriggerHurt, aEntities);

	int iSize = GetArraySize(aEntities);
	delete aEntities;

	if (iSize > 0)
	{
		AnnounceKarma(client, -1, "Charge");
		chargerTimer[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public bool TraceFilter_DontHitPlayers(int entity, int contentsMask)
{
	return !IsEntityPlayer(entity);
}

public bool TraceEnum_TriggerHurt(int entity, ArrayList aEntities)
{
	// If we hit the world, stop enumerating.
	if (!entity)
		return false;

	else if (!IsValidEdict(entity))
		return false;

	char sClassname[16];
	GetEdictClassname(entity, sClassname, sizeof(sClassname));

	// Also works for trigger_hurt_ghost because some maps wager on the fact trigger_hurt_ghost kills the charger and the survivors dies from the fall itself.
	if (strncmp(sClassname, "trigger_hurt", 12) != 0)
		return true;

	TR_ClipCurrentRayToEntity(MASK_ALL, entity);

	if (TR_GetEntityIndex() != entity)
		return true;

	float fDamage = GetEntPropFloat(entity, Prop_Data, "m_flDamage");

	// Does it do incap damage?
	if (fDamage < 100)
		return true;

	int iDamagetype = GetEntProp(entity, Prop_Data, "m_bitsDamageInflict");

	// Does it simulate a fall or water?
	if (iDamagetype != DMG_FALL && iDamagetype != DMG_DROWN)
		return true;

	aEntities.Push(entity);

	return true;
}
void AnnounceKarma(int client, int victim = -1, char[] KarmaName)
{
	if (victim == -1 && GetEntProp(client, Prop_Send, "m_zombieClass") == 6)
	{
		victim = GetCarryVictim(client);
	}
	if (victim == -1) return;

	EmitSoundToAll(SOUND_EFFECT);

	LastCharger[victim] = 0;
	LastJockey[victim]  = 0;
	LastSlapper[victim] = 0;
	LastPuncher[victim] = 0;
	LastSmoker[victim]  = 0;

	// Enforces a one karma per 15 seconds per victim, exlcuding height checkers.
	BlockRegisterCaptor[victim] = true;

	if (BlockRegisterTimer[victim] != INVALID_HANDLE)
	{
		CloseHandle(BlockRegisterTimer[victim]);
		BlockRegisterTimer[victim] = INVALID_HANDLE;
	}

	BlockRegisterTimer[victim] = CreateTimer(15.0, RegisterCaptorDelay, victim, TIMER_FLAG_NO_MAPCHANGE);

	if (GetConVarBool(cvarModeSwitch) || cooldownTimer != INVALID_HANDLE)
		SlowChargeCouple(client);

	else
	{
		cooldownTimer = CreateTimer(GetConVarFloat(cvarCooldown), RestoreSlowmo, _, TIMER_FLAG_NO_MAPCHANGE);
		SlowTime();
	}

	PrintToChatAll("\x03%N\x01 Karma %s'd\x04 %N\x01, for great justice!!", client, KarmaName, victim);

	Call_StartForward(fw_OnKarmaEventPost);

	Call_PushCell(victim);
	Call_PushCell(client);
	Call_PushString(KarmaName);

	Call_Finish();

	if (GetEntPropEnt(client, Prop_Send, "m_carryVictim") == victim)
	{
		int Jockey = GetEntPropEnt(victim, Prop_Send, "m_jockeyAttacker");

		if (Jockey != -1)
		{
			SetEntPropEnt(Jockey, Prop_Send, "m_jockeyVictim", -1);
			SetEntPropEnt(victim, Prop_Send, "m_jockeyAttacker", -1);

			LastJockey[victim] = 0;
		}
	}
}

public Action RestoreSlowmo(Handle Timer)
{
	cooldownTimer = INVALID_HANDLE;

	return Plugin_Continue;
}

stock void SlowChargeCouple(int client)
{
	int target = GetCarryVictim(client);
	if (target == -1) return;

	SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 0.2);
	SetEntPropFloat(target, Prop_Send, "m_flLaggedMovementValue", 0.2);

	Handle data = CreateDataPack();
	WritePackCell(data, client);
	WritePackCell(data, target);

	CreateTimer(GetConVarFloat(karmaTime), _revertCoupleTimeSlow, data, TIMER_FLAG_NO_MAPCHANGE);
}

public Action _revertCoupleTimeSlow(Handle timer, Handle data)
{
	ResetPack(data);
	int client = ReadPackCell(data);
	int target = ReadPackCell(data);
	CloseHandle(data);

	if (IsClientInGame(client))
	{
		SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 1.0);
	}

	if (IsClientInGame(target))
	{
		SetEntPropFloat(target, Prop_Send, "m_flLaggedMovementValue", 1.0);
	}

	return Plugin_Continue;
}

stock bool IsPinnedByCharger(int client)
{
	return GetEntPropEnt(client, Prop_Send, "m_carryAttacker") != -1 || GetEntPropEnt(client, Prop_Send, "m_pummelAttacker") != -1;
}

stock int GetCarryVictim(int client)
{
	int victim = GetEntPropEnt(client, Prop_Send, "m_carryVictim");
	if (victim < 1
	    || victim > MaxClients
	    || !IsClientInGame(victim))
	{
		return -1;
	}

	return victim;
}

stock void SlowTime(const char[] desiredTimeScale = "0.2", const char[] re_Acceleration = "2.0", const char[] minBlendRate = "1.0", const char[] blendDeltaMultiplier = "2.0")
{
	int ent = CreateEntityByName("func_timescale");

	DispatchKeyValue(ent, "desiredTimescale", desiredTimeScale);
	DispatchKeyValue(ent, "acceleration", re_Acceleration);
	DispatchKeyValue(ent, "minBlendRate", minBlendRate);
	DispatchKeyValue(ent, "blendDeltaMultiplier", blendDeltaMultiplier);

	DispatchSpawn(ent);
	AcceptEntityInput(ent, "Start");

	CreateTimer(GetConVarFloat(karmaTime), _revertTimeSlow, ent, TIMER_FLAG_NO_MAPCHANGE);
}

public Action _revertTimeSlow(Handle timer, any ent)
{
	if (IsValidEdict(ent))
	{
		AcceptEntityInput(ent, "Stop");
	}

	return Plugin_Continue;
}

stock void DebugPrintToAll(const char[] format, any...)
{
#if (TEST_DEBUG || TEST_DEBUG_LOG)
	char buffer[256];

	VFormat(buffer, sizeof(buffer), format, 2);

	#if TEST_DEBUG
	PrintToChatAll("[KARMA] %s", buffer);
	PrintToConsole(0, "[KARMA] %s", buffer);
	#endif

	LogMessage("%s", buffer);
#else
	// suppress "format" never used warning
	if (format[0])
		return;
	else
		return;
#endif
}

stock bool isEntityInsideFakeZone(int entity, float xOriginWall, float xOriginParallelWall, float yOriginWall2, float yOriginParallelWall2, float zOriginCeiling, float zOriginFloor)
{
	if (!IsValidEntity(entity))
		ThrowError("Entity %i is not valid!", entity);

	float Origin[3];
	GetEntPropVector(entity, Prop_Data, "m_vecOrigin", Origin);

	if ((Origin[0] >= xOriginWall && Origin[0] <= xOriginParallelWall) || (Origin[0] <= xOriginWall && Origin[0] >= xOriginParallelWall))
	{
		if ((Origin[1] >= yOriginWall2 && Origin[1] <= yOriginParallelWall2) || (Origin[1] <= yOriginWall2 && Origin[1] >= yOriginParallelWall2))
		{
			if ((Origin[2] >= zOriginFloor && Origin[2] <= zOriginCeiling) || (Origin[2] <= zOriginFloor && Origin[2] >= zOriginCeiling))
			{
				return true;
			}
		}
	}

	return false;
}

bool IsClientAffectedByFling(int client)
{
	char model[PLATFORM_MAX_PATH];
	GetEntPropString(client, Prop_Data, "m_ModelName", model, PLATFORM_MAX_PATH);
	switch (model[29])
	{
		case 'b':    // nick
		{
			switch (GetEntProp(client, Prop_Send, "m_nSequence"))
			{
				case 661, 667, 669, 671, 672, 627, 628, 629, 630, 620:
					return true;
			}
		}
		case 'd':    // rochelle
		{
			switch (GetEntProp(client, Prop_Send, "m_nSequence"))
			{
				case 668, 674, 676, 678, 679, 635, 636, 637, 638, 629:
					return true;
			}
		}
		case 'c':    // coach
		{
			switch (GetEntProp(client, Prop_Send, "m_nSequence"))
			{
				case 650, 656, 658, 660, 661, 627, 628, 629, 630, 621:
					return true;
			}
		}
		case 'h':    // ellis
		{
			switch (GetEntProp(client, Prop_Send, "m_nSequence"))
			{
				case 665, 671, 673, 675, 676, 632, 633, 634, 635, 625:
					return true;
			}
		}
		case 'v':    // bill
		{
			switch (GetEntProp(client, Prop_Send, "m_nSequence"))
			{
				case 753, 759, 761, 763, 764, 535, 536, 537, 538, 528:
					return true;
			}
		}
		case 'n':    // zoey
		{
			switch (GetEntProp(client, Prop_Send, "m_nSequence"))
			{
				case 813, 819, 821, 823, 824, 544, 545, 546, 547, 537:
					return true;
			}
		}
		case 'e':    // francis
		{
			switch (GetEntProp(client, Prop_Send, "m_nSequence"))
			{
				case 756, 762, 764, 766, 767, 538, 539, 540, 541, 531:
					return true;
			}
		}
		case 'a':    // louis
		{
			switch (GetEntProp(client, Prop_Send, "m_nSequence"))
			{
				case 753, 759, 761, 763, 764, 535, 536, 537, 538, 528:
					return true;
			}
		}
	}
	return false;
}

stock void PrintToChatEyal(const char[] format, any...)
{
	char buffer[291];
	VFormat(buffer, sizeof(buffer), format, 2);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;

		else if (IsFakeClient(i))
			continue;

		char steamid[64];
		GetClientAuthId(i, AuthId_Engine, steamid, sizeof(steamid));

		if (StrEqual(steamid, "STEAM_1:0:49508144"))
			PrintToChat(i, buffer);
	}
}

stock void PrintToChatRadius(int target, const char[] format, any...)
{
	char buffer[291];
	VFormat(buffer, sizeof(buffer), format, 3);

	float fTargetOrigin[3];
	GetEntPropVector(target, Prop_Data, "m_vecOrigin", fTargetOrigin);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;

		else if (IsFakeClient(i))
			continue;

		float fOrigin[3];
		GetEntPropVector(i, Prop_Data, "m_vecOrigin", fOrigin);

		if (GetVectorDistance(fTargetOrigin, fOrigin, false) < 512.0)
			PrintToChat(i, buffer);
	}
}

stock void RegisterCaptor(int victim)
{
	if (BlockRegisterCaptor[victim])
		return;

	int charger = L4D_GetAttackerCharger(victim);

	if (charger == 0)
		charger = L4D_GetAttackerCarry(victim);

	int jockey = L4D_GetAttackerJockey(victim);
	int smoker = L4D_GetAttackerSmoker(victim);

	if (charger != 0)
		LastCharger[victim] = charger;

	if (jockey != 0)
		LastJockey[victim] = jockey;

	if (smoker != 0)
		LastSmoker[victim] = smoker;
}

stock bool IsEntityPlayer(int entity)
{
	if (entity <= 0)
		return false;

	else if (entity > MaxClients)
		return false;

	return true;
}
