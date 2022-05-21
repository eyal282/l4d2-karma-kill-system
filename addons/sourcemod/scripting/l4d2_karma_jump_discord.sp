
#pragma semicolon 1

#define PLUGIN_AUTHOR  "RumbleFrog, SourceBans++ Dev Team, edit by Eyal282"
#define PLUGIN_VERSION "1.1"

#include <smjansson>
#include <sourcemod>
#include <SteamWorks>

#undef REQUIRE_PLUGIN
#undef REQUIRE_EXTENSIONS
#tryinclude < autoexecconfig>

#pragma newdecls required

int EmbedColor = 0xDA1D87;

char sHostname[256], sHost[64];

ConVar Convar_WebHook;
ConVar Convar_BotName;
ConVar Convar_BotImage;
ConVar Convar_BotMessage;

public Plugin myinfo =
{
	name        = "Karma Jump Discord Plugin",
	author      = PLUGIN_AUTHOR,
	description = "Listens for karma jump forward and sends it to webhook endpoints",
	version     = PLUGIN_VERSION,
	url         = "https://sbpp.github.io"
};

public void OnPluginStart()
{
	CreateConVar("l4d2_karma_jump_discord_version", PLUGIN_VERSION, "Karma Jump Discord Version", FCVAR_REPLICATED | FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_NOTIFY);
}

public void OnAllPluginsLoaded()
{
#if defined _autoexecconfig_included

	AutoExecConfig_SetFile("l4d2_karma_jump_discord");

#endif

	Convar_WebHook    = UC_CreateConVar("l4d2_karma_jump_discord_hook", "https://discord.com/api/webhooks/837021016404262962/IP9ZMDYrCPk7aaoun6MQiPXp9myT7UY3GREK0VEs4Aceuy18iXH9yo6ydN7GqJjC3A96", "Discord web hook endpoint for karma jump forward", FCVAR_PROTECTED);
	Convar_BotName    = UC_CreateConVar("l4d2_karma_jump_discord_name", "Karma Jump", "Discord bot name for webhook", FCVAR_PROTECTED);
	Convar_BotImage   = UC_CreateConVar("l4d2_karma_jump_discord_image", "https://wallpapercave.com/wp/AKsyaeQ.jpg", "Discord bot image URL for webhook.", FCVAR_PROTECTED);
	Convar_BotMessage = UC_CreateConVar("l4d2_karma_jump_discord_message", "<@&744025231521218600>", "Discord message to be sent ( usually mention ).", FCVAR_PROTECTED);

#if defined _autoexecconfig_included

	AutoExecConfig_ExecuteFile();

	AutoExecConfig_CleanFile();

#endif
}

public void OnConfigsExecuted()
{
	FindConVar("hostname").GetString(sHostname, sizeof sHostname);

	int ip[4];

	SteamWorks_GetPublicIP(ip);

	if (SteamWorks_GetPublicIP(ip))
	{
		Format(sHost, sizeof sHost, "%d.%d.%d.%d:%d", ip[0], ip[1], ip[2], ip[3], FindConVar("hostport").IntValue);
	}
	else
	{
		int iIPB = FindConVar("hostip").IntValue;
		Format(sHost, sizeof sHost, "%d.%d.%d.%d:%d", iIPB >> 24 & 0x000000FF, iIPB >> 16 & 0x000000FF, iIPB >> 8 & 0x000000FF, iIPB & 0x000000FF, FindConVar("hostport").IntValue);
	}
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
	Jump_SendReport(jumperSteamId, jumperName);
}

