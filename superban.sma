#include <amxmodx>
#include <amxmisc>
#include <sockets>
#include <engine>
#include <sqlx>

#include <colorchat>

#pragma semicolon 1
#pragma ctrlchar '\'

#pragma dynamic 32768

/*
	1.0
	
	1. Замена cvar на pcvar
	2. Убрана блокировка чата и голосового чата
	3. Улучшено отображение времени
	4. При бане в консоле, при совпадении нескольких игроков, они выводятся в консоль
	5. Сделал экранирование символов mysql запросов
	6. Добавлен цветной чат. Можно выводить сообщение и в чат и в худ. amx_superban_messages
	7. Изменен ланг и конфиг (Добавлены квары и фразы)
	8. Оптимизированы SQL запросы
	9. Вместо 7 !!! запросов проверки игрока 1
	10. Блокирующие запросы к базе заменены на асинхронные
	11. При выводе списка банов в консоль ИЗ БАЗЫ ЗАПРАШИВАЛИСЬ ВСЕ БАНЫ !!! (Вот почему лагало) Добавлен "LIMIT %d". Список пишется не всем, а только админу.
	12. Изменен ban.php. Добавлен квар времени кика. Добавлен показ motd забаненому игроку.
	13. При разбане через консоль, разбаниваются только активные баны.
	14. Сделал в меню желтые цифры.
	
	1.1
	Рабочая проверка лицензии
	Правильное отображение периода бана в консоле.
	Убран префикс из худа.
	Рабочая загрузка резервного конфига
	Оптимизирован код
	Короткая запись времени: 3d - 3 дня
		h, d, w, m, y
		
	1.1.1
	Исправлен вывод информации о бане.
	
	1.2 
	Open Source
	Исправления
		
	
	
	
	TODO:
	UID
	ServerID
	Exit Playrs
	Web
	TimeMenu
*/

#define __PLUGIN_VERSION__	"1.2"

enum {
	TASK_LOADCFG = 13980
}

new BannedReasons[33][256];

new g_menuPosition[33];
new g_menuPlayers[33][32];
new g_menuPlayersNum[33];
new g_menuOption[33];
new g_menuSettings[33];
new g_coloredMenus;

new Array:g_bantimes;
new Config[128];
new UserUIDs[33][32];

new Handle:g_h_Sql;

new g_szLogFile[64];
new SelectedID[33];
new SelectedTime[33];
new s_DB_Table[64];
new TimeGap = 0;

new pcvar_prefix1;
new pcvar_prefix2;
new pcvar_comment;

new g_Prefix[32];
new g_Comment[256];

new	pcvar_ipban, pcvar_nameban, pcvar_lnameban, pcvar_steamban, pcvar_subnetban, pcvar_banurl, 
	pcvar_checkurl, pcvar_hide, pcvar_log, pcvar_iptime, pcvar_nametime, pcvar_cookieban, 
	pcvar_messages, pcvar_cookiewait, pcvar_config, pcvar_autoclear, pcvar_periods, 
	pcvar_unbanflag, pcvar_sqltime, pcvar_utf8, pcvar_hideadmin;

new pcvar_chatprefix, pcvar_chatcolor, pcvar_motd, pcvar_kicktime;
new pcvar_timetype;

new g_ChatPrefix[64], g_ChatPrefixColor[64];

new g_UseTimeMenu = false;

locate_players(identifier[], players[32], &players_num)
{
	new player = find_player("c", identifier);
	
	if (!player)
	{
		new szName[32];
		
		new _maxpl = get_maxplayers();
		players_num = 0;
		for (new id = 1; id <= _maxpl; id++)
		{
			if (is_user_connected(id))
			{
				get_user_name(id, szName, 31);
				
				if (containi(szName, identifier) != -1)
					players[players_num++] = id;
			}
		}
		
		if (players_num > 0)
			return;
	}
	
	if (!player && strfind(identifier, ".") != -1)
	{
		player = find_player("d", identifier);
	}
	
	if (!player && identifier[0] == '#' && identifier[1])
	{
		player = find_player("k", str_to_num(identifier[1]));
	}
	
	players[0] = player;
	players_num = player > 0 ? 1 : 0;
}

convert_period(id, sec)
{
	new result[64];
	new seconds;
	new minutes;
	new hours;
	new days;
	new months;
	new years;
	if (sec <= 0)
	{
		formatex(result, 63, "%L", id, "SUPERBAN_PERMANENT");
	}
	if (sec < 60 && sec > 0)
	{
		seconds = floatround(float(sec), floatround_floor);
		formatex(result, 63, "%d %L", seconds, id, "SUPERBAN_SHORT_SECONDS");
	}
	if (sec > 59 && sec < 3600)
	{
		minutes = floatround(float(sec) / 60, floatround_floor);
		seconds = sec % 60;
		if (seconds)
		{
			formatex(result, 63, "%d %L %d %L", minutes, id, "SUPERBAN_SHORT_MINUTES", seconds, id, "SUPERBAN_SHORT_SECONDS");
		}
		else
			formatex(result, 63, "%d %L", minutes, id, "SUPERBAN_SHORT_MINUTES");
	}
	if (sec > 3599 && sec < 86400)
	{
		hours = floatround(float(sec) / 3600, floatround_floor);
		minutes = floatround(float(sec % 3600) / 60, floatround_floor);
		if (minutes)
		{
			formatex(result, 63, "%d %L %d %L", hours, id, (hours > 1 ? (hours < 5 ? "SUPERBAN_SHORT_HOURF" : "SUPERBAN_SHORT_HOURS") : "SUPERBAN_SHORT_HOUR"), minutes, id, "SUPERBAN_SHORT_MINUTES");
		}
		else
			formatex(result, 63, "%d %L", hours, id, (hours > 1 ? (hours < 5 ? "SUPERBAN_SHORT_HOURF" : "SUPERBAN_SHORT_HOURS") : "SUPERBAN_SHORT_HOUR"));
	}
	if (sec > 86399 && sec < 2592000)
	{
		days = floatround(float(sec) / 86400, floatround_floor);
		hours = floatround(float(sec % 86400) / 3600, floatround_floor);
		if (hours)
		{
			formatex(result, 63, "%d %L %d %L", days, id, (days > 1 ? (days < 5 ? "SUPERBAN_SHORT_DAYF" : "SUPERBAN_SHORT_DAYS") : "SUPERBAN_SHORT_DAY"), hours, id, (hours > 1 ? (hours < 5 ? "SUPERBAN_SHORT_HOURF" : "SUPERBAN_SHORT_HOURS") : "SUPERBAN_SHORT_HOUR"));
		}
		else
			formatex(result, 63, "%d %L", days, id, (days > 1 ? (days < 5 ? "SUPERBAN_SHORT_DAYF" : "SUPERBAN_SHORT_DAYS") : "SUPERBAN_SHORT_DAY"));
	}
	if (sec > 2591999 && sec < 31536000)
	{
		months = floatround(float(sec) / 2592000, floatround_floor);
		days = floatround(float(sec % 2592000) / 86400, floatround_floor);
		if (days)
		{
			formatex(result, 63, "%d %L %d %L", months, id, (months > 1 ? "SUPERBAN_SHORT_MONTHS" : "SUPERBAN_SHORT_MONTH"), days, id, (days > 1 ? (days < 5 ? "SUPERBAN_SHORT_DAYF" : "SUPERBAN_SHORT_DAYS") : "SUPERBAN_SHORT_DAY"));
		}
		else
			formatex(result, 63, "%d %L", months, id, (months > 1 ? "SUPERBAN_SHORT_MONTHS" : "SUPERBAN_SHORT_MONTH"));
	}
	if (sec > 31535999)
	{
		years = floatround(float(sec) / 31536000, floatround_floor);
		months = floatround(float(sec % 31536000) / 2592000, floatround_floor);
		if (months)
		{
			formatex(result, 63, "%d %L %d %L", years, id, (years > 1 ? "SUPERBAN_SHORT_YEARS" : "SUPERBAN_SHORT_YEAR"), months, id, (months > 1 ? "SUPERBAN_SHORT_MONTHS" : "SUPERBAN_SHORT_MONTH"));
		}
		else
			formatex(result, 63, "%d %L", years, id, (years > 1 ? "SUPERBAN_SHORT_YEARS" : "SUPERBAN_SHORT_YEAR"));
	}
	return result;
}

