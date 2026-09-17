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
    version     = "build_0009",
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

// Menu
#define MENU_KEY_BACK 8
#define MENU_KEY_NEXT 9
#define MENU_PAGE_SIZE 6

// Sound
#define DEFAULT_MENU_CLICK_SOUND "ui/buttonclick.wav"
#define DEFAULT_MENU_BACK_SOUND  "ui/buttonrollover.wav"

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

ConVar g_cvMenuClickSound, g_cvMenuBackSound;
char g_szMenuClickSound[PLATFORM_MAX_PATH], g_szMenuBackSound[PLATFORM_MAX_PATH];

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

public void OnMapStart()
{
    LoadSoundFromCvar(g_cvMenuClickSound, g_szMenuClickSound, sizeof g_szMenuClickSound, DEFAULT_MENU_CLICK_SOUND);
    LoadSoundFromCvar(g_cvMenuBackSound, g_szMenuBackSound, sizeof g_szMenuBackSound, DEFAULT_MENU_BACK_SOUND);

    PrecacheSound(g_szMenuClickSound);
    PrecacheSound(g_szMenuBackSound);
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

    g_cvMenuClickSound  = CreateConVar("sm_vb_click_sound", DEFAULT_MENU_CLICK_SOUND, "Path to the sound that is played when ..");
    g_cvMenuBackSound   = CreateConVar("sm_vb_back_sound", DEFAULT_MENU_BACK_SOUND, "Path to the sound that is played when ..");

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
        if (g_eClientMenuState[iClient] == MenuState_None) {
            continue;
        }

        if (!IsClientInGame(iClient) || IsFakeClient(iClient)) {
            continue;
        }

        switch (GetClientMenu(iClient)) {
            case MenuSource_External, MenuSource_Normal: {
                continue;
            }
        }

        g_bUpdateSelf = true;

        switch (g_eClientMenuState[iClient])
        {
            case MenuState_ShowList: {
                ShowBonusMenu(iClient, g_iClientMenuPagePosition[iClient], g_iClientMenuShowRound[iClient]);
            }

            case MenuState_ShowDescription: {
                ShowBonusDescription(iClient, g_iClientMenuShowIndex[iClient]);
            }
        }

        g_bUpdateSelf = false;
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

    Panel panel = CreatePanel();

    int iStart = iStartItem;
    int iMaxPages = GetMaxPages(g_iCriteriesSize);
    int iCurrentPage = GetCurrentPage(iStart);
    int iEnd = GetPageEnd(iStart, g_iCriteriesSize);

    bool bSelectable = g_bRoundIsLive && iRoundNumber == GetRoundNumber();
    bool bSwitchable = GetRoundNumber() == ROUND_SECOND;

    if (!bSelectable && GetArraySize(g_hHistoryCriteries[iRoundNumber - 1]) == 0) {
        return;
    }

    char szFormatedText[128];

    int iItemNumber = 1;
    int iTotalBonus = 0;
    char szItemName[64];
    char szItemShortName[64];
    for (int iIdx = iStart; iIdx < iEnd; iIdx++)
    {
        CriteryInfo critery;
        GetArrayArray(g_hCriteries, iIdx, critery);
        ExecuteForward_GetName(critery.name, szItemName, sizeof szItemName, iClient);
        ExecuteForward_GetShortName(critery.short_name, szItemShortName, sizeof szItemShortName, iClient);

        int iTempValue;
        if (bSelectable) {
            ExecuteForward_GetValue(critery.value, iTempValue);
        } else {
            iTempValue = GetArrayCell(g_hHistoryCriteries[iRoundNumber - 1], iIdx);
        }

        FormatEx(szFormatedText, sizeof szFormatedText,
            "%s%d. %T", bSelectable ? "->" : "", iItemNumber++, "MENU_ITEM", iClient, SIGN(iTempValue), Abs(iTempValue), szItemName, szItemShortName
        );
        DrawPanelText(panel, szFormatedText);

        iTotalBonus += iTempValue;
    }

    DrawPanelSpacer(panel);

    FormatEx(szFormatedText, sizeof szFormatedText, "%s7. %T", bSwitchable ? "->" : "", "MENU_RESULT_OF_ROUND", iClient, InvertRoundNumber(iRoundNumber));
    DrawPanelText(panel, szFormatedText);

    DrawPanelSpacer(panel);

    if (HasPrevPage(iCurrentPage))
    {
        FormatEx(szFormatedText, sizeof szFormatedText, "->%d. %T", MENU_KEY_BACK, "MENU_PREV_PAGE", iClient);
        DrawPanelText(panel, szFormatedText);
    } else {
        FormatEx(szFormatedText, sizeof szFormatedText, "->%d. %T", MENU_KEY_BACK, "MENU_CLOSE", iClient);
        DrawPanelText(panel, szFormatedText);
    }

    if (HasNextPage(iCurrentPage, iMaxPages))
    {
        FormatEx(szFormatedText, sizeof szFormatedText, "->%d. %T", MENU_KEY_NEXT, "MENU_NEXT_PAGE", iClient);
        DrawPanelText(panel, szFormatedText);
    } else if (iMaxPages > 1) {
        DrawPanelSpacer(panel);
    }

    if (iMaxPages > 1) {
        FormatEx(szFormatedText, sizeof szFormatedText, "%T", "MENU_TITLE_WITH_PAGE", iClient, iRoundNumber, SIGN(iTotalBonus), Abs(iTotalBonus), iCurrentPage + 1, iMaxPages);
    } else {
        FormatEx(szFormatedText, sizeof szFormatedText, "%T", "MENU_TITLE", iClient, iRoundNumber, SIGN(iTotalBonus), Abs(iTotalBonus));
    }

    SetPanelTitle(panel, szFormatedText);

    SendPanelToClient(panel, iClient, PanelHandler_ShowBonusMenu, 1);
}

