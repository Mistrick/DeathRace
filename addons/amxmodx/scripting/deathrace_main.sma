#include <amxmodx>
#include <engine>
#include <fakemeta>
#include <hamsandwich>
#include <reapi>

#if AMXX_VERSION_NUM < 183
#include <colorchat>
#endif

#define PLUGIN "Deathrace"
#define VERSION "2.3f"
#define AUTHOR "Xalus/Mistrick"

#pragma semicolon 1

#define PREFIX "^4[Deathrace]"

enum _:Cvars {
	CVAR_BREAKTYPE
};

new g_pCvars[Cvars];

enum _:Forwards {
	FORWARD_CRATEHIT,
	FORWARD_WIN
};

new g_hForwards[Forwards];

enum _:enumPlayers {
	PLAYER_ENT_BLOCK
};
new g_players[33][enumPlayers];


new Trie:g_trieRemoveEntities;
new bool:g_bRoundEnded;

public plugin_init() 
{
	register_plugin(PLUGIN, VERSION, AUTHOR);
	register_cvar("deathrace_mod", VERSION, FCVAR_SERVER);
	
	// Register: Cvars
	g_pCvars[CVAR_BREAKTYPE] 	= register_cvar("deathrace_touch_breaktype", "1");
		// 0 break nothing, 1 break only crates, 2 break everything
	
	register_clcmd("chooseteam", "Command_ChooseTeam");

	// Register: Ham
	RegisterHam(Ham_Touch, "func_breakable", "Ham_TouchCrate_Pre", 0);
	RegisterHam(Ham_TakeDamage, "func_breakable", "Ham_DamageCrate_Pre", 0);
	RegisterHam(Ham_TakeDamage, "player", "Ham_DamagePlayer_Pre", 0);
	
	RegisterHam(Ham_Use, "func_button", "Ham_PressButton_Post", 1);
	RegisterHam(Ham_Killed, "player", "Ham_PlayerKilled_Post", 1);
	
	// Register: Message
	register_message(get_user_msgid("TextMsg"), "Message_TextMsg");
	register_message(get_user_msgid("StatusIcon"), "Message_StatusIcon");
	
	// Register: Event
	register_event("HLTV", "Event_NewRound", "a", "1=0", "2=0");
	
	// Register: Forward
	new description[32];
	formatex(description, charsmax(description), "Deathrace (%s)", VERSION);
	set_member_game(m_GameDesc, description);
	
	// Register: MultiForward
	g_hForwards[FORWARD_CRATEHIT]	= CreateMultiForward("deathrace_crate_hit", ET_STOP, FP_CELL, FP_CELL); 	// deathrace_crate_hit(id, ent)
	g_hForwards[FORWARD_WIN]		= CreateMultiForward("deathrace_win", ET_STOP, FP_CELL, FP_CELL); // deathrace_win(id, type) (type [ 0: Survivor | 1: Map Finish ])

	// add set cvar autojoin
	// join to CT
	// block change team
	set_cvar_num("mp_autoteambalance", 0);
	set_cvar_num("mp_round_infinite", 1);
	set_cvar_num("mp_freezetime", 0);
	set_cvar_num("mp_friendlyfire", 1);
	set_cvar_num("mp_limitteams", 0);
	set_cvar_num("mp_auto_join_team", 1);
	set_cvar_string("humans_join_team", "CT");

	Block_Commands();
}
Block_Commands()
{
	new szBlockedCommands[][] = {"jointeam", "joinclass", "radio1", "radio2", "radio3"};
	for(new i = 0; i < sizeof(szBlockedCommands); i++) {
		register_clcmd(szBlockedCommands[i], "Command_BlockCmds");
	}
}
public Command_BlockCmds(id)
{
	return PLUGIN_HANDLED;
}
public Command_ChooseTeam(id)
{
	return PLUGIN_HANDLED;
}
public plugin_precache()
{
		// Entity stuff (Credit: Exolent[jNr]
	new entity = create_entity( "hostage_entity" );
	entity_set_origin( entity, Float:{ 0.0, 0.0, -55000.0 } );
	entity_set_size( entity, Float:{ -1.0, -1.0, -1.0 }, Float:{ 1.0, 1.0, 1.0 } );
	DispatchSpawn( entity );
	
	entity = create_entity( "player_weaponstrip" );
	DispatchKeyValue( entity, "targetname", "stripper" );
	DispatchSpawn( entity );
	
	entity = create_entity( "game_player_equip" );
	DispatchKeyValue( entity, "weapon_knife", "1" );
	DispatchKeyValue( entity, "targetname", "equipment" );
	
	entity = create_entity( "multi_manager" );
	DispatchKeyValue( entity, "stripper", "0" );
	DispatchKeyValue( entity, "equipment", "0.5" );
	DispatchKeyValue( entity, "targetname", "game_playerspawn" );
	DispatchKeyValue( entity, "spawnflags", "1" );
	DispatchSpawn( entity );
	
	entity = create_entity( "info_map_parameters" );
	DispatchKeyValue( entity, "buying", "3" );
	DispatchSpawn( entity );
	
	new const remove_entities[][] = {
		"func_bomb_target",
		"info_bomb_target",
		"hostage_entity",
		"monster_scientist",
		"func_hostage_rescue",
		"info_hostage_rescue",
		"info_vip_start",
		"func_vip_safetyzone",
		"func_escapezone",
		// "armoury_entity",
		"info_map_parameters",
		"player_weaponstrip",
		"game_player_equip",
		"func_buyzone"
	};
	
	g_trieRemoveEntities = TrieCreate( );
	
	for( new i = 0; i < sizeof( remove_entities ); i++ ) {
		TrieSetCell(g_trieRemoveEntities, remove_entities[i], i);
	}
	// TODO: add unregister
	register_forward(FM_Spawn, "Forward_Spawn");
}