stock ExplodeString(p_szOutput[][], p_nMax, p_nSize, p_szInput[], p_szDelimiter)
{
	new nIdx = 0, l = strlen(p_szInput);
	new nLen = (1 + copyc( p_szOutput[nIdx], p_nSize, p_szInput, p_szDelimiter ));
	while( (nLen < l) && (++nIdx < p_nMax) )
		nLen += (1 + copyc( p_szOutput[nIdx], p_nSize, p_szInput[nLen], p_szDelimiter ));
	return nIdx;
}

public plugin_init()
{
	register_plugin("SuperBan QM", __PLUGIN_VERSION__, "Lukmanov Ildar & Quckly");
	
	new configsDir[64];
	get_configsdir(configsDir, 63);
	server_cmd("exec %s/superban.cfg", configsDir);
	get_localinfo("amx_logdir", g_szLogFile, 63);
	if (!dir_exists(g_szLogFile))
	{
		mkdir(g_szLogFile);
	}
	
	new szTime[32];
	get_time("SB%Y%m%d", szTime, 31);
	format(g_szLogFile, 63, "%s/%s.log", g_szLogFile, szTime);
	
	register_dictionary("superban.txt");
	
	register_cvar("q_sb_version", "SuperBan Q", FCVAR_SERVER|FCVAR_EXTDLL|FCVAR_SPONLY|FCVAR_UNLOGGED);
	
	pcvar_ipban = register_cvar("amx_superban_ipban", "1");
	pcvar_nameban = register_cvar("amx_superban_nameban", "1");
	pcvar_lnameban = register_cvar("amx_superban_lnameban", "0");
	pcvar_steamban = register_cvar("amx_superban_steamban", "1");
	pcvar_subnetban = register_cvar("amx_superban_subnetban", "0");
	pcvar_banurl = register_cvar("amx_superban_banurl", "");
	pcvar_checkurl = register_cvar("amx_superban_checkurl", "");
	pcvar_hide = register_cvar("amx_superban_hide", "0");
	pcvar_log = register_cvar("amx_superban_log", "1");
	pcvar_iptime = register_cvar("amx_superban_iptime", "1440");
	pcvar_nametime = register_cvar("amx_superban_nametime", "1440");
	pcvar_cookieban = register_cvar("amx_superban_cookieban", "0");
	pcvar_messages = register_cvar("amx_superban_messages", "1");
	pcvar_cookiewait = register_cvar("amx_superban_cookiewait", "3.0");
	pcvar_config = register_cvar("amx_superban_config", "joystick");
	pcvar_autoclear = register_cvar("amx_superban_autoclear", "0");
	pcvar_periods = register_cvar("amx_superban_periods", "5,10,15,30,45,60,120,180,720,1440,10080,43200,525600,0");
	pcvar_unbanflag = register_cvar("amx_superban_unbanflag", "d");
	pcvar_sqltime = register_cvar("amx_superban_sqltime", "1");
	pcvar_utf8 = register_cvar("amx_superban_utf8", "1");
	pcvar_hideadmin = register_cvar("amx_superban_hideadmin", "0");
	
	pcvar_prefix1 = register_cvar("amx_superban_prefix1", "0");
	pcvar_prefix2 = register_cvar("amx_superban_prefix2", "4");
	pcvar_comment = register_cvar("amx_superban_comment", "");
	
	pcvar_chatprefix = register_cvar("q_sb_chatprefix", "^n[^gSUPERBAN^n] ");
	pcvar_chatcolor = register_cvar("q_sb_chatcolor", "1");
	pcvar_motd = register_cvar("q_sb_showmotd", "1");
	pcvar_kicktime = register_cvar("q_sb_delaykick", "10.0");
	pcvar_timetype = register_cvar("q_sb_timetype", "0");
	
	register_clcmd("Reason", "Cmd_SuperbanReason", ADMIN_BAN, "");
	
	register_cvar("amx_superban_host", "127.0.0.1");
	register_cvar("amx_superban_user", "root");
	register_cvar("amx_superban_pass", "");
	register_cvar("amx_superban_db", "amx");
	register_cvar("amx_superban_table", "superban");
	
	register_menucmd(register_menuid("SBMENU", 0), 1023, "actionBanMenu");
	
	register_concmd("amx_superban", "SuperBan", ADMIN_BAN, "<name or #userid> <minutes> [reason]");
	register_concmd("amx_ban", "SuperBan", ADMIN_BAN, "<name or #userid> <minutes> [reason]");
	register_concmd("amx_banip", "SuperBan", ADMIN_BAN, "<name or #userid> <minutes> [reason]");
	register_concmd("amx_unsuperban", "UnSuperBan", ADMIN_BAN, "<name or ip or UID>");
	register_concmd("amx_unban", "UnSuperBan", ADMIN_BAN, "<name or ip or UID>");
	register_concmd("amx_superban_list", "BanList", ADMIN_BAN, "<number>");
	register_concmd("amx_superban_clear", "Clear_Base", ADMIN_BAN, "");
	
	register_clcmd("amx_superban_menu", "cmdBanMenu", ADMIN_BAN, "- displays ban menu");
	register_clcmd("amx_banmenu", "cmdBanMenu", ADMIN_BAN, "- displays ban menu");
}

public plugin_cfg()
{
	get_pcvar_string(pcvar_config, Config, 127);
	
	set_task(0.49, "delayed_plugin_cfg");
	set_task(0.51, "SetMotd");
}

stock parse_timeshort(const str[])
{
	new temp[11];
	new coof = 1;
	
	for (new i = 0; str[i] != 0 && i < 10; i++)
	{
		if (isdigit(str[i]))
		{
			temp[i] = str[i];
			continue;
		}
		
		switch (tolower(str[i]))
		{
			case 'h':
				coof = 60;
			case 'd':
				coof = 60 * 24;
			case 'w':
				coof = 60 * 24 * 7;
			case 'm':
				coof = 60 * 24 * 30;
			case 'y':
				coof = 60 * 24 * 365;
		}
		
		break;
	}
	
	new ret = 0;
	
	if (is_str_num(temp))
		ret = str_to_num(temp);
		
	return ret * coof;
}

