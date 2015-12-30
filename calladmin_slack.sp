#include <sourcemod>
#include <cURL>
#include <calladmin>

public Plugin myinfo = {
  name = "CallAdmin - Slack",
  author = "The casual trade and fun server",
  description = "Sends call admin reports to slack",
  version = "0.0.1",
  url = "http://tf2-casual-fun.de/"
}

ConVar slack_url;

public void OnPluginStart()
{
  slack_url = CreateConVar("sm_calladmin_slack_url", "", "Your slack url for incoming webhooks", FCVAR_PROTECTED | FCVAR_SPONLY);
  AutoExecConfig();
}

public void CallAdmin_OnReportPost(int client, int target, const char[] reason)
{
  DataPack notification = new DataPack();
  if(!GetPlayerNames(client, target, notification)) {
    delete notification;
    return;
  }

  if(!GetPlayerSteamIds(client, target, notification)) {
    delete notification;
    return;
  }

  notification.WriteString(reason);

  notification.Reset();
  SendNotification(notification);
  delete notification;
}

bool GetPlayerNames(int client, int target, DataPack store)
{
  return GetPlayerName(client, store)
    && GetPlayerName(target, store);
}

bool GetPlayerName(int client, DataPack store)
{
  if(client == REPORTER_CONSOLE) {
    store.WriteString("Console");
    return true;
  }

  if(IsClientConnected(client)) {
    char name[MAX_NAME_LENGTH];
    if(GetClientName(client, name, sizeof(name))) {
      store.WriteString(name);
      return true;
    }
  }

  return false;
}

bool GetPlayerSteamIds(int client, int target, DataPack store)
{
  return GetPlayerSteamId(client, store)
    && GetPlayerSteamId(target, store);
}

bool GetPlayerSteamId(int client, DataPack store)
{
  if(client == REPORTER_CONSOLE) {
    store.WriteString("UNKNOWN");
    return true;
  }

  if(IsClientConnected(client)) {
    char steamId[32];
    if(GetClientAuthId(client, AuthId_Engine, steamId, sizeof(steamId))) {
      store.WriteString(steamId);
      return true;
    }
  }

  return false;
}

void SendNotification(DataPack notification)
{
  char data[2048];
  CreateData(notification, data, sizeof(data));

  char url[256];
  slack_url.GetString(url, sizeof(url));

  PostData(url, data);
}

void CreateData(DataPack notification, char[] data, int length)
{
  char reporter[MAX_NAME_LENGTH];
  notification.ReadString(reporter, sizeof(reporter));

  char target[MAX_NAME_LENGTH];
  notification.ReadString(target, sizeof(target));

  char reporterId[32];
  notification.ReadString(reporterId, sizeof(reporterId));

  char targetId[32];
  notification.ReadString(targetId, sizeof(targetId));

  char reason[REASON_MAX_LENGTH];
  notification.ReadString(reason, sizeof(reason));

  char connectLink[128];
  CreateConnectLink(connectLink, sizeof(connectLink));

  char preText[144];
  Format(preText, sizeof(preText), "New report! %s", connectLink);

  char title[256];
  Format(title, sizeof(title), "%s reported %s", reporter, target);

  Format(data,
    length,
    "payload={\
      \"attachments\":[{\
        \"fallback\":\"%s | %s: %s\",\
        \"pretext\":\"%s\",\
        \"color\":\"warning\",\
        \"fields\":[{\
          \"title\":\"%s\",\
          \"value\":\"Reporter: %s(%s)\nTarget: %s(%s)\nReason: %s\"}]}]}",
    preText,
    title,
    reason,
    preText,
    title,
    reporter,
    reporterId,
    target,
    targetId,
    reason);
}

void CreateConnectLink(char[] link, int length)
{
  char ip[16];
  CallAdmin_GetHostIP(ip, sizeof(ip));
  int port = CallAdmin_GetHostPort();

  Format(link, length, "<steam://connect/%s:%i|Connect to server>", ip, port);
}

void PostData(const char[] url, const char[] data)
{
  Handle curl = curl_easy_init();
  if(curl == null) return;

  SetUrl(curl, url);
  SetData(curl, data);
  curl_easy_perform_thread(curl, RequestFinished);
}

void SetUrl(Handle curl, const char[] url)
{
  curl_easy_setopt_string(curl, CURLOPT_URL, url);
  curl_easy_setopt_int(curl, CURLOPT_SSL_VERIFYPEER, 0);
}

void SetData(Handle curl, const char[] data)
{
  curl_easy_setopt_string(curl, CURLOPT_POSTFIELDS, data);
}

public int RequestFinished(Handle curl, CURLcode code)
{
  if(code != CURLE_OK) {
    char error[128];
    curl_get_error_buffer(curl, error, sizeof(error));
    LogError("[CallAdmin Slack] %s", error);
  }
  delete curl;
}
