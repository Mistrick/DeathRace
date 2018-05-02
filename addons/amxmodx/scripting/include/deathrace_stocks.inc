#if defined _deathrace_stocks_included
  #endinput
#endif
#define _deathrace_stocks_included

stock give_weapon(id, weaponid, amount)
{
	if(user_has_weapon(id, weaponid)) {
		cs_set_user_bpammo(id, weaponid, (cs_get_user_bpammo(id, weaponid) + amount));
		return 1;
	}
	static weapon_name[32];
	get_weaponname(weaponid, weapon_name, charsmax(weapon_name));
	
	new entity;
	if( (entity = give_item(id, weapon_name)) && amount) {
		cs_set_weapon_ammo(entity, amount);
	}
	return 1
}
stock message_setfov(id, amount=90)
{
	static msg_setfov;
	if(msg_setfov || (msg_setfov = get_user_msgid("SetFOV"))) {
		message_begin(MSG_ONE, msg_setfov, {0,0,0}, id);
		write_byte(amount);
		message_end();
	}
}
stock message_screenshake(id)
{
	static msg_screen_shake;
	if(msg_screen_shake || (msg_screen_shake = get_user_msgid("ScreenShake"))) {
		message_begin(MSG_ONE, msg_screen_shake, {0,0,0}, id);
		write_short(255<<14);
		write_short(10<<14);
		write_short(255<<14);
		message_end();
	}
}