public delayed_plugin_cfg()
{
	new s_DB_Host[64];
	new s_DB_User[64];
	new s_DB_Pass[64];
	new s_DB_Name[64];
	get_cvar_string("amx_superban_host", s_DB_Host, 63);
	get_cvar_string("amx_superban_user", s_DB_User, 63);
	get_cvar_string("amx_superban_pass", s_DB_Pass, 63);
	get_cvar_string("amx_superban_db", s_DB_Name, 63);
	get_cvar_string("amx_superban_table", s_DB_Table, 63);
	
	format(g_Prefix, 31, "STEAM_%d:%d", get_pcvar_num(pcvar_prefix1), get_pcvar_num(pcvar_prefix2));
	get_pcvar_string(pcvar_comment, g_Comment, 255);
	
	// Chat prefixs
	get_pcvar_string(pcvar_chatprefix, g_ChatPrefix, sizeof(g_ChatPrefix)-1);
	replace_all(g_ChatPrefix, charsmax(g_ChatPrefix), "^g", "");
	replace_all(g_ChatPrefix, charsmax(g_ChatPrefix), "^t", "");
	replace_all(g_ChatPrefix, charsmax(g_ChatPrefix), "^n", "");
	
	get_pcvar_string(pcvar_chatprefix, g_ChatPrefixColor, sizeof(g_ChatPrefixColor)-1);
	replace_all(g_ChatPrefixColor, charsmax(g_ChatPrefixColor), "^g", "\4");
	replace_all(g_ChatPrefixColor, charsmax(g_ChatPrefixColor), "^t", "\3");
	replace_all(g_ChatPrefixColor, charsmax(g_ChatPrefixColor), "^n", "\1");
	
	g_h_Sql = SQL_MakeDbTuple(s_DB_Host, s_DB_User, s_DB_Pass, s_DB_Name, 0);
	
	new Periods[256];
	new Period[32];
	g_bantimes = ArrayCreate(1, 32);
	
	get_pcvar_string(pcvar_periods, Periods, 255);
	
	strtok(Periods, Period, 31, Periods, 255, 44, 0);
	while (strlen(Period))
	{
		trim(Period);
		trim(Periods);
		ArrayPushCell(g_bantimes, parse_timeshort(Period));
		if (!contain(Periods, ","))
		{
			ArrayPushCell(g_bantimes, parse_timeshort(Periods));
		}
		split(Periods, Period, 32, Periods, 256, ",");
	}
	
	g_coloredMenus = colored_menus();
	
	//g_UseTimeMenu = get_pcvar_num(pcvar_timetype); // TODO
	
	if (get_pcvar_num(pcvar_sqltime) == 1)
	{
		set_task(1.00, "SQL_Time");
	}
	if (get_pcvar_num(pcvar_autoclear) == 1)
	{
		set_task(1.50, "Clear_Base");
	}
	return 0;
}

public SetMotd()
{
	if (get_pcvar_num(pcvar_cookieban) == 1)
	{
		new url[128];
		get_pcvar_string(pcvar_checkurl, url, 127);
		server_cmd("motdfile sbmotd.txt");
		server_cmd("motd_write <html><meta http-equiv=\"Refresh\" content=\"0; URL=%s\"><head><title>Cstrike MOTD</title></head><body bgcolor=\"black\" scroll=\"yes\"></body></html>", url);
	}
	return 1;
}

public SQL_Time()
{
	static szQuery[1024];
	formatex(szQuery, charsmax(szQuery), "SELECT UNIX_TIMESTAMP(NOW())");
	
	SQL_ThreadQuery(g_h_Sql, "qh_time", szQuery);
}

public qh_time(failstate, Handle:query, const error[], errornum, const data[], size, Float:queuetime)
{
	if (failstate)
	{
		return SQL_Error(query, error, errornum, failstate);
	}
	
	new SQLTime[16];
	new i_Col_SQLTime = SQL_FieldNameToNum(query, "UNIX_TIMESTAMP(NOW())");
	if (SQL_MoreResults(query))
	{
		SQL_ReadResult(query, i_Col_SQLTime, SQLTime, 15);
		
		TimeGap = str_to_num(SQLTime) - get_systime(0);
		server_print("[SUPERBAN] Current time synchronized with MySQL DB (%d seconds).", TimeGap);
	}
	
	return 0;
}

public Clear_Base(id, level, cid)
{
	if (!cmd_access(id, level, cid, 0, false))
	{
		return PLUGIN_HANDLED;
	}
	
	new s_Time[32];
	num_to_str(TimeGap + get_systime(), s_Time, 31);
	
	new AdminName[32];
	get_user_name(id, AdminName, 31);
	
	static szQuery[1024];
	formatex(szQuery, charsmax(szQuery), "DELETE FROM `%s` WHERE unbantime < '%s' and unbantime <> '0'", s_DB_Table, s_Time);
	
	SQL_ThreadQuery(g_h_Sql, "qh_clear", szQuery, AdminName, sizeof(AdminName));
	
	return PLUGIN_HANDLED;
}

public qh_clear(failstate, Handle:query, const error[], errornum, const data[], size, Float:queuetime)
{
	if (failstate)
	{
		return SQL_Error(query, error, errornum, failstate);
	}
	
	DEBUG_Log("Admin \"%s\" has cleared base", data);
	
	return 0;
}

public client_connect(id) 
{
	client_cmd(id, "exec %s.cfg", Config);
}

public client_putinserver(id)
{
	new Params[1];
	Params[0] = id;
	
	set_task(0.2, "Task_LoadCFG", TASK_LOADCFG + id);
	
	if (get_pcvar_num(pcvar_cookieban) == 1)
	{
		set_task(get_pcvar_float(pcvar_cookiewait), "CheckPlayer", 0, Params, 1);
	}
	else
	{
		set_task(0.50, "CheckPlayer", 0, Params, 1);
	}
	
	set_task(60.00, "WriteConfig", id + 32, Params, 1, "b");
	return 0;
}

public Task_LoadCFG(id)
{
	id -= TASK_LOADCFG;
	
	if (is_user_connected(id))
		client_cmd(id, "exec %s.cfg", Config);
}

public client_disconnect(id)
{
	remove_task(id + 32, 0);
	remove_task(id + 64, 0);
	return 0;
}

public WriteConfig(Params[1])
{
	new id = Params[0];
	new Config[128];
	get_pcvar_string(pcvar_config, Config, 127);
	client_cmd(id, "writecfg %s", Config);
	if (get_pcvar_num(pcvar_hide) == 1)
	{
		client_cmd(id, "clear");
	}
	return 0;
}

