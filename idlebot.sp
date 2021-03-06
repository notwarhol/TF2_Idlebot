//Thanks to sigsegv for his reversing work.

#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>
#include <PathFollower>
#include <PathFollower_Nav>
#include <ripext>

#undef REQUIRE_PLUGIN
#include <FillUserInfo>
#define REQUIRE_PLUGIN

#pragma newdecls required

bool g_bEmulate[MAXPLAYERS + 1];
bool g_bPath[MAXPLAYERS + 1];
bool g_bRetreat[MAXPLAYERS + 1];

float g_flNextUpdate[MAXPLAYERS + 1];
float m_ctUseWeaponAbilities[MAXPLAYERS + 1];

float m_ctVelocityLeft[MAXPLAYERS + 1];
float m_ctVelocityRight[MAXPLAYERS + 1];

//Boat
float g_vecCurrentGoal[MAXPLAYERS + 1][3];
int g_iAdditionalButtons[MAXPLAYERS + 1];
float g_flAdditionalVelocity[MAXPLAYERS + 1][3];

enum RouteType
{
	DEFAULT_ROUTE,
	FASTEST_ROUTE,
	SAFEST_ROUTE,
	RETREAT_ROUTE,
};

RouteType m_iRouteType[MAXPLAYERS + 1];

int g_iCurrentAction[MAXPLAYERS + 1];
bool g_bStartedAction[MAXPLAYERS + 1];

bool g_bUpdateLookingAroundForEnemies[MAXPLAYERS + 1];
float g_flNextLookTime[MAXPLAYERS + 1];

//Idle
float g_flLastInput[MAXPLAYERS + 1];
bool g_bIdle[MAXPLAYERS + 1];

char g_szBotModels[][] =
{
	"models/bots/scout/bot_scout.mdl",
	"models/bots/sniper/bot_sniper.mdl",
	"models/bots/soldier/bot_soldier.mdl",
	"models/bots/demo/bot_demo.mdl",
	"models/bots/medic/bot_medic.mdl",
	"models/bots/heavy/bot_heavy.mdl",
	"models/bots/pyro/bot_pyro.mdl",
	"models/bots/spy/bot_spy.mdl",
	"models/bots/engineer/bot_engineer.mdl"
};

#include <actions/CTFBotAim>

enum //ACTION
{
	ACTION_IDLE = 0,
	ACTION_ATTACK,
	ACTION_MARK_GIANT,
	ACTION_COLLECT_MONEY,
	ACTION_GOTO_UPGRADE,
	ACTION_UPGRADE,
	ACTION_GET_AMMO,
	ACTION_MOVE_TO_FRONT,
	ACTION_GET_HEALTH,
	ACTION_USE_ITEM,
	ACTION_SNIPER_LURK,
	ACTION_MEDIC_HEAL,
	ACTION_MELEE_ATTACK,
	ACTION_MVM_ENGINEER_IDLE,
	ACTION_MVM_ENGINEER_BUILD_SENTRYGUN,
	ACTION_MVM_ENGINEER_BUILD_DISPENSER
};

#include <actions/utility>

#include <actions/CTFBotAttack>
#include <actions/CTFBotMarkGiant>
#include <actions/CTFBotCollectMoney>
#include <actions/CTFBotGoToUpgradeStation>
#include <actions/CTFBotGetAmmo>
#include <actions/CTFBotGetHealth>
#include <actions/CTFBotMoveToFront>
#include <actions/CTFBotUseItem>
#include <actions/CTFBotSniperLurk>
#include <actions/CTFBotMedicHeal>
#include <actions/CTFBotMeleeAttack>
#include <actions/CTFBotMvMEngineerIdle>
#include <actions/CTFBotMvMEngineerBuildSentryGun>
#include <actions/CTFBotMvMEngineerBuildDispenser>
#include <actions/CTFBotUpgrade>

Handle g_hHudInfo;

public Plugin myinfo = 
{
	name = "[TF2] MvM AFK Bot",
	author = "Pelipoika",
	description = "",
	version = "1.0",
	url = "http://www.sourcemod.net/plugins.php?author=Pelipoika&search=1"
};

public void OnPluginStart()
{
	RegAdminCmd("sm_defender", Command_Robot, ADMFLAG_ROOT);
	
	for (int i = 1; i <= MaxClients; i++)
		OnClientPutInServer(i);
	
	g_hHudInfo = CreateHudSynchronizer();
	
	InitTFBotAim();
}

bool bCanFakePing = false;
public void OnAllPluginsLoaded()
{
	bCanFakePing = LibraryExists("FillUserInfo");
	
	PrintToServer("[IdleBOT] bCanFakePing = %i", bCanFakePing);
}

public void OnMapStart()
{
	InitGamedata();
}

public void TF2_OnWaitingForPlayersEnd()
{
	if(!TF2_IsMvM())
	{
		SetFailState("[IdleBOT] Disabling for non mvm map");
	}
}

public void OnClientPutInServer(int client)
{
	g_flNextCommand[client] = GetGameTime();
	
	g_iStation[client] = -1;
	g_bEmulate[client] = false;
	g_iAdditionalButtons[client] = 0;
	g_vecCurrentGoal[client] = NULL_VECTOR;
	g_bPath[client] = true;
	g_bRetreat[client] = false;
	g_iCurrentAction[client] = ACTION_IDLE;
	g_bStartedAction[client] = false;
	g_bUpdateLookingAroundForEnemies[client] = true;
	g_flNextLookTime[client] = GetGameTime();
	g_flNextUpdate[client] = GetGameTime();
	g_flLastInput[client] = GetGameTime();
	g_bIdle[client] = false;
	
	m_aNestArea[client] = NavArea_Null;
	
	m_ctVelocityLeft[client] = 0.0;
	m_ctVelocityRight[client] = 0.0;
	m_ctUseWeaponAbilities[client] = 0.0;
	
	m_iRouteType[client] = DEFAULT_ROUTE;
	
	CTFBotMarkGiant_OnEnd(client);
	CTFBotCollectMoney_OnEnd(client);
	CTFBotGoToUpgradeStation_OnEnd(client);
	CTFBotAttack_OnEnd(client);
	CTFBotGetAmmo_OnEnd(client);
	CTFBotGetHealth_OnEnd(client);
	CTFBotMoveToFront_OnEnd(client);
	CTFBotUseItem_OnEnd(client);
}

public Action Command_Robot(int client, int args)
{
	if(client > 0 && client <= MaxClients && IsClientInGame(client))
	{
		if(TF2_IsMvM() && TF2_GetClientTeam(client) != TFTeam_Red)
		{
			ReplyToCommand(client, "For RED team only");
			return Plugin_Handled;
		}
		
		SetDefender(client, !g_bEmulate[client]);
	}
	
	return Plugin_Handled;
}

