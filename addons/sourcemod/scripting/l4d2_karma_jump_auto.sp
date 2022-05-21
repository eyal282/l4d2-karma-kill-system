
// WARNING!!! Reloading this plugin gives every connected player immunity against the ban until they make another takeover.
#pragma semicolon 1

#define PLUGIN_AUTHOR  "RumbleFrog, SourceBans++ Dev Team, edit by Eyal282"
#define PLUGIN_VERSION "1.3"

#include <left4dhooks>
#include <sourcemod>

#undef REQUIRE_PLUGIN
#undef REQUIRE_EXTENSIONS
#tryinclude < autoexecconfig>

#pragma newdecls required

ConVar Convar_AutoRevive;
ConVar Convar_AutoBanTime;
ConVar Convar_AutoBanPlayTime;

StringMap g_smLogins;

bool  g_bCheckTakeover[MAXPLAYERS + 1];
float g_fProperOrigin[MAXPLAYERS + 1][3];
int   g_iProperWeapons[MAXPLAYERS + 1][64];
int   g_iProperHealth[MAXPLAYERS + 1][2];

public Plugin myinfo =
{
	name        = "Karma Jump Auto Ban Plugin",
	author      = PLUGIN_AUTHOR,
	description = "Listens for karma jump forward and automatically bans if done before a certain time passes.",
	version     = PLUGIN_VERSION,
	url         = "https://sbpp.github.io"
};

public void OnMapStart()
{
	g_smLogins.Clear();
}

public void OnPluginStart()
{
	CreateConVar("l4d2_karma_jump_discord_version", PLUGIN_VERSION, "Karma Jump Discord Version", FCVAR_REPLICATED | FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_NOTIFY);

	HookEvent("bot_player_replace", event_PlayerReplacesABot, EventHookMode_Post);
	HookEvent("player_bot_replace", event_BotReplacesAPlayer, EventHookMode_Post);
}

public void OnAllPluginsLoaded()
{
	g_smLogins = new StringMap();

#if defined _autoexecconfig_included

	AutoExecConfig_SetFile("l4d2_karma_jump_auto");

#endif

	Convar_AutoRevive      = UC_CreateConVar("l4d2_karma_jump_auto_revive", "1", "Revive the killed bot to the jumping position?", FCVAR_PROTECTED);
	Convar_AutoBanTime     = UC_CreateConVar("l4d2_karma_jump_auto_ban", "10080", "Time to ban the jumping player, set to negative to disable.", FCVAR_PROTECTED);
	Convar_AutoBanPlayTime = UC_CreateConVar("l4d2_karma_jump_auto_playtime", "30", "Ban only if karma jump is playing for less than this amount of time.", FCVAR_PROTECTED);

#if defined _autoexecconfig_included

	AutoExecConfig_ExecuteFile();

	AutoExecConfig_CleanFile();

#endif
}

public Action event_BotReplacesAPlayer(Handle event, const char[] name, bool dontBroadcast)
{
	int newPlayer = GetClientOfUserId(GetEventInt(event, "bot"));
	int oldPlayer = GetClientOfUserId(GetEventInt(event, "player"));

	if (g_bCheckTakeover[oldPlayer])
	{
		g_bCheckTakeover[oldPlayer] = false;

		Handle DP = CreateDataPack();

		WritePackCell(DP, newPlayer);
		WritePackFloat(DP, g_fProperOrigin[oldPlayer][0]);
		WritePackFloat(DP, g_fProperOrigin[oldPlayer][1]);
		WritePackFloat(DP, g_fProperOrigin[oldPlayer][2]);

		WritePackCell(DP, g_iProperHealth[oldPlayer][0]);
		WritePackCell(DP, g_iProperHealth[oldPlayer][1]);
		int num = 0;

		for (int i = 0; i < 64; i++)
		{
			int weapon = g_iProperWeapons[oldPlayer][i];

			if (weapon != 0 && IsValidEntity(weapon))
			{
				num++;
			}
		}

		WritePackCell(DP, num);

		for (int i = 0; i < 64; i++)
		{
			int weapon = g_iProperWeapons[oldPlayer][i];

			if (weapon != 0 && IsValidEntity(weapon))
			{
				WritePackCell(DP, weapon);
			}
		}

		Frame_Respawn(DP);
	}
}

public Action event_PlayerReplacesABot(Handle event, const char[] name, bool dontBroadcast)
{
	int newPlayer = GetClientOfUserId(GetEventInt(event, "player"));

	char sAuthId[64];
	GetClientAuthId(newPlayer, AuthId_Steam2, sAuthId, sizeof(sAuthId));

	g_smLogins.SetValue(sAuthId, GetGameTime());
}

/**
 * Description
 *
 * @param victim             Player who got killed by the karma jump. This can be anybody. Useful to revive the victim.
 * @param lastPos            Origin from which the jump began.
 * @param jumperWeapons		 Weapons of the jumper at the moment of the jump.
 * @param jumperHealth    	 jumperHealth[0] and jumperHealth[1] = Health and Temp health from which the jump began.
 * @param jumperTimestamp    Timestamp from which the jump began.
 * @param jumperSteamId      jumper's Steam ID.
 * @param jumperName     	 jumper's name

 * @noreturn

 */