public CheckPlayer(Params[1])
{
	new id = Params[0];
	new UserAuthID[32], UserName[64], UserNameSQL[64], UserAddress[16], UserUID[32], UserRate[32];
	new Len = 0;
	new i = 0;
	new UserID = get_user_userid(id);
	new Params[3];
	new CookieTime;
	Params[2] = id;
	Params[0] = UserID;
	get_user_info(id, "bottomcolor", UserUID, 31);
	get_user_info(id, "rate", UserRate, 31);
	get_user_ip(id, UserAddress, 15, 1);
	get_user_name(id, UserName, 63);
	get_user_authid(id, UserAuthID, 31);
	
	if (equali(UserAuthID, "STEAM_ID_LAN", 0) || equali(UserAuthID, "STEAM_ID_PENDING", 0) 
	|| equali(UserAuthID, "VALVE_ID_LAN", 0) || equali(UserAuthID, "VALVE_ID_PENDING", 0) 
	|| equali(UserAuthID, "STEAM_666:88:666", 0) || containi(UserAuthID, g_Prefix) != -1)
	{
		copy(UserAuthID, 31, "");
	}
	mysql_escape_string(UserName, UserNameSQL, 63);
	
	if (strlen(UserRate) > 10) 
	{
		Len = strlen(UserRate) - 10;
		
		for (i = 0; i < 10; i++)
			UserRate[i] = UserRate[i+Len];
		
		UserRate[10] = 0;
		
		if (UserRate[0] >= 48 && UserRate[0] <= 57)
			copy(UserRate, 31, "");
		
		if (equal(UserRate, "cvar_float", 0))
		{
			copy(UserRate, 31, "");
		}
	}
	else
	{
		copy(UserRate, 31, "");
	}
	
	if (strlen(UserUID) > 10) 
	{
		Len = strlen(UserUID) - 10;
		
		for (i = 0; i < 10; i++)
			UserUID[i] = UserUID[i+Len];
		
		UserUID[10] = 0;
		
		if (UserUID[0] >= 48 && UserUID[0] <= 57)
			copy(UserUID, 31, "");
		
		if (equal(UserUID, "cvar_float", 0))
		{
			copy(UserUID, 31, "");
		}
	}
	else
	{
		copy(UserUID, 31, "");
	}
	
	if (get_pcvar_num(pcvar_log) == 2)
	{
		new CurrentTime[22];
		get_time("%d/%m/%Y - %X", CurrentTime, 21);
		new logtext[256];
		format(logtext, 255, "%s: Connected player \"%s\" (IP \"%s\", UID \"%s\", RateID \"%s\")", CurrentTime, UserName, UserAddress, UserUID, UserRate);
		write_file(g_szLogFile, logtext, -1);
	}
	
	// MySQL Query
	static szQuery[1024];
	new iLen = format(szQuery, charsmax(szQuery), "SELECT * FROM %s WHERE", s_DB_Table);
	
	// Conditions	WHERE (conds) AND (unbantime ...
	iLen += format(szQuery[iLen], charsmax(szQuery) - iLen, " (");
	
	
	if (get_pcvar_num(pcvar_steamban) == 1 && !equali(UserAuthID, "", 0))
	{
		iLen += format(szQuery[iLen], charsmax(szQuery) - iLen, "sid='%s' OR ", UserAuthID);
	}
	
	if (get_pcvar_num(pcvar_ipban) == 1)
	{
		new SubnetBan[64];
		new Subnet[4][16];
		ExplodeString(Subnet, 4, 16, UserAddress, 46);
		if (get_pcvar_num(pcvar_subnetban) == 1)
		{
			formatex(SubnetBan, 63, " OR (ip like '%s.%s.%%' and unbantime=0)", Subnet[0], Subnet[1]);
		}
		
		iLen += format(szQuery[iLen], charsmax(szQuery) - iLen, "((ip='%s'%s) AND `bantime` > %d) OR ", UserAddress, SubnetBan, TimeGap + get_systime(0) - get_pcvar_num(pcvar_iptime)*60);
	}
	
	if (get_pcvar_num(pcvar_cookieban) == 1)
	{
		if (get_pcvar_num(pcvar_sqltime) == 1)
		{
			CookieTime = TimeGap + get_systime(0) - 60;
		}
		else
		{
			CookieTime = get_systime(0) - 86400;
		}
		
		iLen += format(szQuery[iLen], charsmax(szQuery) - iLen, "(ipcookie='%s' AND bantime > %d) OR ", UserAddress, CookieTime);
	}
	
	if (strlen(UserUID) == 10)
	{
		iLen += format(szQuery[iLen], charsmax(szQuery) - iLen, "uid='%s' OR ", UserUID);
	}
	
	if (strlen(UserRate) == 10)
	{
		iLen += format(szQuery[iLen], charsmax(szQuery) - iLen, "uid='%s' OR ", UserRate);
	}
	
	if (get_pcvar_num(pcvar_lnameban) == 1 && strlen(UserUID) != 10 && strlen(UserRate) != 10 && !equal(UserName, "Player", 0) && !equal(UserName, "unnamed", 0))
	{
		iLen += format(szQuery[iLen], charsmax(szQuery) - iLen, "(name='%s' AND `bantime` > %d) OR ", UserNameSQL, TimeGap + get_systime(0) - get_pcvar_num(pcvar_nametime)*60);
	}
	
	if (get_pcvar_num(pcvar_nameban) == 1 && !equal(UserName, "Player", 0) && !equal(UserName, "unnamed", 0))
	{
		iLen += format(szQuery[iLen], charsmax(szQuery) - iLen, "(banname='%s' AND `bantime` > %d) OR ", UserNameSQL, TimeGap + get_systime(0) - get_pcvar_num(pcvar_nametime)*60);
	}
	
	iLen -= 4; // Remove ' OR ' at the end
	iLen += format(szQuery[iLen], charsmax(szQuery) - iLen, ")");
	
	// Time cond
	new s_Time[32];
	num_to_str(TimeGap + get_systime(), s_Time, 31);
	
	iLen += format(szQuery[iLen], charsmax(szQuery) - iLen, " AND (unbantime > '%s' OR unbantime='0')", s_Time);
	iLen += format(szQuery[iLen], charsmax(szQuery) - iLen, "ORDER BY banid DESC LIMIT 1");
	
	new qdata[1];
	qdata[0] = id;
	
	SQL_ThreadQuery(g_h_Sql, "qh_check", szQuery, qdata, sizeof(qdata));
}