stock bool SetDefender(int client, bool bEnabled)
{
	g_iCurrentAction[client] = ACTION_IDLE;

	if(TF2_GetClientTeam(client) == TFTeam_Unassigned || TF2_GetClientTeam(client) == TFTeam_Spectator)
	{
		FakeClientCommand(client, "autoteam");
		FakeClientCommand(client, "joinclass random");
		
		ShowVGUIPanel(client, "info", _, false);
		ShowVGUIPanel(client, "class_blue", _, false);
		ShowVGUIPanel(client, "class_red", _, false);
	}
	
	KV_MvM_UpgradesDone(client);
	
	if(!bEnabled && g_bEmulate[client])
	{
		//IDLEBOT OFF
		SetVariantString("");
		AcceptEntityInput(client, "SetCustomModel");
		SetEntProp(client, Prop_Send, "m_bUseClassAnimations", 1);
		
		SendConVarValue(client, FindConVar("sv_client_predict"), "-1");
		SetEntProp(client, Prop_Data, "m_bLagCompensation", true);
		SetEntProp(client, Prop_Data, "m_bPredictWeapons", true);
		
		g_bEmulate[client] = false;
		
		if(PF_Exists(client))
		{
			PF_StopPathing(client);
			PF_Destroy(client);
		}
		
		if(bCanFakePing && FillUserInfo_IsBOT(client))
		{
			FillUserInfo_ToggleBOT(client);
		}
	}
	else if(!g_bEmulate[client])
	{
		//IDLEBOT ON
		SendConVarValue(client, FindConVar("sv_client_predict"), "0");
		SetEntProp(client, Prop_Data, "m_bLagCompensation", false);
		SetEntProp(client, Prop_Data, "m_bPredictWeapons", false);
		
		if(!PF_Exists(client))
		{
			PF_Create(client, 18.0, 45.0, 1000.0, 0.6, MASK_PLAYERSOLID, 200.0, 0.2);
			PF_EnableCallback(client, PFCB_Approach, PluginBot_Approach);
			PF_EnableCallback(client, PFCB_ClimbUpToLedge, PluginBot_Jump);
			PF_EnableCallback(client, PFCB_IsEntityTraversable, PluginBot_IsEntityTraversable);
			PF_EnableCallback(client, PFCB_GetPathCost, PluginBot_PathCost);
			
			PF_EnableCallback(client, PFCB_OnMoveToSuccess, PluginBot_MoveToSuccess);
			
			PF_EnableCallback(client, PFCB_PathFailed, PluginBot_PathFail);
			
			PF_EnableCallback(client, PFCB_OnActorEmoted, PluginBot_OnActorEmoted);
			//PF_EnableCallback(client, PFCB_PathSuccess, PluginBot_PathSuccess);
		}
		
		if(bCanFakePing && !FillUserInfo_IsBOT(client))
		{
			FillUserInfo_ToggleBOT(client);
		}
		
		BotAim(client).Reset();
		g_bEmulate[client] = true;
	}
}

float g_flCollectSentries;
ArrayList g_hSentries;

RoundState g_RoundState;
public void OnGameFrame()
{
	g_RoundState = GameRules_GetRoundState();
	
	if(g_flCollectSentries < GetGameTime())
	{
		g_flCollectSentries = GetGameTime() + 4.0;
		
		if(g_hSentries == null)
			g_hSentries = new ArrayList();
	
		g_hSentries.Clear();
		
		int iEnt = -1;
		while ((iEnt = FindEntityByClassname(iEnt, "obj_sentrygun")) != -1)
		{
			PF_UpdateLastKnownArea(iEnt);
			
			g_hSentries.Push(EntIndexToEntRef(iEnt));
		}
	}
}

public Action OnPlayerRunCmd(int client, int &iButtons, int &iImpulse, float fVel[3], float fAng[3], int &iWeapon)
{
	if(client <= 0)
		return Plugin_Handled;
		
	//AvoidPlayers(client, fVel[0], fVel[1]);
	
	if(!IsClientConnected(client) || IsFakeClient(client))
		return Plugin_Continue;	
	
	//No can do.
	if(TF2_IsMvM() && TF2_GetClientTeam(client) == TFTeam_Blue || iButtons != 0 || iImpulse != 0 || TF2_GetClientTeam(client) == TFTeam_Spectator)
		g_flLastInput[client] = GetGameTime();

	float flLastInput   = (GetGameTime() - g_flLastInput[client]);
	float flMaxIdleTime = (FindConVar("mp_idlemaxtime").FloatValue * 60.0);

	if(flLastInput > (flMaxIdleTime / 2) && !g_bEmulate[client])
	{
		PrintCenterText(client, "You seem to be away... (%.0fs / %.0fs)\n%s", flLastInput, flMaxIdleTime, (flLastInput > (flMaxIdleTime / 1.2)) ? "The server will take over soon..." : "");
	}
	
	if (flLastInput > flMaxIdleTime)
	{
		if(!g_bIdle[client] && !g_bEmulate[client])
		{
			g_bIdle[client] = true;
			SetDefender(client, true);
		}
	}
	else
	{
		if(g_bIdle[client])
		{
			g_bIdle[client] = false;
			SetDefender(client, false);
		}
	}
	
	if(!IsPlayerAlive(client) || !g_bEmulate[client] || !PF_Exists(client))
		return Plugin_Continue;

	bool bChanged = false;
	if(g_iAdditionalButtons[client] != 0)
	{
		iButtons |= g_iAdditionalButtons[client];
		g_iAdditionalButtons[client] = 0;
		bChanged = true;
	}
	
	//Always crouch jump
	if(GetEntProp(client, Prop_Send, "m_bJumping"))
	{
		iButtons |= IN_DUCK;
		bChanged = true;
	}
	
	if(m_ctReload[client]  > GetGameTime()) { iButtons |= IN_RELOAD;  bChanged = true; }
	if(m_ctFire[client]    > GetGameTime()) { iButtons |= IN_ATTACK;  bChanged = true; }
	if(m_ctAltFire[client] > GetGameTime()) { iButtons |= IN_ATTACK2; bChanged = true; }
	
	//EquipRequiredWeapon();
	UpdateLookingAroundForEnemies(client);
	
	BotAim(client).Upkeep();
	BotAim(client).FireWeaponAtEnemy();
	
	StartMainAction(client);
	RunCurrentAction(client);
	
	Dodge(client);
		
	if(g_bPath[client])
	{
		PF_StartPathing(client);
		
		float vecDir[3];
		bool bAvoiding = AvoidBumpingEnemies(client, vecDir);
		if(bAvoiding)
		{
			AddVectors(g_vecCurrentGoal[client], vecDir, g_vecCurrentGoal[client]);
		}
	
		float flDistance = GetVectorDistance(g_vecCurrentGoal[client], WorldSpaceCenter(client));
		if(flDistance > 10.0)
		{
			TF2_MoveTo(client, g_vecCurrentGoal[client], fVel, fAng);
			
			//PrintCenterText(client, "%f %f", fVel[0], fVel[1]);
			
			bChanged = true;
		}
	}
	else
	{
		PF_StopPathing(client);
	}
	
	if(m_ctVelocityLeft[client] > GetGameTime()) {
		fVel[1] += g_flAdditionalVelocity[client][1];
		bChanged = true;
	}	
	if(m_ctVelocityRight[client] > GetGameTime()) {
		fVel[1] += g_flAdditionalVelocity[client][1];
		bChanged = true;
	}
	
	ShowKeys(client, fVel);	
	
	return bChanged ? Plugin_Changed : Plugin_Continue;
}


