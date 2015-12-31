#include <sourcemod>
#include <autoexecconfig>
#include <cURL>
#include <calladmin>

public Plugin myinfo = {
  name = "CallAdmin - Slack",
  author = "The casual trade and fun server",
  description = "Sends call admin reports to slack",
  version = "1.1.0",
  url = "http://tf2-casual-fun.de/"
}

ConVar slack_url;
ArrayList reports;

public void OnPluginStart()
{
  reports = new ArrayList();

  AutoExecConfig_SetFile("plugin.calladmin_slack");
  AutoExecConfig_SetCreateFile(true);
  bool needsCleanup = CreateConfig();
  AutoExecConfig_ExecuteFile();
  if(needsCleanup) {
    AutoExecConfig_CleanFile();
  }
}

bool CreateConfig()
{
  slack_url = AutoExecConfig_CreateConVar("sm_calladmin_slack_url", "", "Your slack url for incoming webhooks", FCVAR_PROTECTED | FCVAR_SPONLY);
  bool needsCleanup = ConfigWasAppended();

  return needsCleanup;
}

bool ConfigWasAppended(bool previousResult = false)
{
  return previousResult
    || AutoExecConfig_GetAppendResult() == AUTOEXEC_APPEND_SUCCESS;
}

public void CallAdmin_OnReportPost(int client, int target, const char[] reason)
{
  DataPack notification = new DataPack();

  int id = CallAdmin_GetReportID();
  reports.Push(id);
  notification.WriteCell(id);

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

  PostData(data);
}

void CreateData(DataPack notification, char[] data, int length)
{
  int reportId = notification.ReadCell();

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
  Format(preText, sizeof(preText), "New report(%i)! %s", reportId, connectLink);

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

void PostData(const char[] data)
{
  char url[256];
  slack_url.GetString(url, sizeof(url));

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

public void CallAdmin_OnReportHandled(int client, int id)
{
  int index = reports.FindValue(id);
  if(index == -1) return;
  reports.Erase(index);

  DataPack notification = new DataPack();
  notification.WriteCell(id);

  if(!GetPlayerName(client, notification)) {
    delete notification;
    return;
  }

  notification.Reset();
  SendHandledNotification(notification);
  delete notification;
}

void SendHandledNotification(DataPack notification)
{
  char data[512];
  CreateHandledData(notification, data, sizeof(data));

  PostData(data);
}

void CreateHandledData(DataPack notification, char[] data, int length)
{
  int reportId = notification.ReadCell();
  char admin[MAX_NAME_LENGTH];
  notification.ReadString(admin, sizeof(admin));

  Format(data,
    length,
    "payload={\
      \"text\":\"*%s* handled the report #%i. :thumbsup:\",\
      \"icon_emoji\":\":heart:\"}",
    admin,
    reportId);
}