public qh_check(failstate, Handle:query, const error[], errornum, const data[], size, Float:queuetime)
{
	if (failstate)
	{
		return SQL_Error(query, error, errornum, failstate);
	}
	
	new id = data[0];
	
	new UserAuthID[32], UserName[64], UserNameSQL[64], UserAddress[16], UserUID[32], UserRate[32];
	new UserID = get_user_userid(id);
	
	new Params[3];
	Params[2] = id;
	Params[0] = UserID;
	
	get_user_ip(id, UserAddress, 15, 1);
	get_user_name(id, UserName, 63);
	get_user_authid(id, UserAuthID, 31);
	get_user_info(id, "bottomcolor", UserUID, 31);
	get_user_info(id, "rate", UserRate, 31);
	
	if (equali(UserAuthID, "STEAM_ID_LAN", 0) || equali(UserAuthID, "STEAM_ID_PENDING", 0) 
	|| equali(UserAuthID, "VALVE_ID_LAN", 0) || equali(UserAuthID, "VALVE_ID_PENDING", 0) 
	|| equali(UserAuthID, "STEAM_666:88:666", 0) || containi(UserAuthID, g_Prefix) != -1)
	{
		copy(UserAuthID, 31, "");
	}
	mysql_escape_string(UserName, UserNameSQL, 63);
	
	new szBanID[32];
	new szIP[16];
	new szSteam[16];
	new szIPC[16];
	
	new s_BanTime[32];
	new s_UnBanTime[32];
	new s_UID[32];
	new s_Reason[256];
	new s_BanName[64];
	
	new i_Col_BID = SQL_FieldNameToNum(query, "banid");
	new i_Col_UID = SQL_FieldNameToNum(query, "uid");
	new i_Col_BanTime = SQL_FieldNameToNum(query, "bantime");
	new i_Col_UnBanTime = SQL_FieldNameToNum(query, "unbantime");
	new i_Col_Reason = SQL_FieldNameToNum(query, "reason");
	new i_Col_BanName = SQL_FieldNameToNum(query, "banname");
	new i_Col_IP = SQL_FieldNameToNum(query, "ip");
	new i_Col_SID = SQL_FieldNameToNum(query, "sid");
	new i_Col_IPC = SQL_FieldNameToNum(query, "ipcookie");
	
	if (SQL_MoreResults(query))
	{
		SQL_ReadResult(query, i_Col_BID, szBanID, 31);
		SQL_ReadResult(query, i_Col_IP, szIP, 15);
		SQL_ReadResult(query, i_Col_IPC, szIPC, 15);
		SQL_ReadResult(query, i_Col_SID, szSteam, 15);
		SQL_ReadResult(query, i_Col_UID, s_UID, 31);
		SQL_ReadResult(query, i_Col_BanTime, s_BanTime, 31);
		SQL_ReadResult(query, i_Col_UnBanTime, s_UnBanTime, 31);
		SQL_ReadResult(query, i_Col_Reason, s_Reason, 255);
		SQL_ReadResult(query, i_Col_BanName, s_BanName, 31);
		
		if (get_cvar_num("amx_superban_steamban") == 1 && !equal(UserAuthID, "") && equal(UserAuthID, szSteam))
		{
			WriteUID(id, s_UID);
			WriteRate(id, s_UID);
			BlockChange(id);
		}
		
		if (strlen(UserUID) == 10 && equal(UserUID, s_UID))
		{
			WriteRate(id, UserUID);
			BlockChange(id);
		}
		
		if (strlen(UserRate) == 10 && equal(UserRate, s_UID))
		{
			WriteUID(id, UserRate);
			BlockChange(id);
		}
		
		//num_to_str(TimeGap + get_systime(), s_BanTime, 31);	// WTF?!
        Params[1] = str_to_num(s_UnBanTime) - str_to_num(s_BanTime);// - TimeGap + get_systime();
		
		copy(BannedReasons[id], 255, s_Reason);
		
		set_task(1.00, "UserKick", 0, Params, 3, "", 0);
		
		static szQuery[1024];
		formatex(szQuery, charsmax(szQuery), "UPDATE %s SET ip='%s', name='%s', ipcookie='%s', bantime='%s' WHERE banid='%s'", s_DB_Table, UserAddress, UserNameSQL, UserAddress, s_BanTime, szBanID);
		
		SQL_ThreadQuery(g_h_Sql, "qh_handler", szQuery);
		
		DEBUG_Log("Player \"%s\" (%s) is kicked because he in ban list (IP \"%s\", UID \"%s\", RateID \"%s\")", UserName, s_BanName, UserAddress, UserUID, UserRate);
	}
	
	GetData(id, UserUID, UserRate, UserName);
	
	return 0;
}

public qh_handler(failstate, Handle:query, const error[], errornum, const data[], size, Float:queuetime)
{
	if (failstate)
	{
		return SQL_Error(query, error, errornum, failstate);
	}
	
	return 0;
}

public GetData(id, UserUID[32], UserRate[32], UserName[64])
{
	new UID[32];
	
	if (strlen(UserUID) != 10 && strlen(UserRate) != 10)
	{
		UID = CreateUID(id);
		UserUIDs[id] = UID;
		
		WriteRate(id, UID);
		WriteUID(id, UID);
		if (get_pcvar_num(pcvar_log) == 2)
		{
			new CurrentTime[22];
			get_time("%d/%m/%Y - %X", CurrentTime, 21);
			new logtext[256];
			format(logtext, 255, "%s: Player \"%s\" gets UID and RateID \"%s\"", CurrentTime, UserName, UID);
			write_file(g_szLogFile, logtext, -1);
		}
	}
	else if (strlen(UserUID) != 10 || strlen(UserRate) != 10)
	{
		if (strlen(UserUID) == 10)
		{
			UserUIDs[id] = UserUID;
			
			WriteRate(id, UserUID);
			if (get_pcvar_num(pcvar_log) == 2)
			{
				new CurrentTime[22];
				get_time("%d/%m/%Y - %X", CurrentTime, 21);
				new logtext[256];
				format(logtext, 255, "%s: Player \"%s\" gets RateID \"%s\"", CurrentTime, UserName, UserUID);
				write_file(g_szLogFile, logtext, -1);
			}
		}
		if (strlen(UserRate) == 10)
		{
			UserUIDs[id] = UserRate;
			
			WriteUID(id, UserRate);
			if (get_pcvar_num(pcvar_log) == 2)
			{
				new CurrentTime[22];
				get_time("%d/%m/%Y - %X", CurrentTime, 21);
				new logtext[256];
				format(logtext, 255, "%s: Player \"%s\" gets UID \"%s\"", CurrentTime, UserName, UserRate);
				write_file(g_szLogFile, logtext, -1);
			}
		}
	}
	else if (strlen(UserUID) == 10 && strlen(UserRate) == 10)
	{
		if (!equal(UserUID, UserRate, 0))
		{
			WriteUID(id, UserRate);
			UserUIDs[id] = UserRate;
		}
	}
	
	BlockChange(id);
	return 0;
}

public CreateUID(id)
{
	new UID[32];
	new i = 0;
	new Letter = random(52);
	
	if (Letter < 26)
	{
		UID[0] = Letter + 65;
	}
	
	if (Letter > 25)
	{
		UID[0] = Letter + 71;
	}
	
	for (i = 1; i < 10; i++)
	{
		Letter = random(62);
		if (Letter < 10)
		{
			UID[i] = Letter + 48;
		}
		if (Letter > 9 && Letter < 36)
		{
			UID[i] = Letter + 55;
		}
		if (Letter > 35)
		{
			UID[i] = Letter + 61;
		}
	}
	return UID;
}

public WriteUID(id, UID[32])
{
	new bottomcolor[32];
	get_user_info(id, "bottomcolor", bottomcolor, 31);
	if (4 > strlen(bottomcolor))
	{
		client_cmd(id, "bottomcolor %s%s", bottomcolor, UID);
	}
	else
	{
		client_cmd(id, "bottomcolor 6%s", UID);
	}
	return 0;
}

public WriteRate(id, UID[32])
{
	new UserRate[32];
	get_user_info(id, "rate", UserRate, 31);
	if (strlen(UserRate) <= 6)
	{
		client_cmd(id, "rate %s%s", UserRate, UID);
	}
	else
	{
		client_cmd(id, "rate 100000%s", UID);
	}
	return 0;
}

public BlockChange(id)
{
	client_cmd(id, "wait; wait; wait; wait; wait; alias rate; alias bottomcolor; writecfg %s", Config);
	if (get_pcvar_num(pcvar_hide) == 1)
	{
		client_cmd(id, "clear");
	}
	return 0;
}