stock bool OpportunisticallyUseWeaponAbilities(int client)
{
	if (!(m_ctUseWeaponAbilities[client] < GetGameTime())) {
		return false;
	}
	
	m_ctUseWeaponAbilities[client] = GetGameTime() + GetRandomFloat(0.3, 1.2);
	
	if (TF2_GetPlayerClass(client) == TFClass_DemoMan && HasDemoShieldEquipped(client)) 
	{
		float eye_vec[3];
		EyeVectors(client, eye_vec);
		
		float absOrigin[3]; absOrigin = GetAbsOrigin(client);
		absOrigin[0] += (100.0 * eye_vec[0]);
		absOrigin[1] += (100.0 * eye_vec[1]);
		absOrigin[2] += (100.0 * eye_vec[2]);
		
		float fraction;
		if (PF_IsPotentiallyTraversable(client, GetAbsOrigin(client), absOrigin, IMMEDIATELY, fraction))
		{
			BotAim(client).PressAltFireButton();
		}
	}
	
	if(HasParachuteEquipped(client))
	{
		bool burning = TF2_IsPlayerInCondition(client, TFCond_OnFire);
		float health_ratio = view_as<float>(GetClientHealth(client)) / view_as<float>(GetMaxHealth(client));
		
		if (TF2_IsPlayerInCondition(client, TFCond_Parachute)) 
		{
			if (health_ratio >= 0.5 && !burning && !l_is_above_ground(client, 150.0)) 
			{
				g_iAdditionalButtons[client] |= IN_JUMP;
			} 
		} 
		else 
		{
			float velocity[3]; 
			velocity = GetAbsVelocity(client);
		
			if (health_ratio >= 0.5 && !burning && velocity[2] < 0.0 && !l_is_above_ground(client, 300.0)) 
			{
				g_iAdditionalButtons[client] |= IN_JUMP;
			} 
		}
	}
	
	//The Hitmans Heatmaker
	if (IsSniperRifle(client) && TF2_IsPlayerInCondition(client, TFCond_Slowed))
	{
		if(GetEntPropFloat(client, Prop_Send, "m_flRageMeter") >= 0.0 && !GetEntProp(client, Prop_Send, "m_bRageDraining"))
		{
			BotAim(client).PressReloadButton();
			return true;
		}
	}
	
	//Phlogistinator
	if(IsWeapon(client, TF_WEAPON_FLAMETHROWER))
	{
		if(GetEntPropFloat(client, Prop_Send, "m_flRageMeter") >= 100.0 && !GetEntProp(client, Prop_Send, "m_bRageDraining"))
		{
			BotAim(client).PressAltFireButton();
			return true;
		}
	}
	
	if(!CTFBotUseItem_IsPossible(client))
		return false;
	
	int elementCount = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
	for (int i = 0; i < elementCount; i++)
	{
		int weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
		if (!IsValidEntity(weapon)) 
			continue;
			
		if (GetWeaponID(weapon) == TF_WEAPON_BUFF_ITEM) 
		{
			if (StrEqual(EntityNetClass(weapon), "CTFBuffItem") && GetEntPropFloat(client, Prop_Send, "m_flRageMeter") >= 100.0)
			{
				ChangeAction(client, ACTION_USE_ITEM, "Using TF_WEAPON_BUFF_ITEM");
				return true;
			}
			
			continue;
		}
		
		if (GetWeaponID(weapon) == TF_WEAPON_LUNCHBOX) 
		{
			if (!HasAmmo(weapon) || (TF2_GetPlayerClass(client) == TFClass_Scout && GetEntPropFloat(client, Prop_Send, "m_flEnergyDrinkMeter") < 100.0))
			{
				continue;
			}
			
			ChangeAction(client, ACTION_USE_ITEM, "Using TF_WEAPON_LUNCHBOX");
			return true;
		}
		
	/*	if (GetWeaponID(weapon) == TF_WEAPON_BAT_WOOD && GetAmmoCount(client, TF_AMMO_GRENADES1) > 0) 
		{
			const CKnownEntity *threat = this->GetVisionInterface()->GetPrimaryKnownThreat(false);
			if (threat == nullptr || !threat->IsVisibleRecently()) 
			{
				continue;
			}
			
			this->PressAltFireButton();
		}*/
	}
	
	return false;
}

bool l_is_above_ground(int actor, float min_height)
{
	float from[3]; from = GetAbsOrigin(actor);
	float to[3]; to = GetAbsOrigin(actor);
	to[2] -= min_height;
	
	return !PF_IsPotentiallyTraversable(actor, from, to, IMMEDIATELY);
}

stock void StartMainAction(int client, bool pretend = false)
{
	bool bCanCheck = g_flNextUpdate[client] < GetGameTime();
	
	if(!bCanCheck)
		return;

	SetHudTextParams(0.05, 0.05, 1.1, 255, 255, 200, 255, 0, 0.0, 0.0, 0.0);
	ShowSyncHudText(client, g_hHudInfo, "%s\nRouteType %s\nPathing %s\nRetreating %s\nLookAroundForEnemies %s\nWeapon %s #%i\n\nThe server plays for you while you are away.\nPress any key to take control\n ", 
										CurrentActionToName(g_iCurrentAction[client]), 
										CurrentRouteTypeToName(client), 
										g_bPath[client] ? "Yes" : "No",
										g_bRetreat[client] ? "Yes" : "No",
										g_bUpdateLookingAroundForEnemies[client] ? "Yes" : "No",
										CurrentWeaponIDToName(client),
										GetWeaponID(GetActiveWeapon(client)));
	
	if(g_RoundState == RoundState_BetweenRounds && !pretend)
	{	
		if(CTFBotCollectMoney_IsPossible(client))
		{
			ChangeAction(client, ACTION_COLLECT_MONEY, "CTFBotCollectMoney is possible");
			m_iRouteType[client] = FASTEST_ROUTE;
		}
		else if(!IsStandingAtUpgradeStation(client) && !GameRules_GetProp("m_bPlayerReady", 1, client)
			&& g_iCurrentAction[client] != ACTION_MOVE_TO_FRONT)
		{
			//g_iCurrentAction[client] != ACTION_MVM_ENGINEER_BUILD_SENTRYGUN
			//g_iCurrentAction[client] != ACTION_MVM_ENGINEER_BUILD_DISPENSER
			
			ChangeAction(client, ACTION_GOTO_UPGRADE, "!IsStandingAtUpgradeStation && RoundState_BetweenRounds");
			m_iRouteType[client] = DEFAULT_ROUTE;
		}
	}
	else if(g_RoundState == RoundState_RoundRunning || pretend)
	{
		OpportunisticallyUseWeaponAbilities(client);
	
		bool low_health = false;
		
		float health_ratio = view_as<float>(GetClientHealth(client)) / view_as<float>(GetMaxHealth(client));
		
		if ((GetTimeSinceWeaponFired(client) > 2.0 || TF2_GetPlayerClass(client) == TFClass_Sniper)	&& health_ratio < FindConVar("tf_bot_health_critical_ratio").FloatValue){
			low_health = true;
		} 
		else if (health_ratio < FindConVar("tf_bot_health_ok_ratio").FloatValue){
			low_health = true;
		}
	
		if (low_health && CTFBotGetHealth_IsPossible(client) && !IsInvulnerable(client))
		{
			ChangeAction(client, ACTION_GET_HEALTH, "Getting health");
			m_iRouteType[client] = SAFEST_ROUTE;
			
			return;
		}
		else if (IsAmmoLow(client) && CTFBotGetAmmo_IsPossible(client))
		{
			ChangeAction(client, ACTION_GET_AMMO, "Getting ammo");
			m_iRouteType[client] = SAFEST_ROUTE;
			
			return;
		}
		
		SetEntProp(client, Prop_Data, "m_bLagCompensation", false);
		SetEntProp(client, Prop_Data, "m_bPredictWeapons", false);
		
		if(g_iCurrentAction[client] != ACTION_USE_ITEM
		&& g_iCurrentAction[client] != ACTION_MELEE_ATTACK)
		{
			switch(TF2_GetPlayerClass(client))
			{
				case TFClass_Medic:
				{
					ChangeAction(client, ACTION_MEDIC_HEAL, "StartMainAction Medic: Start heal mission");
					m_iRouteType[client] = FASTEST_ROUTE;
				}
				case TFClass_Scout:
				{
					if(CTFBotCollectMoney_IsPossible(client))
					{
						ChangeAction(client, ACTION_COLLECT_MONEY, "StartMainAction Scout: Collecting money.");
						m_iRouteType[client] = FASTEST_ROUTE;
					}
					else if(CTFBotMarkGiant_IsPossible(client))
					{
						ChangeAction(client, ACTION_MARK_GIANT, "StartMainAction Scout: Marking giant.");	
						m_iRouteType[client] = SAFEST_ROUTE;
					}
					else if(CTFBotAttack_IsPossible(client))
					{
						ChangeAction(client, ACTION_ATTACK, "StartMainAction Scout: Attacking robots.");
						m_iRouteType[client] = DEFAULT_ROUTE;
					}
					else
					{
						ChangeAction(client, ACTION_IDLE, "StartMainAction Scout: Nothing to do.");
						m_iRouteType[client] = DEFAULT_ROUTE;
					}
				}
				case TFClass_Sniper:
				{
					if(IsSniperRifle(client))
					{
						m_iRouteType[client] = SAFEST_ROUTE;
						ChangeAction(client, ACTION_SNIPER_LURK, "StartMainAction Sniper: wants to lurk."); 
					}
					else
					{
						ChangeAction(client, ACTION_ATTACK, "StartMainAction Sniper: Attacking robots.");
					}
				}
				case TFClass_Engineer:
				{
					if(g_iCurrentAction[client] == ACTION_GET_AMMO && !CTFBotMvMEngineerBuildSentryGun_IsPossible(client) || !CTFBotMvMEngineerBuildDispenser_IsPossible(client))
					{
						return;
					}
					
					if(g_iCurrentAction[client] != ACTION_MVM_ENGINEER_BUILD_SENTRYGUN && g_iCurrentAction[client] != ACTION_MVM_ENGINEER_BUILD_DISPENSER)
					{
						ChangeAction(client, ACTION_MVM_ENGINEER_IDLE, "StartMainAction Engineer: Start building.");
					}
				}
				default:
				{
					if(CTFBotAttack_IsPossible(client))
					{
						ChangeAction(client, ACTION_ATTACK, "StartMainAction CTFBotAttack_IsPossible");
						m_iRouteType[client] = FASTEST_ROUTE;
					}
					else if(CTFBotCollectMoney_IsPossible(client))
					{
						ChangeAction(client, ACTION_COLLECT_MONEY, "StartMainAction CTFBotCollectMoney_IsPossible");
						m_iRouteType[client] = SAFEST_ROUTE;
					}
					else
					{
						ChangeAction(client, ACTION_IDLE, "StartMainAction Nothing to do.");
						m_iRouteType[client] = DEFAULT_ROUTE;
					}
				}
			}
		}
	}
	
	g_flNextUpdate[client] = GetGameTime() + 0.5;
}

