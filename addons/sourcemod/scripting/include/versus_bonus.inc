#if defined _versus_bonus_included
#endinput
#endif
#define _versus_bonus_included

typedef BonusName = function Action(char[] szBuffer, int iLength, int iClient);
typedef BonusShortName = function Action(char[] szBuffer, int iLength, int iClient);
typedef BonusDescription = function Action(char[] szBuffer, int iLength, int iClient);
typedef BonusValue = function Action(int& iValue)

native int MakeBonusCritery(BonusName name, BonusShortName shortName, BonusDescription description, BonusValue value);

public SharedPlugin __pl_versus_bonus = 
{
	name = "versus_bonus",
	file = "versus_bonus.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_versus_bonus_SetNTVOptional()
{
	MarkNativeAsOptional("MakeBonusCritery");
}
#endif
