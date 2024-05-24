#include <amxmodx>
#include <easy_http>
#include <json>
#include <file>
#include <ini_file>

new PLUGIN[] = "GameCMS.ORG";
new AUTHOR[] = "Wohaho";
new VERSION[] = "1.00";

new SERVER_API_KEY[70];
new WEBSITE_API_KEY[70];

new int:ServerId = 0;

new const CONFIG_FILE[] = "gamecms.org"

public plugin_natives()
{
    register_library("gamecms");
    register_native("ReadConfigStringValue","NativeReadStringConfig");
    register_native("ReadConfigIntValue","NativeReadIntConfig");
    register_native("GetGameCMSServerId","getGameCMSServerId");
}

public plugin_init()
{
    
    register_plugin(PLUGIN, VERSION, AUTHOR);
 
    register_concmd("gcms_force_commands","forceCommands", ADMIN_RCON);
    register_concmd("gcms_reload_ini","reloadIniFile", ADMIN_RCON);
    register_concmd("gcms_set_server_api_key","setServerApiKey", ADMIN_RCON, "- gcms_set_server_api_key <key>");
	
    ReadConfigStringValue("SERVER-API-KEY", "SERVER_API_KEY", "none", SERVER_API_KEY, charsmax(SERVER_API_KEY));
    ReadConfigStringValue("WEBSITE-API-KEY", "WEBSITE_API_KEY", "none", WEBSITE_API_KEY, charsmax(WEBSITE_API_KEY));

    setServerId();

    set_task(120.0, "requestBegin", 2222, _, _, "b");
}

public NativeReadStringConfig(plugin, params)
{	
	new szsection[70],szKey[70],szDefaultValue[70],szOutPut[70];
	get_string(1,szsection,charsmax(szsection));
	get_string(2,szKey,charsmax(szKey));
	get_string(3,szDefaultValue,charsmax(szDefaultValue));
	
	ReadConfigStringValue(szsection,szKey,szDefaultValue,szOutPut,charsmax(szOutPut));
	
	set_string(4, szOutPut,charsmax(szOutPut));	
}

public ReadConfigStringValue(const section[], const key[],  defaultValue[], output[], maxLength)
{
    if (!ini_read_string(CONFIG_FILE, section, key, output, maxLength))
    {
        ini_write_string(CONFIG_FILE, section, key, defaultValue);
        ini_read_string(CONFIG_FILE, section, key, output, maxLength);
    }
}

public NativeReadIntConfig(plugin, params)
{
    new szsection[70], szKey[70], szDefaultValue[70];
    get_string(1, szsection, charsmax(szsection));
    get_string(2, szKey, charsmax(szKey));
    get_string(3, szDefaultValue, charsmax(szDefaultValue));
    
    new intOutput;
    ReadConfigIntValue(szsection, szKey, szDefaultValue, intOutput);
    return intOutput;
}


public ReadConfigIntValue(const section[], const key[], defaultValue[], &output)
{
    new defaultValueInt = str_to_num(defaultValue);
    if (!ini_read_int(CONFIG_FILE, section, key, output))
    {
        ini_write_int(CONFIG_FILE, section, key, defaultValueInt);
        ini_read_int(CONFIG_FILE, section, key, output);
    }
}


public reloadIniFile(){
	
	ReadConfigStringValue("SERVER-API-KEY", "SERVER_API_KEY", "none",SERVER_API_KEY, charsmax(SERVER_API_KEY));
	ReadConfigStringValue("WEBSITE-API-KEY", "WEBSITE_API_KEY","none", WEBSITE_API_KEY, charsmax(WEBSITE_API_KEY));
	server_print("[GameCMS] Ini file reloaded!");
	
	return PLUGIN_CONTINUE;
}

public setServerApiKey(id, level, cid){
	
	if (!cmd_access (id, level, cid, 1)){
		return PLUGIN_HANDLED;
	}
	
	new server_api_key[65]
	read_argv(1, server_api_key, charsmax(server_api_key));
	server_print("%i", strlen(server_api_key))
	ini_write_string(CONFIG_FILE, "SERVER-API-KEY", "SERVER_API_KEY", server_api_key);
	SERVER_API_KEY = server_api_key
	server_print("[GameCMS] Server API key changed!");
	return PLUGIN_CONTINUE;
}

public forceCommands()
{
    requestBegin();
    return PLUGIN_HANDLED;
}

