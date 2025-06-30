#pragma semicolon              1
#pragma newdecls               required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <versus_bonus>


public Plugin myinfo =
{
    name        = "[VersusBonus] Damage Bonus",
    author      = "TouchMe",
    description = "",
    version     = "build_0001",
    url         = "https://github.com/TouchMe-Inc/l4d2_versus_bonus"
};


#define TRANSLATIONS            "vb_damage.phrases"

// Team
#define TEAM_SURVIVOR           2


int g_iTempHealth[MAXPLAYERS + 1] = {0, ...};
int g_iLostTempHealth = 0;

ConVar g_cvTeamSize = null;
ConVar g_cvBonusPerSurvivorMultiplier = null;
ConVar g_cvPermanentHealthProportion = null;

float g_fMapTempHealthBonus = 0.0;
float g_fMapDamageBonus = 0.0;
float g_fTempHpWorth = 0.0;


/**
  * Global event. Called when all plugins loaded.
  */
public void OnAllPluginsLoaded()
{
    if (LibraryExists("versus_bonus")) {
        MakeBonusCritery(GetBonusName, GetBonusShortName, GetBonusDescription, GetBonusValue);
    }
}

public void OnPluginStart()
{
    LoadTranslations(TRANSLATIONS);

    g_cvTeamSize = FindConVar("survivor_limit");

    g_cvBonusPerSurvivorMultiplier = CreateConVar("sm2_bonus_per_survivor_multiplier", "0.5", "Total Survivor Bonus = this * Number of Survivors * Map Distance");
    g_cvPermanentHealthProportion = CreateConVar("sm2_permament_health_proportion", "0.75", "Permanent Health Bonus = this * Map Bonus; rest goes for Temporary Health Bonus");

    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("player_incapacitated", Event_OnPlayerIncapped, EventHookMode_Post);
    HookEvent("player_ledge_grab", Event_OnPlayerLedgeGrab, EventHookMode_Post);
    HookEvent("player_hurt", Event_OnPlayerHurt, EventHookMode_Post);
    HookEvent("revive_success", Event_OnPlayerRevived, EventHookMode_Post);
    HookEvent("player_death", Event_OnPlayerDeath, EventHookMode_Post);
}

public void OnConfigsExecuted()
{
    int iTeamSize = GetConVarInt(g_cvTeamSize);
    int iMapDistance = L4D_GetVersusMaxCompletionScore();
    float fMapBonus = iMapDistance * (GetConVarFloat(g_cvBonusPerSurvivorMultiplier) * iTeamSize);

    float fPermHealthProportion = GetConVarFloat(g_cvPermanentHealthProportion);
    float fTempHealthProportion = 1.0 - fPermHealthProportion;

    g_fMapDamageBonus = fMapBonus * fTempHealthProportion;
    g_fMapTempHealthBonus = iTeamSize * 100/* HP */ / fPermHealthProportion * fTempHealthProportion;

    g_fTempHpWorth = fMapBonus * fTempHealthProportion / g_fMapTempHealthBonus; // this should be almost equal to the perm hp worth, but for accuracy we'll keep it separate
}