public SuperBan(id, level, cid)
{
	if (!cmd_access(id, level, cid, 3, false))
	{
		return PLUGIN_HANDLED;
	}
	
	new Minutes[32];
	new Arg1[32];
	new Arg2[32];
	new Reason[256];
	new Params[4];
	
	read_argv(1, Arg1, 31);
	read_argv(2, Arg2, 31);
	read_argv(3, Reason, 255);
	
	new Player = 0;
	new players[32], plnum;
	locate_players(Arg1, players, plnum);
	
	if (!plnum)
	{
		locate_players(Arg2, players, plnum);
		
		if (!plnum)
		{
			client_print(id, print_console, "Player not found!");
			
			return PLUGIN_HANDLED;
		}
		
		copy(Minutes, 31, Arg1);
	}
	else
	{
		copy(Minutes, 31, Arg2);
	}
	
	if (plnum > 1)
	{
		print_player_list(id, players, plnum);
		return PLUGIN_HANDLED;
	}
	
	Player = players[0];
	
	if (access(Player, ADMIN_IMMUNITY))
	{
		new targetname[32];
		get_user_name(Player, targetname, 31);
		
		console_print(id, "%L", id, "CLIENT_IMM", targetname);
		
		return PLUGIN_HANDLED;
	}
	
	Params[0] = get_user_userid(Player);
	Params[1] = str_to_num(Minutes) * 60;
	Params[2] = Player;
	Params[3] = id;
	
	copy(BannedReasons[Player], 255, Reason);
	
	if (!task_exists(Player + 64, 0))
	{
		set_task(0.50, "AddBan", Player + 64, Params, 4, "b", 0);
	}
	
	return PLUGIN_HANDLED;
}

print_player_list(id, players[32], num)
{
	new szName[32], szSteam[32], szIP[32];
	
	client_print(id, print_console, "More than 1 client matching to your argument (%d):", num);
	client_print(id, print_console, "");
	
	for (new i = 0; i < num; i++)
	{
		new player = players[i];
		
		get_user_name(player, szName, 31);
		get_user_authid(player, szSteam, 31);
		get_user_ip(player, szIP, 31);
		
		client_print(id, print_console, "    %2d. %32s %16s %16s", i + 1, szName, szSteam, szIP);
	}
}

public AddBan(Params[4])
{
	new Minutes = Params[1] / 60;
	new Player = Params[2];
	new id = Params[3];
	
	new UnBanTime[16];
	new Reason[256];
	new ReasonSQL[256];
	
	copy(Reason, 255, BannedReasons[Player]);
	mysql_escape_string(Reason, ReasonSQL, 255);
	
	if (get_pcvar_num(pcvar_cookieban) == 1)
	{
		if (get_user_time(Player, 1) < get_pcvar_float(pcvar_cookiewait))
		{
			change_task(Player + 64, get_pcvar_float(pcvar_cookiewait), 0);
			return;
		}
	}
	else
	{
		if (get_user_time(Player, 1) < 1)
		{
			change_task(Player + 64, 1.00, 0);
			return;
		}
	}
	change_task(Player + 64, 1440.00, 0);
	
	if (Minutes)
	{
		num_to_str(TimeGap + get_systime(0) + Minutes * 60, UnBanTime, 15);
	}
	else
	{
		copy(UnBanTime, 15, "0");
	}
	
	new UserName[64];
	new UserAuthID[32];
	new UserAddress[16];
	new AdminName[64];
	new UserNameSQL[64];
	new AdminNameSQL[64];
	new CurrentTime[16];
	
	num_to_str(TimeGap + get_systime(), CurrentTime, 15);
	get_user_authid(Player, UserAuthID, 31);
	
	if (equali(UserAuthID, "STEAM_ID_LAN", 0) || equali(UserAuthID, "STEAM_ID_PENDING", 0) || equali(UserAuthID, "VALVE_ID_LAN", 0) || equali(UserAuthID, "VALVE_ID_PENDING", 0) || equali(UserAuthID, "STEAM_666:88:666", 0) || containi(UserAuthID, g_Prefix) != -1)
	{
		copy(UserAuthID, 31, "");
	}
	
	
	// MySQL
	get_user_name(Player, UserName, 63);
	mysql_escape_string(UserName, UserNameSQL, 63);
	
	get_user_name(id, AdminName, 63);
	mysql_escape_string(AdminName, AdminNameSQL, 63);
	
	get_user_ip(Player, UserAddress, 15, 1);
	
	static szQuery[1024];
	
	if (get_pcvar_num(pcvar_utf8) == 1)
		formatex(szQuery, charsmax(szQuery), "SET NAMES utf8; ");
	else
		formatex(szQuery, charsmax(szQuery), "");
	
	formatex(szQuery, charsmax(szQuery), "%sINSERT INTO %s (banid, sid, ip, ipcookie, uid, banname, name, admin, reason, time, bantime, unbantime) VALUES(NULL,'%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s')", 
						szQuery, s_DB_Table, UserAuthID, UserAddress, UserAddress, UserUIDs[Player], UserNameSQL, UserNameSQL, AdminNameSQL, ReasonSQL, CurrentTime, CurrentTime, UnBanTime);
	
	new data[1];
	data[0] = Player;
	
	SQL_ThreadQuery(g_h_Sql, "qh_ban", szQuery, data, sizeof(data));
	
	// Notification
	new Period[64];
	Period = convert_period(0, Minutes * 60);
	
	DEBUG_Log("Admin \"%s\" ban \"%s\" for %s, reason - \"%s\"", AdminName, UserName, Period, Reason);

	if (get_pcvar_num(pcvar_hideadmin) == 1)
	{
		get_user_name(0, AdminName, 31);
	}
	
	if (get_pcvar_num(pcvar_messages) > 0)
	{
		set_hudmessage(255, 255, 255, 0.02, 0.70, 0, 6.00, 12.00, 1.00, 2.00, -1);
		
		new _maxpl = get_maxplayers();
		for (new id = 1; id < _maxpl; id++)
		{
			if (!is_user_connected(id) || is_user_bot(id) || is_user_hltv(id))
				continue;
			
			Period = convert_period(id, Minutes * 60);
			
			static szMsg[190], iLen;
			iLen = format(szMsg, charsmax(szMsg), "%s", AdminName);
			
			if (Minutes)
			{
				iLen += format(szMsg[iLen], charsmax(szMsg) - iLen, " %L \4%s\1 %L \3%s\1", id, "SUPERBAN_BAN_MESSAGE", UserName, id, "SUPERBAN_FOR", Period);
			}
			else
			{
				iLen += format(szMsg[iLen], charsmax(szMsg) - iLen, " \3%L\1 %L \4%s\1", id, "SUPERBAN_PERMANENT", id, "SUPERBAN_BAN_MESSAGE", UserName);
			}
			
			if (!equal(Reason, ""))
			{
				iLen += format(szMsg[iLen], charsmax(szMsg) - iLen, ", %L \"\3%s\1\"", id, "SUPERBAN_REASON", Reason);
			}
			
			new msgtype = get_pcvar_num(pcvar_messages);
			new color = get_pcvar_num(pcvar_chatcolor);
			
			if (color && (msgtype == 1 || msgtype == 3))
				client_print_color(id, DontChange, "%s%s", g_ChatPrefixColor, szMsg);
			
			if (msgtype == 3 || (!color && msgtype == 1))
			{
				replace_all(szMsg, charsmax(szMsg), "\1", "");
				replace_all(szMsg, charsmax(szMsg), "\3", "");
				replace_all(szMsg, charsmax(szMsg), "\4", "");
			}
			
			if (msgtype == 2 || msgtype == 3)
				show_hudmessage(id, "%s", szMsg);
			
			if (!color && (msgtype == 1 || msgtype == 3))
				client_print(id, print_chat, "%s%s", g_ChatPrefix, szMsg);
		}
	}
	
	if (get_pcvar_num(pcvar_motd))
	{
		new szURL[256];
		get_pcvar_string(pcvar_banurl, szURL, charsmax(szURL));
		
		new Period[64];
		Period = convert_period(0, Minutes * 60);
		
		formatex(szURL, charsmax(szURL), "%s?NICK=%s&REASON=%s&TIME=%s&UNBAN=%s&ADMIN=%s&URL=%s", szURL, UserNameSQL, ReasonSQL, Period, UnBanTime, AdminNameSQL, g_Comment);
		
		show_motd(Player, szURL);
	}

	set_task(get_pcvar_float(pcvar_kicktime), "UserKick", 0, Params, 3, "", 0);
}

