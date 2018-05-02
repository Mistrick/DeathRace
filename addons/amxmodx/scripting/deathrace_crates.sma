#include <amxmodx>
#include <fun>
#include <hamsandwich>
#include <cstrike>
#include <fakemeta>
#include <deathrace_stocks>

#if AMXX_VERSION_NUM < 183
#include <colorchat>
#endif

#define PLUGIN "Deathrace: Crates"
#define VERSION "1.2f"
#define AUTHOR "Xalus/Mistrick"

#pragma semicolon 1

#define PREFIX "^4[Deathrace]"

forward deathrace_crate_hit(id, ent);
forward deathrace_win(id, Float:flTime);

enum _:Cvars {
	CVAR_BREAKTYPE
};

new g_pCvars[Cvars];

enum _:Forwards {
	FORWARD_CRATEHIT
};

new g_hForwards[Forwards];

enum _:CrateInfo {
	CRATEINFO_NAME[32],
	CRATEINFO_NEWNAME[32],
	
	CRATEINFO_AMOUNT,
	CRATEINFO_MAXUSE
};

enum _:CrateList {
	CRATE_SPEED,
	CRATE_HENADE,
	CRATE_UZI,
	CRATE_SHIELD,
	CRATE_GODMODE,
	CRATE_GRAVITY,
	CRATE_HEALTH,
	CRATE_ARMOR,
	CRATE_FROST,
	CRATE_SMOKE,
	CRATE_DEATH,
	CRATE_DRUGS,
	CRATE_SHAKE,
	CRATE_FREEZE,
	CRATE_RANDOM
};

new const g_aCrate[CrateList][CrateInfo] = {
	{"speedcrate",		"extra speed", 		400, 	2}, // Amount: Speed
	{"hecrate", 		"a hegrenade",		1, 	2}, // Amount: Nades
	{"uzicrate", 		"an uzi",		3, 	2}, // Amount: Bullets
	{"shieldcrate", 	"a shield",		1, 	2}, // Amount: Nothing
	{"godmodecrate",	"godmode",		10, 	2}, // Amount: Seconds
	{"gravitycrate", 	"gravity",		560, 	2}, // Amount: Gravity
	{"hpcrate", 		"extra health",		50,	3}, // Amount: Health
	{"armorcrate",		"extra armor",		50,	3}, // Amount: Armor
	{"frostcrate",		"a frostgrenade", 	1, 	2}, // Amount: Nades
	{"smokecrate",		"a smokegrenade", 	1, 	2}, // Amount: Nades
	{"deathcrate",		"death",		1,	0}, // Amount: Nothing
	{"drugcrate",		"drugs",		10,	0}, // Amount: Seconds
	{"shakecrate",		"an hangover",		0, 	0}, // Amount: Nothing
	{"freezecrate",		"a body freeze",	50, 	0}, // Amount: Speed
	{"randomcrate",		"a random crate",	1,	2}  // Amount: Nothing
};
new Trie:g_tCrates;

new g_aCrateAmount[33][CrateList];
new g_aCrateActive[33][CrateList];

enum _:enumPlayers {
	PLAYER_ENT_BLOCK
};
new g_players[33][enumPlayers];
new bool:g_bRoundEnded;

