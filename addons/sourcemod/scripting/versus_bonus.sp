#pragma semicolon              1
#pragma newdecls               required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <colors>


#undef REQUIRE_PLUGIN
#include <nativevotes_rework>
#define REQUIRE_PLUGIN


public Plugin myinfo =
{
    name        = "VersusBonus",
    author      = "TouchMe",
    description = "[API ONLY] Modular system of bonuses/penalties",
    version     = "build_0008",
    url         = "https://github.com/TouchMe-Inc/l4d2_versus_bonus"
};


#define LIB_NATIVEVOTES         "nativevotes_rework"

#define TRANSLATIONS            "versus_bonus.phrases"

// Gamemode
#define GAMEMODE_VERSUS         "versus"
#define GAMEMODE_VERSUS_REALISM "mutation12"

// Num of round
#define ROUND_FIRST             1
#define ROUND_SECOND            2

// Team
#define TEAM_SURVIVOR           2

// Slots
#define SLOT_HEAVY_HEALTH       3
#define SLOT_LIGHT_HEALTH       4

// Game Rule Team
#define TEAM_A                  0
#define TEAM_B                  1

// Sugar
#define GetVersusCampaignScores L4D2_GetVersusCampaignScores
#define SetVersusCampaignScores L4D2_SetVersusCampaignScores
#define OnEndVersusModeRound    L4D2_OnEndVersusModeRound

#define SIGN(%0)                (%0 >= 0 ? "+" : "−")


enum MenuState
{
    MenuState_None = 0,
    MenuState_ShowList,
    MenuState_ShowDescription
}

enum struct CriteryInfo
{
    Handle name;
    Handle short_name;
    Handle description;
    Handle value;
}


bool g_bGamemodeAvailable = false; /**< Only versus mode */

ConVar g_cvGameMode = null;         /**< mp_gamemode */

bool g_bRoundIsLive = false;

Handle g_hCriteries = INVALID_HANDLE;
Handle g_hHistoryCriteries[2] = {INVALID_HANDLE, ...};

int g_iCriteriesSize = 0;

int g_iClientMenuPagePosition[MAXPLAYERS + 1] = {0, ...};
int g_iClientMenuShowRound[MAXPLAYERS + 1] = {0, ...};
int g_iClientMenuShowIndex[MAXPLAYERS + 1] = {0, ...};
MenuState g_eClientMenuState[MAXPLAYERS + 1] = {MenuState_None, ...};

bool g_bUpdateSelf = false;

bool g_bNativeVotesAvailable = false;

/**
  * Global event. Called when all plugins loaded.
  */
public void OnAllPluginsLoaded() {
    g_bNativeVotesAvailable = LibraryExists(LIB_NATIVEVOTES);
}

/**
  * Global event. Called when a library is removed.
  *
  * @param sName     Library name
  */
public void OnLibraryRemoved(const char[] sName)
{
    if (StrEqual(sName, LIB_NATIVEVOTES)) {
        g_bNativeVotesAvailable = false;
    }
}

/**
  * Global event. Called when a library is added.
  *
  * @param sName     Library name
  */
public void OnLibraryAdded(const char[] sName)
{
    if (StrEqual(sName, LIB_NATIVEVOTES)) {
        g_bNativeVotesAvailable = true;
    }
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    if (GetEngineVersion() != Engine_Left4Dead2)
    {
        strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
        return APLRes_SilentFailure;
    }

    CreateNative("MakeBonusCritery", Native_MakeBonusCritery);

    // Library.
    RegPluginLibrary("versus_bonus");

    return APLRes_Success;
}

any Native_MakeBonusCritery(Handle hPlugin, int iParams)
{
    Function funcName = GetNativeFunction(1);
    Function funcShortName = GetNativeFunction(2);
    Function funcDescription = GetNativeFunction(3);
    Function funcValue = GetNativeFunction(4);

    CriteryInfo critery;
    critery.name = CreateForward(ET_Single, Param_String, Param_Cell, Param_Cell);
    critery.short_name = CreateForward(ET_Single, Param_String, Param_Cell, Param_Cell);
    critery.description = CreateForward(ET_Single, Param_String, Param_Cell, Param_Cell);
    critery.value = CreateForward(ET_Single, Param_CellByRef);

    AddToForward(critery.name, hPlugin, funcName);
    AddToForward(critery.short_name, hPlugin, funcShortName);
    AddToForward(critery.description, hPlugin, funcDescription);
    AddToForward(critery.value, hPlugin, funcValue);

    int iIndex = PushArrayArray(g_hCriteries, critery);

    g_iCriteriesSize = GetArraySize(g_hCriteries);

    return iIndex;
}

