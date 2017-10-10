
int g_iStation[MAXPLAYERS + 1];

float m_ctUpgradeTimeout[MAXPLAYERS + 1];

bool CTFBotGoToUpgradeStation_OnStart(int actor)
{
	g_iStation[actor] = FindClosestUpgradeStation(actor);

	if(g_iStation[actor] == -1)
	{
		g_bPath[actor] = false;
		return false;
	}
	
	m_ctUpgradeTimeout[actor] = GetGameTime() + 50.0;
	
	EquipWeaponSlot(actor, TFWeaponSlot_Melee);
	
	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, PLATFORM_MAX_PATH);
	
	if(StrContains(map, "mvm_mannworks") != -1)
	{
		PF_SetGoalVector(actor, view_as<float>({-643.9, -2635.2, 384.0}));
		g_bPath[actor] = true;
		return true;
	}
	else if(StrContains(map, "mvm_teien") != -1)
	{
		PF_SetGoalVector(actor, view_as<float>({4613.1, -6561.9, 260.0}));
		g_bPath[actor] = true;
		return true;
	}
	else if(StrContains(map, "mvm_sequoia") != -1)
	{
		PF_SetGoalVector(actor, view_as<float>({-5117.0, -377.3, 4.5}));
		g_bPath[actor] = true;
		return true;
	}
	
	NavArea area = TheNavMesh.GetNearestNavArea_Vec(WorldSpaceCenter(g_iStation[actor]), true, 1000.0, false, false, TEAM_ANY);
	if(area == NavArea_Null)
		return false;
	
	float center[3];
	area.GetRandomPoint(center);
	
	center[2] += 50.0;
	
	TR_TraceRay(center, WorldSpaceCenter(g_iStation[actor]), MASK_PLAYERSOLID_BRUSHONLY, RayType_EndPoint);
	TR_GetEndPosition(center);
	
	PF_SetGoalVector(actor, center);
	
	g_bPath[actor] = true;
	return true;
}

bool CTFBotGoToUpgradeStation_Update(int actor)
{
	if (m_ctUpgradeTimeout[actor] < GetGameTime())
	{
		PrintToServer("[%8.3f] CTFBotGoToUpgradeStation(#%d): Timeout elapsed!", GetGameTime(), actor);
		
		NavArea area = TheNavMesh.GetNearestNavArea_Vec(WorldSpaceCenter(actor), true, 4000.0, false, false, GetClientTeam(actor));
		if(area == NavArea_Null)
		{
			ChangeAction(actor, ACTION_IDLE);
		}
		else
		{
			float center[3];
			area.GetCenter(center);
			
			center[2] += GetEntPropFloat(actor, Prop_Send, "m_flStepSize");
			
			TeleportEntity(actor, center, NULL_VECTOR, NULL_VECTOR);
		}
		
		m_ctUpgradeTimeout[actor] = GetGameTime() + 30.0;
		
		return false;
	}

	int station = g_iStation[actor];
	if (!IsValidEntity(station))
	{
		PrintToServer("[%8.3f] CTFBotGoToUpgradeStation(#%d): Upgrade station is invalid.", GetGameTime(), actor);
		g_bPath[actor] = false;
		return false;
	}
	
	if (IsStandingAtUpgradeStation(actor)) 
	{
		BotAim(actor).AimHeadTowards(WorldSpaceCenter(station), IMPORTANT, 3.0, "Look at our upgrade station");
		PrintToServer("Reached upgrade station; buying upgrades.");
		ChangeAction(actor, ACTION_UPGRADE);
		return false;
	}
	
	g_bPath[actor] = true;
	
	return true;
}

void CTFBotGoToUpgradeStation_OnEnd(int actor)
{
	g_iStation[actor] = -1;
}

int FindClosestUpgradeStation(int actor)
{
	int stations[MAXPLAYERS+1];
	int stationcount;
	
	int i = -1;
	while ((i = FindEntityByClassname(i, "func_upgradestation")) != -1)
	{
		if(GetEntProp(i, Prop_Data, "m_bDisabled"))
			continue;
		
		NavArea area = TheNavMesh.GetNearestNavArea_Vec(WorldSpaceCenter(i), true, 8000.0, false, false, TEAM_ANY);
		if(area == NavArea_Null)
			return false;
		
		float center[3];
		area.GetCenter(center);
		
		center[2] += 50.0;
		
		TR_TraceRay(center, WorldSpaceCenter(i), MASK_PLAYERSOLID_BRUSHONLY, RayType_EndPoint);
		TR_GetEndPosition(center);
		
		if(!PF_IsPathToVectorPossible(actor, center, NULL_FLOAT))
			continue;
		
		stations[stationcount] = i;
		stationcount++;
	}
	
	return stations[GetRandomInt(0, stationcount - 1)];
}