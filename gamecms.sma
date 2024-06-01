#include <amxmodx>
#include <easy_http>
#include <json>
#include <file>

new PLUGIN[] = "[GameCMS] Core";
new AUTHOR[] = "Wohaho";
new VERSION[] = "1.3";



enum _:cvar_set
{
	CVAR_SQL_HOST,
	CVAR_SQL_USER,
	CVAR_SQL_PASS,
	CVAR_SQL_DB,
	CVAR_SERVER_API_KEY,
	CVAR_WEBSITE_API_KEY,
	CVAR_ADMIN_COMMAND_SERIVCE,
	CVAR_ADMIN_DELETE_EXPIRED,
	CVAR_ADVANCED_BANS_PREFIX,
	CVAR_SERVER_ID,
	CVAR_SERVER_TIME
}
new cvar[cvar_set]

new SERVER_API_KEY[70];
new WEBSITE_API_KEY[70];

new ServerId = 0;

public plugin_precache() {
    
    cvar[CVAR_SERVER_API_KEY] = create_cvar("server-api-key", "none",  FCVAR_PROTECTED, "GameCMS Server API Key.")
    cvar[CVAR_WEBSITE_API_KEY] = create_cvar("website-api-key", "none",  FCVAR_PROTECTED, "GameCMS Website API Key.")

    cvar[CVAR_ADMIN_COMMAND_SERIVCE] = create_cvar("admin-command-service", "gcms-service",  FCVAR_PROTECTED, "Command for the admin plugin that display if the player has any access flags.")
    cvar[CVAR_ADMIN_DELETE_EXPIRED] = create_cvar("admin-delete-expired-admins", "0",  FCVAR_PROTECTED, 
                                                    "Should the plugin delete expired admins from the database?^n\
                                                    By default is 0^n\
												    1 - Delete admins from database^n\
												    0 - Do not delete^n\");

    cvar[CVAR_ADVANCED_BANS_PREFIX] = create_cvar("advanced-bans-prefix", "s1", FCVAR_PROTECTED, "GameCMS Advanced Bans table prefix.^n\
                                                    This is the table prefix for the server.^n\
                                                    If you want each server to have its own ban system, you can change this table prefix.^n\
                                                    Alternatively, you can set the ab_single_server cvar to 1 in amx.cfg.");


    cvar[CVAR_SQL_HOST] = create_cvar("gcms-sql-host", "localhost", FCVAR_PROTECTED, "MySQL host")
    cvar[CVAR_SQL_DB] = create_cvar("gcmss-sql-db", "amxx", FCVAR_PROTECTED, "MySQL Database Name")
    cvar[CVAR_SQL_USER] = create_cvar("gcms-sql-user", "root", FCVAR_PROTECTED, "MySQL Username")
    cvar[CVAR_SQL_PASS] = create_cvar("gcms-sql-password", "", FCVAR_PROTECTED, "MySQL User Password")
    cvar[CVAR_SERVER_ID] = create_cvar("gamcms-server-id", "0", FCVAR_PROTECTED, "GameCMS Server ID. DO NOT CHANGE OR TOUCH THIS VALUE!!")
    
    AutoExecConfig();
}



public plugin_natives()
{
    register_library("gamecms");
    register_native("GetGameCMSServerId","getGameCMSServerId");
}


public plugin_init()
{
    
    register_plugin(PLUGIN, VERSION, AUTHOR,"https://gamecms.org");
 
    register_concmd("gcms_force_commands","forceCommands", ADMIN_RCON);
    register_concmd("gcms_reload_ini","reloadIniFile", ADMIN_RCON);
    register_concmd("gcms_set_server_api_key","setServerApiKey", ADMIN_RCON, "- gcms_set_server_api_key <key>");
	
}


public OnConfigsExecuted(){

    get_pcvar_string(cvar[CVAR_SERVER_API_KEY], SERVER_API_KEY, charsmax(SERVER_API_KEY))
    get_pcvar_string(cvar[CVAR_WEBSITE_API_KEY], WEBSITE_API_KEY, charsmax(WEBSITE_API_KEY))
    setServerId();
    set_task(120.0, "requestBegin", 2222, _, _, "b");
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
    new error[64];

    // Check for request errors
    if (ezhttp_get_error_code(request_id) != EZH_OK) {
        ezhttp_get_error_message(request_id, error, charsmax(error));
        server_print("[GameCMS] Response error: %s", error);
        return PLUGIN_HANDLED;
    }

    // Check for HTTP errors
    if (ezhttp_get_http_code(request_id) != 200) {
        server_print("[GameCMS] Could not connect to GameCMS API. Please make sure your Server API key is set correctly.");
        return PLUGIN_HANDLED;
    }

    new SERVER_ID_CONFIG_FILE[50] = "addons/amxmodx/data/gamecms_server_id.json";
    
    // Save the response to a file
    if (!ezhttp_save_data_to_file(request_id, SERVER_ID_CONFIG_FILE)) {
        server_print("[GameCMS] Failed to save response data to file.");
        return PLUGIN_HANDLED;
    }

    // Parse JSON data from the file
    new JSON:main_object = json_parse(SERVER_ID_CONFIG_FILE, true);
    if (main_object == Invalid_JSON) {
        server_print("[GameCMS] Invalid JSON response!");
        return PLUGIN_HANDLED;
    }

    // Get the "id" object from the JSON data
    new JSON:id_object = json_object_get_value(main_object, "id");
    if (id_object == Invalid_JSON) {
        server_print("[GameCMS] Failed to get 'id' from JSON response!");
        json_free(main_object);
        return PLUGIN_HANDLED;
    }

    // Extract the server ID from the JSON object
    ServerId = json_get_number(id_object);
    if (ServerId == 0) {
        server_print("[GameCMS] Invalid Server ID received from JSON response!");
    } else {
        server_print("[GameCMS] Successfully connected to GameCMS API with Server ID: %d.", ServerId);
        set_pcvar_num(cvar[CVAR_SERVER_ID],ServerId)
    }
    
    // Clean up JSON objects and delete the temporary file
    json_free(id_object);
    json_free(main_object);
    delete_file(SERVER_ID_CONFIG_FILE);

    return PLUGIN_HANDLED;
}