// Public: Forward
public Forward_Spawn(entity)
{
	if(pev_valid(entity)) {
		static classname[ 32 ];
		pev(entity, pev_classname, classname, charsmax(classname));
		
		if(TrieKeyExists(g_trieRemoveEntities, classname)) {
			remove_entity(entity);
			return FMRES_SUPERCEDE;
		}
		if(equal(classname, "info_player_deathmatch")) {
			set_pev(entity, pev_classname, "info_player_start");
		}
	}
	return FMRES_IGNORED;
}

// Public: Messages
public Message_TextMsg()
{
	static textmsg[22];
	get_msg_arg_string(2, textmsg, charsmax(textmsg));
		
	// Block Teammate attack and kill Message
	if (equal(textmsg, "#Game_teammate_attack") || equal(textmsg, "#Killed_Teammate")) {
		return PLUGIN_HANDLED;
	}

	return PLUGIN_CONTINUE;
}
public Message_StatusIcon(const iMsgId, const iMsgDest, const id) 
{
	static msg[8];
	get_msg_arg_string(2, msg, charsmax(msg));
	
	if(equal(msg, "buyzone") && get_msg_arg_int(1)) {
		set_pdata_int(id, 235, get_pdata_int(id, 235) & ~(1 << 0));
		return PLUGIN_HANDLED;
	}
	return PLUGIN_CONTINUE;
}

// Public: Event
public Event_NewRound()
{
	g_bRoundEnded = false;
}

// Public: Ham
public Ham_PlayerKilled_Post(id)
{
	
	new players[32], pnum;
	get_players(players, pnum, "ae", "CT");
	
	if(pnum <= 1) {
		new winmsg[64] = "All dead!";

		if(players[0]) {
			new ret;
			ExecuteForward(g_hForwards[FORWARD_WIN], ret, id, 0);
			
			if(ret == 2) {
				return HAM_IGNORED;
			}
			
			new name[32];
			get_user_name(players[0], name, charsmax(name));
			
			client_print_color(0, print_team_default, "%s^3 %s^1 was the only survivor left!", PREFIX, name);

			formatex(winmsg, charsmax(winmsg), "%s was the only survivor left!", name);
		}
		
		rg_round_end(5.0, WINSTATUS_CTS, ROUND_NONE, winmsg);
	}
	return HAM_IGNORED;
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
public Ham_DamagePlayer_Pre(id, inflictor, attacker, Float:damage, bits)
{
	if(is_user_alive(id) && is_user_connected(attacker) && inflictor == attacker) {
		return (get_user_weapon(attacker) == CSW_KNIFE) ? HAM_SUPERCEDE : HAM_IGNORED;
	}
	return HAM_IGNORED;
}
public Ham_PressButton_Post(entity, id)	
{
	if(pev_valid(entity) && is_user_alive(id) && !g_bRoundEnded) {		
		static target_name[32];
		pev(entity, pev_targetname, target_name, charsmax(target_name));
		
		// winbut 
		if(equal(target_name, "winbut")) {
			g_bRoundEnded = true;
		
			new ret;
			ExecuteForward(g_hForwards[FORWARD_WIN], ret, id, 1);
			
			new name[32];
			get_user_name(id, name, charsmax(name));
			
			if(!ret) {
				client_print_color(0, print_team_default, "%s^3 %s^1 finished the deathrace!", PREFIX, name);
			}
			
			// End round
			new winmsg[64];
			formatex(winmsg, charsmax(winmsg), "%s finished the deathrace!", name);
			rg_round_end(5.0, WINSTATUS_CTS, ROUND_NONE, winmsg);
		}
	}
}