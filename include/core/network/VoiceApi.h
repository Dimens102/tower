#pragma once

#include <functional>
#include <string>
#include <vector>

struct VoiceDisplayAction
{
    std::string target;
    std::string command;
};

struct VoiceDisplayNotification
{
    std::vector<std::string> path;
    std::vector<VoiceDisplayAction> actions;
    bool ok = false;
    int durationSeconds = 2;
};

struct VoiceApiResponse
{
    int status = 200;
    std::string statusText = "OK";
    std::string jsonBody;
};

using VoiceDisplayNotificationHandler =
    std::function<void(const VoiceDisplayNotification&)>;

bool isVoiceApiPath(const std::string& path);

VoiceApiResponse handleVoiceApiRequest(
    const std::string& method,
    const std::string& path,
    const std::string& body,
    const VoiceDisplayNotificationHandler& notificationHandler);
