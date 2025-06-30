#pragma semicolon              1
#pragma newdecls               required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <versus_bonus>

public Plugin myinfo =
{
    name        = "[VersusBonus] Pills Bonus",
    author      = "TouchMe",
    description = "",
    version     = "build_0001",
    url         = "https://github.com/TouchMe-Inc/l4d2_versus_bonus"
};


// Team
#define TEAM_SURVIVOR           2

// Slots
#define SLOT_LIGHT_HEALTH       4

#define TRANSLATIONS            "vb_pills.phrases"


ConVar g_cvTeamSize = null;
ConVar g_cvBonusPerSurvivorMultiplier = null;
ConVar g_cvPermanentHealthProportion = null;
ConVar g_cvPillsHpFactor = null;
ConVar g_cvPillsMaxBonus = null;

int g_iPillWorth = 0;

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
    g_cvPillsHpFactor = CreateConVar("sm2_pills_hp_factor", "6.0", "Unused pills HP worth = map bonus HP value / this");
    g_cvPillsMaxBonus = CreateConVar("sm2_pills_max_bonus", "30", "Unused pills cannot be worth more than this");
}

public void OnConfigsExecuted()
{
    int iTeamSize = GetConVarInt(g_cvTeamSize);
    int iMapDistance = L4D_GetVersusMaxCompletionScore();
    float fMapBonus = iMapDistance * (GetConVarFloat(g_cvBonusPerSurvivorMultiplier) * iTeamSize);
    float fPermHealthProportion = GetConVarFloat(g_cvPermanentHealthProportion);
    float fPermHpWorth = fMapBonus / iTeamSize / 100 * fPermHealthProportion;

    g_iPillWorth = Clamp(RoundToNearest(50 * (fPermHpWorth / GetConVarFloat(g_cvPillsHpFactor)) / 5) * 5, 5, GetConVarInt(g_cvPillsMaxBonus));
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
    Format(szBuffer, iLength, "%T", "BONUS_DESCRIPTION", iClient, g_iPillWorth);

    return Plugin_Handled;
}

public Action GetBonusValue(int& iValue)
{
    iValue = 0;

    for (int iClient = 1; iClient <= MaxClients; iClient ++)
    {
        if (!IsClientInGame(iClient) || !IsPlayerAlive(iClient) || GetClientTeam(iClient) != TEAM_SURVIVOR) {
            continue;
        }

        if (L4D_IsPlayerIncapacitated(iClient)) {
            continue;
        }

        if (HasPills(iClient)) {
            iValue += g_iPillWorth;
        }
    }

    return Plugin_Handled;
}

/**
 * Checks if a weapon is in a slot.
 */
bool HasClientWeapon(int iClient, int iSlot, const char[] szClassname)
{
    int iEnt = GetPlayerWeaponSlot(iClient, iSlot);

    if (IsValidEdict(iEnt))
    {
        char szBuffer[32]; GetEdictClassname(iEnt, szBuffer, sizeof(szBuffer));

        if (StrEqual(szBuffer, szClassname)) {
            return true;
        }
    }

    return false;
}

bool HasPills(int iClient) {
    return HasClientWeapon(iClient, SLOT_LIGHT_HEALTH, "weapon_pain_pills");
}

int Clamp(int inc, int low, int high) {
	return (inc > high) ? high : ((inc < low) ? low : inc);
}