//Stop whatever current action we're doing properly, and change to another.
//Return whether or not a new action was started.
stock bool ChangeAction(int client, int new_action, const char[] reason = "None")
{
	//Don't allow starting the same function twice.
	if(new_action == g_iCurrentAction[client])
		return false;
	
	//Cannot start new actions unless use item is done.
	if(g_iCurrentAction[client] == ACTION_USE_ITEM && !CTFBotUseItem_IsDone(client) && m_ctTimeout[client] > GetGameTime())
		return false;

	PrintToServer("\"%N\" Change Action \"%s\" -> \"%s\" Reason: \"%s\"", client, CurrentActionToName(g_iCurrentAction[client]), CurrentActionToName(new_action), reason);
	
	g_bRetreat[client] = false;
	g_bStartedAction[client] = false;
	
	//Stop
	StopCurrentAction(client);

	//Start
	StartNewAction(client, new_action);
	
	//Store
	g_iCurrentAction[client] = new_action;
	
	SetVariantString(g_szBotModels[view_as<int>(TF2_GetPlayerClass(client)) - 1]);
	AcceptEntityInput(client, "SetCustomModel");
	SetEntProp(client, Prop_Send, "m_bUseClassAnimations", 1);

	return g_bStartedAction[client];
}

stock void StopCurrentAction(int client)
{
	switch(g_iCurrentAction[client])
	{
		case ACTION_MARK_GIANT:                   CTFBotMarkGiant_OnEnd(client);
		case ACTION_COLLECT_MONEY:                CTFBotCollectMoney_OnEnd(client);
		case ACTION_UPGRADE:                      CTFBotPurchaseUpgrades_OnEnd(client);
		case ACTION_GOTO_UPGRADE:                 CTFBotGoToUpgradeStation_OnEnd(client);
		case ACTION_ATTACK:                       CTFBotAttack_OnEnd(client);
		case ACTION_GET_AMMO:                     CTFBotGetAmmo_OnEnd(client);
		case ACTION_GET_HEALTH:                   CTFBotGetHealth_OnEnd(client);
		case ACTION_MOVE_TO_FRONT:                CTFBotMoveToFront_OnEnd(client);
		case ACTION_USE_ITEM:                     CTFBotUseItem_OnEnd(client);
		case ACTION_SNIPER_LURK:                  CTFBotSniperLurk_OnEnd(client);
		case ACTION_MEDIC_HEAL:                   CTFBotMedicHeal_OnEnd(client);
		case ACTION_MELEE_ATTACK:                 CTFBotMeleeAttack_OnEnd(client);
		case ACTION_MVM_ENGINEER_IDLE:            CTFBotMvMEngineerIdle_OnEnd(client);
		case ACTION_MVM_ENGINEER_BUILD_SENTRYGUN: CTFBotMvMEngineerBuildSentryGun_OnEnd(client);
		case ACTION_MVM_ENGINEER_BUILD_DISPENSER: CTFBotMvMEngineerBuildDispenser_OnEnd(client);
	}
}

stock void StartNewAction(int client, int new_action)
{
	switch(new_action)
	{
		case ACTION_IDLE:                         g_bPath[client] = false;
		case ACTION_MARK_GIANT:                   g_bStartedAction[client] = CTFBotMarkGiant_OnStart(client);
		case ACTION_COLLECT_MONEY:                g_bStartedAction[client] = CTFBotCollectMoney_OnStart(client);
		case ACTION_UPGRADE:                      g_bStartedAction[client] = CTFBotPurchaseUpgrades_OnStart(client);
		case ACTION_GOTO_UPGRADE:                 g_bStartedAction[client] = CTFBotGoToUpgradeStation_OnStart(client);
		case ACTION_ATTACK:                       g_bStartedAction[client] = CTFBotAttack_OnStart(client);
		case ACTION_GET_AMMO:                     g_bStartedAction[client] = CTFBotGetAmmo_OnStart(client);
		case ACTION_GET_HEALTH:                   g_bStartedAction[client] = CTFBotGetHealth_OnStart(client);
		case ACTION_MOVE_TO_FRONT:                g_bStartedAction[client] = CTFBotMoveToFront_OnStart(client);
		case ACTION_USE_ITEM:                     g_bStartedAction[client] = CTFBotUseItem_OnStart(client);
		case ACTION_SNIPER_LURK:                  g_bStartedAction[client] = CTFBotSniperLurk_OnStart(client);
		case ACTION_MEDIC_HEAL:                   g_bStartedAction[client] = CTFBotMedicHeal_OnStart(client);
		case ACTION_MELEE_ATTACK:                 g_bStartedAction[client] = CTFBotMeleeAttack_OnStart(client);
		case ACTION_MVM_ENGINEER_IDLE:            g_bStartedAction[client] = CTFBotMvMEngineerIdle_OnStart(client);
		case ACTION_MVM_ENGINEER_BUILD_SENTRYGUN: g_bStartedAction[client] = CTFBotMvMEngineerBuildSentryGun_OnStart(client);	
		case ACTION_MVM_ENGINEER_BUILD_DISPENSER: g_bStartedAction[client] = CTFBotMvMEngineerBuildDispenser_OnStart(client);	
	}
}