public plugin_init() 
{
	register_plugin(PLUGIN, VERSION, AUTHOR);
	
	// Register: Cvars
	g_pCvars[CVAR_BREAKTYPE] 	= register_cvar("deathrace_touch_breaktype", "1");
	// 0 break nothing, 1 break only crates, 2 break everything

	// Register: Ham
	RegisterHam(Ham_Touch, "func_breakable", "Ham_TouchCrate_Pre", 0);
	RegisterHam(Ham_TakeDamage, "func_breakable", "Ham_DamageCrate_Pre", 0);
	RegisterHam(Ham_Item_PreFrame, "player", "Ham_PlayerResetMaxSpeed_Post", 1);
	RegisterHam(Ham_Spawn, "player", "Ham_PlayerSpawn_Post", 1);
	
	// Register: Event
	register_event("HLTV", "Event_NewRound", "a", "1=0", "2=0");

	g_hForwards[FORWARD_CRATEHIT]	= CreateMultiForward("deathrace_crate_hit", ET_STOP, FP_CELL, FP_CELL); 	// deathrace_crate_hit(id, ent)

	// Install: Crates
	g_tCrates = TrieCreate();
	
	for(new i = 0; i < CrateList; i++) {
		TrieSetCell(g_tCrates, g_aCrate[i][CRATEINFO_NAME], i);
	}
}
// Public: Deathrace
public deathrace_crate_hit(id, entity)
{
	static target_name[32];
	pev(entity, pev_targetname, target_name, charsmax(target_name));
	if(TrieKeyExists(g_tCrates, target_name)) {
		static crate;
		TrieGetCell(g_tCrates, target_name, crate);
		
		return crate_touch(id, crate);
	}
	return 0;
}
public deathrace_win(id, Float:flTime)
{
	g_bRoundEnded = true;
}
public Event_NewRound()
{
	g_bRoundEnded = false;
}
public Ham_TouchCrate_Pre(entity, id)
{
	if(pev_valid(entity) && is_user_alive(id) && !g_bRoundEnded) {
		static break_type;
		if(g_players[id][PLAYER_ENT_BLOCK] != entity && (break_type || (break_type = get_pcvar_num(g_pCvars[CVAR_BREAKTYPE]))) ) {
			static target_name[32];
			pev(entity, pev_targetname, target_name, charsmax(target_name));
				
			// Lets see if we got a crate.
			if( (break_type == 2) || (break_type == 1 && containi(target_name, "crate") >= 0) ) {
				ExecuteHamB(Ham_TakeDamage, entity, id, id, 9999.0, DMG_CRUSH);
			}
		}
	}
	return HAM_IGNORED;
}
public Ham_DamageCrate_Pre(entity, inflictor, attacker, Float:damage, bits)
{
	if(pev_valid(entity) && is_user_alive(attacker) && !g_bRoundEnded
		&& (get_user_weapon(attacker) == CSW_KNIFE || bits & DMG_CRUSH)
		&& g_players[attacker][PLAYER_ENT_BLOCK] != entity) {	
		if( (pev(entity, pev_health) - damage) <= 0.0 ) {
			g_players[attacker][PLAYER_ENT_BLOCK] = entity;
			
			new ret;
			ExecuteForward(g_hForwards[FORWARD_CRATEHIT], ret, attacker, entity);
			
			return ret;
		}
	}
	return HAM_IGNORED;
}
// Public: Ham
public Ham_PlayerResetMaxSpeed_Post(id)
{
	if(is_user_alive(id) && (g_aCrateActive[id][CRATE_SPEED] || g_aCrateActive[id][CRATE_FREEZE])) {
		set_user_maxspeed(id, float(g_aCrate[ g_aCrateActive[id][CRATE_SPEED] ? CRATE_SPEED : CRATE_FREEZE ][CRATEINFO_AMOUNT]));
	}
}
public Ham_PlayerSpawn_Post(id)
{
	if(is_user_alive(id)) {
		arrayset(g_aCrateAmount[id], 0, CrateList);
		arrayset(g_aCrateActive[id], 0, CrateList);
	}
}