public void KarmaKillSystem_OnKarmaJumpPost(int victim, float lastPos[3], int jumperWeapons[64], int jumperHealth[2], float jumperTimestamp, char[] jumperSteamId, char[] jumperName)
{
	if (GetConVarInt(Convar_AutoBanTime) < 0)
		return;

	float fLastLogin;
	g_smLogins.GetValue(jumperSteamId, fLastLogin);

	if (jumperTimestamp < fLastLogin + GetConVarFloat(Convar_AutoBanPlayTime))
	{
		if (GetConVarBool(Convar_AutoRevive))
		{
			if (victim == 0)
			{
				int insect = FindClientByAuthId(jumperSteamId);

				if (insect != 0)
				{
					KickClient(insect, "It appears that you're getting checkmated");
				}

				return;
			}

			int insect = FindClientByAuthId(jumperSteamId);

			if (insect == 0 || insect != victim)
			{
				Handle DP = CreateDataPack();

				WritePackCell(DP, victim);
				WritePackFloat(DP, lastPos[0]);
				WritePackFloat(DP, lastPos[1]);
				WritePackFloat(DP, lastPos[2]);

				WritePackCell(DP, jumperHealth[0]);
				WritePackCell(DP, jumperHealth[1]);

				int num = 0;

				for (int i = 0; i < 64; i++)
				{
					int weapon = jumperWeapons[i];

					if (weapon != 0 && IsValidEntity(weapon))
					{
						num++;
					}
				}

				WritePackCell(DP, num);

				for (int i = 0; i < 64; i++)
				{
					int weapon = jumperWeapons[i];

					if (weapon != 0 && IsValidEntity(weapon))
					{
						WritePackCell(DP, weapon);
					}
				}

				RequestFrame(Frame_Respawn, DP);
			}
			else
			{
				g_bCheckTakeover[insect] = true;
				g_fProperOrigin[insect]  = lastPos;
				g_iProperWeapons[insect] = jumperWeapons;
				g_iProperHealth[insect]  = jumperHealth;
			}

			if (insect != 0)
				KickClient(insect, "It appears that you're getting checkmated");
		}

		ServerCommand("sm_addban %i \"%s\" Karma Jump detected %.2f seconds after login.", GetConVarInt(Convar_AutoBanTime), jumperSteamId, GetGameTime() - fLastLogin);

		char sPrefix[64];
		GetKarmaPrefix(sPrefix, sizeof(sPrefix));

		PrintToChatAll("%s\x03The most recent suicide jumper got Karma Banned, for great justice!!", sPrefix);
	}
}

public void Frame_Respawn(Handle DP)
{
	ResetPack(DP);

	int victim = ReadPackCell(DP);

	float lastPos[3];

	lastPos[0] = ReadPackFloat(DP);
	lastPos[1] = ReadPackFloat(DP);
	lastPos[2] = ReadPackFloat(DP);

	int health     = ReadPackCell(DP);
	int tempHealth = ReadPackCell(DP);

	int num = ReadPackCell(DP);

	int weapons[64];

	for (int i = 0; i < num; i++)
	{
		weapons[i] = ReadPackCell(DP);
	}

	CloseHandle(DP);

	// Clients cannot replace eachother in a single frame, only invalidate.
	if (!IsClientInGame(victim))
		return;

	L4D_RespawnPlayer(victim);

	TeleportEntity(victim, lastPos, NULL_VECTOR, NULL_VECTOR);

	SetEntityHealth(victim, health);
	L4D_SetPlayerTempHealth(victim, tempHealth);

	for (int i = 0; i < num; i++)
	{
		if (IsValidEntity(weapons[i]))
		{
			EquipPlayerWeapon(victim, weapons[i]);
		}
	}
}

#if defined _autoexecconfig_included

stock ConVar UC_CreateConVar(const char[] name, const char[] defaultValue, const char[] description = "", int flags = 0, bool hasMin = false, float min = 0.0, bool hasMax = false, float max = 0.0)
{
	ConVar hndl = AutoExecConfig_CreateConVar(name, defaultValue, description, flags, hasMin, min, hasMax, max);

	if (flags & FCVAR_PROTECTED)
		ServerCommand("sm_cvar protect %s", name);

	return hndl;
}

#else

stock ConVar UC_CreateConVar(const char[] name, const char[] defaultValue, const char[] description = "", int flags = 0, bool hasMin = false, float min = 0.0, bool hasMax = false, float max = 0.0)
{
	ConVar hndl = CreateConVar(name, defaultValue, description, flags, hasMin, min, hasMax, max);

	if (flags & FCVAR_PROTECTED)
		ServerCommand("sm_cvar protect %s", name);

	return hndl;
}

#endif

stock int FindClientByAuthId(const char[] sAuthId)
{
	char iAuthId[35];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;

		GetClientAuthId(i, AuthId_Steam2, iAuthId, sizeof(iAuthId));

		if (StrEqual(sAuthId, iAuthId, true))
			return i;
	}

	return 0;
}

stock void GetKarmaPrefix(char[] sPrefix, int iPrefixLen)
{
	GetConVarString(FindConVar("l4d2_karma_charge_prefix"), sPrefix, iPrefixLen);

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