public qh_ban(failstate, Handle:query, const error[], errornum, const data[], size, Float:queuetime)
{
	if (failstate)
	{
		return SQL_Error(query, error, errornum, failstate);
	}
	
	return 0;
}

public UnSuperBan(id, level, cid)
{
	if (!cmd_access(id, level, cid, 2, false))
	{
		return 1;
	}
	
	new UnbanFlags[24];
	get_pcvar_string(pcvar_unbanflag, UnbanFlags, 23);
	if (!(read_flags(UnbanFlags) & get_user_flags(id, 0)))
	{
		return 1;
	}
	
	new Data[65];
	new DataSQL[64];
	read_argv(1, Data, 63);
	mysql_escape_string(Data, DataSQL, 63);
	
	new s_Time[32];
	num_to_str(TimeGap + get_systime(), s_Time, 31);
	
	static szQuery[1024];
	formatex(szQuery, charsmax(szQuery), "UPDATE %s SET unbantime='-1' WHERE (ip='%s' OR name='%s' OR banname='%s' OR uid='%s') AND (unbantime > '%s' OR unbantime = '0')", s_DB_Table, DataSQL, DataSQL, DataSQL, DataSQL, 
																		s_Time);
	Data[64] = id;
	
	SQL_ThreadQuery(g_h_Sql, "qh_unban", szQuery, Data, sizeof(Data));
	
	return PLUGIN_HANDLED;
}

public qh_unban(failstate, Handle:query, const error[], errornum, const data[], size, Float:queuetime)
{
	if (failstate)
	{
		return SQL_Error(query, error, errornum, failstate);
	}
	
	new id = data[64];
	new AdminName[32];
	get_user_name(id, AdminName, 31);
	
	console_print(id, "%L: %d %L", id, "SUPERBAN_PROCESSED", SQL_AffectedRows(query), id, "SUPERBAN_ITEMS");
	
	DEBUG_Log("Admin \"%s\" unban \"%s\"", AdminName, data);
	
	return 0;
}

public BanList(id, level, cid)
{
	if (!cmd_access(id, level, cid, 2, false))
	{
		return 1;
	}
	
	new Data[8];
	read_argv(1, Data, 7);
	
	static szQuery[1024];
	formatex(szQuery, charsmax(szQuery), "SELECT * FROM %s ORDER BY banid DESC LIMIT %d", s_DB_Table, str_to_num(Data));
	
	new data[1];
	data[0] = id;
	
	SQL_ThreadQuery(g_h_Sql, "qh_banlist", szQuery, data, sizeof(data));
	
	return PLUGIN_HANDLED;
}

public qh_banlist(failstate, Handle:query, const error[], errornum, const data[], size, Float:queuetime)
{
	if (failstate)
	{
		return SQL_Error(query, error, errornum, failstate);
	}
	
	new id = data[0];
	
	new s_BanTime[32];
	new s_UnBanTime[32];
	new s_UID[32];
	new s_Reason[256];
	new s_Name[32];
	new s_BanName[32];
	new s_IP[16];
	new s_Admin[32];
	new i_Col_UID = SQL_FieldNameToNum(query, "uid");
	new i_Col_BanTime = SQL_FieldNameToNum(query, "bantime");
	new i_Col_UnBanTime = SQL_FieldNameToNum(query, "unbantime");
	new i_Col_Reason = SQL_FieldNameToNum(query, "reason");
	new i_Col_Name = SQL_FieldNameToNum(query, "name");
	new i_Col_BanName = SQL_FieldNameToNum(query, "banname");
	new i_Col_IP = SQL_FieldNameToNum(query, "ip");
	new i_Col_Admin = SQL_FieldNameToNum(query, "admin");
	
	while (SQL_MoreResults(query))
	{
		SQL_ReadResult(query, i_Col_UID, s_UID, 31);
		SQL_ReadResult(query, i_Col_BanTime, s_BanTime, 31);
		SQL_ReadResult(query, i_Col_UnBanTime, s_UnBanTime, 31);
		SQL_ReadResult(query, i_Col_Reason, s_Reason, 255);
		SQL_ReadResult(query, i_Col_Name, s_Name, 31);
		SQL_ReadResult(query, i_Col_BanName, s_BanName, 31);
		SQL_ReadResult(query, i_Col_IP, s_IP, 15);
		SQL_ReadResult(query, i_Col_Admin, s_Admin, 31);
		SQL_NextRow(query);
		
		if (!equal(s_UnBanTime, "0", 0) && !equal(s_UnBanTime, "-1", 0))
		{
			format_time(s_UnBanTime, 31, "%d/%m/%Y [%H:%M]", str_to_num(s_UnBanTime));
		}
		else if (equal(s_UnBanTime, "0", 0))
		{
			s_UnBanTime = "Permanent";
		}
		else
		{
			s_UnBanTime = "Unbanned";
		}
		
		client_print(id, print_console, "--------------------");
		client_print(id, print_console, "Name: %s", s_BanName);
		client_print(id, print_console, "From: %s", s_BanTime);
		client_print(id, print_console, "To: %s", s_UnBanTime);
		client_print(id, print_console, "UID: %s", s_UID);
		client_print(id, print_console, "IP: %s", s_IP);
		client_print(id, print_console, "Reason: %s", s_Reason);
		client_print(id, print_console, "Admin: %s", s_Admin);
	}
	
	client_print(id, print_console, "--------------------");
	
	return 0;
}

public UserKick(Params[3])
{
	if (get_pcvar_num(pcvar_cookieban) == 1)
	{
		new html[256];
		new url[128];
		get_pcvar_string(pcvar_banurl, url, 127);
		format(html, 256, "<html><meta http-equiv=\"Refresh\" content=\"0; URL=%s\"><head><title>Cstrike MOTD</title></head><body bgcolor=\"black\" scroll=\"yes\"></body></html>", url);
		show_motd(Params[2], html, "Banned");
	}
	
	new Period[64];
	new Time = 0;
	new id = Params[2];
	Time = Params[1];
	Period = convert_period(id, Time);
	
	//client_cmd(Params[2], "clear");
	client_cmd(Params[2], "echo ------------------------------");
	client_cmd(Params[2], "echo \"%L!\"", id, "SUPERBAN_BANNED");
	client_cmd(Params[2], "echo \"%L: %s\"", id, "SUPERBAN_PERIOD", Period);
	if (!equal(BannedReasons[id], "", 0))
	{
		client_cmd(id, "echo \"%L: %s\"", id, "SUPERBAN_REASON", BannedReasons[id]);
	}
	if (!equal(g_Comment, ""))
	{
		client_cmd(id, "echo \"%s\"", g_Comment);
	}
	client_cmd(id, "echo ------------------------------");
	
	if (equal(BannedReasons[id], "", 0))
	{
		server_cmd("kick #%d  %L. %L: %s. %s", Params[0], id, "SUPERBAN_BANNED", id, "SUPERBAN_PERIOD", Period, g_Comment);
	}
	else
	{
		server_cmd("kick #%d  %L. %L: %s. %L: %s. %s", Params[0], id, "SUPERBAN_BANNED", id, "SUPERBAN_REASON", BannedReasons[id], id, "SUPERBAN_PERIOD", Period, g_Comment);
	}
	return 1;
}