public void OnPluginStart()
{
    LoadTranslations(TRANSLATIONS);
    LoadTranslations("core.phrases");

    g_cvGameMode = FindConVar("mp_gamemode");

    HookConVarChange(g_cvGameMode, OnGamemodeChanged);

    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);

    RegConsoleCmd("sm_bonusmenu", Cmd_BonusMenu);
    RegConsoleCmd("sm_bonus", Cmd_Bonus);

    char szGamemode[16];
    GetConVarString(g_cvGameMode, szGamemode, sizeof szGamemode);
    g_bGamemodeAvailable = IsVersusMode(szGamemode);

    g_hCriteries = CreateArray(sizeof CriteryInfo);
    g_hHistoryCriteries[0] = CreateArray();
    g_hHistoryCriteries[1] = CreateArray();

    CreateTimer(1.0, Timer_UpdateBonusList, .flags = TIMER_REPEAT);
}

Action Timer_UpdateBonusList(Handle hTimer)
{
    if (g_bNativeVotesAvailable && NativeVotes_IsVoteInProgress()) {
        return Plugin_Continue;
    }

    for (int iClient = 1; iClient <= MaxClients; iClient ++)
    {
        if (!IsClientInGame(iClient) || IsFakeClient(iClient)) {
            continue;
        }

        switch (g_eClientMenuState[iClient])
        {
            case MenuState_ShowList: {
                g_bUpdateSelf = true;
                ShowBonusMenu(iClient, g_iClientMenuPagePosition[iClient], g_iClientMenuShowRound[iClient]);
                g_bUpdateSelf = false;
            }

            case MenuState_ShowDescription: {
                g_bUpdateSelf = true;
                ShowBonusMenuDescription(iClient, g_iClientMenuShowIndex[iClient]);
                g_bUpdateSelf = false;
            }
        }
    }

    return Plugin_Continue;
}

/**
 * Called when a console variable value is changed.
 */
public void OnGamemodeChanged(ConVar cv, const char[] sOldValue, const char[] sNewValue) {
    g_bGamemodeAvailable = IsVersusMode(sNewValue);
}

void Event_RoundStart(Handle event, char[] name, bool dontBroadcast)
{
    if (g_bGamemodeAvailable == false) {
        return;
    }

    if (!InSecondHalfOfRound())
    {
        ClearArray(g_hHistoryCriteries[0]);
        ClearArray(g_hHistoryCriteries[1]);
    }

    g_bRoundIsLive = true;
}

public Action OnEndVersusModeRound(bool bHasSurvivor)
{
    if (g_bGamemodeAvailable == false) {
        return Plugin_Continue;
    }

    int iTeamIndex = AreTeamsFlipped() ? TEAM_B : TEAM_A;
    int iRoundNumber = GetRoundNumber();
    int iTotalBonus = 0, iMaxDigits = 0;
    for (int iIdx = 0, iTempValue = 0; iIdx < g_iCriteriesSize; iIdx ++)
    {
        CriteryInfo critery;
        GetArrayArray(g_hCriteries, iIdx, critery);
        ExecuteForward_GetValue(critery.value, iTempValue);

        PushArrayCell(g_hHistoryCriteries[iRoundNumber - 1], iTempValue);

        iTotalBonus += iTempValue;

        if ((iTempValue = GetNumberOfDigits(iTempValue)) > iMaxDigits) {
            iMaxDigits = iTempValue;
        }
    }

    if (iTotalBonus != 0) {
        AddTeamScore(iTeamIndex, iTotalBonus);
    }

    return Plugin_Continue;
}

