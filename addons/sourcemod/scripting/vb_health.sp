#pragma semicolon              1
#pragma newdecls               required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <versus_bonus>


public Plugin myinfo =
{
    name        = "[VersusBonus] Health Bonus",
    author      = "TouchMe",
    description = "",
    version     = "build_0001",
    url         = "https://github.com/TouchMe-Inc/l4d2_versus_bonus"
};


#define TRANSLATIONS            "vb_health.phrases"

// Team
#define TEAM_SURVIVOR           2


enum
{
    BILL = 0,
    ZOEY = 1,
    FRANCIS = 2,
    LOUIS = 3,
    NICK = 4,
    ROCHELLE = 5,
    COACH = 6,
    ELLIS = 7,
};

int g_iCharacterHealthResored[8] = {0, ...};

ConVar g_cvTeamSize = null;
ConVar g_cvBonusPerSurvivorMultiplier = null;
ConVar g_cvPermanentHealthProportion = null;

float g_fPermHpWorth = 0.0;


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
    HookEvent("heal_success", Event_HealSuccess);
}

public void OnConfigsExecuted()
{
    int iTeamSize = GetConVarInt(g_cvTeamSize);
    int iMapDistance = L4D_GetVersusMaxCompletionScore();

    float fMapBonus = iMapDistance * (GetConVarFloat(g_cvBonusPerSurvivorMultiplier) * iTeamSize);
    float fPermHealthProportion = GetConVarFloat(g_cvPermanentHealthProportion);

    g_fPermHpWorth = fMapBonus / iTeamSize / 100 * fPermHealthProportion;
}

void Event_RoundStart(Event event, char[] szEventName, bool bDontBroadcast)
{
    for (int iCharacter = BILL; iCharacter <= ELLIS; iCharacter ++)
    {
        g_iCharacterHealthResored[iCharacter] = 0;
    }
}

void Event_HealSuccess(Event event, char[] szEventName, bool bDontBroadcast)
{
    int iHealthRestored = GetEventInt(event, "health_restored");
    int iClient = GetClientOfUserId(GetEventInt(event, "subject"));
    int iCharacter = GetSurvivorCharacter(iClient);

    g_iCharacterHealthResored[iCharacter] += iHealthRestored;
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
    int iCharacterBonus[8] = {0, ...};
    
    int iBonus = CalculateHealthBonus(iCharacterBonus);

    int iLen = Format(szBuffer, iLength, "%T", "BONUS_DESCRIPTION", iClient);

    if (iBonus == 0) {
        return Plugin_Handled;
    }

    char szCharacterName[32];
    for (int iCharacter = BILL; iCharacter <= ELLIS; iCharacter ++)
    {
        if (!iCharacterBonus[iCharacter]) {
            continue;
        }

        GetSurvivorCharacterName(iCharacter, szCharacterName, sizeof(szCharacterName));

        iLen += Format(szBuffer[iLen], iLength - iLen, "%T", "BONUS_CHARACTER", iClient, szCharacterName, iCharacterBonus[iCharacter], RoundToFloor(g_fPermHpWorth * iCharacterBonus[iCharacter]));
    }

    return Plugin_Handled;
}

public Action GetBonusValue(int& iValue)
{
    iValue = CalculateHealthBonus();

    return Plugin_Handled;
}

int CalculateHealthBonus(int iCharacterBonus[8] = {0, ...})
{
    int iTotalBonus = 0;

    for (int iClient = 1; iClient <= MaxClients; iClient ++)
    {
        if (!IsClientInGame(iClient) || !IsPlayerAlive(iClient) || GetClientTeam(iClient) != TEAM_SURVIVOR) {
            continue;
        }

        if (L4D_IsPlayerIncapacitated(iClient)) {
            continue;
        }

        if (L4D_GetPlayerReviveCount(iClient) > 0) {
            continue;
        }

        int iCharacter = GetSurvivorCharacter(iClient);

        iCharacterBonus[iCharacter] = GetClientHealth(iClient) - g_iCharacterHealthResored[iCharacter];

        if (iCharacterBonus[iCharacter] < 0) {
            iCharacterBonus[iCharacter] = 0;
        }

        iTotalBonus += RoundToFloor(g_fPermHpWorth * iCharacterBonus[iCharacter]);
    }

    return iTotalBonus;
}

int GetSurvivorCharacter(int iClient) {
    return GetEntProp(iClient, Prop_Send, "m_Gender") - 3;
}

void GetSurvivorCharacterName(int iCharacter, char[] szCharacterName, int iLength)
{
    switch (iCharacter)
    {
        case BILL: strcopy(szCharacterName, iLength, "Bill");
        case FRANCIS: strcopy(szCharacterName, iLength, "Francis");
        case LOUIS: strcopy(szCharacterName, iLength, "Louis");
        case ZOEY: strcopy(szCharacterName, iLength, "Zoey");
        case COACH: strcopy(szCharacterName, iLength, "Coach");
        case ELLIS: strcopy(szCharacterName, iLength, "Ellis");
        case NICK: strcopy(szCharacterName, iLength, "Nick");
        case ROCHELLE: strcopy(szCharacterName, iLength, "Rochelle");

        default: strcopy(szCharacterName, iLength, "Unknown");
    }
}
