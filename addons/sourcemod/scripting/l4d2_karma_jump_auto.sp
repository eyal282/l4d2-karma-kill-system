
// WARNING!!! Reloading this plugin gives every connected player immunity against the ban until they make another takeover.
#pragma semicolon 1

#define PLUGIN_AUTHOR  "RumbleFrog, SourceBans++ Dev Team, edit by Eyal282"
#define PLUGIN_VERSION "1.1"

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
 * @param jumperSteamId      Artist name.
 * @param jumperName     	 Artist steam ID.
 * @param KarmaName          Name of karma: "Charge", "Impact", "Jockey", "Slap", "Punch", "Smoke"
 * @param bBird              true if a bird charge event occured, false if a karma kill was detected or performed.
 * @param bKillConfirmed     Whether or not this indicates the complete death of the player. This is NOT just !IsPlayerAlive(victim)
 * @param bOnlyConfirmed     Whether or not only kill confirmed are allowed.

 * @noreturn
 * @note					This can be called more than once. One for the announcement, one for the kill confirmed.
                            If you want to reward both killconfirmed and killunconfirmed you should reward when killconfirmed is false.
                            If you want to reward if killconfirmed you should reward when killconfirmed is true.

 * @note					If the plugin makes a kill confirmed without a previous announcement without kill confirmed,
                            it compensates by sending two consecutive events, one without kill confirmed, one with kill confirmed.



 */
public void KarmaKillSystem_OnKarmaJumpPost(int victim, float lastPos[3], char[] jumperSteamId, char[] jumperName, const char[] KarmaName, bool bBird, bool bKillConfirmed, bool bOnlyConfirmed)
{
	if (GetConVarInt(Convar_AutoBanTime) < 0)
		return;

	float fLastLogin;
	g_smLogins.GetValue(jumperSteamId, fLastLogin);

	if (GetGameTime() < fLastLogin + GetConVarFloat(Convar_AutoBanPlayTime))
	{
		if (GetConVarBool(Convar_AutoRevive))
		{
			DataPack DP;
			CreateDataTimer(0.1, Timer_Respawn, DP, TIMER_FLAG_NO_MAPCHANGE);

			WritePackCell(DP, GetClientUserId(victim));
			WritePackString(DP, jumperSteamId);
			WritePackCell(DP, lastPos[0]);
			WritePackCell(DP, lastPos[1]);
			WritePackCell(DP, lastPos[2]);
		}

		ServerCommand("sm_addban %i \"%s\" Karma Jump detected %.2f seconds after login.", GetConVarInt(Convar_AutoBanTime), jumperSteamId, GetGameTime() - fLastLogin);

		char sPrefix[64];
		GetKarmaPrefix(sPrefix, sizeof(sPrefix));

		PrintToChatAll("%s\x03The most recent suicide jumper got Karma Banned, for great justice!!", sPrefix);
	}
}

public Action Timer_Respawn(Handle hTimer, Handle DP)
{
	ResetPack(DP);

	int victim = GetClientOfUserId(ReadPackCell(DP));

	char jumperSteamId[35];
	ReadPackString(DP, jumperSteamId, sizeof(jumperSteamId));

	float lastPos[3];

	lastPos[0] = ReadPackCell(DP);
	lastPos[1] = ReadPackCell(DP);
	lastPos[2] = ReadPackCell(DP);

	if (victim == 0)
	{
		int insect = FindClientByAuthId(jumperSteamId);

		if (insect != 0)
		{
			KickClient(insect, "It appears that you're getting checkmated");
		}

		return Plugin_Stop;
	}

	L4D_RespawnPlayer(victim);

	TeleportEntity(victim, lastPos, NULL_VECTOR, NULL_VECTOR);

	int insect = FindClientByAuthId(jumperSteamId);

	if (insect != 0)
	{
		KickClient(insect, "It appears that you're getting checkmated");
	}

	return Plugin_Continue;
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