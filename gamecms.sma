#include <amxmodx>
#include <easy_http>
#include <json>
#include <ini_file>


new PLUGIN[]="GameCMS.ORG"
new AUTHOR[]="Wohaho"
new VERSION[]="1.00"
new SERVER_API_KEY[70] = "none"
new const FILENAME[] = "gamecms.org"
public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)
	register_concmd("amx_gamecms_force_commands","forceCommands", ADMIN_RCON)
	register_concmd("amx_gamecms_reload_ini","reloadIniFile", ADMIN_RCON)
	register_concmd("amx_gamecms_set_server_api_key","setServerApiKey", ADMIN_RCON)
	//SERVER_API_KEY = register_cvar("gamecms_server_api_key", "none")
	
	if (!ini_read_string(FILENAME, "SERVER-API-KEY", "SERVER_API_KEY", SERVER_API_KEY, charsmax(SERVER_API_KEY))){
		ini_write_string(FILENAME, "SERVER-API-KEY", "SERVER_API_KEY", SERVER_API_KEY);
	}
	
	
	//task that run every 2 min and fetch new comm
	set_task(120.0 , "requestBegin", 2222,_,_,"b")
}

public forceCommands(){
	requestBegin()
	return PLUGIN_HANDLED
}

public reloadIniFile(){
	ini_read_string(FILENAME, "SERVER-API-KEY", "SERVER_API_KEY", SERVER_API_KEY, charsmax(SERVER_API_KEY))
	
	server_print("[GameCMS.ORG] Ini file reloaded!")
	return PLUGIN_CONTINUE;
}


public setServerApiKey(id, level, cid){
	if (!cmd_access ( id, level, cid, 1)){
		return PLUGIN_HANDLED;
	}
	new server_api_key[65]
	read_argv(1, server_api_key, charsmax(server_api_key));
	server_print("%i", strlen(server_api_key))
	ini_write_string(FILENAME, "SERVER-API-KEY", "SERVER_API_KEY", server_api_key);
	SERVER_API_KEY = server_api_key
	server_print("[GameCMS.ORG] Server API key changed!")
	return PLUGIN_CONTINUE;
}

public requestBegin()
{	
	new EzHttpOptions:options_id = ezhttp_create_options()
	
	ezhttp_option_set_header(options_id, "Authorization", fmt("Bearer %s", getServerApiKey()))
	
	ezhttp_get("https://api.gamecms.org/v2/commands/queue/cs16", "handleQueueCommands", options_id)
}


public handleQueueCommands(EzHttpRequest:request_id)
{
	if (ezhttp_get_error_code(request_id) != EZH_OK)
	{
		new error[64]
		ezhttp_get_error_message(request_id, error, charsmax(error))
		server_print("[GameCMS.ORG] Response error: %s", error);
		return PLUGIN_HANDLED;
	}
	
	if (ezhttp_get_http_code(request_id) != 200){
		server_print("[GameCMS.ORG] No due commands found.");
		return PLUGIN_HANDLED;
	}
	
	ezhttp_save_data_to_file(request_id, fmt("addons/amxmodx/data/gamecms_response_%d.json", request_id))
	
	new EzHttpOptions:options_id = ezhttp_create_options()
	ezhttp_option_set_header(options_id, "Authorization", fmt("Bearer %s", getServerApiKey()))
	ezhttp_get("https://api.gamecms.org/v2/commands/complete", "handleCompleteRequest", options_id)
	
	parserJsonFile(request_id)
}


public parserJsonFile(EzHttpRequest:request_id)
{
	new JSON:main_object = json_parse(fmt("addons/amxmodx/data/gamecms_response_%d.json", request_id), true);
	
	if (main_object == Invalid_JSON)
	{
		server_print("[GameCMS.ORG] Invalid data!");
		return PLUGIN_HANDLED;
	}
	
	new JSON:data_array = json_object_get_value(main_object, "data");
	new count_array = json_array_get_count(data_array);
	
	for (new i = 0; i < count_array; i++)
	{
		new JSON:command_object = json_array_get_value(data_array, i);
		
		new JSON:commands_array = json_object_get_value(command_object, "commands");
		
		new count_commands = json_array_get_count(commands_array);
		
		for (new j = 0; j < count_commands; j++){
			new command[250];
			json_array_get_string(commands_array, j, command, sizeof(command));
			server_cmd(command);
		}
		
		json_free(commands_array);
		json_free(command_object);
	}
	
	server_print("[GameCMS.ORG] All [%i] commands fetched.", sizeof data_array)
	
	json_free(data_array);
	json_free(main_object);
	delete_file(fmt("addons/amxmodx/data/gamecms_response_%d.json", request_id))
	return PLUGIN_CONTINUE;
}


public handleCompleteRequest(EzHttpRequest:request_id){
	return PLUGIN_CONTINUE;
}


public getServerApiKey(){
	return SERVER_API_KEY;
}