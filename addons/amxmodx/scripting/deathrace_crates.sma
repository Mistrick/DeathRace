#include <amxmodx>
#include <fun>
#include <fakemeta>
#include <hamsandwich>
#include <cstrike>
#include <engine>
#include <reapi>
#include <deathrace_stocks>
#include <xs>

#if AMXX_VERSION_NUM < 183
#include <colorchat>
#endif

#define PLUGIN "Deathrace: Crates"
#define VERSION "1.3"
#define AUTHOR "Xalus/Mistrick"

#pragma semicolon 1

#define get_num(%0) get_pcvar_num(g_pCvars[%0])
#define get_float(%0) get_pcvar_float(g_pCvars[%0])

#define PREFIX "^4[Deathrace]"

// TODO: move to own inc
forward deathrace_crate_hit(id, ent);
forward deathrace_win(id, Float:flTime);

new const CRATE_CLASSNAME[] = "crate";
new const CRATE_MODEL[] = "models/deathrace/deathrace_crates.mdl";
new const Float:CRATE_MINS[3] = {-40.0, -40.0, -40.0};
new const Float:CRATE_MAXS[3] = {40.0, 40.0, 40.0};

enum _:Cvars {
	BREAKTYPE,
	RANDOM_CRATES,
	CRATE_RESPAWN
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

enum _:CrateSpawns {
	CrateType,
	Float:CrateOrigin[3]
};
new Array:g_aCrateCoords;

public plugin_init() 
{
	register_plugin(PLUGIN, VERSION, AUTHOR);
	
	// Register: Cvars
	g_pCvars[BREAKTYPE] = register_cvar("deathrace_touch_breaktype", "1"); // 0 break nothing, 1 break only crates, 2 break everything
	g_pCvars[RANDOM_CRATES] = register_cvar("deathrace_random_crates", "1"); // 0 - disable, 1 - enable
	g_pCvars[CRATE_RESPAWN] = register_cvar("deathrace_crate_respawn", "5"); // 0 - disable, seconds

	// Register: Ham
	RegisterHam(Ham_Touch, "func_breakable", "ham_touch_crate_pre", 0);
	RegisterHam(Ham_TakeDamage, "func_breakable", "ham_damage_crate_pre", 0);
	RegisterHam(Ham_Item_PreFrame, "player", "ham_player_reset_max_speed_post", 1);
	RegisterHam(Ham_Spawn, "player", "ham_player_spawn_post", 1);
	
	// Register: Event
	register_event("HLTV", "event_new_round", "a", "1=0", "2=0");

	g_hForwards[FORWARD_CRATEHIT]	= CreateMultiForward("deathrace_crate_hit", ET_STOP, FP_CELL, FP_CELL); 	// deathrace_crate_hit(id, ent)

	// Install: Crates
	g_tCrates = TrieCreate();
	
	for(new i = 0; i < CrateList; i++) {
		TrieSetCell(g_tCrates, g_aCrate[i][CRATEINFO_NAME], i);
	}
}
public plugin_precache()
{
	precache_model(CRATE_MODEL);
}
public plugin_cfg()
{

	g_aCrateCoords = ArrayCreate(CrateSpawns, 1);

	new ent = -1, target_name[32], Float:origin[3], Float:mins[3], Float:maxs[3];
	new crate_info[CrateSpawns];

	while( (ent = find_ent_by_class(ent, "func_breakable")) ) {
		pev(ent, pev_targetname, target_name, charsmax(target_name));
		if(TrieKeyExists(g_tCrates, target_name)) {
			pev(ent, pev_absmin, mins);
			pev(ent, pev_absmax, maxs);
			xs_vec_add(mins, maxs, origin);
			xs_vec_mul_scalar(origin, 0.5, origin);

			TrieGetCell(g_tCrates, target_name, crate_info[CrateType]);
			crate_info[CrateOrigin][0] = _:origin[0];
			crate_info[CrateOrigin][1] = _:origin[1];
			crate_info[CrateOrigin][2] = _:origin[2];
			ArrayPushArray(g_aCrateCoords, crate_info);
			remove_entity(ent);
		}
	}

	for(new i, size = ArraySize(g_aCrateCoords); i < size; i++) {
		ArrayGetArray(g_aCrateCoords, i, crate_info);
		origin[0] = Float:crate_info[CrateOrigin][0];
		origin[1] = Float:crate_info[CrateOrigin][1];
		origin[2] = Float:crate_info[CrateOrigin][2];
		create_crate(get_num(RANDOM_CRATES) ? random(CrateList) : crate_info[CrateType], origin);
	}
}
create_crate(crate, Float:origin[3])
{
	new ent = create_entity("func_breakable");
	set_pev(ent, pev_classname, CRATE_CLASSNAME);

	set_pev(ent, pev_targetname, g_aCrate[crate][CRATEINFO_NAME]);
	
	DispatchKeyValue(ent, "material", "1");
	DispatchKeyValue(ent, "spawnflags", "2" );
	DispatchSpawn(ent);

	engfunc(EngFunc_SetModel, ent, CRATE_MODEL);
	engfunc(EngFunc_SetOrigin, ent, origin);
	engfunc(EngFunc_SetSize, ent, CRATE_MINS, CRATE_MAXS);

	set_pev(ent, pev_solid, SOLID_BBOX);
	set_pev(ent, pev_health, 1.0);
	set_pev(ent, pev_skin, crate);
}
// Public: Deathrace
public deathrace_crate_hit(id, ent)
{
	static target_name[32];
	pev(ent, pev_targetname, target_name, charsmax(target_name));
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
	return 0;
}
public event_new_round()
{
	g_bRoundEnded = false;

	new ent = -1, target_name[32];
	while( (ent = find_ent_by_class(ent, CRATE_CLASSNAME)) ) {
		pev(ent, pev_targetname, target_name, charsmax(target_name));
		if(TrieKeyExists(g_tCrates, target_name)) {
			remove_entity(ent);
		}
	}

	new Float:origin[3], crate_info[CrateSpawns];
	for(new i, size = ArraySize(g_aCrateCoords); i < size; i++) {
		ArrayGetArray(g_aCrateCoords, i, crate_info);
		origin[0] = Float:crate_info[CrateOrigin][0];
		origin[1] = Float:crate_info[CrateOrigin][1];
		origin[2] = Float:crate_info[CrateOrigin][2];
		create_crate(get_num(RANDOM_CRATES) ? random(CrateList) : crate_info[CrateType], origin);
	}
}
public ham_touch_crate_pre(ent, id)
{
	if(pev_valid(ent) && is_user_alive(id) && !g_bRoundEnded) {
		static break_type;
		if(g_players[id][PLAYER_ENT_BLOCK] != ent && (break_type || (break_type = get_pcvar_num(g_pCvars[BREAKTYPE]))) ) {
			static target_name[32];
			pev(ent, pev_targetname, target_name, charsmax(target_name));
				
			// Lets see if we got a crate.
			if( (break_type == 2) || (break_type == 1 && containi(target_name, "crate") >= 0) ) {
				ExecuteHamB(Ham_TakeDamage, ent, id, id, 9999.0, DMG_CRUSH);
			}
		}
	}
	return HAM_IGNORED;
}
public ham_damage_crate_pre(ent, inflictor, attacker, Float:damage, bits)
{
	if(pev_valid(ent) && is_user_alive(attacker) && !g_bRoundEnded
		&& (get_user_weapon(attacker) == CSW_KNIFE || bits & DMG_CRUSH)
		&& g_players[attacker][PLAYER_ENT_BLOCK] != ent) {	
		if( (pev(ent, pev_health) - damage) <= 0.0 ) {
			g_players[attacker][PLAYER_ENT_BLOCK] = ent;
			
			new ret;
			ExecuteForward(g_hForwards[FORWARD_CRATEHIT], ret, attacker, ent);

			if(get_num(CRATE_RESPAWN) > 0) {
				new Flaot:origin[3];
				pev(ent, pev_origin, origin);
				set_task(get_float(CRATE_RESPAWN), "task_crate_respawn", get_member_game(m_iTotalRoundsPlayed), _:origin, sizeof(origin));
			}
			
			return ret;
		}
	}
	return HAM_IGNORED;
}
public task_crate_respawn(params[], taskid)
{
	if(taskid != get_member_game(m_iTotalRoundsPlayed)) {
		return;
	}

	new Float:origin[3];
	origin[0] = Float:params[0];
	origin[1] = Float:params[1];
	origin[2] = Float:params[2];
	create_crate(random(CrateList), origin);
}
// Public: Ham
public ham_player_reset_max_speed_post(id)
{
	if(is_user_alive(id) && (g_aCrateActive[id][CRATE_SPEED] || g_aCrateActive[id][CRATE_FREEZE])) {
		set_user_maxspeed(id, float(g_aCrate[ g_aCrateActive[id][CRATE_SPEED] ? CRATE_SPEED : CRATE_FREEZE ][CRATEINFO_AMOUNT]));
	}
}
public ham_player_spawn_post(id)
{
	if(is_user_alive(id)) {
		arrayset(g_aCrateAmount[id], 0, CrateList);
		arrayset(g_aCrateActive[id], 0, CrateList);
	}
}

// Public: Tasks
public task_timer(arrayTemp[2])
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
	set_task(flTime, "task_timer", 15151, arrayTemp, sizeof(arrayTemp));
}