stock bool RunCurrentAction(int client)
{
	StuckMonitor(client);
	
	//Keep jumping while stuck
	if(IsStuck(client) && GetEntityFlags(client) & FL_ONGROUND)
	{
		//Can't jump if we just hold space
		//This fixes that.
		int nOldButtons = GetEntProp(client, Prop_Data, "m_nOldButtons");
		SetEntProp(client, Prop_Data, "m_nOldButtons", (nOldButtons &= ~(IN_JUMP|IN_DUCK)));
	
		g_iAdditionalButtons[client] |= IN_JUMP;
		
		TF2_RemoveCondition(client, TFCond_Taunting);
	}

	//Update
	switch(g_iCurrentAction[client])
	{
		case ACTION_MARK_GIANT:                   g_bStartedAction[client] = CTFBotMarkGiant_Update(client);
		case ACTION_COLLECT_MONEY:                g_bStartedAction[client] = CTFBotCollectMoney_Update(client);
		case ACTION_UPGRADE:                      g_bStartedAction[client] = CTFBotPurchaseUpgrades_Update(client);
		case ACTION_GOTO_UPGRADE:                 g_bStartedAction[client] = CTFBotGoToUpgradeStation_Update(client);
		case ACTION_ATTACK:                       g_bStartedAction[client] = CTFBotAttack_Update(client);
		case ACTION_GET_AMMO:                     g_bStartedAction[client] = CTFBotGetAmmo_Update(client);
		case ACTION_MOVE_TO_FRONT:                g_bStartedAction[client] = CTFBotMoveToFront_Update(client);
		case ACTION_GET_HEALTH:                   g_bStartedAction[client] = CTFBotGetHealth_Update(client);
		case ACTION_USE_ITEM:                     g_bStartedAction[client] = CTFBotUseItem_Update(client);
		case ACTION_SNIPER_LURK:                  g_bStartedAction[client] = CTFBotSniperLurk_Update(client);
		case ACTION_MEDIC_HEAL:                   g_bStartedAction[client] = CTFBotMedicHeal_Update(client);
		case ACTION_MELEE_ATTACK:                 g_bStartedAction[client] = CTFBotMeleeAttack_Update(client);
		case ACTION_MVM_ENGINEER_IDLE:            g_bStartedAction[client] = CTFBotMvMEngineerIdle_Update(client);	
		case ACTION_MVM_ENGINEER_BUILD_SENTRYGUN: g_bStartedAction[client] = CTFBotMvMEngineerBuildSentryGun_Update(client);	
		case ACTION_MVM_ENGINEER_BUILD_DISPENSER: g_bStartedAction[client] = CTFBotMvMEngineerBuildDispenser_Update(client);	
	}

	if(g_iCurrentAction[client] == ACTION_GET_HEALTH
	|| g_iCurrentAction[client] == ACTION_GET_AMMO)
	{
		bool bHealedByDispenser = false;
		
		for (int i = 0; i < GetEntProp(client, Prop_Send, "m_nNumHealers"); i++)
		{
			int iHealerIndex = GetHealerByIndex(client, i);
			
			//Skip player healers, we want to know if we are healed by a dispenser.
			if(IsValidClientIndex(iHealerIndex))
				continue;
			
			//We are on the hunt for ammo, this dispenser is empty, NEXT
			if(g_iCurrentAction[client] == ACTION_GET_AMMO && GetEntProp(iHealerIndex, Prop_Send, "m_iAmmoMetal") <= 0)
				continue;
			
			//If we are being healed by a non player entity it's propably a dispenser.
			bHealedByDispenser = true;
			
			break;
		}
		
		//Unzoom when no target and not healed by dispenser because we arent allowed to move if zoomed.
		if(TF2_GetPlayerClass(client) == TFClass_Sniper && !IsValidClientIndex(m_hAimTarget[client]))
		{
			if (TF2_IsPlayerInCondition(client, TFCond_Zoomed) && !bHealedByDispenser)
			{
				BotAim(client).PressAltFireButton();
			}
		}
	
		
		//Path if not healed by dispenser.
		g_bPath[client] = !bHealedByDispenser;
	}

	return g_bStartedAction[client];
}

stock void ShowKeys(int client, float fVel[3])
{
	char sOutput[256];
	
	int iButtons = g_iAdditionalButtons[client];
	
	if(m_ctReload[client]  > GetGameTime()) { iButtons |= IN_RELOAD;  }
	if(m_ctFire[client]    > GetGameTime()) { iButtons |= IN_ATTACK;  }
	if(m_ctAltFire[client] > GetGameTime()) { iButtons |= IN_ATTACK2; }
	
	if (fVel[0] > 0) iButtons |= IN_FORWARD;
	if (fVel[0] < 0) iButtons |= IN_BACK;
	
	if (fVel[1] < 0) iButtons |= IN_MOVELEFT;
	if (fVel[1] > 0) iButtons |= IN_MOVERIGHT;
	
	
	// Is he pressing "w"?
	if(iButtons & IN_FORWARD)
		Format(sOutput, sizeof(sOutput), "     W     ");
	else
		Format(sOutput, sizeof(sOutput), "     -     ");
	
	// Is he pressing "space"?
	if(iButtons & IN_JUMP)
		Format(sOutput, sizeof(sOutput), "%s     JUMP\n", sOutput);
	else
		Format(sOutput, sizeof(sOutput), "%s     _   \n", sOutput);
	
	// Is he pressing "a"?
	if(iButtons & IN_MOVELEFT)
		Format(sOutput, sizeof(sOutput), "%s  A", sOutput);
	else
		Format(sOutput, sizeof(sOutput), "%s  -", sOutput);
		
	// Is he pressing "s"?
	if(iButtons & IN_BACK)
		Format(sOutput, sizeof(sOutput), "%s  S", sOutput);
	else
		Format(sOutput, sizeof(sOutput), "%s  -", sOutput);
		
	// Is he pressing "d"?
	if(iButtons & IN_MOVERIGHT)
		Format(sOutput, sizeof(sOutput), "%s  D", sOutput);
	else
		Format(sOutput, sizeof(sOutput), "%s  -", sOutput);
	
	// Is he pressing "ctrl"?
	if(iButtons & IN_DUCK)
		Format(sOutput, sizeof(sOutput), "%s       DUCK\n", sOutput);
	else
		Format(sOutput, sizeof(sOutput), "%s       _   \n", sOutput);
		
	// Is he pressing "mouse1"?
	if(iButtons & IN_ATTACK)
		Format(sOutput, sizeof(sOutput), "%sMOUSE1", sOutput);
	else
		Format(sOutput, sizeof(sOutput), "%s_     ", sOutput);
	
	// Is he pressing "mouse1"?
	if(iButtons & IN_ATTACK2)
		Format(sOutput, sizeof(sOutput), "%s  MOUSE2", sOutput);
	else
		Format(sOutput, sizeof(sOutput), "%s  _     ", sOutput);
	
	Handle hBuffer = StartMessageOne("KeyHintText", client);
	BfWriteByte(hBuffer, 1);
	BfWriteString(hBuffer, sOutput);
	EndMessage();
}

