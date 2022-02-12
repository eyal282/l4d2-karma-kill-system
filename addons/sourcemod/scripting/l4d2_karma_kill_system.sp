#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#undef REQUIRE_PLUGIN
#undef REQUIRE_EXTENSIONS
#tryinclude <updater>  // Comment out this line to remove updater support by force.
#define REQUIRE_PLUGIN
#define REQUIRE_EXTENSIONS

#define UPDATE_URL "https://github.com/eyal282/l4d2-karma-kill-system/blob/master/addons/sourcemod/updatefile.txt"

#define PLUGIN_VERSION 						  "1.1"

#define TEST_DEBUG 		0
#define TEST_DEBUG_LOG 	0


static const Float:CHARGE_CHECKING_INTERVAL	= 0.1;
static const Float:ANGLE_STRAIGHT_DOWN[3]	= { 90.0 , 0.0 , 0.0 };
static const String:SOUND_EFFECT[]			= "./level/loud/climber.wav";

new Handle:cvarisEnabled					= INVALID_HANDLE;
new Handle:triggeringHeight				= INVALID_HANDLE;
new Handle:chargerTimer[MAXPLAYERS] = { INVALID_HANDLE, ... };
new Handle:karmaTime						= INVALID_HANDLE;
new Handle:cvarModeSwitch				= INVALID_HANDLE;
new Handle:cvarCooldown			= INVALID_HANDLE;
new bool:isEnabled						= true;
new Float:lethalHeight					= 475.0;

new Handle:fw_OnKarmaEventPost = INVALID_HANDLE;

new LastCharger[MAXPLAYERS];
new LastJockey[MAXPLAYERS];
new LastSlapper[MAXPLAYERS];
new LastPuncher[MAXPLAYERS];
new LastImpacter[MAXPLAYERS];
new LastSmoker[MAXPLAYERS];


new bool:BlockSlapChange[MAXPLAYERS];
new bool:BlockJockChange[MAXPLAYERS];
new bool:BlockPunchChange[MAXPLAYERS];
new bool:BlockImpactChange[MAXPLAYERS];
new bool:BlockSmokeChange[MAXPLAYERS];

new Handle:LastChargerTimer[MAXPLAYERS] = { INVALID_HANDLE, ... };


new bool:bAllowKarmaHardRain = false;

new Handle:SlapRegisterTimer[MAXPLAYERS] = { INVALID_HANDLE, ... };
new Handle:PunchRegisterTimer[MAXPLAYERS] = { INVALID_HANDLE, ... };
new Handle:ImpactRegisterTimer[MAXPLAYERS] = { INVALID_HANDLE, ... };
new Handle:SmokeRegisterTimer[MAXPLAYERS] = { INVALID_HANDLE, ... };

new Handle:cooldownTimer = INVALID_HANDLE;

public Plugin:myinfo = 
{
	name = "L4D2 Karma Kill System",
	author = " AtomicStryker, heavy edit by Eyal282",
	description = " Very Very loudly announces the event of either a charger charging a survivor from a high height, or any SI sending a survivor to a death by height. ",
	version = PLUGIN_VERSION,
	url = "http://forums.alliedmods.net/showthread.php?p=1239108"
}