public void OnClientPutInServer(int iClient)
{
    SDKHook(iClient, SDKHook_OnTakeDamage, OnTakeDamage);
    SDKHook(iClient, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
}

public void OnClientDisconnect(int iClient)
{
    SDKUnhook(iClient, SDKHook_OnTakeDamage, OnTakeDamage);
    SDKUnhook(iClient, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
}

public Action OnTakeDamage(int iVictim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (!IsClientSurvivor(iVictim) || L4D_IsPlayerIncapacitated(iVictim)) return Plugin_Continue;

    g_iTempHealth[iVictim] = GetSurvivorTemporaryHealth(iVictim);

    return Plugin_Continue;
}

public void OnTakeDamagePost(int iVictim, int attacker, int inflictor, float damage, int damagetype)
{
    if (!IsClientSurvivor(iVictim)) return;

    if (!IsPlayerAlive(iVictim) || (L4D_IsPlayerIncapacitated(iVictim) && !IsPlayerLedged(iVictim)))
    {
        g_iLostTempHealth += g_iTempHealth[iVictim];
    }
    else if (!IsPlayerLedged(iVictim))
    {
        g_iLostTempHealth += g_iTempHealth[iVictim] ? (g_iTempHealth[iVictim] - GetSurvivorTemporaryHealth(iVictim)) : 0;
    }

    g_iTempHealth[iVictim] = L4D_IsPlayerIncapacitated(iVictim) ? 0 : GetSurvivorTemporaryHealth(iVictim);
}

void Event_RoundStart(Event event, char[] szEventName, bool bDontBroadcast)
{
    g_iLostTempHealth = 0;

    for (int iClient = 0; iClient <= MaxClients; iClient ++)
    {
        g_iTempHealth[iClient] = 0;
    }
}

void Event_OnPlayerIncapped(Event event, char[] szEventName, bool bDontBroadcast)
{
    int iClient = GetClientOfUserId(GetEventInt(event, "userid"));

    if (!IsClientSurvivor(iClient)) {
        return;
    }

    g_iLostTempHealth+= RoundToFloor((g_fMapDamageBonus / 100.0) * 5.0 / g_fTempHpWorth);
}

void Event_OnPlayerLedgeGrab(Event event, char[] szEventName, bool bDontBroadcast)
{
    int iClient = GetClientOfUserId(GetEventInt(event, "userid"));

    g_iLostTempHealth += L4D2Direct_GetPreIncapHealthBuffer(iClient);
}

void Event_OnPlayerHurt(Event event, char[] szEventName, bool bDontBroadcast)
{
    int iVictim = GetClientOfUserId(GetEventInt(event, "userid"));
    int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
    int damage = GetEventInt(event, "dmg_health");
    int damagetype = GetEventInt(event, "type");

    int iFakeDamage = damage;

    if (!iVictim || !attacker
        || !IsClientSurvivor(iVictim)                        // Victim has to be a Survivor.
        || !IsClientSurvivor(attacker)                       // Attacker has to be a Survivor.
        || L4D_IsPlayerIncapacitated(iVictim)                // Player can't be Incapped.
        || damagetype != DMG_PLASMA                          // Damage has to be from manipulated Shotgun FF. (Plasma)
        || iFakeDamage < GetSurvivorPermanentHealth(iVictim) // Damage has to be higher than the Survivor's permanent health.
    ) return;

    g_iTempHealth[iVictim] = GetSurvivorTemporaryHealth(iVictim);
    if (iFakeDamage > g_iTempHealth[iVictim]) iFakeDamage = g_iTempHealth[iVictim];

    g_iLostTempHealth += iFakeDamage;

    g_iTempHealth[iVictim] = GetSurvivorTemporaryHealth(iVictim) - iFakeDamage;
}

void Event_OnPlayerRevived(Event event, char[] szEventName, bool bDontBroadcast)
{
    if (!GetEventBool(event, "ledge_hang")) {
        return;
    }

    int iClient = GetClientOfUserId(GetEventInt(event, "subject"));
    if (!iClient || !IsClientSurvivor(iClient)) {
        return;
    }

    RequestFrame(Event_OnPlayerRevived_Post, iClient);
}

void Event_OnPlayerRevived_Post(int iClient)
{
    g_iLostTempHealth -= GetSurvivorTemporaryHealth(iClient);
}

void Event_OnPlayerDeath(Event event, char[] szEventName, bool bDontBroadcast)
{
    int iVictim = GetClientOfUserId(GetEventInt(event, "userid"));
    if (!iVictim || !IsClientSurvivor(iVictim)) {
        return;
    }
   
    int incaps = L4D_GetPlayerReviveCount(iVictim);
    int iStandardPenalty = RoundToFloor((g_fMapDamageBonus / 100.0) * 5.0 / g_fTempHpWorth);
    int iPenalty = 0;

    for (int loops = 2 - incaps; loops > 0; loops--)
    {
        iPenalty += iStandardPenalty + 30;
    }

    g_iLostTempHealth += iPenalty;
}

public Action GetBonusName(char[] szBuffer, int iLength, int iClient)
{
    Format(szBuffer, iLength, "%T", "BONUS_NAME", iClient);

    return Plugin_Handled;
}

public Action GetBonusShortName(char[] szBuffer, int iLength, int iClient)
{
    Format(szBuffer, iLength, "%T", "BONUS_SHORT_NAME", iClient);

    return Plugin_Handled;
}

public Action GetBonusDescription(char[] szBuffer, int iLength, int iClient)
{
    Format(szBuffer, iLength, "%T", "BONUS_DESCRIPTION", iClient);

    return Plugin_Handled;
}

public Action GetBonusValue(int& iValue)
{
    iValue = CalculateDamageBonus();

    return Plugin_Handled;
}

int CalculateDamageBonus()
{
    int iAliveSurvivorCount = GetAliveSurvivorCount();

    if (!iAliveSurvivorCount) {
        return 0;
    }

    float fDamageBonus = (g_fMapTempHealthBonus - float(g_iLostTempHealth)) * g_fTempHpWorth / GetConVarInt(g_cvTeamSize) * iAliveSurvivorCount;

    return (fDamageBonus > 0.0 && iAliveSurvivorCount > 0) ? RoundToFloor(fDamageBonus) : 0;
}

bool IsClientSurvivor(int iClient) {
    return GetClientTeam(iClient) == TEAM_SURVIVOR;
}

int GetSurvivorPermanentHealth(int iClient)
{
    // Survivors always have minimum 1 permanent hp
    // so that they don't faint in place just like that when all temp hp run out
    // We'll use a workaround for the sake of fair calculations
    // Edit 2: "Incapped HP" are stored in m_iHealth too; we heard you like workarounds, dawg, so we've added a workaround in a workaround
    return GetEntProp(iClient, Prop_Send, "m_currentReviveCount") > 0 ? 0 : (GetEntProp(iClient, Prop_Send, "m_iHealth") > 0 ? GetEntProp(iClient, Prop_Send, "m_iHealth") : 0);
}

int GetSurvivorTemporaryHealth(int iClient)
{
    int temphp = RoundToCeil(GetEntPropFloat(iClient, Prop_Send, "m_healthBuffer") - ((GetGameTime() - GetEntPropFloat(iClient, Prop_Send, "m_healthBufferTime")) * GetConVarFloat(FindConVar("pain_pills_decay_rate")))) - 1;
    return (temphp > 0 ? temphp : 0);
}

bool IsPlayerLedged(int iClient) {
    return view_as<bool>(GetEntProp(iClient, Prop_Send, "m_isHangingFromLedge") | GetEntProp(iClient, Prop_Send, "m_isFallingFromLedge"));
}

int GetAliveSurvivorCount()
{
    int iAliveCount = 0;

    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientInGame(iClient) || !IsClientSurvivor(iClient)) {
            continue;
        }

        if (!L4D_IsPlayerIncapacitated(iClient) && !IsPlayerLedged(iClient)) {
            iAliveCount++;
        }
    }

    return iAliveCount;
}