stock void UpdateLookingAroundForEnemies(int client)
{
	if(!g_bUpdateLookingAroundForEnemies[client])
		return;

	int iTarget = -1;

	//Don't constantly switch target as sniper.
	if (TF2_GetPlayerClass(client) == TFClass_Sniper && IsValidClientIndex(m_hAimTarget[client]) 
	&& IsValidClientIndex(m_hAttackTarget[client]) && IsLineOfFireClear(GetEyePosition(client), GetEyePosition(m_hAttackTarget[client]))
	&& !IsInvulnerable(m_hAttackTarget[client]))
		iTarget = m_hAimTarget[client];
	else
		iTarget = Entity_GetClosestClient(client);
	
	if(IsValidClientIndex(iTarget))
	{
		BotAim(client).AimHeadTowardsEntity(iTarget, CRITICAL, 0.1, "Looking at visible threat");
	}
	else
	{
		m_hAimTarget[client] = -1;
		
		if(g_flNextLookTime[client] > GetGameTime())
			return;
		
		g_flNextLookTime[client] = GetGameTime() + GetRandomFloat(0.3, 1.0);
		
		UpdateLookingAroundForIncomingPlayers(client, true);
	}
	
	if(!IsValidClientIndex(m_hAttackTarget[client]))
		return;

	//Pathing stops when we are near enough enemy.
	if(g_iCurrentAction[client] == ACTION_ATTACK || g_iCurrentAction[client] == ACTION_USE_ITEM)
	{	
		float dist_to_target = GetVectorDistance(GetAbsOrigin(client), GetAbsOrigin(m_hAttackTarget[client]));
		
		bool bLOS = IsLineOfFireClear(GetEyePosition(client), GetEyePosition(m_hAttackTarget[client]));
		if(!bLOS)
		{
			g_bPath[client] = true;
		}
		else
		{
			if(((IsMeleeWeapon(client) || IsWeapon(client, TF_WEAPON_FLAMETHROWER)) && dist_to_target > 100.0) 
			|| (IsCombatWeapon(client) && dist_to_target > 500.0))
			{
				g_bRetreat[client] = false;
				g_bPath[client] = true;
			}
			else
			{
				if(dist_to_target <= 300.0)
				{
					//Keep distance to enemy.
				
					if(!g_bRetreat[client] && !IsMeleeWeapon(client))
					{
						float flRetreatRange = 400.0;
						
						NavArea lastArea = PF_GetLastKnownArea(client);
						if(lastArea == NavArea_Null)
							return;	
						
						int iTeamNum = view_as<int>(GetEnemyTeam(client));
												
						int eax = (iTeamNum + iTeamNum * 4); //eax
						int edi = view_as<int>(lastArea) + eax * 4 + 364;  //edi
						
						eax = edi + 0xC; // +12
						
						int connections = LoadFromAddress(view_as<Address>(eax), NumberType_Int32);
						
						if(connections > 0)
						{
							float vecRandomPoint[3];
							NavArea navArea = NavArea_Null;
							
							for (int i = 0; i <= 20; i++)
							{
								int iRandomArea = (4 * GetRandomInt(0, connections - 1));
								
								Address areas = view_as<Address>(LoadFromAddress(view_as<Address>(eax + 4), NumberType_Int32));
								navArea = view_as<NavArea>(LoadFromAddress(areas + view_as<Address>(iRandomArea), NumberType_Int32));
								
								if(navArea == NavArea_Null)
									continue;
								
								navArea.GetRandomPoint(vecRandomPoint);
								vecRandomPoint[2] += 18.0;
								
								//PrintToServer("[#%i] NavArea ID %i (x %f y %f z %f)", i, navArea.GetID(), vecRandomPoint[0], vecRandomPoint[1], vecRandomPoint[2]);
								
								float to[3]; SubtractVectors(GetAbsOrigin(client), vecRandomPoint, to);
								if(GetVectorLength(to, true) > flRetreatRange * flRetreatRange)
								{
									if (IsLineOfFireClear(GetEyePosition(client), vecRandomPoint))
										break;
								}
							}
							
							PF_SetGoalVector(client, vecRandomPoint);
							g_bPath[client] = true;
							g_bRetreat[client] = true;
							//PrintToChatAll("Retreat to %f %f %f", vecRandomPoint[0], vecRandomPoint[1], vecRandomPoint[2]);
						}
					}
				}
				else
				{
					g_bRetreat[client] = false;
					g_bPath[client] = false;
				}
			}
		}
	}
}

stock void UpdateLookingAroundForIncomingPlayers(int client, bool enemy)
{
	NavArea lastArea = PF_GetLastKnownArea(client);
	if(lastArea == NavArea_Null)
		return;	
	
	int iTeamNum = GetClientTeam(client);
	
	if(!enemy)
		iTeamNum = view_as<int>(GetEnemyTeam(client));
		
	float flRange = 150.0;
	if(TF2_IsPlayerInCondition(client, TFCond_Zoomed))
		flRange = 750.0;
	
	int eax = (iTeamNum + iTeamNum * 4); //eax
	int edi = view_as<int>(lastArea) + eax * 4 + 364;  //edi
	
	eax = edi + 0xC; // +12
	
	int connections = LoadFromAddress(view_as<Address>(eax), NumberType_Int32);
	
	if(connections > 0)
	{
		float vecRandomPoint[3];
		NavArea navArea = NavArea_Null;
		
		for (int i = 0; i <= 20; i++)
		{
			int iRandomArea = (4 * GetRandomInt(0, connections - 1));
			
			Address areas = view_as<Address>(LoadFromAddress(view_as<Address>(eax + 4), NumberType_Int32));
			navArea = view_as<NavArea>(LoadFromAddress(areas + view_as<Address>(iRandomArea), NumberType_Int32));
			
			if(navArea == NavArea_Null)
				continue;
			
			navArea.GetRandomPoint(vecRandomPoint);
			vecRandomPoint[2] += 53.25;
			
			//PrintToServer("[#%i] NavArea ID %i (x %f y %f z %f)", i, navArea.GetID(), vecRandomPoint[0], vecRandomPoint[1], vecRandomPoint[2]);
			
			float to[3]; SubtractVectors(GetAbsOrigin(client), vecRandomPoint, to);
			if(GetVectorLength(to, true) > flRange * flRange)
			{
				if (IsLineOfFireClear(GetEyePosition(client), vecRandomPoint))
					break;
			}
		}
		
		//PrintToChatAll("Look @ %f %f %f", vecRandomPoint[0], vecRandomPoint[1], vecRandomPoint[2]);
		BotAim(client).AimHeadTowards(vecRandomPoint, BORING, 1.0, "Looking toward enemy invasion areas");
	}
}

stock void Dodge(int actor)
{
	if (IsInvulnerable(actor) ||
		TF2_IsPlayerInCondition(actor, TFCond_Zoomed)   ||
		TF2_IsPlayerInCondition(actor, TFCond_Taunting))
	{
		return;
	}
	
	if (TF2_GetPlayerClass(actor) == TFClass_Engineer  ||
		TF2_GetPlayerClass(actor) == TFClass_Medic||
		TF2_IsPlayerInCondition(actor, TFCond_Disguised)  ||
		TF2_IsPlayerInCondition(actor, TFCond_Disguising) ||
		IsStealthed(actor)) 
	{
		return;
	}
	
	if (IsWeapon(actor, TF_WEAPON_COMPOUND_BOW)) 
	{
		if (GetCurrentCharge(GetActiveWeapon(actor)) != 0.0) 
		{
			return;
		}
	}
	/*else {
		if (!this->IsLineOfFireClear(threat->GetLastKnownPosition())) {
			return;
		}
	}*/
	
	if(g_bPath[actor])
		return;
	
	if(m_hAimTarget[actor] <= 0)
		return;
		
	float eye_vec[3];
	EyeVectors(actor, eye_vec);
	
	float side_dir[3];
	side_dir[0] = -eye_vec[1];
	side_dir[1] = eye_vec[0];
	
	NormalizeVector(side_dir, side_dir);
	
	int random = GetRandomInt(0, 100);
	if (random < 20) 
	{
		float strafe_left[3]; strafe_left = GetAbsOrigin(actor);
		strafe_left[0] += 25.0 * side_dir[0];
		strafe_left[1] += 25.0 * side_dir[1];
		strafe_left[2] += 0.0;
		
		if (!PF_HasPotentialGap(actor, GetAbsOrigin(actor), strafe_left)) 
		{
			g_flAdditionalVelocity[actor][1] = -500.0;
			m_ctVelocityLeft[actor] = GetGameTime() + 0.5;
		}
	} 
	else if (random > 80) 
	{
		float strafe_right[3]; strafe_right = GetAbsOrigin(actor);
		strafe_right[0] += 25.0 * side_dir[0];
		strafe_right[1] += 25.0 * side_dir[1];
		strafe_right[2] += 0.0;
		
		if (!PF_HasPotentialGap(actor, GetAbsOrigin(actor), strafe_right)) 
		{
			g_flAdditionalVelocity[actor][1] = 500.0;
			m_ctVelocityRight[actor] = GetGameTime() + 0.5;
		}
	}
}