void Event_RoundEnd(Handle event, char[] name, bool dontBroadcast)
{
    if (g_bGamemodeAvailable == false || !g_bRoundIsLive) {
        return;
    }

    g_bRoundIsLive = false;

    int iRoundNumber = GetRoundNumber();
    int iTotalBonus = 0;
    char szFormatedText[192], szSeparator[32];
    char szItemName[32];
    int iLen = 0;

    for (int iIdx = 0, iTempValue = 0; iIdx < g_iCriteriesSize; iIdx ++)
    {
        CriteryInfo critery;
        GetArrayArray(g_hCriteries, iIdx, critery);
        ExecuteForward_GetValue(critery.value, iTempValue);

        iTotalBonus += iTempValue;
    }

    for (int iClient = 1; iClient <= MaxClients; iClient ++)
    {
        if (!IsClientInGame(iClient) || IsFakeClient(iClient)) {
            continue;
        }

        iLen = 0;
        FormatEx(szSeparator, sizeof szSeparator, "%T", "CHAT_BONUS_ITEM_DELIMITER", iClient);

        for (int iIdx = 0, iTempValue = 0; iIdx < g_iCriteriesSize; iIdx ++)
        {
            CriteryInfo critery;
            GetArrayArray(g_hCriteries, iIdx, critery);
            ExecuteForward_GetShortName(critery.short_name, szItemName, sizeof szItemName, iClient);
            ExecuteForward_GetValue(critery.value, iTempValue);

            iLen += Format(szFormatedText[iLen], sizeof szFormatedText, "%T", "CHAT_BONUS_ITEM", iClient, szItemName, iTempValue, iIdx + 1 == g_iCriteriesSize ? "" : szSeparator);
        }

        CPrintToChat(iClient, "%T%T",
            "TAG", iClient,
            "CHAT_SHOW_BONUS_OR_PENALTY_FULL", iClient, iRoundNumber, iTotalBonus, szFormatedText
        );
    }
}

Action Cmd_BonusMenu(int iClient, int iArgs)
{
    if (g_bGamemodeAvailable == false) {
        return Plugin_Continue;
    }

    ShowBonusMenu(iClient, 0, GetRoundNumber());

    return Plugin_Handled;
}

Action Cmd_Bonus(int iClient, int iArgs)
{
    if (g_bGamemodeAvailable == false) {
        return Plugin_Continue;
    }

    int iRoundNumber = GetRoundNumber();
    int iTotalBonus = 0;

    CPrintToChat(iClient, "%T%T%T", "BRACKET_START", iClient, "TAG", iClient, "CHAT_BONUS_TITLE", iClient);

    if (iRoundNumber == 2)
    {
        for (int iIdx = 0, iTempValue = 0; iIdx < g_iCriteriesSize; iIdx ++)
        {
            CriteryInfo critery;
            GetArrayArray(g_hCriteries, iIdx, critery);
            ExecuteForward_GetValue(critery.value, iTempValue);

            iTempValue = GetArrayCell(g_hHistoryCriteries[0], iIdx);

            iTotalBonus += iTempValue;
        }

        CPrintToChat(iClient, "%T%T",
            "BRACKET_MIDDLE", iClient,
            "CHAT_SHOW_BONUS_OR_PENALTY", iClient, 1, iTotalBonus
        );
    }

    char szSeparator[32], szFormatedText[192];
    FormatEx(szSeparator, sizeof szSeparator, "%T", "CHAT_BONUS_ITEM_DELIMITER", iClient);

    char szItemName[64];
    int iLen = 0;
    iTotalBonus = 0;
    for (int iIdx = 0, iTempValue = 0; iIdx < g_iCriteriesSize; iIdx ++)
    {
        CriteryInfo critery;
        GetArrayArray(g_hCriteries, iIdx, critery);
        ExecuteForward_GetShortName(critery.short_name, szItemName, sizeof szItemName, iClient);
        ExecuteForward_GetValue(critery.value, iTempValue);

        iLen += Format(szFormatedText[iLen], sizeof szFormatedText, "%T", "CHAT_BONUS_ITEM", iClient, szItemName, iTempValue, iIdx + 1 == g_iCriteriesSize ? "" : szSeparator);

        iTotalBonus += iTempValue;
    }

    CPrintToChat(iClient, "%T%T",
        "BRACKET_END", iClient,
        "CHAT_SHOW_BONUS_OR_PENALTY_FULL", iClient, iRoundNumber, iTotalBonus, szFormatedText
    );

    return Plugin_Handled;
}

