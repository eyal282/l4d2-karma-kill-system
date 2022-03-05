#include <autoexecconfig>
#include <left4dhooks>
#include <sdkhooks>
#include <sdktools>
#include <sourcemod>

#pragma newdecls required
#pragma semicolon 1

#undef REQUIRE_PLUGIN
#undef REQUIRE_EXTENSIONS
#tryinclude < updater>    // Comment out this line to remove updater support by force.
#define REQUIRE_PLUGIN
#define REQUIRE_EXTENSIONS

#define UPDATE_URL "https://raw.githubusercontent.com/eyal282/l4d2-karma-kill-system/master/addons/sourcemod/updatefile.txt"

#define PLUGIN_VERSION "1.5"

#define TEST_DEBUG     0
#define TEST_DEBUG_LOG 0

// All of these must be 0.1 * n, basically 0.1, 0.2, 0.3, 0.4...
// Jockey Jump uses seconds needed per 500 units.
float JOCKEY_JUMP_SECONDS_NEEDED_AGAINST_LEDGE_HANG_PER_FORCE = 1.0;
float IMPACT_SECONDS_NEEDED_AGAINST_LEDGE_HANG                = 0.3;
float PUNCH_SECONDS_NEEDED_AGAINST_LEDGE_HANG                 = 0.3;
float FLING_SECONDS_NEEDED_AGAINST_LEDGE_HANG                 = 0.7;
float CHARGE_CHECKING_INTERVAL                                = 0.1;

float ANGLE_STRAIGHT_DOWN[3] = { 90.0, 0.0, 0.0 };
char  SOUND_EFFECT[]         = "./level/loud/climber.wav";

Handle cvarisEnabled            = INVALID_HANDLE;
Handle cvarNoFallDamageOnCarry  = INVALID_HANDLE;
// Handle triggeringHeight				= INVALID_HANDLE;
Handle chargerTimer[MAXPLAYERS] = { INVALID_HANDLE, ... };
Handle victimTimer[MAXPLAYERS]  = { INVALID_HANDLE, ... };

Handle karmaPrefix           = INVALID_HANDLE;
Handle karmaSlowTimeOnServer = INVALID_HANDLE;
Handle karmaSlowTimeOnCouple = INVALID_HANDLE;
Handle karmaSlow             = INVALID_HANDLE;
Handle cvarModeSwitch        = INVALID_HANDLE;
Handle cvarCooldown          = INVALID_HANDLE;
bool   isEnabled             = true;
// float lethalHeight					= 475.0;

Handle fw_OnKarmaEventPost = INVALID_HANDLE;

int LastCharger[MAXPLAYERS + 1];
int LastJockey[MAXPLAYERS + 1];
int LastSlapper[MAXPLAYERS + 1];
int LastPuncher[MAXPLAYERS + 1];
int LastImpacter[MAXPLAYERS + 1];
int LastSmoker[MAXPLAYERS + 1];

float apexHeight[MAXPLAYERS + 1];
/* Blockers have two purposes:
1. For the duration they are there, the last responsible karma maker cannot change.
2. BlockAllChange must be active to register a karma that isn't height check based. This is because it is triggered upon the survivor being hurt.
*/
bool  BlockRegisterCaptor[MAXPLAYERS + 1];
bool  BlockAllChange[MAXPLAYERS + 1];
bool  BlockSlapChange[MAXPLAYERS + 1];
bool  BlockJockChange[MAXPLAYERS + 1];
bool  BlockPunchChange[MAXPLAYERS + 1];
bool  BlockImpactChange[MAXPLAYERS + 1];
bool  BlockSmokeChange[MAXPLAYERS + 1];

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
	description = " Very Very loudly announces the predicted event of a player leaving the map and or life through height or drown. ",
	version     = PLUGIN_VERSION,
	url         = "http://forums.alliedmods.net/showthread.php?p=1239108"

};