// Public: Tasks
public Task_Timer(arrayTemp[2])
{
	new id, crateid;
	id = arrayTemp[0];
	crateid = arrayTemp[1];

	if(is_user_connected(id)) {
		g_aCrateActive[id][crateid] = 0;
		
		switch(crateid) {
			case CRATE_GODMODE: {
				set_user_godmode(id);
			}
			case CRATE_GRAVITY: {
				set_user_gravity(id);
			}
			case CRATE_DRUGS: {
				message_setfov(id);
			}
			case CRATE_FREEZE, CRATE_SPEED: {
				ExecuteHamB(Ham_Item_PreFrame, id);
			}
		}
	}
}
crate_touch(id, crateid, bool:randomcrate = false)
{
	if(g_aCrate[crateid][CRATEINFO_MAXUSE] && ++g_aCrateAmount[id][crateid] > g_aCrate[crateid][CRATEINFO_MAXUSE] && !randomcrate) {
		return HAM_IGNORED;
	}
	
	switch(crateid) {
		case CRATE_SPEED: {
			g_aCrateActive[id][CRATE_FREEZE] = 0;
			
			set_user_maxspeed(id, float(g_aCrate[crateid][CRATEINFO_AMOUNT]));
			set_timer(id, crateid, 3.0);
		}
		case CRATE_HENADE: {
			give_weapon(id, CSW_HEGRENADE, g_aCrate[crateid][CRATEINFO_AMOUNT]);
		}
		case CRATE_UZI: {
			give_weapon(id, CSW_TMP, g_aCrate[crateid][CRATEINFO_AMOUNT]);
		}
		case CRATE_SHIELD: {
			give_item(id, "weapon_shield");
		}
		case CRATE_GODMODE: {
			set_user_godmode(id, 1);
			set_timer(id, crateid);
		}	
		case CRATE_GRAVITY: {
			set_user_gravity(id, (float(g_aCrate[crateid][CRATEINFO_AMOUNT]) / 800.0));
			set_timer(id, crateid, 10.0);
		}
		case CRATE_HEALTH: {
			set_user_health(id, min(get_user_health(id) + g_aCrate[crateid][CRATEINFO_AMOUNT], 100));
		}
		case CRATE_ARMOR: {
			set_user_armor(id, min(get_user_armor(id) + g_aCrate[crateid][CRATEINFO_AMOUNT], 100));
		}
		case CRATE_FROST: {
			give_weapon(id, CSW_FLASHBANG, g_aCrate[crateid][CRATEINFO_AMOUNT]);
		}
		case CRATE_SMOKE: {
			give_weapon(id, CSW_SMOKEGRENADE, g_aCrate[crateid][CRATEINFO_AMOUNT]);
		}
		case CRATE_DEATH: {
			if(get_user_godmode(id) || randomcrate) {
				g_aCrateAmount[id][crateid]--;
				return HAM_IGNORED;
			}
			user_kill(id);
		}
		case CRATE_DRUGS: {
			message_setfov(id, 170);
			set_timer(id, crateid);
		}	
		case CRATE_SHAKE: {
			message_screenshake(id);
		}
		case CRATE_FREEZE: {
			g_aCrateActive[id][CRATE_SPEED] = 0;
			
			set_user_maxspeed(id, float(g_aCrate[crateid][CRATEINFO_AMOUNT]));
			set_timer(id, crateid, 2.0);
		}
		case CRATE_RANDOM: {
			crate_touch(id, random(CRATE_RANDOM), true);
			return HAM_IGNORED;
		}
		default: {
			return HAM_IGNORED;
		}
	}
	client_print_color(id, print_team_default, "%s^1 You pickedup%s^3 %s^1.", PREFIX, randomcrate ? " a random crate and received" : "", g_aCrate[crateid][CRATEINFO_NEWNAME]);
	
	return HAM_IGNORED;
}
set_timer(id, crateid, Float:flTime = 0.0)
{
	new arrayTemp[2];
	arrayTemp[0] = id;
	arrayTemp[1] = crateid;
	
	g_aCrateActive[id][crateid]++;
	
	if(!flTime) {
		flTime = float(g_aCrate[crateid][CRATEINFO_AMOUNT]);
	}
	set_task(flTime, "Task_Timer", 15151, arrayTemp, sizeof(arrayTemp));
}