public OnPluginStart()
{
	HookEvent("charger_carry_start", event_ChargerGrab);
	HookEvent("charger_carry_end", event_GrabEnded);
	HookEvent("jockey_ride_end", event_jockeyRideEndPre, EventHookMode_Pre);
	HookEvent("tongue_grab", event_tongueGrabOrRelease, EventHookMode_Post);
	HookEvent("tongue_release", event_tongueGrabOrRelease, EventHookMode_Post);
	HookEvent("charger_impact", event_ChargerImpact);
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
	HookEvent("player_hurt", CheckFallInHardRain, EventHookMode_Post);
	HookEvent("player_death", event_playerDeathPre, EventHookMode_Pre);
	HookEvent("round_start", RoundStart, EventHookMode_PostNoCopy);
	HookEvent("success_checkpoint_button_used", DisallowCheckHardRain, EventHookMode_PostNoCopy);
	
	RegConsoleCmd("sm_xyz", Command_XYZ);
	CreateConVar("l4d2_karma_charge_version", 						PLUGIN_VERSION, " L4D2 Karma Charge Plugin Version ");
	triggeringHeight = 	CreateConVar("l4d2_karma_charge_height",	"475.0", 		" What Height is considered karma ");
	karmaTime =			CreateConVar("l4d2_karma_charge_slowtime", 	"1.5", 			" How long does Time get slowed ");
	cvarisEnabled = 	CreateConVar("l4d2_karma_charge_enabled", 	"1", 			" Turn Karma Charge on and off ");
	cvarModeSwitch =	CreateConVar("l4d2_karma_charge_slowmode", 	"0", 			" 0 - Entire Server gets slowed, 1 - Only Charger and Survivor do ");
	cvarCooldown = CreateConVar("l4d2_karma_charge_cooldown", "0.0", "Non-decimal number that determines how long does it take for the next karma to freeze the entire map.");
	
	// public void KarmaKillSystem_OnKarmaEventPost(victim, attacker, const String:KarmaName[])
	fw_OnKarmaEventPost = CreateGlobalForward("KarmaKillSystem_OnKarmaEventPost", ET_Ignore, Param_Cell, Param_Cell, Param_String);
	
	HookConVarChange(cvarisEnabled, 	_cvarChange);
	HookConVarChange(triggeringHeight, 	_cvarChange);
	
	#if defined _updater_included
	if (LibraryExists("updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
	#endif
}

public OnLibraryAdded(const String:name[])
{
	#if defined _updater_included
	if (StrEqual(name, "updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
	#endif
}

public OnMapStart()
{
	PrefetchSound(SOUND_EFFECT);
	PrecacheSound(SOUND_EFFECT);
	for(new i=1;i <= MaxClients;i++)
	{
		LastChargerTimer[i] = INVALID_HANDLE;
		
		chargerTimer[i] = INVALID_HANDLE;
		
		SlapRegisterTimer[i] = INVALID_HANDLE;
		
		PunchRegisterTimer[i] = INVALID_HANDLE;
	}	
	cooldownTimer = INVALID_HANDLE;
	new String:MapName[50];
	GetCurrentMap(MapName, sizeof(MapName) - 1);
	if(StrEqual(MapName, "c3m1_plankcountry", false))
		lethalHeight = 444.0;
		
	else if(StrEqual(MapName, "c4m1_milltown_a", false) || StrEqual(MapName, "c4m5_milltown_escape", false))
		lethalHeight = 400.0;
		
	else if(StrEqual(MapName, "c4m2_sugarmill_a", false))
		lethalHeight = 450.0;
		
	else if(StrEqual(MapName, "c11m1_greenhouse", false))
		lethalHeight = 360.0; // Not related to angles, just a coincidence.
}

public _cvarChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
	isEnabled = 	GetConVarBool(cvarisEnabled);
	lethalHeight = 	GetConVarFloat(triggeringHeight);
}

public Action:Event_PlayerHurt(Handle:event, const String:name[], bool:dontBroadcast)
{
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	new type = GetEventInt(event, "type");
	
	CheckDamageByMapElements(victim, attacker, type);
	
	if(victim < 1 || victim > MaxClients || attacker < 1 || attacker > MaxClients)
		return;
	
	else if(GetClientTeam(victim) != 2 || GetClientTeam(attacker) != 3)
		return;
		
	else if(GetEntPropEnt(victim, Prop_Send, "m_carryAttacker") != -1)
		return;
	
	new Class = GetEntProp(attacker, Prop_Send, "m_zombieClass");
	if(Class == 2) // Boomer
	{
		LastSlapper[victim] = attacker;
		BlockSlapChange[victim] = true;
		SlapRegisterTimer[victim] = CreateTimer(0.25, RegisterSlapDelay, victim, TIMER_FLAG_NO_MAPCHANGE);
	}
	else if(Class == 8) // Tank
	{
		LastPuncher[victim] = attacker;
		BlockPunchChange[victim] = true;
		PunchRegisterTimer[victim] = CreateTimer(0.25, RegisterPunchDelay, victim, TIMER_FLAG_NO_MAPCHANGE);	
	}
}

public CheckDamageByMapElements(victim, attacker, type)
{
	if(victim < 1 || victim > MaxClients)
		return;
		
	else if(type != DMG_DROWN && type != DMG_FALL)
		return;
		
	// Ensures that it won't reset last charger on karma charges that deal less damage.
	if(LastChargerTimer[victim] != INVALID_HANDLE)
	{
		CloseHandle(LastChargerTimer[victim]);
		LastChargerTimer[victim] = INVALID_HANDLE;
		LastChargerTimer[victim] = CreateTimer(1.0, ResetLastCharger, victim, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action:CheckFallInHardRain(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(!bAllowKarmaHardRain)
		return;
	
	new String:MapName[25];
	GetCurrentMap(MapName, sizeof(MapName));
	
	if(!StrEqual(MapName, "c4m2_sugarmill_a"))
		return;
		
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	
	new type = GetEventInt(event, "type");

	if(type == DMG_FALL)
	{
		if(isEntityInsideFakeZone(victim, 100000.0, -100000.0, -9485.0, -100000.0, 85.0, 340.0))
		{
			LastCharger[victim] = 0; 
			
			
			ForcePlayerSuicide(victim);
			
			if(LastJockey[victim] != 0)
			{
				AnnounceKarma(LastJockey[victim], victim, "Jockey");
				
				return;
			}
			
			else if(LastSlapper[victim] != 0)
			{	
				AnnounceKarma(LastSlapper[victim], victim, "Slap");
				
				return;
			}
			
			else if(LastPuncher[victim] != 0)
			{
				AnnounceKarma(LastPuncher[victim], victim, "Punch");
					
				return;
			}	
			
			else if(LastSmoker[victim] != 0)
			{
				AnnounceKarma(LastSmoker[victim], victim, "Smoke");
					
				return;
			}	
			
			LastJockey[victim] = 0;
			LastSlapper[victim] = 0;
			LastCharger[victim] = 0;
			LastImpacter[victim] = 0;
			LastSmoker[victim] = 0;
		}
	}
}

public Action:RegisterSlapDelay(Handle timer, any:victim)
{
	BlockSlapChange[victim] = false;
	
	SlapRegisterTimer[victim] = INVALID_HANDLE;
}

public Action:RegisterPunchDelay(Handle timer, any:victim)
{
	BlockPunchChange[victim] = false;
	
	PunchRegisterTimer[victim] = INVALID_HANDLE;
}

public Action:event_playerDeathPre(Handle:event, const String:name[], bool:dontBroadcast)
{
	static String:MapName[50];
	GetCurrentMap(MapName, sizeof(MapName) - 1);
		
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	new attackerent = GetEventInt(event, "attackerentid");
	
	new type = GetEventInt(event, "type");

	if(victim < 1 || victim > MaxClients) // victim >= 1 && victim <= MaxClients -> Victim is a player
		return;
		
	else if(!IsClientInGame(victim)) // IsClientInGame(victim) -> Victim is inside the game.
		return;
		
	else if(GetClientTeam(victim) != 2) // GetClientTeam(victim) == 2 -> Victim is a survivor
		return;
		
	else if(attacker > 0 && attacker <= MaxClients) // ( attacker <= 0 && attacker > MaxClients ) || attacker == victim -> Attacker is not a player, attacker can be a player if the attacker is the victim.
			return;

	new String:Classname[50];
	GetEdictClassname(attackerent, Classname, sizeof(Classname));
	
	if(StrEqual(Classname, "infected", false) || StrEqual(Classname, "witch", false))
		return;
		
	if(LastJockey[victim] != 0)
	{
		AnnounceKarma(LastJockey[victim], victim, "Jockey");
		
		return;
	}
	
	else if(LastSlapper[victim] != 0)
	{
		AnnounceKarma(LastSlapper[victim], victim, "Slap");
		
		return;
	}
	
	else if(LastPuncher[victim] != 0)
	{
		AnnounceKarma(LastPuncher[victim], victim, "Punch");
		
		return;
	}
	
	else if(LastImpacter[victim] != 0)
	{
		AnnounceKarma(LastImpacter[victim], victim, "Impact");
		
		return;
	}
	
	else if(LastSmoker[victim] != 0)
	{
		//PrintToChatAll("Karma smoke kill detected by %N on %N.\nIf detection is mistaken, contact Eyal282", LastSmoker[victim], victim);
		AnnounceKarma(LastSmoker[victim], victim, "Smoke");
		
		return;
	}

	if( (StrEqual(MapName, "c10m5_houseboat", false) && type == DMG_DROWN) || ( StrEqual(MapName, "c2m5_concert", false) && type == DMG_FALL ))
	{
		if(LastCharger[victim] != 0)
		{
			
			SetEntPropEnt(LastCharger[victim], Prop_Send, "m_carryVictim", -1);
			SetEntPropEnt(LastCharger[victim], Prop_Send, "m_pummelVictim", -1);
			
			CreateTimer(0.1, ResetAbility, LastCharger[victim], TIMER_FLAG_NO_MAPCHANGE);
			
			AnnounceKarma(LastCharger[victim], victim, "Charge");
		}
	}	
}

public Action:ResetAbility(Handle:hTimer, client)
{
	new iEntity = GetEntPropEnt(client, Prop_Send, "m_customAbility");
	
	if(iEntity != -1)
	{
		SetEntPropFloat(iEntity, Prop_Send, "m_timestamp", GetGameTime());
		SetEntPropFloat(iEntity, Prop_Send, "m_duration", 0.0);
	}
}

public Action:RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	bAllowKarmaHardRain = true;
}

public Action:DisallowCheckHardRain(Handle:event, const String:name[], bool:dontBroadcast)
{
	bAllowKarmaHardRain = false;
}

public Action:Command_XYZ(client, args)
{
	new Float:Origin[3];
	GetEntPropVector(client, Prop_Data, "m_vecOrigin", Origin);
	
	PrintToChat(client, "%f %f %f", Origin[0], Origin[1], Origin[2]);
}

public OnGameFrame()
{
	
	for(new i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
			
		else if(!IsPlayerAlive(i))
			continue;
		
		else if(!(GetEntityFlags(i) & FL_ONGROUND))
			continue;
			
		else if(GetEntProp(i, Prop_Send, "m_isHangingFromLedge") || GetEntProp(i, Prop_Send, "m_isFallingFromLedge"))
			continue;
			
		if(!BlockJockChange[i] && LastJockey[i] != 0)
			LastJockey[i] = 0;
				
				
		else if(LastSlapper[i] != 0 && SlapRegisterTimer[i] == INVALID_HANDLE && !BlockSlapChange[i])
			LastSlapper[i] = 0;


		else if(LastPuncher[i] != 0 && PunchRegisterTimer[i] == INVALID_HANDLE && !BlockPunchChange[i])
			LastPuncher[i] = 0;


		else if(LastImpacter[i] != 0 && ImpactRegisterTimer[i] == INVALID_HANDLE && !BlockImpactChange[i])
			LastImpacter[i] = 0;
			
			
		else if(LastSmoker[i] != 0 && SmokeRegisterTimer[i] == INVALID_HANDLE && !BlockSmokeChange[i])
			LastSmoker[i] = 0;
	}
}	

public Action:event_ChargerGrab(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!isEnabled
	|| !client
	|| !IsClientInGame(client))
	{
		return;
	}
	
	new victim = GetClientOfUserId(GetEventInt(event, "victim"));
	
	LastCharger[victim] = client;
	
	DebugPrintToAll("Charger Carry event caught, initializing timer");
	
	if (chargerTimer[client] != INVALID_HANDLE)
	{
		CloseHandle(chargerTimer[client]);
		chargerTimer[client] = INVALID_HANDLE;
	}
	
	chargerTimer[client] = CreateTimer(CHARGE_CHECKING_INTERVAL, _timer_Check, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	TriggerTimer(chargerTimer[client], true);
}

public Action:event_GrabEnded(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new victim = GetClientOfUserId(GetEventInt(event, "victim"));
	//LastCharger[victim] = client;
	
	if(LastChargerTimer[victim] != INVALID_HANDLE)
	{
		CloseHandle(LastChargerTimer[victim]);
		LastChargerTimer[victim] = INVALID_HANDLE;
	}
	LastChargerTimer[victim] = CreateTimer(1.5, ResetLastCharger, victim, TIMER_FLAG_NO_MAPCHANGE);
	
	if (chargerTimer[client] != INVALID_HANDLE)
	{
		CloseHandle(chargerTimer[client]);
		chargerTimer[client] = INVALID_HANDLE;
	}
	
	static String:MapName[50];
	GetCurrentMap(MapName, sizeof(MapName));
	
	if(StrEqual(MapName, "c10m4_mainstreet", false) && isEntityInsideFakeZone(client, -2720.0, -1665.0, -340.0, 1200.0, -75.0, 162.0) && GetEntProp(victim, Prop_Send, "m_isFallingFromLedge") == 0 && IsPlayerAlive(victim))
	{
		LastCharger[victim] = 0;
		LastJockey[victim] = 0;	
		LastSlapper[victim] = 0;
		LastPuncher[victim] = 0;
		LastImpacter[victim] = 0;
		LastSmoker[victim] = 0;
		
		SetEntProp(victim, Prop_Send, "m_isFallingFromLedge", 1); // Makes his body impossible to defib.
		
		ForcePlayerSuicide(victim);
	
		AnnounceKarma(client, victim, "Charge");
	}
	
	else if(StrEqual(MapName, "c4m2_sugarmill_a", false) && isEntityInsideFakeZone(client, 100000.0, -100000.0, -9485.0, -100000.0, 85.0, 340.0) && bAllowKarmaHardRain)
	{
		LastCharger[victim] = 0;
		LastJockey[victim] = 0;	
		LastSlapper[victim] = 0;
		LastPuncher[victim] = 0;
		LastImpacter[victim] = 0;
		LastSmoker[victim] = 0;
		
		SetEntPropEnt(victim, Prop_Send, "m_carryAttacker", -1);
		SetEntPropEnt(victim, Prop_Send, "m_pummelAttacker", -1);
		for(new i=1;i <= MaxClients;i++) // Due to stealing from a charger bug ( irrelevant on vanilla servers )
		{
			if(!IsClientInGame(i))
				continue;
				
			else if(GetClientTeam(i) != 3)
				continue;
				
			else if(GetEntProp(i, Prop_Send, "m_zombieClass") != 6)
				continue;
				
			if(GetEntPropEnt(i, Prop_Send, "m_carryVictim") == victim)
				SetEntPropEnt(i, Prop_Send, "m_carryVictim", -1);
				
			if(GetEntPropEnt(i, Prop_Send, "m_pummelVictim") == victim)
				SetEntPropEnt(i, Prop_Send, "m_pummelVictim", -1);
				
		}
		new Float:Origin[3];
		GetEntPropVector(client, Prop_Data, "m_vecOrigin", Origin);
		TeleportEntity(victim, Origin, NULL_VECTOR, NULL_VECTOR);
		
		new iEntity = GetEntPropEnt(client, Prop_Send, "m_customAbility");
		
		if(iEntity != -1 && IsValidEntity(iEntity))
		{
			SetEntPropFloat(iEntity, Prop_Send, "m_timestamp", GetGameTime());
			SetEntPropFloat(iEntity, Prop_Send, "m_duration", 0.0);
		}
		
		ForcePlayerSuicide(victim);
	}
}

public Action:ResetLastCharger(Handle:hTimer, victim)
{
	
	LastChargerTimer[victim] = INVALID_HANDLE;
		
	LastCharger[victim] = 0;
}

public Action:event_ChargerImpact(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new victim = GetClientOfUserId(GetEventInt(event, "victim"));
	
	if(GetEntPropEnt(victim, Prop_Send, "m_carryAttacker") == -1)
		LastImpacter[victim] = client;
}

public Action:event_jockeyRideEndPre(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new victim = GetClientOfUserId(GetEventInt(event, "victim"));

		
	static String:MapName[50];
	
	GetCurrentMap(MapName, sizeof(MapName));
	
	
	
	if( ( StrEqual(MapName, "c6m2_bedlam", false) && isEntityInsideFakeZone(victim, 2319.031250, 2448.96875, -1296.031250, -1345.0, -2.0, -128.0) && GetEntProp(victim, Prop_Send, "m_isFallingFromLedge") == 0 && IsPlayerAlive(victim) ) )
	{
		LastJockey[victim] = 0;
		LastCharger[victim] = 0;
		LastSlapper[victim] = 0;
		LastPuncher[victim] = 0;
		LastSmoker[victim] = 0;
		
		SetEntProp(victim, Prop_Send, "m_isFallingFromLedge", 1); // Makes his body impossible to defib.
		
		ForcePlayerSuicide(victim);
		
		AnnounceKarma(client, victim, "Jockey");
		
		return Plugin_Continue;
	}
	
	BlockJockChange[victim] = true;
	LastJockey[victim] = client;
	
	CreateTimer(0.7, EndLastJockey, victim, TIMER_FLAG_NO_MAPCHANGE);
	
	return Plugin_Continue;

}

public Action:EndLastJockey(Handle:timer, any:victim)
{
	BlockJockChange[victim] = false;
}	 


public Action:event_tongueGrabOrRelease(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new victim = GetClientOfUserId(GetEventInt(event, "victim"));

	if(client == 0 || victim == 0)
		return;
		
	Handle DP = CreateDataPack();
	
	WritePackCell(DP, client);
	WritePackCell(DP, victim);
	
	RequestFrame(Frame_TongueRelease, DP);

}

public void Frame_TongueRelease(Handle DP)
{
	ResetPack(DP);
	
	int client = ReadPackCell(DP);
	int victim = ReadPackCell(DP);
	
	CloseHandle(DP);
	
	if(!IsClientInGame(client) || !IsClientInGame(victim))
		return;
		
	if(!IsPlayerAlive(victim))
		return;
		
	BlockSmokeChange[victim] = true;
	LastSmoker[victim] = client;
	
	CreateTimer(0.7, EndLastSmoker, victim, TIMER_FLAG_NO_MAPCHANGE);
	
	return;
}

public Action:EndLastSmoker(Handle:timer, any:victim)
{
	BlockSmokeChange[victim] = false;
}	 

public Action:_timer_Check(Handle:timer, any:client)
{
	if (!client || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		chargerTimer[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	if (GetEntityFlags(client) & FL_ONGROUND) return Plugin_Continue;
	
	new Float:height = GetHeightAboveGround(client);
	
	DebugPrintToAll("Karma Check - Charger Height is now: %f", height);
	
	if (height > lethalHeight)
	{
		AnnounceKarma(client, -1, "Charge");
		chargerTimer[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}

static Float:GetHeightAboveGround(client)
{
	decl Float:pos[3];
	GetClientAbsOrigin(client, pos);
	
	// execute Trace straight down
	new Handle:trace = TR_TraceRayFilterEx(pos, ANGLE_STRAIGHT_DOWN, MASK_SHOT, RayType_Infinite, _TraceFilter);
	
	if (!TR_DidHit(trace))
	{
		LogError("Tracer Bug: Trace did not hit anything, WTF");
	}
	
	decl Float:vEnd[3];
	TR_GetEndPosition(vEnd, trace); // retrieve our trace endpoint
	CloseHandle(trace);
	
	return GetVectorDistance(pos, vEnd, false);
}

public bool:_TraceFilter(entity, contentsMask)
{
	if (!entity || !IsValidEntity(entity)) // dont let WORLD, or invalid entities be hit
	{
		return false;
	}
	
	return true;
}

AnnounceKarma(client, victim=-1, String:KarmaName[])
{	
	if(victim == -1 && GetEntProp(client, Prop_Send, "m_zombieClass") == 6)
	{
		victim = GetCarryVictim(client);
	}
	if (victim == -1) return;

	EmitSoundToAll(SOUND_EFFECT, client);

	LastCharger[victim] = 0;
	LastJockey[victim] = 0;	
	LastSlapper[victim] = 0;
	LastPuncher[victim] = 0;
	LastSmoker[victim] = 0;
	
	if(cooldownTimer == INVALID_HANDLE)
	{
		cooldownTimer = CreateTimer(GetConVarFloat(cvarCooldown), RestoreSlowmo, _, TIMER_FLAG_NO_MAPCHANGE);
		if(GetConVarBool(cvarModeSwitch))
			SlowChargeCouple(client);
			
		else
			SlowTime();
	}
	
	PrintToChatAll("\x03%N\x01 Karma %s'd\x04 %N\x01, for great justice!!", client, KarmaName, victim);	
	
	Call_StartForward(fw_OnKarmaEventPost);
	
	Call_PushCell(victim);
	Call_PushCell(client);
	Call_PushString(KarmaName);
	
	Call_Finish();
	
	if(GetEntPropEnt(client, Prop_Send, "m_carryVictim") == victim)
	{
		new Jockey = GetEntPropEnt(victim, Prop_Send, "m_jockeyAttacker");
		
		if(Jockey != -1)
		{
			SetEntPropEnt(Jockey, Prop_Send, "m_jockeyVictim", -1);
			SetEntPropEnt(victim, Prop_Send, "m_jockeyAttacker", -1);
			
			LastJockey[victim] = 0;
		}
	}
}
public Action:RestoreSlowmo(Handle:Timer)
{
	cooldownTimer = INVALID_HANDLE;
}

stock SlowChargeCouple(client)
{
	new target = GetCarryVictim(client);
	if (target == -1) return;
	
	SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 0.2);
	SetEntPropFloat(target, Prop_Send, "m_flLaggedMovementValue", 0.2);
	
	new Handle:data = CreateDataPack();
	WritePackCell(data, client);
	WritePackCell(data, target);
	
	CreateTimer(GetConVarFloat(karmaTime), _revertCoupleTimeSlow, data, TIMER_FLAG_NO_MAPCHANGE);
}

public Action:_revertCoupleTimeSlow(Handle:timer, Handle:data)
{
	ResetPack(data);
	new client = ReadPackCell(data);
	new target = ReadPackCell(data);
	CloseHandle(data);

	if (IsClientInGame(client))
	{
		SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 1.0);
	}
	
	if (IsClientInGame(target))
	{
		SetEntPropFloat(target, Prop_Send, "m_flLaggedMovementValue", 1.0);
	}
}

static GetCarryVictim(client)
{
	new victim = GetEntPropEnt(client, Prop_Send, "m_carryVictim");
	if (victim < 1
	|| victim > MaxClients
	|| !IsClientInGame(victim))
	{
		return -1;
	}
	
	return victim;
}

stock SlowTime(const String:desiredTimeScale[] = "0.2", const String:re_Acceleration[] = "2.0", const String:minBlendRate[] = "1.0", const String:blendDeltaMultiplier[] = "2.0")
{
	new ent = CreateEntityByName("func_timescale");
	
	DispatchKeyValue(ent, "desiredTimescale", desiredTimeScale);
	DispatchKeyValue(ent, "acceleration", re_Acceleration);
	DispatchKeyValue(ent, "minBlendRate", minBlendRate);
	DispatchKeyValue(ent, "blendDeltaMultiplier", blendDeltaMultiplier);
	
	DispatchSpawn(ent);
	AcceptEntityInput(ent, "Start");
	
	CreateTimer(GetConVarFloat(karmaTime), _revertTimeSlow, ent, TIMER_FLAG_NO_MAPCHANGE);
}

public Action:_revertTimeSlow(Handle:timer, any:ent)
{
	if(IsValidEdict(ent))
	{
		AcceptEntityInput(ent, "Stop");
	}
}

stock DebugPrintToAll(const String:format[], any:...)
{
	#if (TEST_DEBUG || TEST_DEBUG_LOG)
	decl String:buffer[256];
	
	VFormat(buffer, sizeof(buffer), format, 2);
	
	#if TEST_DEBUG
	PrintToChatAll("[KARMA] %s", buffer);
	PrintToConsole(0, "[KARMA] %s", buffer);
	#endif
	
	LogMessage("%s", buffer);
	#else
	//suppress "format" never used warning
	if(format[0])
		return;
	else
		return;
	#endif
}

stock bool:isEntityInsideFakeZone(entity, Float:xOriginWall, Float:xOriginParallelWall, Float:yOriginWall2, Float:yOriginParallelWall2, Float:zOriginCeiling, Float:zOriginFloor)
{
	if(!IsValidEntity(entity))
		ThrowError("Entity %i is not valid!", entity);
	
	new Float:Origin[3];
	GetEntPropVector(entity, Prop_Data, "m_vecOrigin", Origin);

	if( ( Origin[0] >= xOriginWall && Origin[0] <= xOriginParallelWall ) || ( Origin[0] <= xOriginWall && Origin[0] >= xOriginParallelWall ) )
	{
		if( ( Origin[1] >= yOriginWall2 && Origin[1] <= yOriginParallelWall2 ) || ( Origin[1] <= yOriginWall2 && Origin[1] >= yOriginParallelWall2 ) )
		{
			if( ( Origin[2] >= zOriginFloor && Origin[2] <= zOriginCeiling ) || ( Origin[2] <= zOriginFloor && Origin[2] >= zOriginCeiling ) )
			{
				return true;
			}
		}
	}	
	
	return false;
}	


stock void PrintToChatEyal(const char[] format, any ...)
{
	char buffer[291];
	VFormat(buffer, sizeof(buffer), format, 2);
	for(int i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		else if(IsFakeClient(i))
			continue;
			

		char steamid[64];
		GetClientAuthId(i, AuthId_Engine, steamid, sizeof(steamid));
		
		if(StrEqual(steamid, "STEAM_1:0:49508144"))
			PrintToChat(i, buffer);
	}
}
