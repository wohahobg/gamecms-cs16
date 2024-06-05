#include <amxmodx>
#include <amxmisc>
#include <easy_http>
#include <json>
#include <file>

#define CACHE_DURATION_HOURS 24

new PLUGIN[] = "[GameCMS] Core";
new AUTHOR[] = "Wohaho";
new VERSION[] = "1.4";

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
new g_iPlayerData[33];

new SERVER_ID_CONFIG_FILE[50] = "addons/amxmodx/data/gamecms_server_id.json";

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

public plugin_init()
{
    
    register_plugin(PLUGIN, VERSION, AUTHOR,"https://gamecms.org");
 
    register_concmd("gcms_force_commands","forceCommands", ADMIN_RCON);
    register_concmd("gcms_get_players","getPlayersList", ADMIN_RCON);
    register_concmd("gcms_kick","kickPlayer", ADMIN_RCON);

}


public OnConfigsExecuted(){

    get_pcvar_string(cvar[CVAR_SERVER_API_KEY], SERVER_API_KEY, charsmax(SERVER_API_KEY))
    get_pcvar_string(cvar[CVAR_WEBSITE_API_KEY], WEBSITE_API_KEY, charsmax(WEBSITE_API_KEY))
    setServerId();
    set_task(120.0, "requestBegin", 2222, _, _, "b");
}

public client_putinserver(id){
    g_iPlayerData[id] = get_systime();
}

public forceCommands()
{
    requestBegin();
    return PLUGIN_HANDLED;
}


public getPlayersList(id, level, cid)
{
    new arg[65];
    read_argv(1, arg, charsmax(arg));
    
    new iPlayers[32], iPlayersNum;
    new i, iPlayer, szName[32], szAuthID[32], szIP[64];
    new JSON:jsonObject;
    new jsonString[4096];

    if (!equal(arg, "")) {
        // Search for a specific player if arg is provided
        iPlayer = findPlayer(arg);

        if (iPlayer != -1) {
            get_user_name(iPlayer, szName, charsmax(szName));
            get_user_authid(iPlayer, szAuthID, charsmax(szAuthID));
            get_user_ip(iPlayer, szIP, charsmax(szIP), 1);
            new playerScore = get_user_frags(iPlayer) - get_user_deaths(iPlayer);
            new playerPing, playerLoss;
            get_user_ping(iPlayer, playerPing, playerLoss);

            jsonObject = json_init_object();
            json_object_set_number(jsonObject, "user_id", iPlayer);
            json_object_set_string(jsonObject, "name", szName);
            json_object_set_string(jsonObject, "steamid", szAuthID);
            json_object_set_string(jsonObject, "ip_address", szIP);
            json_object_set_number(jsonObject, "kills", get_user_frags(iPlayer));
            json_object_set_number(jsonObject, "deaths", get_user_deaths(iPlayer));
            json_object_set_number(jsonObject, "score", playerScore);
            json_object_set_number(jsonObject, "joined_time", g_iPlayerData[iPlayer]);
            json_object_set_number(jsonObject, "ping", playerPing);
            json_object_set_number(jsonObject, "is_spectator", get_user_team(iPlayer) == 3);
            json_object_set_number(jsonObject, "is_terrorist", get_user_team(iPlayer) == 1);
            json_object_set_number(jsonObject, "is_counter_terrorist", get_user_team(iPlayer) == 2);

            json_serial_to_string(jsonObject, jsonString, charsmax(jsonString), false);
            server_print(jsonString);
            json_free(jsonObject);
        } else {
            jsonObject = json_init_object();
            json_object_set_string(jsonObject, "status", "error");
            json_object_set_string(jsonObject, "message", "User not found");

            json_serial_to_string(jsonObject, jsonString, charsmax(jsonString), false);
            server_print(jsonString);
            json_free(jsonObject);
        }
    } else {
        get_players(iPlayers, iPlayersNum);
        new playerInfo[512];
        for (i = 0; i < iPlayersNum; i++) {
            iPlayer = iPlayers[i];
            
            // Skip bots
            if (is_user_bot(iPlayer)) {
                continue;
            }

            get_user_name(iPlayer, szName, charsmax(szName));
            get_user_authid(iPlayer, szAuthID, charsmax(szAuthID));
            get_user_ip(iPlayer, szIP, charsmax(szIP), 1);
            new playerScore = get_user_frags(iPlayer) - get_user_deaths(iPlayer);
            new playerPing, playerLoss;
            get_user_ping(iPlayer, playerPing, playerLoss);

            format(playerInfo, charsmax(playerInfo), "%d|%s|%s|%s|%d|%d|%d|%d|%d|%d|%d|%d", 
                iPlayer, szName, szAuthID, szIP, get_user_frags(iPlayer), get_user_deaths(iPlayer), playerScore, playerPing, g_iPlayerData[iPlayer], 
                get_user_team(iPlayer) == 3, get_user_team(iPlayer) == 1, get_user_team(iPlayer) == 2);
            
            server_print(playerInfo);
        }
    }

    return PLUGIN_HANDLED;
}