// stuck monitoring
bool m_isStuck[MAXPLAYERS + 1];					// if true, we are stuck
float m_stuckTimer[MAXPLAYERS + 1];				// how long we've been stuck
float m_stuckPos[MAXPLAYERS + 1][3];			// where we got stuck
float m_moveRequestTimer[MAXPLAYERS + 1];

#define STUCK_RADIUS 100.0

//Stuck check
stock void StuckMonitor(int client)
{
	// a timer is needed to smooth over a few frames of inactivity due to state changes, etc.
	// we only want to detect idle situations when the bot really doesn't "want" to move.
	const float idleTime = 0.25;
	if ( (GetGameTime() - m_moveRequestTimer[client]) > idleTime )
	{
		// we have no desire to move, and therefore cannot emit stuck events
		// prepare our internal state for when the bot starts to move next
		m_stuckPos[client] = GetAbsOrigin(client);
		m_stuckTimer[client] = GetGameTime();

		return;
	}
	
	if ( IsStuck(client) )
	{
		// we are/were stuck - have we moved enough to consider ourselves "dislodged"
		if ( GetVectorDistance(GetAbsOrigin(client), m_stuckPos[client]) > STUCK_RADIUS )
		{
			// we've just become un-stuck
			ClearStuckStatus(client, "UN-STUCK" );
		}
	}
	else
	{
		// we're not stuck - yet
		if ( GetVectorDistance(GetAbsOrigin(client), m_stuckPos[client]) > STUCK_RADIUS )
		{
			// we have moved - reset anchor
			m_stuckPos[client] = GetAbsOrigin(client);
			m_stuckTimer[client] = GetGameTime();
		}
		else
		{
			const float flDesiredSpeed = 300.0;
		
			// within stuck range of anchor. if we've been here too long, we're stuck
			float minMoveSpeed = 0.1 * flDesiredSpeed + 0.1;
			float escapeTime = STUCK_RADIUS / minMoveSpeed;
			
			if ( (GetGameTime() - m_stuckTimer[client]) > escapeTime )
			{
				// we have taken too long - we're stuck
				m_isStuck[client] = true;
				
				PrintToServer("StuckMonitor STUCK");
			}
		}
	}
}

//Reset stuck status to un-stuck
stock void ClearStuckStatus( int client, const char[] reason )
{
	if ( IsStuck(client) )
	{
		m_isStuck[client] = false;
	}

	// always reset stuck monitoring data in case we cleared preemptively are were not yet stuck
	m_stuckPos[client] = GetAbsOrigin(client);
	m_stuckTimer[client] = GetGameTime();
	
	//PrintToServer("ClearStuckStatus \"%s\"", reason);
}

stock bool IsStuck( int client )
{
	return m_isStuck[client];
}

stock float GetStuckDuration( int client )
{
	return IsStuck(client) ? (GetGameTime() - m_stuckTimer[client]) : 0.0;
}


public void PluginBot_Approach(int bot_entidx, const float vec[3])
{
	if(TF2_IsPlayerInCondition(bot_entidx, TFCond_Taunting))
		return;

	m_moveRequestTimer[bot_entidx] = GetGameTime();
	
	g_vecCurrentGoal[bot_entidx] = vec;
	
	float nothing[3];
	if(!IsValidClientIndex(m_hAimTarget[bot_entidx]) && PF_GetFutureSegment(bot_entidx, 1, nothing) && !g_bUpdateLookingAroundForEnemies[bot_entidx])
	{
		BotAim(bot_entidx).AimHeadTowards(TF2_GetLookAheadPosition(bot_entidx), BORING, 0.1, "Aiming towards our goal");
	}
}

public bool PluginBot_IsEntityTraversable(int bot_entidx, int other_entidx, TraverseWhenType when) 
{
	//Can't walk through our own buildings unfortunately :/
	if(IsBaseObject(other_entidx) && GetEntPropEnt(other_entidx, Prop_Send, "m_hBuilder") == bot_entidx)
	{
		return false;
	}
	
	//Traversing "teammates" is okay.
	if(IsValidClientIndex(other_entidx) && GetTeamNumber(bot_entidx) == GetTeamNumber(other_entidx))
	{
		return true;
	}
	
	//Traversing our target should always be possible in order for PF_IsPotentiallyTraversable to work in PredictSubjectPosition.
	return (m_hAttackTarget[bot_entidx] == other_entidx) ? true : false; 
}

public bool PluginBot_Jump(int bot_entidx, float vecPos[3], const float dir[3])
{
	//const float watchForClimbRange = 75.0;
	//if (PF_IsDiscontinuityAhead(bot_entidx, CLIMB_UP, watchForClimbRange))
	//{
	//If no target, stop pressing M2 so we can jump if we are heavy and spun up.
	if(m_hAimTarget[bot_entidx] <= 0)
	{
		BotAim(bot_entidx).ReleaseAltFireButton();
	}
	
	if(GetEntityFlags(bot_entidx) & FL_ONGROUND)
	{
		g_iAdditionalButtons[bot_entidx] |= IN_JUMP;
	}
	//}
}