public int PanelHandler_ShowBonusMenu(Menu menu, MenuAction action, int iClient, int iParam)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            int iStart = g_iClientMenuPagePosition[iClient];
            int iCurrentPage = GetCurrentPage(iStart);
            int iMaxPages = GetMaxPages(g_iCriteriesSize);

            switch (iParam)
            {
                case 7:
                {
                    ShowBonusMenu(iClient, 0, InvertRoundNumber(g_iClientMenuShowRound[iClient]));
                    PlaySoundMenuBack(iClient);
                }

                case MENU_KEY_NEXT:
                {
                    if (HasNextPage(iCurrentPage, iMaxPages)) {
                        ShowBonusMenu(iClient, iStart + MENU_PAGE_SIZE, g_iClientMenuShowRound[iClient]);
                        PlaySoundMenuClick(iClient);
                    }
                }

                case MENU_KEY_BACK:
                {
                    if (HasPrevPage(iCurrentPage)) {
                        ShowBonusMenu(iClient, iStart - MENU_PAGE_SIZE, g_iClientMenuShowRound[iClient]);
                        PlaySoundMenuClick(iClient);
                    } else {
                        g_eClientMenuState[iClient] = MenuState_None;
                        PlaySoundMenuBack(iClient);
                    }
                }

                default:
                {
                    int iEnd   = GetPageEnd(iStart, g_iCriteriesSize);
                    int iItemsOnPage = iEnd - iStart;
                    int iSelectedIndex = iParam;

                    if (iSelectedIndex && iSelectedIndex <= iItemsOnPage)
                    {
                        ShowBonusDescription(iClient, iStart + iSelectedIndex - 1);
                        PlaySoundMenuClick(iClient);
                    }
                }
            }
        }

        case MenuAction_Cancel:
        {
            switch (iParam)
            {
                case MenuCancel_Interrupted:
                {
                    if (!g_bUpdateSelf) g_eClientMenuState[iClient] = MenuState_None;
                }
            }
        }
    }

    return 0;
}