void ShowBonusMenu(int iClient, int iStartItem, int iRoundNumber)
{
    g_iClientMenuPagePosition[iClient] = iStartItem;
    g_iClientMenuShowRound[iClient] = iRoundNumber;
    g_eClientMenuState[iClient] = MenuState_ShowList;

    Menu menu = CreateMenu(HandleShowBonusMenu);

    int iCurrentRoundNumber = GetRoundNumber();
    int iInvertedRoundNumber = InvertRoundNumber(iRoundNumber);

    bool bSelectable = g_bRoundIsLive && iRoundNumber == GetRoundNumber();
    bool bSwitchable = iCurrentRoundNumber == ROUND_SECOND;

    if (!bSelectable && GetArraySize(g_hHistoryCriteries[iRoundNumber - 1]) == 0) {
        return;
    }

    char szFormatedText[64];

    FormatEx(szFormatedText, sizeof szFormatedText, "%T", "PANEL_RESULT_OF_ROUND", iClient, iInvertedRoundNumber);
    AddMenuItem(menu, "switcher", szFormatedText, bSwitchable ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

    int iTotalBonus = 0;
    char szItemName[64];
    for (int iIdx = 0, iTempValue = 0; iIdx < g_iCriteriesSize; iIdx ++)
    {
        CriteryInfo critery;
        GetArrayArray(g_hCriteries, iIdx, critery);
        ExecuteForward_GetName(critery.name, szItemName, sizeof(szItemName), iClient);

        if (bSelectable) {
            ExecuteForward_GetValue(critery.value, iTempValue);
        } else {
            iTempValue = GetArrayCell(g_hHistoryCriteries[iRoundNumber - 1], iIdx);
        }

        FormatEx(szFormatedText, sizeof szFormatedText,
            "%T", "PANEL_BONUS_ITEM", iClient, szItemName, SIGN(iTempValue), Abs(iTempValue)
        );
        AddMenuItem(menu, "item", szFormatedText, bSelectable ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

        iTotalBonus += iTempValue;
    }

    SetMenuTitle(menu, "%T",
        "PANEL_BONUS_TITLE", iClient, iRoundNumber, SIGN(iTotalBonus), Abs(iTotalBonus)
    );

    DisplayMenuAtItem(menu, iClient, iStartItem, 1);
}

public int HandleShowBonusMenu(Menu menu, MenuAction action, int iParam1, int iParam2)
{
    switch (action)
    {
        case MenuAction_Display: g_iClientMenuPagePosition[iParam1] = GetMenuSelectionPosition();

        case MenuAction_Cancel:
        {
            int iClient = iParam1;

            switch (iParam2)
            {
                case MenuCancel_Exit, MenuCancel_Disconnected: {
                    g_eClientMenuState[iClient] = MenuState_None;
                }

                case MenuCancel_Interrupted: {
                    if (!g_bUpdateSelf) g_eClientMenuState[iClient] = MenuState_None;
                }
            }
        }

        case MenuAction_Select:
        {
            int iClient = iParam1;
            int iSelectedIndex = iParam2;

            if (iSelectedIndex == 0) {
                ShowBonusMenu(iClient, g_iClientMenuPagePosition[iClient], InvertRoundNumber(g_iClientMenuShowRound[iClient]));
            } else {
                ShowBonusMenuDescription(iClient, g_iClientMenuPagePosition[iClient] + iSelectedIndex - 1);
            }
        }

        case MenuAction_End: delete menu;
    }

    return 0;
}

void ShowBonusMenuDescription(int iClient, int iIndex)
{
    g_eClientMenuState[iClient] = MenuState_ShowDescription;
    g_iClientMenuShowIndex[iClient] = iIndex;

    Menu menu = CreateMenu(HandleShowBonusMenuDescription);

    CriteryInfo critery;
    GetArrayArray(g_hCriteries, iIndex, critery);

    char szName[64];
    ExecuteForward_GetName(critery.name, szName, sizeof szName, iClient);

    char szDescription[384];
    ExecuteForward_GetDescription(critery.description, szDescription, sizeof szDescription, iClient);

    int iValue = 0;
    ExecuteForward_GetValue(critery.value, iValue);

    SetMenuTitle(menu, "%T", "PANEL_BONUS_INFO", iClient, szName, szDescription, SIGN(iValue), Abs(iValue));

    char szFormatedText[32];
    FormatEx(szFormatedText, sizeof szFormatedText, "%T", "Back", iClient);
    AddMenuItem(menu, "nav", szFormatedText);

    SetMenuExitButton(menu, false);

    DisplayMenu(menu, iClient, MENU_TIME_FOREVER);
}

public int HandleShowBonusMenuDescription(Menu menu, MenuAction action, int iParam1, int iParam2)
{
    switch (action)
    {
        case MenuAction_Cancel:
        {
            int iClient = iParam1;

            switch (iParam2)
            {
                case MenuCancel_Exit, MenuCancel_Disconnected: {
                    g_eClientMenuState[iClient] = MenuState_None;
                }

                case MenuCancel_Interrupted: {
                    if (!g_bUpdateSelf) g_eClientMenuState[iClient] = MenuState_None;
                }
            }
        }

        case MenuAction_Select:
        {
            int iClient = iParam1;
            ShowBonusMenu(iClient, g_iClientMenuPagePosition[iClient], g_iClientMenuShowRound[iClient]);
        }

        case MenuAction_End: delete menu;
    }

    return 0;
}

/**
 *
 */
Action ExecuteForward_GetName(Handle hForward, char[] szBuffer, int iLength, int iClient)
{
    Action aReturn = Plugin_Continue;

    if (GetForwardFunctionCount(hForward))
    {
        Call_StartForward(hForward);
        Call_PushStringEx(szBuffer, iLength, SM_PARAM_STRING_COPY|SM_PARAM_STRING_UTF8, SM_PARAM_COPYBACK);
        Call_PushCell(iLength);
        Call_PushCell(iClient);
        Call_Finish(aReturn);
    }

    return aReturn;
}

Action ExecuteForward_GetShortName(Handle hForward, char[] szBuffer, int iLength, int iClient)
{
    Action aReturn = Plugin_Continue;

    if (GetForwardFunctionCount(hForward))
    {
        Call_StartForward(hForward);
        Call_PushStringEx(szBuffer, iLength, SM_PARAM_STRING_COPY|SM_PARAM_STRING_UTF8, SM_PARAM_COPYBACK);
        Call_PushCell(iLength);
        Call_PushCell(iClient);
        Call_Finish(aReturn);
    }

    return aReturn;
}

Action ExecuteForward_GetDescription(Handle hForward, char[] szBuffer, int iLength, int iClient)
{
    Action aReturn = Plugin_Continue;

    if (GetForwardFunctionCount(hForward))
    {
        Call_StartForward(hForward);
        Call_PushStringEx(szBuffer, iLength, SM_PARAM_STRING_COPY|SM_PARAM_STRING_UTF8, SM_PARAM_COPYBACK);
        Call_PushCell(iLength);
        Call_PushCell(iClient);
        Call_Finish(aReturn);
    }

    return aReturn;
}

Action ExecuteForward_GetValue(Handle hForward, int& iValue)
{
    Action aReturn = Plugin_Continue;

    if (GetForwardFunctionCount(hForward))
    {
        Call_StartForward(hForward);
        Call_PushCellRef(iValue);
        Call_Finish(aReturn);
    }

    return aReturn;
}

int GetNumberOfDigits(int iNumber)
{
    int iDigits = 0;
    do {
        iNumber /= 10;
        iDigits ++;
    } while (iNumber != 0);
    return iDigits;
}

void AddTeamScore(int iTeamIndex, int iValue)
{
    int iScores[2];
    GetVersusCampaignScores(iScores);

    iScores[iTeamIndex] += iValue;
    SetVersusCampaignScores(iScores);
}

int GetRoundNumber() {
    return InSecondHalfOfRound() ? 2 : 1;
}

int InvertRoundNumber(int iRoundNumber) {
    return iRoundNumber == ROUND_SECOND ? ROUND_FIRST : ROUND_SECOND;
}

/**
 * Checks if the current round is the second.
 *
 * @return                  Returns true if is second round, otherwise false.
 */
bool InSecondHalfOfRound() {
    return view_as<bool>(GameRules_GetProp("m_bInSecondHalfOfRound"));
}

/**
 * Checks if team A has swapped places with team B.
 *
 * @return                  Returns true if team A swapped, otherwise false.
 */
bool AreTeamsFlipped() {
    return view_as<bool>(GameRules_GetProp("m_bAreTeamsFlipped"));
}

/**
 * Is the game mode versus.
 *
 * @param szGamemode        A string containing the name of the game mode.
 *
 * @return                  Returns true if verus, otherwise false.
 */
bool IsVersusMode(const char[] szGamemode) {
    return (StrEqual(szGamemode, GAMEMODE_VERSUS, false)
    || StrEqual(szGamemode, GAMEMODE_VERSUS_REALISM, false));
}

int Abs(int iValue) {
    return iValue < 0 ? -iValue : iValue;
}