void Jump_SendReport(const char[] AuthId, const char[] Name)
{
	char sBotWebHook[512], sBotName[64], sBotImage[256], sBotMessage[256];

	Convar_WebHook.GetString(sBotWebHook, sizeof(sBotWebHook));
	Convar_BotImage.GetString(sBotImage, sizeof(sBotImage));
	Convar_BotName.GetString(sBotName, sizeof(sBotName));
	Convar_BotMessage.GetString(sBotMessage, sizeof(sBotMessage));

	if (sBotWebHook[0] == EOS)
	{
		LogError("Missing karma jump hook endpoint");
		return;
	}

	else if (sBotName[0] == EOS)
	{
		LogError("Missing karma jump bot name");
		return;
	}

	else if (sBotImage[0] == EOS)
	{
		LogError("Missing karma jump bot image");
		return;
	}

	char sJson[2048], sBuffer[256];

	Handle jRequest = json_object();

	Handle jEmbeds = json_array();

	Handle jContent = json_object();

	json_object_set(jContent, "color", json_integer(GetEmbedColor()));

	Handle jContentAuthor = json_object();

	json_object_set_new(jContentAuthor, "name", json_string(Name));

	char steam3[64];
	SteamIDToSteamID3(AuthId, steam3, sizeof(steam3));

	Format(sBuffer, sizeof sBuffer, "https://steamcommunity.com/profiles/%s", steam3);
	json_object_set_new(jContentAuthor, "url", json_string(sBuffer));
	json_object_set_new(jContentAuthor, "icon_url", json_string(sBotImage));
	json_object_set_new(jContent, "author", jContentAuthor);

	Handle jContentFooter = json_object();

	Format(sBuffer, sizeof sBuffer, "%s (%s)", sHostname, sHost);
	json_object_set_new(jContentFooter, "text", json_string(sBuffer));
	json_object_set_new(jContentFooter, "icon_url", json_string(sBotImage));
	json_object_set_new(jContent, "footer", jContentFooter);

	Handle jFields = json_array();

	Handle jFieldAuthor = json_object();
	json_object_set_new(jFieldAuthor, "name", json_string("Karma Jumper"));
	Format(sBuffer, sizeof sBuffer, "%s (%s)", Name, AuthId);
	json_object_set_new(jFieldAuthor, "value", json_string(sBuffer));
	json_object_set_new(jFieldAuthor, "inline", json_boolean(true));

	json_array_append_new(jFields, jFieldAuthor);

	json_object_set_new(jContent, "fields", jFields);

	json_array_append_new(jEmbeds, jContent);

	json_object_set_new(jRequest, "username", json_string(sBotName));
	json_object_set_new(jRequest, "avatar_url", json_string(sBotImage));
	json_object_set_new(jRequest, "embeds", jEmbeds);

	if (sBotMessage[0] != EOS)
	{
		json_object_set_new(jRequest, "content", json_string(sBotMessage));
	}

	json_dump(jRequest, sJson, sizeof sJson, 0, false, false, true);

#if defined DEBUG
	PrintToServer(sJson);
#endif

	CloseHandle(jRequest);

	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, sBotWebHook);

	SteamWorks_SetHTTPRequestContextValue(hRequest, 0, 0);
	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "payload_json", sJson);
	SteamWorks_SetHTTPCallbacks(hRequest, OnHTTPRequestComplete);

	if (!SteamWorks_SendHTTPRequest(hRequest))
		LogError("HTTP request failed for %s (%s)", Name, AuthId);
}

public int OnHTTPRequestComplete(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode)
{
	if (!bRequestSuccessful || eStatusCode != k_EHTTPStatusCode204NoContent)
	{
		LogError("HTTP request failed");

#if defined DEBUG
		int iSize;

		SteamWorks_GetHTTPResponseBodySize(hRequest, iSize);

		char[] sBody = new char[iSize];

		SteamWorks_GetHTTPResponseBodyData(hRequest, sBody, iSize);

		PrintToServer(sBody);
		PrintToServer("Status Code: %d", eStatusCode);
		PrintToServer("SteamWorks_IsLoaded: %d", SteamWorks_IsLoaded());
#endif
	}

	CloseHandle(hRequest);

	return 0;
}

int GetEmbedColor()
{
	return EmbedColor;
}

stock bool IsValidClient(int iClient, bool bAlive = false)
{
	if (iClient >= 1 && iClient <= MaxClients && IsClientConnected(iClient) && IsClientInGame(iClient) && !IsFakeClient(iClient) && (bAlive == false || IsPlayerAlive(iClient)))
	{
		return true;
	}

	return false;
}

void SteamIDToSteamID3(const char[] authid, char[] steamid3, int len)
{
	// STEAM_X:Y:Z
	// W = Z * 2 + Y
	// [U:1:W]
	char buffer[3][32];
	ExplodeString(authid, ":", buffer, sizeof buffer, sizeof buffer[]);
	int w = StringToInt(buffer[2]) * 2 + StringToInt(buffer[1]);
	FormatEx(steamid3, len, "[U:1:%i]", w);
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