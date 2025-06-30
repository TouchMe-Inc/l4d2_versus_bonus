#pragma semicolon              1
#pragma newdecls               required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <versus_bonus>
#include <colors>


public Plugin myinfo =
{
    name        = "[VersusBonus] WitchHunter",
    author      = "TouchMe",
    description = "",
    version     = "build_0001",
    url         = "https://github.com/TouchMe-Inc/l4d2_versus_bonus"
};


#define TRANSLATIONS            "vb_witchhunter.phrases"

// Team
#define TEAM_SURVIVOR           2

#define SI_CLASS_WITCH          "witch"

#define MAP_DISTANCE_BASE       400


float g_fMapFactor = 0.0;

Handle g_hWitchList = null;

ConVar g_cvBonusWitchHunter = null;


/**
  * Global event. Called when all plugins loaded.
  */
public void OnAllPluginsLoaded()
{
    if (LibraryExists("versus_bonus")) {
        MakeBonusCritery(GetBonusName, GetBonusShortName, GetBonusDescription, GetBonusValue);
    }
}

public void OnEntityCreated(int iEnt, const char[] sClassName)
{
    if (iEnt > MaxClients && IsValidEntity(iEnt) && StrEqual(sClassName, SI_CLASS_WITCH))
    {
        PushArrayCell(g_hWitchList, EntIndexToEntRef(iEnt));

        CPrintToChatAll("%t%t", "TAG", "ON_WITCH_CREATED", RoundToFloor(g_fMapFactor * GetConVarInt(g_cvBonusWitchHunter)));
    }
}

public void OnPluginStart()
{
    LoadTranslations(TRANSLATIONS);

    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("witch_killed", Event_WitchKilled, EventHookMode_Post);

    g_cvBonusWitchHunter = CreateConVar("sm_vb_witch_hunter", "50");

    g_hWitchList = CreateArray();
}

public void OnConfigsExecuted() {
    g_fMapFactor = float(L4D_GetVersusMaxCompletionScore()) / float(MAP_DISTANCE_BASE);
}

void Event_RoundStart(Event event, const char[] sEventName, bool bDontBroadcast) {
    ClearArray(g_hWitchList);
}

void Event_WitchKilled(Event event, const char[] sEventName, bool bDontBroadcast)
{
    int iWitchEnt = GetEventInt(event, "witchid");

    int iWitchIndex = FindWitchIndex(iWitchEnt);

    if (iWitchIndex == -1) {
        return;
    }

    RemoveFromArray(g_hWitchList, iWitchIndex);
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
    Format(szBuffer, iLength, "%T", "BONUS_DESCRIPTION", iClient, RoundToFloor(g_fMapFactor * GetConVarInt(g_cvBonusWitchHunter)));

    return Plugin_Handled;
}

public Action GetBonusValue(int& iValue)
{
    iValue = 0;

    if (GetWitchFlowPercent() - GetFurthestSurvivorFlowPercent() < 0) {
        iValue = RoundToFloor(g_fMapFactor * GetArraySize(g_hWitchList) * -GetConVarInt(g_cvBonusWitchHunter));
    }

    return Plugin_Handled;
}

int FindWitchIndex(int iWitchEnt)
{
    int iArraySize = GetArraySize(g_hWitchList);

    if (!iArraySize) {
        return -1;
    }

    int iWitchIndex = -1;

    for (int iIndex = 0; iIndex < iArraySize; iIndex ++)
    {
        int iEntRef = GetArrayCell(g_hWitchList, iIndex);

        if (iWitchEnt == EntRefToEntIndex(iEntRef))
        {
            iWitchIndex = iIndex;
            break;
        }
    }

    return iWitchIndex;
}

int GetWitchFlowPercent()
{
    int iRound = InSecondHalfOfRound() ? 1 : 0;

    return RoundToNearest(L4D2Direct_GetVSWitchFlowPercent(iRound) * 100.0);
}

int GetFurthestSurvivorFlowPercent()
{
    int iFlow = RoundToCeil(100.0 * (L4D2_GetFurthestSurvivorFlow()) / L4D2Direct_GetMapMaxFlowDistance());

    return iFlow < 100 ? iFlow : 100;
}

/**
 * Checks if the current round is the second.
 *
 * @return                  Returns true if is second round, otherwise false.
 */
bool InSecondHalfOfRound() {
    return view_as<bool>(GameRules_GetProp("m_bInSecondHalfOfRound"));
}