public float PluginBot_PathCost(int bot_entidx, NavArea area, NavArea from_area, float length)
{
//	PrintToServer("area %x from_area %x length %f", area, from_area, length);
	
	TFTeam botTeam = TF2_GetClientTeam(bot_entidx);

	if ((botTeam == TFTeam_Red  && HasTFAttributes(area, BLUE_SPAWN_ROOM)) ||
		(botTeam == TFTeam_Blue && HasTFAttributes(area, RED_SPAWN_ROOM)))
	{
		if (GameRules_GetRoundState() != RoundState_TeamWin) 
		{
			/* dead end */
			return -1.0;
		}
	}
	
	float multiplier = 1.0;
	float dist;
	
	if (m_iRouteType[bot_entidx] == FASTEST_ROUTE) 
	{
		if (length > 0.0) 
		{
			dist = length;
		} 
		else 
		{
			float center[3];          area.GetCenter(center);
			float fromCenter[3]; from_area.GetCenter(fromCenter);
		
			float subtracted[3]; SubtractVectors(center, fromCenter, subtracted);
		
			dist = GetVectorLength(subtracted);
		}
		
		if(area.ComputeAdjacentConnectionHeightChange(from_area) >= 18.0)
		{
			dist *= 2.0;
		}
		
		return dist + from_area.GetCostSoFar();
	}
	
	if (m_iRouteType[bot_entidx] == DEFAULT_ROUTE) 
	{
		if (length > 0.0) 
		{
			dist = length;
		} 
		else 
		{
			float center[3];          area.GetCenter(center);
			float fromCenter[3]; from_area.GetCenter(fromCenter);
		
			float subtracted[3]; SubtractVectors(center, fromCenter, subtracted);
		
			dist = GetVectorLength(subtracted);
		}
		
		if(area.ComputeAdjacentConnectionHeightChange(from_area) >= 18.0)
		{
			dist *= 2.0;
		}
		
		if (!GetEntProp(bot_entidx, Prop_Send, "m_bIsMiniBoss")) 
		{
			/* very similar to CTFBot::TransientlyConsistentRandomValue */
			int seed = RoundToFloor(GetGameTime() * 0.1) + 1;
			seed *= area.GetID();
			seed *= bot_entidx;
			
			/* huge random cost modifier [0, 100] for non-giant bots! */
			multiplier += (Cosine(float(seed)) + 1.0) * 10.0;
		}
	}
	
	if (m_iRouteType[bot_entidx] == SAFEST_ROUTE) 
	{
		if (IsInCombat(area))
		{
			dist *= 4.0 * GetCombatIntensity(area);
		}
		
		if ((botTeam == TFTeam_Red  && HasTFAttributes(area, BLUE_SENTRY)) ||
			(botTeam == TFTeam_Blue && HasTFAttributes(area, RED_SENTRY))) 
		{
			dist *= 5.0;
		}
	}
	
	TFClassType botClass = TF2_GetPlayerClass(bot_entidx);
	
	if(botClass == TFClass_Sniper || botClass == TFClass_Spy)
	{
		int enemy_team = view_as<int>(GetEnemyTeam(bot_entidx));
		
		for (int i = 0; i < g_hSentries.Length; i++)
		{
			int obj = EntRefToEntIndex(g_hSentries.Get(i));
			if(IsValidEntity(obj))
			{
				if(GetTeamNumber(obj) == enemy_team)
				{
					if (area == PF_GetLastKnownArea(obj)) 
					{
						dist *= 10.0;
					}
				}
			}
		}
	
		dist += (dist * 10.0 * area.GetPlayerCount(enemy_team));
	}
	
	float cost = dist * multiplier;
	
/*	if (area.HasAttributes(NAV_MESH_FUNC_COST)) 
	{
		cost *= area->ComputeFuncNavCost(this->m_Actor);
	}*/
	
	return from_area.GetCostSoFar() + cost;
}

public void PluginBot_PathFail(int bot_entidx)
{
	ChangeAction(bot_entidx, ACTION_IDLE, "Path construction failed.");
	
	float goal[3];
	PF_GetGoalVector(bot_entidx, goal);
	PrintToServer("   > TO %f %f %f", goal[0], goal[1], goal[2]);
	
	m_aNestArea[bot_entidx] = NavArea_Null;
}

public void PluginBot_OnActorEmoted(int bot_entidx, int who, int concept)
{
	//PrintToServer(">>>>>>>>>> PluginBot_OnActorEmoted %i who %i concept %i", bot_entidx, who, concept);
	
	if(g_iCurrentAction[bot_entidx] != ACTION_MEDIC_HEAL)
		return;
	
	if(!IsValidClientIndex(who))
		return;
	
	//"Move Up!"
	if (concept == 13 || concept == 25 )
	{
		int patient = m_hPatient[bot_entidx];
		
		if (IsValidClientIndex(patient) && who == patient)
		{
			BotAim(bot_entidx).PressAltFireButton();
		}
	}
}

public void PluginBot_MoveToSuccess(int bot_entidx, Address path)
{	
/*	if(g_bRetreat[bot_entidx])
	{
		g_bPath[bot_entidx] = false;
	}

	if(g_iCurrentAction[bot_entidx] != ACTION_MOVE_TO_FRONT
	|| g_iCurrentAction[bot_entidx] != ACTION_GOTO_UPGRADE)
		return;
	ChangeAction(bot_entidx, ACTION_IDLE, "PluginBot_MoveToSuccess: Reached path goal.");
	*/
	
	ClearStuckStatus(bot_entidx, "Arrived at goal");
	
	g_bRetreat[bot_entidx] = false;
	g_bPath[bot_entidx] = false;
}


//TODO
//https://github.com/danielmm8888/TF2Classic/blob/d070129a436a8a070659f0267f6e63564a519a47/src/game/shared/tf/tf_gamemovement.cpp#L171-L174
//https://github.com/sigsegv-mvm/mvm-reversed/blob/b2a43a54093fca4e16068e64e567b871bd7d875e/server/tf/bot/behavior/tf_bot_behavior.cpp#L270-L301
//Reverse CTFBotVision AFTER you have implemented IVision into extension

//CTFNavMesh stuff, maybe put in PathFollower_Nav
//
//	364 windows | 368 linux
//		CUtlVector<CTFNavArea *> m_InvasionAreas[4];
//
//	548 windows | 552 linux
//		m_flBombTargetDistance 
//

//What is 544 l
//	mark
//	Appears in CTFNavArea::IsTFMarked and 
//	is compared agains CTFNavArea::m_masterTFMark

//What is 468 l
//	Appears in CTFNavArea::IsPotentiallyVisibleToTeam

//What is 348 w or 352 l
//	Appears at the start of 
//	CTFNavArea::CollectPriorIncursionAreas 
//	AND CTFNavArea::CollectNextIncursionAreas
//	I think 352 is GetNextIncursionArea

//452 l = m_nAttributes

//What is 456 l and 448 l
//	Both appear in CTFNavArea::AddPotentiallyVisibleActor

//Some CombatIntensity shit 
//https://mxr.alliedmods.net/hl2sdk-sdk2013/source/game/shared/util_shared.h#531
//l 536 = IntervalTimer m_timestamp
//l 540 = IntervalTimer m_startTime

//CTFNavArea::OnCombat doesnt make sense
//	m_timestamp = Min(tf_nav_combat_build_rate + m_timestamp, 1.0);
//
//CTFNavArea::GetCombatIntensity
//	if(m_startTime > 0.0)
//	{
//		return Max(m_timestamp - ((GetGameTime() - m_startTime) * tf_nav_combat_decay_rate), 0.0);
//	}

//CTFNavMesh offsets organized
//	float unknown;										l 352	
//	float unknown; 										l 356	
//	float m_flIncursionDistanceRed; 					l 360	tf_nav_show_incursion_distance 
//	float m_flIncursionDistanceBlu;						l 364	tf_nav_show_incursion_distance 
//	CUtlVector<CTFNavArea *> m_InvasionAreas[4];		l 368	
//	CUtlVector<CBaseCombatCharacter *> m_PVActors[4];	l 448	CTFNavArea::AddPotentiallyVisibleActor
//	TFNavAttributeType m_nAttributes;					l 452	
//	CTFNavArea::AddPotentiallyVisibleActor 				l 456	
//	CTFNavArea::IsPotentiallyVisibleToTeam				l 468
//															l 452
//															l 456
//															l 460
//															l 464
//															l 468
//															l 472
//															l 476
//															l 480
//															l 484
//															l 488
//															l 492
//															l 496
//															l 500
//
//	IntervalTimer m_timestamp							l 536	GetCombatIntensity
//	IntervalTimer m_startTime							l 540	GetCombatIntensity
//	CTFNavArea::IsTFMarked mark 						l 544
//	m_flBombTargetDistance						 		l 552	tf_nav_show_bomb_target_distance
//size 0x238 w

//Reverse void CTFBotTacticalMonitor::AvoidBumpingEnemies                    DONE
//Reverse void CTFBotEngineerMoveToBuild::SelectBuildLocation(CTFBot *actor) WIP
//Reverse void CTFBotEngineerMoveToBuild::CollectBuildAreas(CTFBot *actor)   WIP
//Reverse void CTFBot::EquipBestWeaponForThreat(CKnownEntity const*)         WIP
//	Mainly for soldiers shotgun handling
//	Seems to just switch to shotgun if target is closer than 750.0 units
//	and ran out of rocketlauncher ammo
//	switches back once shotgun is empty