void ShowBonusDescription(int iClient, int iIndex)
{
    if (iIndex < 0 || iIndex >= g_iCriteriesSize)
    {
        ShowBonusMenu(iClient, 0, g_iClientMenuShowRound[iClient]);
        return;
    }

    g_eClientMenuState[iClient] = MenuState_ShowDescription;
    g_iClientMenuShowIndex[iClient] = iIndex;

    Panel panel = CreatePanel();

    CriteryInfo critery;
    GetArrayArray(g_hCriteries, iIndex, critery);

    char szName[64];
    ExecuteForward_GetName(critery.name, szName, sizeof szName, iClient);

    char szDescription[384];
    ExecuteForward_GetDescription(critery.description, szDescription, sizeof szDescription, iClient);

    int iValue = 0;
    ExecuteForward_GetValue(critery.value, iValue);

    char szFormatedText[128];

    DrawPanelText(panel, szDescription);

    DrawPanelSpacer(panel);

    FormatEx(szFormatedText, sizeof szFormatedText, "->%d. %T", MENU_KEY_BACK, "MENU_CLOSE", iClient);
    DrawPanelText(panel, szFormatedText);

    FormatEx(szFormatedText, sizeof szFormatedText, "%T", "MENU_BONUS_INFO", iClient, szName, SIGN(iValue), Abs(iValue));
    SetPanelTitle(panel, szFormatedText);

    SendPanelToClient(panel, iClient, PanelHandler_ShowBonusMenuDescription, 1);
}

public int PanelHandler_ShowBonusMenuDescription(Menu menu, MenuAction action, int iClient, int iParam)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            switch (iParam)
            {
                case MENU_KEY_BACK: {
                    ShowBonusMenu(iClient, g_iClientMenuPagePosition[iClient], g_iClientMenuShowRound[iClient]);
                    PlaySoundMenuBack(iClient);
                }
            }
        }

        case MenuAction_Cancel:
        {
            switch (iParam)
            {
                case MenuCancel_Interrupted:
                {
                    if (!g_bUpdateSelf) g_eClientMenuState[iClient] = MenuState_None;
                }
            }
        }
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

void LoadSoundFromCvar(ConVar hCvar, char[] szBuffer, int iLength, const char[] szDefault)
{
    GetConVarString(hCvar, szBuffer, iLength);

    if (szBuffer[0] == '\0' || !IsSoundExists(szBuffer)) {
        strcopy(szBuffer, iLength, szDefault);
    }
}

bool IsSoundExists(const char[] szSoundPath)
{
    char szPath[PLATFORM_MAX_PATH];
    FormatEx(szPath, sizeof(szPath), "sound/%s", szSoundPath);

    return (FileExists(szPath, true));
}

void PlaySoundMenuClick(int iClient) {
    EmitSoundToClient(iClient, g_szMenuClickSound);
}

void PlaySoundMenuBack(int iClient) {
    EmitSoundToClient(iClient, g_szMenuBackSound);
}

// ============================================================================
// HELPERS: PAGINATION
// ============================================================================

int GetMaxPages(int iTotalItems) {
    return (iTotalItems + MENU_PAGE_SIZE - 1) / MENU_PAGE_SIZE;
}

int GetCurrentPage(int iStart) {
    return iStart / MENU_PAGE_SIZE;
}

int GetPageEnd(int iStart, int iTotalItems)
{
    int iEnd = iStart + MENU_PAGE_SIZE;
    return (iEnd > iTotalItems) ? iTotalItems : iEnd;
}

bool HasNextPage(int iCurrentPage, int iMaxPages) {
    return iCurrentPage < iMaxPages - 1;
}

bool HasPrevPage(int iCurrentPage) {
    return iCurrentPage > 0;
}

// ============================================================================
// HELPERS: PANEL
// ============================================================================

void DrawPanelSpacer(Handle hPanel)
{
    DrawPanelText(hPanel, " ");
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