public requestBegin()
{
    new EzHttpOptions:options_id = ezhttp_create_options();

    ezhttp_option_set_header(options_id, "Authorization", fmt("Bearer %s", SERVER_API_KEY));

    ezhttp_get("https://api.gamecms.org/v2/commands/queue/cs16", "handleQueueCommands", options_id);
}

public handleQueueCommands(EzHttpRequest:request_id)
{
    if (ezhttp_get_error_code(request_id) != EZH_OK) {
        new error[64];
        ezhttp_get_error_message(request_id, error, charsmax(error));
        server_print("[GameCMS] Response error: %s", error);
        return PLUGIN_HANDLED;
    }

    if (ezhttp_get_http_code(request_id) != 200) {
        server_print("[GameCMS] No due commands found.");
        return PLUGIN_HANDLED;
    }

    ezhttp_save_data_to_file(request_id, fmt("addons/amxmodx/data/gamecms_response_%d.json", request_id));

    new EzHttpOptions:options_id = ezhttp_create_options();
    ezhttp_option_set_header(options_id, "Authorization", fmt("Bearer %s", SERVER_API_KEY));
    ezhttp_get("https://api.gamecms.org/v2/commands/complete", "handleCompleteRequest", options_id);

    return parserJsonFile(request_id);
}

public parserJsonFile(EzHttpRequest:request_id)
{
    new JSON:main_object = json_parse(fmt("addons/amxmodx/data/gamecms_response_%d.json", request_id), true);

    if (main_object == Invalid_JSON) {
        server_print("[GameCMS] Invalid JSON response!");
        return PLUGIN_HANDLED;
    }

    new JSON:data_array = json_object_get_value(main_object, "data");
    new count_array = json_array_get_count(data_array);

    for (new i = 0; i < count_array; i++) {
        new JSON:command_object = json_array_get_value(data_array, i);

        new JSON:commands_array = json_object_get_value(command_object, "commands");

        new count_commands = json_array_get_count(commands_array);

        for (new j = 0; j < count_commands; j++) {
            new command[250];
            json_array_get_string(commands_array, j, command, sizeof(command));
            server_cmd(command);
        }

        json_free(commands_array);
        json_free(command_object);
    }

    server_print("[GameCMS] All [%i] commands fetched.", sizeof data_array);

    json_free(data_array);
    json_free(main_object);
    delete_file(fmt("addons/amxmodx/data/gamecms_response_%d.json", request_id));

    return PLUGIN_CONTINUE;
}

public handleCompleteRequest(EzHttpRequest:request_id)
{
    return PLUGIN_CONTINUE;
}

public setServerId()
{
    new EzHttpOptions:options_id = ezhttp_create_options();
    
    ezhttp_option_set_header(options_id, "Authorization", fmt("Bearer %s", SERVER_API_KEY));

    ezhttp_get("https://api.gamecms.org/v2/server", "handleServerIdResponse", options_id);
}

public handleServerIdResponse(EzHttpRequest:request_id)
{
    if (ezhttp_get_error_code(request_id) != EZH_OK) {
        new error[64];
        ezhttp_get_error_message(request_id, error, charsmax(error));
        server_print("[GameCMS] Response error: %s", error);
        return PLUGIN_HANDLED;
    }

    if (ezhttp_get_http_code(request_id) != 200) {
        server_print("[GameCMS] Could not connect to GameCMS API Please make sure your Server API key is set correctly.");
        return PLUGIN_HANDLED;
    }
    new SERVER_ID_CONFIG_FILE[50] = "addons/amxmodx/data/gamecms_server_id.json";
    
    ezhttp_save_data_to_file(request_id, SERVER_ID_CONFIG_FILE);

    new JSON:main_object = json_parse(SERVER_ID_CONFIG_FILE, true);
    if (main_object == Invalid_JSON) {
        server_print("[GameCMS] Invalid JSON response!");
        return PLUGIN_HANDLED;
    }

    new JSON:id_object = json_object_get_value(main_object, "id");
    ServerId = json_get_number(id_object);
  

    server_print("[GameCMS] Successfully connected to GameCMS API.");
   
    json_free(id_object);
    json_free(main_object);
    delete_file(SERVER_ID_CONFIG_FILE);

    return PLUGIN_HANDLED;
}

public getServerApiKey()
{
    return SERVER_API_KEY;
}

public getGameCMSServerId(){
	return ServerId;
}