public kickPlayer(id, level, cid)
{
    new arg[64];
    new szReason[256];
    read_argv(1, arg, charsmax(arg));
    read_argv(2, szReason, charsmax(szReason));
    

    new JSON:jsonObject = json_init_object();

    if (equal(arg, "")) {
        json_object_set_string(jsonObject, "status", "error");
        json_object_set_string(jsonObject, "message", "Usage: gcms_kick <name|steamid|ip>");
        new jsonString[512];
        json_serial_to_string(jsonObject, jsonString, charsmax(jsonString), false);
        server_print(jsonString);
        json_free(jsonObject);
        return PLUGIN_HANDLED;
    }

    new iPlayer = findPlayer(arg);
    
    if (iPlayer == -1) {
        json_object_set_string(jsonObject, "status", "error");
        json_object_set_string(jsonObject, "message", "Player not found");
        new jsonString[128];
        json_serial_to_string(jsonObject, jsonString, charsmax(jsonString), false);
        server_print(jsonString);
        json_free(jsonObject);
        return PLUGIN_HANDLED;
    }

    if (hasImmunity(iPlayer)) {
        json_object_set_string(jsonObject, "status", "error");
        json_object_set_string(jsonObject, "message", "Player has immunity");
        new jsonString[512];
        json_serial_to_string(jsonObject, jsonString, charsmax(jsonString), false);
        server_print(jsonString);
        json_free(jsonObject);
        return PLUGIN_HANDLED;
    }

    // Check if a reason is provided
    if (equal(szReason, "")) {
        server_cmd("kick #%d", get_user_userid(iPlayer));
    } else {
        server_cmd("kick #%d ^"%s^"", get_user_userid(iPlayer), szReason);
    }

    json_object_set_string(jsonObject, "status", "success");
    json_object_set_string(jsonObject, "message", "Player kicked successfully");
    new jsonString[128];
    json_serial_to_string(jsonObject, jsonString, charsmax(jsonString), false);
    server_print(jsonString);
    json_free(jsonObject);

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


public setServerId() {
    if (file_exists(SERVER_ID_CONFIG_FILE)) {
        new fileTime = GetFileTime(SERVER_ID_CONFIG_FILE,FileTime_LastChange);
        new currentTime = get_systime();

        new elapsedHours = (currentTime - fileTime) / 3600;
        if (elapsedHours > CACHE_DURATION_HOURS) {
            log_amx("here");
            requestNewServerId();
        } else {
            readServerIdFromFile();
        }
    } else {
        requestNewServerId();
    }
}

public requestNewServerId() {
    new EzHttpOptions:options_id = ezhttp_create_options();
    ezhttp_option_set_header(options_id, "Authorization", fmt("Bearer %s", SERVER_API_KEY));
    ezhttp_get("https://api.gamecms.org/v2/server", "handleServerIdResponse", options_id);
}

public handleServerIdResponse(EzHttpRequest:request_id) {
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

    // Save the response to a file
    if (!ezhttp_save_data_to_file(request_id, SERVER_ID_CONFIG_FILE)) {
        server_print("[GameCMS] Failed to save response data to file.");
        return PLUGIN_HANDLED;
    }

    // Parse JSON data from the file
    readServerIdFromFile();

    return PLUGIN_HANDLED;
}

public readServerIdFromFile() {
    // Parse JSON data from the file
    new JSON:main_object = json_parse(SERVER_ID_CONFIG_FILE, true);
    if (main_object == Invalid_JSON) {
        server_print("[GameCMS] Invalid JSON response!");
        return;
    }

    // Get the "id" object from the JSON data
    new JSON:id_object = json_object_get_value(main_object, "id");
    if (id_object == Invalid_JSON) {
        server_print("[GameCMS] Failed to get 'id' from JSON response!");
        json_free(main_object);
        return;
    }

    // Extract the server ID from the JSON object
    ServerId = json_get_number(id_object);
    if (ServerId == 0) {
        server_print("[GameCMS] Invalid Server ID received from JSON response!");
    } else {
        server_print("[GameCMS] Successfully connected to GameCMS API with Server ID: %d.", ServerId);
        set_pcvar_num(cvar[CVAR_SERVER_ID], ServerId);
    }

    // Clean up JSON objects
    json_free(id_object);
    json_free(main_object);
}

public findPlayer(const searchTerm[])
{
    new iPlayers[32], iPlayersNum;
    new i, iPlayer, szName[32], szAuthID[32], szIP[64];

    get_players(iPlayers, iPlayersNum);

    for (i = 0; i < iPlayersNum; i++) {
        iPlayer = iPlayers[i];

        // Skip bots
        if (is_user_bot(iPlayer)) {
            continue;
        }

        get_user_name(iPlayer, szName, charsmax(szName));
        get_user_authid(iPlayer, szAuthID, charsmax(szAuthID));
        get_user_ip(iPlayer, szIP, charsmax(szIP),1);
        if (equal(szAuthID, searchTerm) || equal(szIP, searchTerm) || equal(szName, searchTerm)) {
            return iPlayer;
        }
    }

    return -1;
}

public hasImmunity(iPlayer) {
    return get_user_flags(iPlayer) & ADMIN_IMMUNITY;
}