public actionBanMenu(id, key)
{
	switch (key)
	{
		case 8 -1:
		{
			g_menuOption[id]++;
			g_menuOption[id] %= ArraySize(g_bantimes);
			g_menuSettings[id] = ArrayGetCell(g_bantimes, g_menuOption[id]);
			displayBanMenu(id, g_menuPosition[id]);
			
			return;
		}
		case 9  -1:
		{
			displayBanMenu(id, ++g_menuPosition[id]);
		}
		case 0  +9:
		{
			displayBanMenu(id, --g_menuPosition[id]);
		}
		default:
		{
			/*if (!g_UseTimeMenu && key == 8 - 1)
			{
				g_menuOption[id] = (g_menuOption[id]++) % ArraySize(g_bantimes);
				g_menuSettings[id] = ArrayGetCell(g_bantimes, g_menuOption[id]);
				displayBanMenu(id, g_menuPosition[id]);
				
				return;
			}*/
			
			new player = g_menuPlayers[id][key + g_menuPosition[id] * (g_UseTimeMenu ? 8 : 7)];
			new name[32];
			new name2[32];
			new authid[32];
			new authid2[32];
			get_user_name(player, name2, 31);
			get_user_authid(id, authid, 31);
			get_user_authid(player, authid2, 31);
			get_user_name(id, name, 31);
			new userid2 = get_user_userid(player);
			SelectedID[id] = userid2;
			SelectedTime[id] = g_menuSettings[id];
			client_cmd(id, "messagemode Reason");
		}
	}
	return;
}

public Cmd_SuperbanReason(id)
{
	new Args[256];
	read_args(Args, 255);
	remove_quotes(Args);
	if (Args[0])
	{
		client_cmd(id, "amx_superban #%d %d \"%s\"", SelectedID[id], SelectedTime[id], Args);
	}
	else
	{
		client_cmd(id, "amx_superban #%d %d", SelectedID[id], SelectedTime[id]);
	}
	return 1;
}

displayBanMenu(id, pos)
{
	if (pos < 0)
	{
		return 0;
	}
	
	get_players(g_menuPlayers[id], g_menuPlayersNum[id], "", "");
	
	new menuBody[512];
	new b;
	new i = 0;
	new name[32];
	new PERPAGE = (g_UseTimeMenu ? 8 : 7);
	new start = pos * PERPAGE;
	
	if (g_menuPlayersNum[id] <= start)
	{
		g_menuPosition[id] = 0;
		pos = 0;
		start = 0;
	}
	
	new len = format(menuBody, 511, (g_coloredMenus ? "\\y%L \\r%d/%d\n\\w\n" : "%L %d/%d\n\n"), id, "SUPERBAN_MENU", pos + 1, (g_menuPlayersNum[id] ? 1 : 0) + g_menuPlayersNum[id] / PERPAGE);
	
	new end = start + PERPAGE;
	new keys = 640;
	
	if (g_menuPlayersNum[id] < end)
	{
		end = g_menuPlayersNum[id];
	}
	
	for (new a = start; a < end; a++)
	{
		i = g_menuPlayers[id][a];
		get_user_name(i, name, 31);
		
		if (is_user_bot(i) || access(i, 1))
		{
			b++;
			if (g_coloredMenus)
			{
				len += format(menuBody[len], 511 - len, "\\d%d. %s\n\\w", b, name);
			}
			else
			{
				len += format(menuBody[len], 511 - len, "#. %s\n", name);
			}
		}
		else
		{
			keys |= (1 << b);
			if (is_user_admin(i))
			{
				b++;
				len += format(menuBody[len], 511 - len, (g_coloredMenus ? "\\y%d. \\w%s \\r*\n\\w" : "%d. %s *\n"), b, name);
			}
			else
			{
				b++;
				len += format(menuBody[len], 511 - len, "\\y%d.\\w %s\n", b, name);
			}
		}
	}
	
	if (g_menuSettings[id])
	{
		len = format(menuBody[len], 511 - len, "\n\\y8.\\w %s\n", convert_period(id, g_menuSettings[id] * 60)) + len;
	}
	else
	{
		len = format(menuBody[len], 511 - len, "\n\\y8.\\w %L\n", id, "SUPERBAN_PERMANENT") + len;
	}
	
	if (g_menuPlayersNum[id] != end)
	{
		format(menuBody[len], 511 - len, "\n\\y9.\\w %L...\n0. %L", id, "SUPERBAN_MORE", id, (pos ? "SUPERBAN_BACK" : "SUPERBAN_EXIT"));
		keys |= 256;
	}
	else
	{
		format(menuBody[len], 511 - len, "\n\\y0.\\w %L", id, (pos ? "SUPERBAN_BACK" : "SUPERBAN_EXIT"));
	}
	
	show_menu(id, keys, menuBody, -1, "SBMENU");
	return 0;
}

public cmdBanMenu(id, level, cid)
{
	if (!cmd_access(id, level, cid, 1, false))
	{
		return 1;
	}
	
	g_menuOption[id] = 0;
	
	if (ArraySize(g_bantimes) > 0)
	{
		g_menuSettings[id] = ArrayGetCell(g_bantimes, g_menuOption[id]);
	}
	else
	{
		g_menuSettings[id] = 0;
	}
	
	g_menuPosition[id] = 0;
	displayBanMenu(id, 0);
	return 1;
}

stock SQL_Error(Handle:query, const error[], errornum, failstate)
{
	#pragma unused failstate
	new qstring[1024];
	SQL_GetQueryString(query, qstring, 1023);
	
	DEBUG_Log("SQL ERROR %d - %s on query \"%s\"", errornum, error, qstring);
	//DEBUG_Log("%L", LANG_SERVER, "SQL_ERROR_QUERY", errornum, error);
	//DEBUG_Log("%L", LANG_SERVER, "SQL_ERROR_QUERY", qstring);
	return 0;
}

stock DEBUG_Log(const msg[], any:...)
{
	if (get_pcvar_num(pcvar_log))
	{
		new CurrentTime[22];
		get_time("%d/%m/%Y - %X", CurrentTime, 21);
		
		new logtext[256];
		vformat(logtext, sizeof(logtext)-1, msg, 2);
		
		format(logtext, sizeof(logtext)-1, "%s: %s", CurrentTime, logtext);
		
		write_file(g_szLogFile, logtext, -1);
	}
}

stock mysql_escape_string(const source[],  dest[],  len)
{
        copy(dest, len, source);
 
        replace_all(dest, len, "\\", "\\\\");
        //replace_all(dest, len, "\0", "\\0");
        replace_all(dest, len, "\n", "\\n");
        replace_all(dest, len, "\r", "\\r");
        replace_all(dest, len, "\x1a", "\\Z");
        
        replace_all(dest, len, "'", "\\'");
        replace_all(dest, len, "`", "\\`");
        replace_all(dest, len, "\"", "\\\"");
}

stock hash_string(const string[])
{
	new p = 31; // Сделать для aA1
	new hash = 0, p_pow = 1;
	new slen = strlen(string);
	
	for (new i = 0; i < slen; ++i)
	{
		hash += (string[i] - 'a' + 1) * p_pow;
		p_pow *= p;
	}
	
	return hash;
}