public void OnPluginStart()
{
	HookEvent("charger_carry_start", event_ChargerGrab, EventHookMode_Post);
	HookEvent("charger_carry_end", event_GrabEnded, EventHookMode_Post);
	HookEvent("jockey_ride_end", event_jockeyRideEndPre, EventHookMode_Pre);
	HookEvent("tongue_grab", event_tongueGrabOrRelease, EventHookMode_Post);
	HookEvent("tongue_release", event_tongueGrabOrRelease, EventHookMode_Post);
	HookEvent("charger_impact", event_ChargerImpact, EventHookMode_Post);
	HookEvent("player_hurt", CheckFallInHardRain, EventHookMode_Post);
	HookEvent("player_ledge_grab", Event_PlayerLedgeGrab, EventHookMode_Post);
	HookEvent("player_death", event_playerDeathPre, EventHookMode_Pre);
	HookEvent("round_start", RoundStart, EventHookMode_PostNoCopy);
	HookEvent("success_checkpoint_button_used", DisallowCheckHardRain, EventHookMode_PostNoCopy);

	AutoExecConfig_SetFile("l4d2_karma_kill_system");

	CreateConVar("l4d2_karma_charge_version", PLUGIN_VERSION, " L4D2 Karma Charge Plugin Version ", FCVAR_DONTRECORD);
	// triggeringHeight = 	AutoExecConfig_CreateConVar("l4d2_karma_charge_height",	"475.0", 		" What Height is considered karma ");
	karmaPrefix             = AutoExecConfig_CreateConVar("l4d2_karma_charge_prefix", "", "Prefix for announcements. For colors, replace the side the slash points towards, example is /x04[/x05KarmaCharge/x03]");
	karmaSlowTimeOnServer   = AutoExecConfig_CreateConVar("l4d2_karma_charge_slowtime_on_server", "5.0", " How long does Time get slowed for the server");
	karmaSlowTimeOnCouple   = AutoExecConfig_CreateConVar("l4d2_karma_charge_slowtime_on_couple", "3.0", " How long does Time get slowed for the karma couple");
	karmaSlow               = AutoExecConfig_CreateConVar("l4d2_karma_charge_slowspeed", "0.2", " How slow Time gets. Hardwired to minimum 0.1 or the server crashes", _, true, 0.1);
	cvarisEnabled           = AutoExecConfig_CreateConVar("l4d2_karma_charge_enabled", "1", " Turn Karma Charge on and off ");
	cvarNoFallDamageOnCarry = AutoExecConfig_CreateConVar("l4d2_karma_charge_no_fall_damage_on_carry", "1", "Fixes this by disabling fall damage when carried: https://streamable.com/xuipb6");
	cvarModeSwitch          = AutoExecConfig_CreateConVar("l4d2_karma_charge_slowmode", "0", " 0 - Entire Server gets slowed, 1 - Only Charger and Survivor do", _, true, 0.0, true, 1.0);
	cvarCooldown            = AutoExecConfig_CreateConVar("l4d2_karma_charge_cooldown", "0.0", "If slowmode is 0, how long does it take for the next karma to freeze the entire map. Begins counting from the end of the previous freeze");

	// This makes an internal call to AutoExecConfig with the given configfile
	AutoExecConfig_ExecuteFile();

	// Cleaning should be done at the end
	AutoExecConfig_CleanFile();

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

public void OnClientDisconnect(int client)
{
	if (chargerTimer[client] != INVALID_HANDLE)
	{
		CloseHandle(chargerTimer[client]);
		chargerTimer[client] = INVALID_HANDLE;
	}

	if (victimTimer[client] != INVALID_HANDLE)
	{
		CloseHandle(victimTimer[client]);
		victimTimer[client] = INVALID_HANDLE;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (LastCharger[i] == client)
			LastCharger[i] = 0;

		if (LastJockey[i] == client)
			LastJockey[i] = 0;

		if (LastSlapper[i] == client)
			LastSlapper[i] = 0;

		if (LastPuncher[i] == client)
			LastPuncher[i] = 0;

		if (LastImpacter[i] == client)
			LastImpacter[i] = 0;

		if (LastSmoker[i] == client)
			LastSmoker[i] = 0;
	}
}

public void OnMapStart()
{
	PrefetchSound(SOUND_EFFECT);
	PrecacheSound(SOUND_EFFECT);

	for (int i = 1; i <= MaxClients; i++)
	{
		chargerTimer[i] = INVALID_HANDLE;
		victimTimer[i]  = INVALID_HANDLE;

		AllKarmaRegisterTimer[i] = INVALID_HANDLE;
		BlockRegisterTimer[i]    = INVALID_HANDLE;
		SlapRegisterTimer[i]     = INVALID_HANDLE;
		PunchRegisterTimer[i]    = INVALID_HANDLE;
		ImpactRegisterTimer[i]   = INVALID_HANDLE;
		SmokeRegisterTimer[i]    = INVALID_HANDLE;

		apexHeight[i] = -65535.0;
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

public void Plugins_OnJockeyJumpPost(int victim, int jockey, float fForce)
{
	BlockJockChange[victim] = true;

	LastJockey[victim] = jockey;

	CreateTimer(0.7, EndLastJockey, victim, TIMER_FLAG_NO_MAPCHANGE);

	if (victimTimer[victim] != INVALID_HANDLE)
	{
		CloseHandle(victimTimer[victim]);
		victimTimer[victim] = INVALID_HANDLE;
	}

	DataPack DP;
	victimTimer[victim] = CreateDataTimer(CHARGE_CHECKING_INTERVAL, Timer_CheckVictim, DP, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);

	DP.WriteFloat(JOCKEY_JUMP_SECONDS_NEEDED_AGAINST_LEDGE_HANG_PER_FORCE * (fForce / 500.0));
	DP.WriteCell(victim);
}

public void L4D2_OnPlayerFling_Post(int victim, int attacker, float vecDir[3])
{
	if (victim < 1 || victim > MaxClients || attacker < 1 || attacker > MaxClients)
		return;

	else if (L4D_GetClientTeam(victim) != L4DTeam_Survivor || L4D_GetClientTeam(attacker) != L4DTeam_Infected)
		return;

	L4D2ZombieClassType class = L4D2_GetPlayerZombieClass(attacker);

	if (class == L4D2ZombieClass_Boomer)    // Boomer
	{
		LastSlapper[victim]       = attacker;
		BlockSlapChange[victim]   = true;
		SlapRegisterTimer[victim] = CreateTimer(0.25, RegisterSlapDelay, victim, TIMER_FLAG_NO_MAPCHANGE);

		if (victimTimer[victim] != INVALID_HANDLE)
		{
			CloseHandle(victimTimer[victim]);
			victimTimer[victim] = INVALID_HANDLE;
		}

		DataPack DP;
		victimTimer[victim] = CreateDataTimer(CHARGE_CHECKING_INTERVAL, Timer_CheckVictim, DP, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);

		DP.WriteFloat(FLING_SECONDS_NEEDED_AGAINST_LEDGE_HANG);
		DP.WriteCell(victim);
	}
}

public Action Timer_CheckVictim(Handle timer, DataPack DP)
{
	DP.Reset();

	float secondsLeft = DP.ReadFloat();
	int   client      = DP.ReadCell();

	if (!client || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		victimTimer[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}

	char sKarmaName[32];
	int  lastKarma = GetAnyLastKarma(client, sKarmaName, sizeof(sKarmaName));
	if (lastKarma == 0)
	{
		victimTimer[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}

	else if (GetEntProp(client, Prop_Send, "m_isHangingFromLedge"))
	{
		victimTimer[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}

	float fOrigin[3], fEndOrigin[3], fMins[3], fMaxs[3];
	GetEntPropVector(client, Prop_Data, "m_vecOrigin", fOrigin);

	GetClientMins(client, fMins);
	GetClientMaxs(client, fMaxs);

	TR_TraceRayFilter(fOrigin, ANGLE_STRAIGHT_DOWN, MASK_SHOT, RayType_Infinite, TraceFilter_DontHitPlayers);

	TR_GetEndPosition(fEndOrigin);

	// Now try again with hull to avoid funny stuff.
	TR_TraceHullFilter(fOrigin, fEndOrigin, fMins, fMaxs, MASK_SHOT, TraceFilter_DontHitPlayers);

	TR_GetEndPosition(fEndOrigin);

	// You must EXCEED 340.0 height fall damage to instantly die at 100 health.

	if (!CanClientSurviveFall(client, apexHeight[client] - fEndOrigin[2]))
	{
		if (secondsLeft <= 0.0)
		{
			AnnounceKarma(lastKarma, client, sKarmaName);
			victimTimer[client] = INVALID_HANDLE;
			return Plugin_Stop;
		}
		else
		{
			secondsLeft -= CHARGE_CHECKING_INTERVAL;

			DP.Reset();

			DP.WriteFloat(secondsLeft);
		}
	}
	// No height? Maybe we can find some useful trigger_hurt.
	else
	{
		ArrayList aEntities = new ArrayList(1);

		TR_EnumerateEntities(fOrigin, fEndOrigin, PARTITION_SOLID_EDICTS | PARTITION_TRIGGER_EDICTS | PARTITION_STATIC_PROPS, RayType_EndPoint, TraceEnum_TriggerHurt, aEntities);

		int iSize = GetArraySize(aEntities);
		delete aEntities;

		if (iSize > 0)
		{
			if (secondsLeft <= 0.0)
			{
				AnnounceKarma(lastKarma, client, sKarmaName);
				victimTimer[client] = INVALID_HANDLE;
				return Plugin_Stop;
			}
			else
			{
				secondsLeft -= CHARGE_CHECKING_INTERVAL;

				DP.Reset();

				DP.WriteFloat(secondsLeft);
			}
		}
	}

	return Plugin_Continue;
}

public void L4D_TankClaw_OnPlayerHit_Post(int tank, int claw, int victim)
{
	if (victim < 1 || victim > MaxClients || tank < 1 || tank > MaxClients)
		return;

	else if (L4D_GetClientTeam(victim) != L4DTeam_Survivor || L4D_GetClientTeam(tank) != L4DTeam_Infected)
		return;

	LastPuncher[victim]        = tank;
	BlockPunchChange[victim]   = true;
	PunchRegisterTimer[victim] = CreateTimer(0.25, RegisterPunchDelay, victim, TIMER_FLAG_NO_MAPCHANGE);

	if (victimTimer[victim] != INVALID_HANDLE)
	{
		CloseHandle(victimTimer[victim]);
		victimTimer[victim] = INVALID_HANDLE;
	}

	DataPack DP;
	victimTimer[victim] = CreateDataTimer(CHARGE_CHECKING_INTERVAL, Timer_CheckVictim, DP, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);

	DP.WriteFloat(PUNCH_SECONDS_NEEDED_AGAINST_LEDGE_HANG);
	DP.WriteCell(victim);
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

	if (victim == 0)
		return Plugin_Continue;

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

public Action Event_PlayerLedgeGrab(Handle event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));

	if (victim == 0)
		return Plugin_Continue;

	char sKarmaName[32];
	int  lastKarma = GetAnyLastKarma(victim, sKarmaName, sizeof(sKarmaName));

	if (lastKarma == 0)
		return Plugin_Continue;

	CreateTimer(0.1, Timer_CheckLedgeChange, GetClientUserId(victim), TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);

	return Plugin_Continue;
}

public Action Timer_CheckLedgeChange(Handle hTimer, int userId)
{
	int victim = GetClientOfUserId(userId);

	if (victim == 0)
		return Plugin_Stop;

	else if (!IsPlayerAlive(victim))
		return Plugin_Stop;

	else if (L4D_GetClientTeam(victim) != L4DTeam_Survivor)
		return Plugin_Stop;

	if (GetEntProp(victim, Prop_Send, "m_isFallingFromLedge"))
	{
		char sKarmaName[32];
		int  lastKarma = GetAnyLastKarma(victim, sKarmaName, sizeof(sKarmaName));

		if (lastKarma == 0)
			return Plugin_Stop;

		AnnounceKarma(lastKarma, victim, sKarmaName);
		return Plugin_Stop;
	}
	else if (GetEntProp(victim, Prop_Send, "m_isHangingFromLedge"))
		return Plugin_Continue;

	else
		return Plugin_Stop;
}

public Action event_playerDeathPre(Handle event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));

	if (victim == 0)    // Are the victim and attacker player?
		return Plugin_Continue;

	else if (L4D_GetClientTeam(victim) != L4DTeam_Survivor)    // L4D_GetClientTeam(victim) == 2 -> Victim is a survivor
		return Plugin_Continue;

	FixChargeTimeleftBug();

	// New by Eyal282 because any fall or drown damage trigger this block.

	if (!BlockAllChange[victim])
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

	return Plugin_Handled;
}

public void OnGameFrame()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			if (GetEntityFlags(i) & FL_ONGROUND)
				apexHeight[i] = -65535.0;

			else
			{
				float fOrigin[3];

				GetEntPropVector(i, Prop_Data, "m_vecOrigin", fOrigin);

				if (fOrigin[2] > apexHeight[i])
					apexHeight[i] = fOrigin[2];
			}

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

			if (GetEntProp(i, Prop_Send, "m_isHangingFromLedge") || GetEntProp(i, Prop_Send, "m_isFallingFromLedge"))
				continue;

			apexHeight[i] = -65535.0;

			if (IsClientAffectedByFling(i))
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

			// No blocks, remove victim timer.
			if (victimTimer[i] != INVALID_HANDLE && !FindAnyRegisterBlocks(i))
			{
				CloseHandle(victimTimer[i]);
				victimTimer[i] = INVALID_HANDLE;
			}
		}
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

	chargerTimer[client] = CreateTimer(CHARGE_CHECKING_INTERVAL, Timer_CheckCharge, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
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

			else if (L4D_GetClientTeam(i) != L4DTeam_Infected)
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
	{
		LastImpacter[victim] = client;

		if (victimTimer[victim] != INVALID_HANDLE)
		{
			CloseHandle(victimTimer[victim]);
			victimTimer[victim] = INVALID_HANDLE;
		}

		DataPack DP;
		victimTimer[victim] = CreateDataTimer(CHARGE_CHECKING_INTERVAL, Timer_CheckVictim, DP, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);

		DP.WriteFloat(IMPACT_SECONDS_NEEDED_AGAINST_LEDGE_HANG);
		DP.WriteCell(victim);
	}

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

	// This is disabled by the new jockey mechanism except for ledges
	if (L4D_IsPlayerHangingFromLedge(victim))
	{
		BlockJockChange[victim] = true;

		LastJockey[victim] = client;

		CreateTimer(0.7, EndLastJockey, victim, TIMER_FLAG_NO_MAPCHANGE);
	}

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

public Action Timer_CheckCharge(Handle timer, any client)
{
	if (!client || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		chargerTimer[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}

	int victim = GetCarryVictim(client);

	if (victim == -1)
		return Plugin_Continue;

	else if (IsDoubleCharged(victim))
		return Plugin_Continue;

	else if (GetEntityFlags(client) & FL_ONGROUND) return Plugin_Continue;

	float fOrigin[3], fEndOrigin[3], fMins[3], fMaxs[3];
	GetEntPropVector(client, Prop_Data, "m_vecOrigin", fOrigin);

	ArrayList aEntities = new ArrayList(1);

	GetClientMins(client, fMins);
	GetClientMaxs(client, fMaxs);

	TR_TraceRayFilter(fOrigin, ANGLE_STRAIGHT_DOWN, MASK_SHOT, RayType_Infinite, TraceFilter_DontHitPlayers);

	TR_GetEndPosition(fEndOrigin);

	// Now try again with hull to avoid funny stuff.
	TR_TraceHullFilter(fOrigin, fEndOrigin, fMins, fMaxs, MASK_SHOT, TraceFilter_DontHitPlayers);

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

	LastCharger[victim]  = 0;
	LastImpacter[victim] = 0;
	LastJockey[victim]   = 0;
	LastSlapper[victim]  = 0;
	LastPuncher[victim]  = 0;
	LastSmoker[victim]   = 0;

	// Enforces a one karma per 15 seconds per victim, exlcuding height checkers.
	BlockRegisterCaptor[victim] = true;

	if (BlockRegisterTimer[victim] != INVALID_HANDLE)
	{
		CloseHandle(BlockRegisterTimer[victim]);
		BlockRegisterTimer[victim] = INVALID_HANDLE;
	}

	BlockRegisterTimer[victim] = CreateTimer(15.0, RegisterCaptorDelay, victim, TIMER_FLAG_NO_MAPCHANGE);

	if (GetConVarBool(cvarModeSwitch) || cooldownTimer != INVALID_HANDLE)
		SlowKarmaCouple(victim, client, KarmaName);

	else
	{
		SlowTime();
	}

	char sPrefix[64];
	GetKarmaPrefix(sPrefix, sizeof(sPrefix));

	PrintToChatAll("%s\x03%N\x01 Karma %s'd\x04 %N\x01, for great justice!!", sPrefix, client, KarmaName, victim);

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

stock void SlowKarmaCouple(int victim, int attacker, char[] sKarmaName)
{
	float fAttackerOrigin[3], fVictimOrigin[3];
	GetEntPropVector(attacker, Prop_Data, "m_vecOrigin", fAttackerOrigin);
	GetEntPropVector(victim, Prop_Data, "m_vecOrigin", fVictimOrigin);

	// Karma can register a lot of time after the register because of ledge hang, so no random slowdowns...
	if (StrEqual(sKarmaName, "Charge"))
		SetEntPropFloat(attacker, Prop_Send, "m_flLaggedMovementValue", GetConVarFloat(karmaSlow));

	SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", GetConVarFloat(karmaSlow));

	Handle data = CreateDataPack();
	WritePackCell(data, attacker);
	WritePackCell(data, victim);

	CreateTimer(GetConVarFloat(karmaSlowTimeOnCouple), _revertCoupleTimeSlow, data, TIMER_FLAG_NO_MAPCHANGE);
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

stock void SlowTime(const char[] re_Acceleration = "2.0", const char[] minBlendRate = "1.0", const char[] blendDeltaMultiplier = "2.0")
{
	char  desiredTimeScale[16];
	float fSlowPower = GetConVarFloat(karmaSlow);

	if (fSlowPower < 0.1)
		fSlowPower = 0.1;

	FloatToString(fSlowPower, desiredTimeScale, sizeof(desiredTimeScale));

	int ent = CreateEntityByName("func_timescale");

	DispatchKeyValue(ent, "desiredTimescale", desiredTimeScale);
	DispatchKeyValue(ent, "acceleration", re_Acceleration);
	DispatchKeyValue(ent, "minBlendRate", minBlendRate);
	DispatchKeyValue(ent, "blendDeltaMultiplier", blendDeltaMultiplier);

	DispatchSpawn(ent);
	AcceptEntityInput(ent, "Start");

	char sAddOutput[64];

	// Must compensate for the timescale making every single timer slower, both CreateTimer type timers and OnUser1 type timers
	FormatEx(sAddOutput, sizeof(sAddOutput), "OnUser1 !self:Stop::%.2f:1", GetConVarFloat(karmaSlowTimeOnServer) * fSlowPower);
	SetVariantString(sAddOutput);
	AcceptEntityInput(ent, "AddOutput");
	AcceptEntityInput(ent, "FireUser1");

	FormatEx(sAddOutput, sizeof(sAddOutput), "OnUser2 !self:Kill::%.2f:1", (GetConVarFloat(karmaSlowTimeOnServer) * fSlowPower) + 5.0);
	SetVariantString(sAddOutput);
	AcceptEntityInput(ent, "AddOutput");
	AcceptEntityInput(ent, "FireUser2");

	// Start counting the cvarCooldown from after the freeze ends, also this timer needs to account for the timescale.
	cooldownTimer = CreateTimer((GetConVarFloat(karmaSlowTimeOnServer) * fSlowPower) + GetConVarFloat(cvarCooldown), RestoreSlowmo, _, TIMER_FLAG_NO_MAPCHANGE);
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

stock int GetAnyLastKarma(int victim, char[] sKarmaName = "", int iLen = 0)
{
	if (LastCharger[victim] != 0)
	{
		FormatEx(sKarmaName, iLen, "Charge");

		return LastCharger[victim];
	}
	else if (LastJockey[victim] != 0)
	{
		FormatEx(sKarmaName, iLen, "Jockey");

		return LastJockey[victim];
	}

	else if (LastSlapper[victim] != 0)
	{
		FormatEx(sKarmaName, iLen, "Slap");

		return LastSlapper[victim];
	}

	else if (LastPuncher[victim] != 0)
	{
		FormatEx(sKarmaName, iLen, "Punch");

		return LastPuncher[victim];
	}

	else if (LastImpacter[victim] != 0)
	{
		FormatEx(sKarmaName, iLen, "Impact");

		return LastImpacter[victim];
	}

	else if (LastSmoker[victim] != 0)
	{
		FormatEx(sKarmaName, iLen, "Smoke");

		return LastSmoker[victim];
	}

	return 0;
}

stock bool FindAnyRegisterBlocks(int victim)
{
	return BlockRegisterCaptor[victim] || BlockAllChange[victim] || BlockSlapChange[victim] || BlockJockChange[victim] || BlockPunchChange[victim] || BlockImpactChange[victim] || BlockSmokeChange[victim];
}

stock void GetKarmaPrefix(char[] sPrefix, int iPrefixLen)
{
	GetConVarString(karmaPrefix, sPrefix, iPrefixLen);

	ReplaceString(sPrefix, iPrefixLen, "/x01", "\x01");
	ReplaceString(sPrefix, iPrefixLen, "/x02", "\x02");
	ReplaceString(sPrefix, iPrefixLen, "/x03", "\x03");
	ReplaceString(sPrefix, iPrefixLen, "/x04", "\x04");
	ReplaceString(sPrefix, iPrefixLen, "/x05", "\x05");
	ReplaceString(sPrefix, iPrefixLen, "/x06", "\x06");
	ReplaceString(sPrefix, iPrefixLen, "/x07", "\x07");
	ReplaceString(sPrefix, iPrefixLen, "/x08", "\x08");
	ReplaceString(sPrefix, iPrefixLen, "/x09", "\x09");
}

stock bool CanClientSurviveFall(int client, float fTotalDistance)
{
	if (IsClientAffectedByFling(client))
		fTotalDistance -= 30.0;    // No clue why it acts like that...

	else
		fTotalDistance -= 15.0;    // No clue why it acts like that...

	if (fTotalDistance <= 340.0)
		return true;

	float fDistancesVsDamages[][] = {
		{340.0,  224.0 },
		{ 350.0, 224.0 },
		{ 360.0, 224.0 },
		{ 370.0, 277.0 },
		{ 380.0, 277.0 },
		{ 390.0, 277.0 },
		{ 400.0, 336.0 },
		{ 410.0, 336.0 },
		{ 420.0, 336.0 },
		{ 430.0, 399.0 },
		{ 440.0, 399.0 },
		{ 450.0, 399.0 },
		{ 460.0, 469.0 },
		{ 470.0, 469.0 },
		{ 480.0, 469.0 },
		{ 490.0, 624.0 },
		{ 500.0, 711.0 },
		{ 510.0, 711.0 },
		{ 520.0, 711.0 },
		{ 530.0, 711.0 },
		{ 540.0, 711.0 },
		{ 550.0, 802.0 },
		{ 560.0, 802.0 },
		{ 570.0, 802.0 },
		{ 580.0, 899.0 },
		{ 590.0, 899.0 },
		{ 600.0, 899.0 },
		{ 610.0, 899.0 },
		{ 620.0, 1002.0}
	};

	for (int i = sizeof(fDistancesVsDamages) - 1; i >= 0; i--)
	{
		if (fTotalDistance > fDistancesVsDamages[i][0])
		{
			return GetEntProp(client, Prop_Send, "m_iHealth") > fDistancesVsDamages[i][1];
		}
	}

	return false;
}

stock bool IsDoubleCharged(int victim)
{
	int count;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;

		else if (GetClientTeam(i) != view_as<int>(L4DTeam_Infected))
			continue;

		else if (L4D2_GetPlayerZombieClass(i) != L4D2ZombieClass_Charger)
			continue;

		if (L4D_GetVictimCarry(i) == victim || L4D_GetVictimCharger(i) == victim)
			count++;
	}

	return count >= 2;
}